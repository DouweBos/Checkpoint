import Foundation
import Network
import os

final class HookServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.houwert.checkpoint.server")
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let lock = NSLock()

    var onRequest: (@Sendable (PermissionRequest, @escaping @Sendable (PermissionResponse) -> Void) -> Void)?

    init(port: UInt16) throws {
        guard port != 0, let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw HookServerError.invalidPort
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params, on: nwPort)
    }

    func start() {
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                Logger(subsystem: "com.houwert.checkpoint", category: "server")
                    .error("Server failed: \(error)")

                self?.stop()
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
        lock.lock()
        let conns = connections.values
        lock.unlock()
        for connection in conns {
            connection.cancel()
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let connId = ObjectIdentifier(connection)
        lock.lock()
        connections[connId] = connection
        lock.unlock()

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveHTTPRequest(on: connection)
            case .cancelled:
                self?.lock.lock()
                self?.connections.removeValue(forKey: connId)
                self?.lock.unlock()
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func receiveHTTPRequest(on connection: NWConnection, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var accumulated = buffer
            if let data { accumulated.append(data) }

            if let parsed = self.parseHTTPRequest(accumulated) {
                self.handleParsedRequest(parsed, on: connection)
            } else if isComplete || error != nil {
                self.sendResponse(on: connection, status: 400, body: Data("{\"error\":\"Bad request\"}".utf8))
            } else {
                // Need more data — keep reading
                self.receiveHTTPRequest(on: connection, buffer: accumulated)
            }
        }
    }

    private func handleParsedRequest(_ parsed: (method: String, body: Data), on connection: NWConnection) {
        guard parsed.method == "POST" else {
            sendResponse(on: connection, status: 405, body: Data("{\"error\":\"Method not allowed\"}".utf8))
            return
        }

        guard let request = try? JSONDecoder().decode(PermissionRequest.self, from: parsed.body) else {
            sendResponse(on: connection, status: 400, body: Data("{\"error\":\"Invalid JSON\"}".utf8))
            return
        }

        let responseGuard = ResponseGuard()

        let respond: @Sendable (PermissionResponse) -> Void = { [weak self] response in
            guard responseGuard.tryRespond() else { return }

            guard let responseData = try? JSONEncoder().encode(response) else {
                connection.cancel()
                return
            }
            self?.sendResponse(on: connection, status: 200, body: responseData)
        }

        onRequest?(request, respond)
    }

    private func parseHTTPRequest(_ data: Data) -> (method: String, body: Data)? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }

        // Split headers from body
        guard let headerEnd = raw.range(of: "\r\n\r\n") else { return nil }

        let headerSection = raw[raw.startIndex..<headerEnd.lowerBound]
        let bodyString = raw[headerEnd.upperBound...]

        // Check Content-Length to ensure we have the full body
        let headers = headerSection.split(separator: "\r\n")
        for header in headers {
            let parts = header.split(separator: ":", maxSplits: 1)
            if parts.count == 2,
               parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length",
               let length = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                if bodyString.utf8.count < length {
                    return nil  // Incomplete body — need more data
                }
            }
        }

        // Extract method from request line
        let requestLine = headers.first ?? ""
        let method = String(requestLine.split(separator: " ", maxSplits: 2).first ?? "")

        return (method, Data(bodyString.utf8))
    }

    private func sendResponse(on connection: NWConnection, status: Int, body: Data) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 405: statusText = "Method Not Allowed"
        default: statusText = "Error"
        }

        let header = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: application/json",
            "Content-Length: \(body.count)",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")
        var responseData = Data(header.utf8)
        responseData.append(body)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private final class ResponseGuard: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    func tryRespond() -> Bool {
        state.withLock { responded in
            if responded { return false }
            responded = true
            return true
        }
    }
}

enum HookServerError: Error {
    case invalidPort
}
