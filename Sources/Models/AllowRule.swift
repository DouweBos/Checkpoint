import Foundation

/// A pattern-based permission rule scoped to a session.
///
/// Unlike the old blanket session rules, an `AllowRule` matches only requests
/// whose tool name and content (command prefix, file extension, or domain)
/// match the pattern that was active when the rule was created.
struct AllowRule: Identifiable, Sendable {
    let id: UUID
    let sessionId: String
    let label: String
    let toolName: String
    let contentMatcher: ContentMatcher?
    let grantedAt: Date

    enum ContentMatcher: Sendable, Equatable {
        /// Bash: matches commands whose first token equals the stored binary.
        case commandPrefix(String)
        /// Edit / Write / MultiEdit / NotebookEdit: matches file paths ending with the stored extension.
        case fileExtension(String)
        /// WebFetch: matches URLs whose host equals the stored domain.
        case domain(String)
    }

    /// Returns `true` when the incoming request should be auto-approved by this rule.
    func matches(_ request: PermissionRequest) -> Bool {
        guard request.sessionId == sessionId,
              request.toolName == toolName else { return false }

        guard let matcher = contentMatcher else { return true }

        switch matcher {
        case .commandPrefix(let binary):
            guard let cmd = request.toolInput["command"]?.stringValue?
                .trimmingCharacters(in: .whitespaces) else { return false }
            return cmd == binary || cmd.hasPrefix(binary + " ")

        case .fileExtension(let ext):
            guard let path = request.toolInput["file_path"]?.stringValue else { return false }
            return path.hasSuffix(".\(ext)")

        case .domain(let host):
            guard let urlStr = request.toolInput["url"]?.stringValue,
                  let url = URL(string: urlStr),
                  let reqHost = url.host else { return false }
            return reqHost == host
        }
    }

    /// Creates a rule by extracting the pattern from the request that triggered it.
    static func from(_ request: PermissionRequest) -> AllowRule {
        let matcher: ContentMatcher?

        switch request.toolName {
        case "Bash":
            if let cmd = request.toolInput["command"]?.stringValue?
                .trimmingCharacters(in: .whitespaces),
               let binary = cmd.split(separator: " ", maxSplits: 1).first,
               !binary.isEmpty {
                matcher = .commandPrefix(String(binary))
            } else {
                matcher = nil
            }

        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            if let path = request.toolInput["file_path"]?.stringValue,
               let ext = path.split(separator: ".").last.map(String.init),
               ext != path, !ext.contains("/") {
                matcher = .fileExtension(ext)
            } else {
                matcher = nil
            }

        case "WebFetch":
            if let urlStr = request.toolInput["url"]?.stringValue,
               let url = URL(string: urlStr),
               let host = url.host {
                matcher = .domain(host)
            } else {
                matcher = nil
            }

        default:
            matcher = nil
        }

        return AllowRule(
            id: UUID(),
            sessionId: request.sessionId,
            label: request.allowRuleLabel,
            toolName: request.toolName,
            contentMatcher: matcher,
            grantedAt: Date()
        )
    }
}
