@testable import Checkpoint
import Foundation
import Testing

@Suite("PermissionRequest")
struct PermissionRequestTests {
    @Test("Decode from JSON")
    func decodeFromJSON() throws {
        let request = try JSONDecoder().decode(
            PermissionRequest.self,
            from: TestFixtures.sampleHookJSON
        )

        #expect(request.sessionId == "abc123")
        #expect(request.transcriptPath == "/tmp/transcript.txt")
        #expect(request.cwd == "/Users/test/project")
        #expect(request.permissionMode == "ask")
        #expect(request.hookEventName == "PreToolUse")
        #expect(request.toolName == "Write")
        #expect(request.toolUseId == "tu_12345")
        #expect(request.toolInput["file_path"]?.stringValue == "/tmp/test.txt")
        #expect(request.toolInput["content"]?.stringValue == "hello world")
    }

    @Test("Decode with nested tool input")
    func decodeNestedToolInput() throws {
        let json: [String: Any] = [
            "session_id": "s1",
            "transcript_path": "/t",
            "cwd": "/c",
            "permission_mode": "ask",
            "hook_event_name": "PreToolUse",
            "tool_name": "Bash",
            "tool_input": [
                "command": "echo hello",
                "timeout": 30
            ],
            "tool_use_id": "tu1"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let request = try JSONDecoder().decode(PermissionRequest.self, from: data)

        #expect(request.toolName == "Bash")
        #expect(request.toolInput["command"]?.stringValue == "echo hello")
        if case .number(30) = request.toolInput["timeout"] {
            // pass
        } else {
            Issue.record("Expected number 30 for timeout")
        }
    }

    // MARK: - allowRuleLabel

    @Test("allowRuleLabel extracts binary for Bash")
    func allowRuleLabelBash() {
        let request = TestFixtures.makePermissionRequest(
            toolName: "Bash",
            toolInput: ["command": .string("npm install")]
        )
        #expect(request.allowRuleLabel == "Bash(npm *)")
    }

    @Test("allowRuleLabel extracts extension for Edit")
    func allowRuleLabelEdit() {
        let request = TestFixtures.makePermissionRequest(
            toolName: "Edit",
            toolInput: ["file_path": .string("/src/app.tsx")]
        )
        #expect(request.allowRuleLabel == "Edit(**/*.tsx)")
    }

    @Test("allowRuleLabel extracts extension for Write")
    func allowRuleLabelWrite() {
        let request = TestFixtures.makePermissionRequest(
            toolName: "Write",
            toolInput: ["file_path": .string("/tmp/config.json")]
        )
        #expect(request.allowRuleLabel == "Write(**/*.json)")
    }

    @Test("allowRuleLabel falls back to tool name for extensionless file")
    func allowRuleLabelNoExtension() {
        let request = TestFixtures.makePermissionRequest(
            toolName: "Write",
            toolInput: ["file_path": .string("/tmp/Makefile")]
        )
        #expect(request.allowRuleLabel == "Write")
    }

    @Test("allowRuleLabel extracts host for WebFetch")
    func allowRuleLabelWebFetch() {
        let request = TestFixtures.makePermissionRequest(
            toolName: "WebFetch",
            toolInput: ["url": .string("https://docs.example.com/api")]
        )
        #expect(request.allowRuleLabel == "WebFetch(domain:docs.example.com)")
    }

    @Test("allowRuleLabel falls back to tool name for unknown tool")
    func allowRuleLabelUnknown() {
        let request = TestFixtures.makePermissionRequest(
            toolName: "CustomTool",
            toolInput: ["arg": .string("value")]
        )
        #expect(request.allowRuleLabel == "CustomTool")
    }

    @Test("allowRuleLabel falls back for Bash with empty command")
    func allowRuleLabelBashEmpty() {
        let request = TestFixtures.makePermissionRequest(
            toolName: "Bash",
            toolInput: ["command": .string("   ")]
        )
        #expect(request.allowRuleLabel == "Bash")
    }

    // MARK: - Encode/Decode

    @Test("Encode roundtrip")
    func encodeRoundtrip() throws {
        let original = try JSONDecoder().decode(
            PermissionRequest.self,
            from: TestFixtures.sampleHookJSON
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PermissionRequest.self, from: encoded)

        #expect(decoded.sessionId == original.sessionId)
        #expect(decoded.toolName == original.toolName)
        #expect(decoded.toolUseId == original.toolUseId)
        #expect(decoded.cwd == original.cwd)
    }
}
