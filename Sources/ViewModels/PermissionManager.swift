import Foundation
import SwiftUI

@Observable
@MainActor
final class PermissionManager {
    private(set) var pendingRequests: [PendingRequest] = []
    private(set) var serverRunning = false
    private(set) var port: UInt16 = 0
    private var server: HookServer?
    private var expirationTimer: Timer?
    private let notifier: any NotificationPosting

    /// Pattern-based allow rules. Each rule matches a specific tool + content
    /// pattern within a single session — not a blanket session pass.
    private(set) var allowRules: [AllowRule] = []

    var pendingCount: Int { pendingRequests.count }

    struct PendingRequest: Identifiable {
        let id: String
        let request: PermissionRequest
        let receivedAt: Date
        let respond: @Sendable (PermissionResponse) -> Void
    }

    init(notifier: any NotificationPosting = NotificationManager.shared) {
        self.notifier = notifier
    }

    func startServer() {
        guard server == nil else { return }

        let preferredPort: UInt16 = 19275
        for offset: UInt16 in 0..<10 {
            let tryPort = preferredPort + offset
            do {
                let hookServer = try HookServer(port: tryPort)
                hookServer.onRequest = { [weak self] request, respond in
                    Task { @MainActor in
                        self?.addRequest(request, respond: respond)
                    }
                }
                hookServer.start()
                server = hookServer
                port = tryPort
                serverRunning = true

                HookConfigManager.install(port: tryPort)

                startExpirationTimer()
                return
            } catch {
                continue
            }
        }
    }

    func stopServer() {
        expirationTimer?.invalidate()
        expirationTimer = nil

        for request in pendingRequests {
            request.respond(PermissionResponse(decision: .ask))
        }
        pendingRequests.removeAll()

        server?.stop()
        server = nil
        serverRunning = false
        port = 0

        HookConfigManager.uninstall()
    }

    // MARK: - Single-request actions

    func approve(_ request: PendingRequest) {
        request.respond(PermissionResponse(decision: .allow))
        pendingRequests.removeAll { $0.id == request.id }
    }

    func deny(_ request: PendingRequest) {
        request.respond(PermissionResponse(decision: .deny))
        pendingRequests.removeAll { $0.id == request.id }
    }

    func approveById(_ toolUseId: String) {
        guard let request = pendingRequests.first(where: { $0.id == toolUseId }) else { return }
        approve(request)
    }

    func denyById(_ toolUseId: String) {
        guard let request = pendingRequests.first(where: { $0.id == toolUseId }) else { return }
        deny(request)
    }

    // MARK: - Pattern-based rules

    /// Creates a pattern-based allow rule from the given request, approves it,
    /// and auto-approves any other pending requests that match the new rule.
    func createRule(from request: PendingRequest) {
        let rule = AllowRule.from(request.request)

        // Don't create duplicate rules
        if !allowRules.contains(where: { $0.label == rule.label && $0.sessionId == rule.sessionId }) {
            allowRules.append(rule)
        }

        // Approve the triggering request
        approve(request)

        // Auto-approve other pending requests that match the new rule
        let matching = pendingRequests.filter { rule.matches($0.request) }
        for pending in matching {
            approve(pending)
        }
    }

    func createRuleById(_ toolUseId: String) {
        guard let request = pendingRequests.first(where: { $0.id == toolUseId }) else { return }
        createRule(from: request)
    }

    func revokeRule(_ rule: AllowRule) {
        allowRules.removeAll { $0.id == rule.id }
    }

    // MARK: - Request intake

    private static let autoApprovedTools: Set<String> = [
        "Read", "Glob", "Grep", "Diff", "TaskCreate", "TaskUpdate", "Agent"
    ]

    func addRequest(
        _ request: PermissionRequest,
        receivedAt: Date = Date(),
        respond: @escaping @Sendable (PermissionResponse) -> Void
    ) {
        if Self.autoApprovedTools.contains(request.toolName) {
            respond(PermissionResponse(decision: .allow, reason: "Auto-approved tool"))
            return
        }

        if let rule = allowRules.first(where: { $0.matches(request) }) {
            respond(PermissionResponse(decision: .allow, reason: "Matched rule: \(rule.label)"))
            return
        }

        // Deduplicate: if a request with this toolUseId already exists, deny the old one first
        if let existingIndex = pendingRequests.firstIndex(where: { $0.id == request.toolUseId }) {
            let existing = pendingRequests.remove(at: existingIndex)
            existing.respond(PermissionResponse(decision: .ask))
        }

        let pending = PendingRequest(
            id: request.toolUseId,
            request: request,
            receivedAt: receivedAt,
            respond: respond
        )
        pendingRequests.append(pending)
        notifier.postPermissionNotification(for: request)
    }

    // MARK: - Expiration

    private func startExpirationTimer() {
        expirationTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.expireOldRequests()
            }
        }
    }

    func expireOldRequests() {
        let cutoff = Date().addingTimeInterval(-Constants.requestTimeout)
        let expired = pendingRequests.filter { $0.receivedAt < cutoff }
        for request in expired {
            request.respond(PermissionResponse(decision: .ask, reason: "Permission request timed out"))
        }
        pendingRequests.removeAll { $0.receivedAt < cutoff }
    }
}
