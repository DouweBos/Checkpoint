@testable import Checkpoint
import Foundation
import Testing
import os

@Suite("HookServer")
struct HookServerTests {
    @Test("Server starts and accepts connections", .timeLimit(.minutes(1)))
    func serverStartsAndAccepts() async throws {
        let server = try HookServer(port: 19290)
        let received = Confirmation()

        server.onRequest = { request, respond in
            #expect(request.toolName == "Bash")
            #expect(request.toolInput["command"]?.stringValue == "echo hello")
            respond(PermissionResponse(decision: .allow))
            received.signal()
        }
        server.start()

        try await Task.sleep(for: .milliseconds(100))

        let (data, response) = try await sendHookRequest(
            port: 19290,
            toolName: "Bash",
            toolInput: ["command": "echo hello"]
        )
        let httpResponse = response as! HTTPURLResponse // swiftlint:disable:this force_cast

        #expect(httpResponse.statusCode == 200)

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any] // swiftlint:disable:this force_cast
        let output = json["hookSpecificOutput"] as? [String: Any]
        #expect(output?["permissionDecision"] as? String == "allow")

        await received.wait()
        server.stop()
    }

    @Test("Server returns deny response", .timeLimit(.minutes(1)))
    func serverReturnsDeny() async throws {
        let server = try HookServer(port: 19291)

        server.onRequest = { _, respond in
            respond(PermissionResponse(decision: .deny))
        }
        server.start()

        try await Task.sleep(for: .milliseconds(100))

        let (data, _) = try await sendHookRequest(
            port: 19291,
            toolName: "Read",
            toolInput: ["file_path": "/etc/passwd"]
        )
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any] // swiftlint:disable:this force_cast
        let output = json["hookSpecificOutput"] as? [String: Any]
        #expect(output?["permissionDecision"] as? String == "deny")

        server.stop()
    }

    @Test("Server holds connection until response", .timeLimit(.minutes(1)))
    func serverHoldsConnection() async throws {
        let server = try HookServer(port: 19292)
        let responderBox = ResponderBox()
        let received = Confirmation()

        server.onRequest = { _, respond in
            responderBox.store(respond)
            received.signal()
        }
        server.start()

        try await Task.sleep(for: .milliseconds(100))

        let dataTask = Task {
            try await sendHookRequest(
                port: 19292,
                toolName: "Bash",
                toolInput: ["command": "rm -rf /"]
            )
        }

        await received.wait()

        // Delay the response to verify the connection is held
        try await Task.sleep(for: .milliseconds(200))
        responderBox.respond(with: .deny)

        let (data, _) = try await dataTask.value
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any] // swiftlint:disable:this force_cast
        let output = json["hookSpecificOutput"] as? [String: Any]
        #expect(output?["permissionDecision"] as? String == "deny")

        server.stop()
    }

    @Test("Invalid port throws error")
    func invalidPort() {
        #expect(throws: HookServerError.self) {
            _ = try HookServer(port: 0)
        }
    }

    // MARK: - Helpers

    private func sendHookRequest(
        port: UInt16,
        toolName: String,
        toolInput: [String: String],
        toolUseId: String = "tu-\(UUID())"
    ) async throws -> (Data, URLResponse) {
        let body: [String: Any] = [
            "session_id": "s1",
            "transcript_path": "/t",
            "cwd": "/c",
            "permission_mode": "ask",
            "hook_event_name": "PreToolUse",
            "tool_name": toolName,
            "tool_input": toolInput,
            "tool_use_id": toolUseId
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        let url = URL(string: "http://localhost:\(port)/claude-permissions")!
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return try await URLSession.shared.data(for: request)
    }
}

// Thread-safe box to store the respond closure across async boundaries
private final class ResponderBox: Sendable {
    private let storage = OSAllocatedUnfairLock<(@Sendable (PermissionResponse) -> Void)?>(
        initialState: nil
    )

    func store(_ respond: @escaping @Sendable (PermissionResponse) -> Void) {
        storage.withLock { $0 = respond }
    }

    func respond(with decision: PermissionResponse.Decision) {
        let respond = storage.withLock { stored -> (@Sendable (PermissionResponse) -> Void)? in
            let value = stored
            stored = nil
            return value
        }
        respond?(PermissionResponse(decision: decision))
    }
}

// Async-safe confirmation helper for Swift Testing
private final class Confirmation: Sendable {
    private let continuation = OSAllocatedUnfairLock<CheckedContinuation<Void, Never>?>(
        initialState: nil
    )
    private let fulfilled = OSAllocatedUnfairLock(initialState: false)

    func signal() {
        fulfilled.withLock { $0 = true }
        let cont = continuation.withLock { stored -> CheckedContinuation<Void, Never>? in
            let value = stored
            stored = nil
            return value
        }
        cont?.resume()
    }

    func wait() async {
        if fulfilled.withLock({ $0 }) { return }

        await withCheckedContinuation { cont in
            if fulfilled.withLock({ $0 }) {
                cont.resume()
                return
            }
            continuation.withLock { $0 = cont }
            // Check again in case signal() fired between our check and storing the continuation
            if fulfilled.withLock({ $0 }) {
                let stored = continuation.withLock { s -> CheckedContinuation<Void, Never>? in
                    let v = s
                    s = nil
                    return v
                }
                stored?.resume()
            }
        }
    }
}
