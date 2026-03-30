@testable import Checkpoint
import Foundation
import Testing

@Suite("NotificationManager Summary")
struct NotificationSummaryTests {
    let manager = NotificationManager.shared

    @Test("Summary for Bash command")
    func bashCommand() {
        let request = TestFixtures.makePermissionRequest(
            toolName: "Bash",
            toolInput: ["command": .string("echo hello world")]
        )
        let summary = manager.summaryForRequest(request)
        #expect(summary == "echo hello world")
    }

    @Test("Summary truncates long commands")
    func longCommand() {
        let long = String(repeating: "a", count: 100)
        let request = TestFixtures.makePermissionRequest(
            toolName: "Bash",
            toolInput: ["command": .string(long)]
        )
        let summary = manager.summaryForRequest(request)
        #expect(summary.count == 80)
        #expect(summary.hasSuffix("..."))
    }

    @Test("Summary for Write with file path")
    func writeFilePath() {
        let request = TestFixtures.makePermissionRequest(
            toolName: "Write",
            toolInput: ["file_path": .string("/tmp/test.txt"), "content": .string("data")]
        )
        let summary = manager.summaryForRequest(request)
        #expect(summary == "Write /tmp/test.txt")
    }

    @Test("Summary for Grep with pattern")
    func grepPattern() {
        let request = TestFixtures.makePermissionRequest(
            toolName: "Grep",
            toolInput: ["pattern": .string("TODO")]
        )
        let summary = manager.summaryForRequest(request)
        #expect(summary == "Grep: TODO")
    }

    @Test("Summary fallback for unknown tool")
    func fallback() {
        let request = TestFixtures.makePermissionRequest(
            toolName: "CustomTool",
            toolInput: ["arg": .number(42)]
        )
        let summary = manager.summaryForRequest(request)
        #expect(summary == "CustomTool in /tmp/test")
    }
}
