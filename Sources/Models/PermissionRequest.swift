import Foundation

struct PermissionRequest: Codable, Sendable {
    let sessionId: String
    let transcriptPath: String
    let cwd: String
    let permissionMode: String
    let hookEventName: String
    let toolName: String
    let toolInput: [String: JSONValue]
    let toolUseId: String

    var allowRuleLabel: String {
        switch toolName {
        case "Bash":
            if let cmd = toolInput["command"]?.stringValue?.trimmingCharacters(in: .whitespaces),
               let binary = cmd.split(separator: " ", maxSplits: 1).first, !binary.isEmpty {
                return "\(toolName)(\(binary) *)"
            }
        case "Edit", "MultiEdit", "Write":
            if let filePath = toolInput["file_path"]?.stringValue {
                let ext = filePath.split(separator: ".").last.map(String.init)
                if let ext, ext != filePath, !ext.contains("/") {
                    return "\(toolName)(**/*.\(ext))"
                }
            }
        case "WebFetch":
            if let urlString = toolInput["url"]?.stringValue,
               let url = URL(string: urlString),
               let host = url.host {
                return "\(toolName)(domain:\(host))"
            }
        default:
            break
        }
        return toolName
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case permissionMode = "permission_mode"
        case hookEventName = "hook_event_name"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolUseId = "tool_use_id"
    }
}
