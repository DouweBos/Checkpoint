import Foundation

struct PermissionResponse: Codable, Sendable {
    let hookSpecificOutput: HookOutput

    struct HookOutput: Codable, Sendable {
        let hookEventName: String
        let permissionDecision: String
        let permissionDecisionReason: String
        var updatedInput: [String: JSONValue]?
        var updatedPermissions: UpdatedPermissions?
    }

    /// Rules to persist in Claude Code's settings.json.
    /// When included in the hook response, Claude Code writes these rules so they
    /// survive beyond the current session. Requests matching a persisted allow rule
    /// are auto-approved by Claude Code itself — the hook is never called.
    struct UpdatedPermissions: Codable, Sendable {
        var allow: [String]?
        var deny: [String]?
    }

    init(
        decision: Decision,
        reason: String? = nil,
        updatedInput: [String: JSONValue]? = nil,
        updatedPermissions: UpdatedPermissions? = nil
    ) {
        hookSpecificOutput = HookOutput(
            hookEventName: "PreToolUse",
            permissionDecision: decision.rawValue,
            permissionDecisionReason: reason ?? decision.defaultReason,
            updatedInput: updatedInput,
            updatedPermissions: updatedPermissions
        )
    }

    enum Decision: String, Sendable {
        case allow
        case deny
        case ask

        var defaultReason: String {
            switch self {
            case .allow: "User approved"
            case .deny: "User denied"
            case .ask: "Fallback to CLI prompt"
            }
        }
    }
}
