@testable import Checkpoint
import Foundation

enum TestFixtures {
    static func makePermissionRequest(
        sessionId: String = "test-session-123",
        transcriptPath: String = "/tmp/transcript.txt",
        cwd: String = "/tmp/test",
        permissionMode: String = "ask",
        hookEventName: String = "PreToolUse",
        toolName: String = "Bash",
        toolInput: [String: JSONValue] = ["command": .string("echo hello")],
        toolUseId: String = "tool-use-\(UUID().uuidString)"
    ) -> PermissionRequest {
        PermissionRequest(
            sessionId: sessionId,
            transcriptPath: transcriptPath,
            cwd: cwd,
            permissionMode: permissionMode,
            hookEventName: hookEventName,
            toolName: toolName,
            toolInput: toolInput,
            toolUseId: toolUseId
        )
    }

    static let sampleHookJSON: Data = {
        let json: [String: Any] = [
            "session_id": "abc123",
            "transcript_path": "/tmp/transcript.txt",
            "cwd": "/Users/test/project",
            "permission_mode": "ask",
            "hook_event_name": "PreToolUse",
            "tool_name": "Write",
            "tool_input": [
                "file_path": "/tmp/test.txt",
                "content": "hello world"
            ],
            "tool_use_id": "tu_12345"
        ]
        return try! JSONSerialization.data(withJSONObject: json) // swiftlint:disable:this force_try
    }()

    static let sampleHTTPRequest: String = {
        let body = String(data: sampleHookJSON, encoding: .utf8)!
        return "POST /claude-permissions HTTP/1.1\r\n" +
            "Host: localhost\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: \(sampleHookJSON.count)\r\n" +
            "\r\n" +
            body
    }()
}
