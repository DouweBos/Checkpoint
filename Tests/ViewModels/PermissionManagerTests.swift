@testable import Checkpoint
import Foundation
import os
import Testing

// Thread-safe box for capturing values in @Sendable closures
private final class Box<T: Sendable>: Sendable {
    private let lock = OSAllocatedUnfairLock<T?>(initialState: nil)

    var value: T? {
        lock.withLock { $0 }
    }

    func set(_ newValue: T) {
        lock.withLock { $0 = newValue }
    }
}

private final class DecisionMap: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [String: String]())

    subscript(key: String) -> String? {
        get { lock.withLock { $0[key] } }
        set { lock.withLock { $0[key] = newValue } }
    }
}

private final class Flag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    var value: Bool { state.withLock { $0 } }

    func set() { state.withLock { $0 = true } }
}

@Suite("PermissionManager")
@MainActor
struct PermissionManagerTests {
    let mockNotifier = MockNotificationPosting()

    @Test("Initial state")
    func initialState() {
        let manager = PermissionManager(notifier: mockNotifier)
        #expect(manager.pendingRequests.isEmpty)
        #expect(manager.pendingCount == 0)
        #expect(!manager.serverRunning)
        #expect(manager.port == 0)
    }

    @Test("Add request increases pending count")
    func addRequest() {
        let manager = PermissionManager(notifier: mockNotifier)
        let request = TestFixtures.makePermissionRequest()

        manager.addRequest(request) { _ in }

        #expect(manager.pendingCount == 1)
        #expect(manager.pendingRequests.first?.request.toolName == "Bash")
    }

    @Test("Add request triggers notification")
    func addRequestNotifies() {
        let manager = PermissionManager(notifier: mockNotifier)
        let request = TestFixtures.makePermissionRequest(toolName: "Write")

        manager.addRequest(request) { _ in }

        #expect(mockNotifier.postedRequests.count == 1)
        #expect(mockNotifier.postedRequests.first?.toolName == "Write")
    }

    @Test("Approve removes request and sends allow")
    func approve() {
        let manager = PermissionManager(notifier: mockNotifier)
        let request = TestFixtures.makePermissionRequest()
        let decision = Box<String>()

        manager.addRequest(request) { response in
            decision.set(response.hookSpecificOutput.permissionDecision)
        }

        let pending = manager.pendingRequests.first!
        manager.approve(pending)

        #expect(manager.pendingCount == 0)
        #expect(decision.value == "allow")
    }

    @Test("Deny removes request and sends deny")
    func deny() {
        let manager = PermissionManager(notifier: mockNotifier)
        let request = TestFixtures.makePermissionRequest()
        let decision = Box<String>()

        manager.addRequest(request) { response in
            decision.set(response.hookSpecificOutput.permissionDecision)
        }

        let pending = manager.pendingRequests.first!
        manager.deny(pending)

        #expect(manager.pendingCount == 0)
        #expect(decision.value == "deny")
    }

    @Test("Approve by ID")
    func approveById() {
        let manager = PermissionManager(notifier: mockNotifier)
        let request = TestFixtures.makePermissionRequest(toolUseId: "specific-id")
        let decision = Box<String>()

        manager.addRequest(request) { response in
            decision.set(response.hookSpecificOutput.permissionDecision)
        }

        manager.approveById("specific-id")

        #expect(manager.pendingCount == 0)
        #expect(decision.value == "allow")
    }

    @Test("Deny by ID")
    func denyById() {
        let manager = PermissionManager(notifier: mockNotifier)
        let request = TestFixtures.makePermissionRequest(toolUseId: "specific-id")
        let decision = Box<String>()

        manager.addRequest(request) { response in
            decision.set(response.hookSpecificOutput.permissionDecision)
        }

        manager.denyById("specific-id")

        #expect(manager.pendingCount == 0)
        #expect(decision.value == "deny")
    }

    @Test("Approve/deny unknown ID does nothing")
    func unknownIdNoOp() {
        let manager = PermissionManager(notifier: mockNotifier)
        let request = TestFixtures.makePermissionRequest()
        let responded = Flag()

        manager.addRequest(request) { _ in
            responded.set()
        }

        manager.approveById("nonexistent")
        #expect(manager.pendingCount == 1)
        #expect(!responded.value)

        manager.denyById("nonexistent")
        #expect(manager.pendingCount == 1)
        #expect(!responded.value)
    }

    @Test("Multiple concurrent requests")
    func multipleConcurrentRequests() {
        let manager = PermissionManager(notifier: mockNotifier)
        let decisions = DecisionMap()

        for idx in 0..<3 {
            let id = "request-\(idx)"
            let request = TestFixtures.makePermissionRequest(toolUseId: id)
            manager.addRequest(request) { response in
                decisions[id] = response.hookSpecificOutput.permissionDecision
            }
        }

        #expect(manager.pendingCount == 3)

        manager.approveById("request-0")
        manager.denyById("request-1")
        manager.approveById("request-2")

        #expect(manager.pendingCount == 0)
        #expect(decisions["request-0"] == "allow")
        #expect(decisions["request-1"] == "deny")
        #expect(decisions["request-2"] == "allow")
    }

    @Test("Expire old requests sends ask")
    func expireOldRequests() {
        let manager = PermissionManager(notifier: mockNotifier)
        let decision = Box<String>()

        let request = TestFixtures.makePermissionRequest()
        manager.addRequest(
            request,
            receivedAt: Date().addingTimeInterval(-60)
        ) { response in
            decision.set(response.hookSpecificOutput.permissionDecision)
        }

        manager.expireOldRequests()

        #expect(manager.pendingCount == 0)
        #expect(decision.value == "ask")
    }

    @Test("Non-expired requests are kept")
    func nonExpiredRequestsKept() {
        let manager = PermissionManager(notifier: mockNotifier)

        let request = TestFixtures.makePermissionRequest()
        manager.addRequest(
            request,
            receivedAt: Date().addingTimeInterval(-10)
        ) { _ in }

        manager.expireOldRequests()

        #expect(manager.pendingCount == 1)
    }

    // MARK: - Pattern-based Allow Rules

    @Test("Create rule approves request and stores rule")
    func createRule() {
        let manager = PermissionManager(notifier: mockNotifier)
        let request = TestFixtures.makePermissionRequest(
            sessionId: "session-A",
            toolName: "Bash",
            toolInput: ["command": .string("npm install")]
        )
        let decision = Box<String>()

        manager.addRequest(request) { response in
            decision.set(response.hookSpecificOutput.permissionDecision)
        }

        let pending = manager.pendingRequests.first!
        manager.createRule(from: pending)

        #expect(manager.pendingCount == 0)
        #expect(decision.value == "allow")
        #expect(manager.allowRules.count == 1)
        #expect(manager.allowRules.first?.label == "Bash(npm *)")
    }

    @Test("Rule auto-approves matching requests from same session")
    func ruleAutoApprovesMatching() {
        let manager = PermissionManager(notifier: mockNotifier)

        // Create rule from npm command
        let first = TestFixtures.makePermissionRequest(
            sessionId: "session-A",
            toolName: "Bash",
            toolInput: ["command": .string("npm install")],
            toolUseId: "tu-1"
        )
        manager.addRequest(first) { _ in }
        manager.createRule(from: manager.pendingRequests.first!)

        // New npm command from same session should be auto-approved
        let decision = Box<String>()
        let second = TestFixtures.makePermissionRequest(
            sessionId: "session-A",
            toolName: "Bash",
            toolInput: ["command": .string("npm test")],
            toolUseId: "tu-2"
        )
        manager.addRequest(second) { response in
            decision.set(response.hookSpecificOutput.permissionDecision)
        }

        #expect(manager.pendingCount == 0)
        #expect(decision.value == "allow")
    }

    @Test("Rule does NOT auto-approve non-matching tool from same session")
    func ruleDoesNotApproveNonMatchingTool() {
        let manager = PermissionManager(notifier: mockNotifier)

        // Create rule from Bash(npm *)
        let first = TestFixtures.makePermissionRequest(
            sessionId: "session-A",
            toolName: "Bash",
            toolInput: ["command": .string("npm install")],
            toolUseId: "tu-1"
        )
        manager.addRequest(first) { _ in }
        manager.createRule(from: manager.pendingRequests.first!)

        // Edit request from same session should NOT be auto-approved
        let second = TestFixtures.makePermissionRequest(
            sessionId: "session-A",
            toolName: "Edit",
            toolInput: ["file_path": .string("/src/app.tsx")],
            toolUseId: "tu-2"
        )
        manager.addRequest(second) { _ in }

        #expect(manager.pendingCount == 1)
    }

    @Test("Rule does NOT auto-approve non-matching content from same session")
    func ruleDoesNotApproveNonMatchingContent() {
        let manager = PermissionManager(notifier: mockNotifier)

        // Create rule from Bash(npm *)
        let first = TestFixtures.makePermissionRequest(
            sessionId: "session-A",
            toolName: "Bash",
            toolInput: ["command": .string("npm install")],
            toolUseId: "tu-1"
        )
        manager.addRequest(first) { _ in }
        manager.createRule(from: manager.pendingRequests.first!)

        // git command from same session should NOT be auto-approved
        let second = TestFixtures.makePermissionRequest(
            sessionId: "session-A",
            toolName: "Bash",
            toolInput: ["command": .string("git push --force")],
            toolUseId: "tu-2"
        )
        manager.addRequest(second) { _ in }

        #expect(manager.pendingCount == 1)
    }

    @Test("Rule does NOT auto-approve different session")
    func ruleDoesNotCrossSession() {
        let manager = PermissionManager(notifier: mockNotifier)
        let first = TestFixtures.makePermissionRequest(
            sessionId: "session-A",
            toolName: "Bash",
            toolInput: ["command": .string("npm install")],
            toolUseId: "tu-1"
        )

        manager.addRequest(first) { _ in }
        manager.createRule(from: manager.pendingRequests.first!)

        let second = TestFixtures.makePermissionRequest(
            sessionId: "session-B",
            toolName: "Bash",
            toolInput: ["command": .string("npm test")],
            toolUseId: "tu-2"
        )
        manager.addRequest(second) { _ in }

        #expect(manager.pendingCount == 1)
    }

    @Test("Create rule only approves matching pending requests")
    func createRuleApprovesOnlyMatching() {
        let manager = PermissionManager(notifier: mockNotifier)
        let decisions = DecisionMap()

        // Three pending requests: two npm, one git
        let npm1 = TestFixtures.makePermissionRequest(
            sessionId: "session-A",
            toolName: "Bash",
            toolInput: ["command": .string("npm install")],
            toolUseId: "tu-npm1"
        )
        let npm2 = TestFixtures.makePermissionRequest(
            sessionId: "session-A",
            toolName: "Bash",
            toolInput: ["command": .string("npm test")],
            toolUseId: "tu-npm2"
        )
        let git = TestFixtures.makePermissionRequest(
            sessionId: "session-A",
            toolName: "Bash",
            toolInput: ["command": .string("git status")],
            toolUseId: "tu-git"
        )

        manager.addRequest(npm1) { decisions["tu-npm1"] = $0.hookSpecificOutput.permissionDecision }
        manager.addRequest(npm2) { decisions["tu-npm2"] = $0.hookSpecificOutput.permissionDecision }
        manager.addRequest(git) { decisions["tu-git"] = $0.hookSpecificOutput.permissionDecision }

        #expect(manager.pendingCount == 3)

        // Create rule from the first npm request
        let pending = manager.pendingRequests.first { $0.id == "tu-npm1" }!
        manager.createRule(from: pending)

        // npm requests approved, git stays pending
        #expect(decisions["tu-npm1"] == "allow")
        #expect(decisions["tu-npm2"] == "allow")
        #expect(decisions["tu-git"] == nil)
        #expect(manager.pendingCount == 1)
    }

    @Test("Revoke rule")
    func revokeRule() {
        let manager = PermissionManager(notifier: mockNotifier)
        let request = TestFixtures.makePermissionRequest(sessionId: "session-A")

        manager.addRequest(request) { _ in }
        manager.createRule(from: manager.pendingRequests.first!)

        #expect(manager.allowRules.count == 1)

        manager.revokeRule(manager.allowRules.first!)

        #expect(manager.allowRules.isEmpty)
    }

    @Test("Create rule by ID")
    func createRuleById() {
        let manager = PermissionManager(notifier: mockNotifier)
        let request = TestFixtures.makePermissionRequest(
            sessionId: "session-A",
            toolUseId: "specific-id"
        )
        let decision = Box<String>()

        manager.addRequest(request) { response in
            decision.set(response.hookSpecificOutput.permissionDecision)
        }

        manager.createRuleById("specific-id")

        #expect(manager.pendingCount == 0)
        #expect(decision.value == "allow")
        #expect(manager.allowRules.count == 1)
    }

    @Test("Duplicate rules are not created")
    func noDuplicateRules() {
        let manager = PermissionManager(notifier: mockNotifier)

        // Create first rule
        let first = TestFixtures.makePermissionRequest(
            sessionId: "session-A",
            toolName: "Bash",
            toolInput: ["command": .string("npm install")],
            toolUseId: "tu-1"
        )
        manager.addRequest(first) { _ in }
        manager.createRule(from: manager.pendingRequests.first!)

        // Try to create same rule from a matching request
        let second = TestFixtures.makePermissionRequest(
            sessionId: "session-A",
            toolName: "Bash",
            toolInput: ["command": .string("npm test")],
            toolUseId: "tu-2"
        )
        manager.addRequest(second) { _ in }
        // The second request was auto-approved, but if it weren't:
        // creating a rule with the same label+session should not duplicate

        #expect(manager.allowRules.count == 1)
    }

    @Test("Multiple rules can coexist for same session")
    func multipleRulesPerSession() {
        let manager = PermissionManager(notifier: mockNotifier)

        // Create npm rule
        let npm = TestFixtures.makePermissionRequest(
            sessionId: "session-A",
            toolName: "Bash",
            toolInput: ["command": .string("npm install")],
            toolUseId: "tu-1"
        )
        manager.addRequest(npm) { _ in }
        manager.createRule(from: manager.pendingRequests.first!)

        // Create Edit rule
        let edit = TestFixtures.makePermissionRequest(
            sessionId: "session-A",
            toolName: "Edit",
            toolInput: ["file_path": .string("/src/app.tsx")],
            toolUseId: "tu-2"
        )
        manager.addRequest(edit) { _ in }
        manager.createRule(from: manager.pendingRequests.first!)

        #expect(manager.allowRules.count == 2)
    }

    // MARK: - Deduplication

    @Test("Duplicate toolUseId replaces previous request")
    func deduplicateRequest() {
        let manager = PermissionManager(notifier: mockNotifier)
        let oldDecision = Box<String>()
        let newDecision = Box<String>()

        let first = TestFixtures.makePermissionRequest(toolUseId: "dup-id")
        manager.addRequest(first) { response in
            oldDecision.set(response.hookSpecificOutput.permissionDecision)
        }

        let second = TestFixtures.makePermissionRequest(toolUseId: "dup-id")
        manager.addRequest(second) { response in
            newDecision.set(response.hookSpecificOutput.permissionDecision)
        }

        #expect(manager.pendingCount == 1)
        #expect(oldDecision.value == "ask") // old one gets fallback

        manager.approveById("dup-id")
        #expect(newDecision.value == "allow")
    }

    // MARK: - Auto-approved tools

    @Test("Auto-approved tools are immediately allowed")
    func autoApprovedTools() {
        let manager = PermissionManager(notifier: mockNotifier)
        let decision = Box<String>()

        let request = TestFixtures.makePermissionRequest(
            toolName: "Read",
            toolInput: ["file_path": .string("/tmp/test.txt")]
        )
        manager.addRequest(request) { response in
            decision.set(response.hookSpecificOutput.permissionDecision)
        }

        #expect(manager.pendingCount == 0)
        #expect(decision.value == "allow")
        #expect(mockNotifier.postedRequests.isEmpty)
    }
}
