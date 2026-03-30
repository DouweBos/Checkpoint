@testable import Checkpoint
import Foundation
import Testing

@Suite("AllowRule")
struct AllowRuleTests {
    // MARK: - Factory

    @Test("Creates command prefix matcher for Bash")
    func bashCommandPrefix() {
        let request = TestFixtures.makePermissionRequest(
            toolName: "Bash",
            toolInput: ["command": .string("npm install lodash")]
        )
        let rule = AllowRule.from(request)

        #expect(rule.toolName == "Bash")
        #expect(rule.label == "Bash(npm *)")
        #expect(rule.contentMatcher == .commandPrefix("npm"))
    }

    @Test("Creates file extension matcher for Edit")
    func editFileExtension() {
        let request = TestFixtures.makePermissionRequest(
            toolName: "Edit",
            toolInput: ["file_path": .string("/src/components/App.tsx")]
        )
        let rule = AllowRule.from(request)

        #expect(rule.toolName == "Edit")
        #expect(rule.label == "Edit(**/*.tsx)")
        #expect(rule.contentMatcher == .fileExtension("tsx"))
    }

    @Test("Creates domain matcher for WebFetch")
    func webFetchDomain() {
        let request = TestFixtures.makePermissionRequest(
            toolName: "WebFetch",
            toolInput: ["url": .string("https://docs.example.com/api/v2")]
        )
        let rule = AllowRule.from(request)

        #expect(rule.toolName == "WebFetch")
        #expect(rule.label == "WebFetch(domain:docs.example.com)")
        #expect(rule.contentMatcher == .domain("docs.example.com"))
    }

    @Test("Creates nil matcher for unknown tool")
    func unknownToolNilMatcher() {
        let request = TestFixtures.makePermissionRequest(
            toolName: "mcp__linear__save_issue",
            toolInput: ["title": .string("Fix bug")]
        )
        let rule = AllowRule.from(request)

        #expect(rule.toolName == "mcp__linear__save_issue")
        #expect(rule.contentMatcher == nil)
    }

    @Test("Creates nil matcher for Bash with empty command")
    func bashEmptyCommand() {
        let request = TestFixtures.makePermissionRequest(
            toolName: "Bash",
            toolInput: ["command": .string("   ")]
        )
        let rule = AllowRule.from(request)
        #expect(rule.contentMatcher == nil)
    }

    @Test("Creates nil matcher for Write with extensionless file")
    func writeNoExtension() {
        let request = TestFixtures.makePermissionRequest(
            toolName: "Write",
            toolInput: ["file_path": .string("/tmp/Makefile")]
        )
        let rule = AllowRule.from(request)
        #expect(rule.contentMatcher == nil)
    }

    @Test("Creates file extension matcher for NotebookEdit")
    func notebookEditExtension() {
        let request = TestFixtures.makePermissionRequest(
            toolName: "NotebookEdit",
            toolInput: ["file_path": .string("/notebooks/analysis.ipynb")]
        )
        let rule = AllowRule.from(request)

        #expect(rule.toolName == "NotebookEdit")
        #expect(rule.contentMatcher == .fileExtension("ipynb"))
    }

    // MARK: - Matching

    @Test("Matches same tool and command prefix")
    func matchesBashPrefix() {
        let rule = makeRule(
            sessionId: "s1", toolName: "Bash", matcher: .commandPrefix("npm")
        )
        let request = TestFixtures.makePermissionRequest(
            sessionId: "s1",
            toolName: "Bash",
            toolInput: ["command": .string("npm test --coverage")]
        )
        #expect(rule.matches(request))
    }

    @Test("Matches exact binary with no arguments")
    func matchesExactBinary() {
        let rule = makeRule(
            sessionId: "s1", toolName: "Bash", matcher: .commandPrefix("npm")
        )
        let request = TestFixtures.makePermissionRequest(
            sessionId: "s1",
            toolName: "Bash",
            toolInput: ["command": .string("npm")]
        )
        #expect(rule.matches(request))
    }

    @Test("Does not match different binary")
    func doesNotMatchDifferentBinary() {
        let rule = makeRule(
            sessionId: "s1", toolName: "Bash", matcher: .commandPrefix("npm")
        )
        let request = TestFixtures.makePermissionRequest(
            sessionId: "s1",
            toolName: "Bash",
            toolInput: ["command": .string("npx create-react-app")]
        )
        #expect(!rule.matches(request))
    }

    @Test("Does not match partial binary prefix")
    func doesNotMatchPartialPrefix() {
        let rule = makeRule(
            sessionId: "s1", toolName: "Bash", matcher: .commandPrefix("npm")
        )
        let request = TestFixtures.makePermissionRequest(
            sessionId: "s1",
            toolName: "Bash",
            toolInput: ["command": .string("npmrc-edit config")]
        )
        #expect(!rule.matches(request))
    }

    @Test("Matches same file extension")
    func matchesFileExtension() {
        let rule = makeRule(
            sessionId: "s1", toolName: "Edit", matcher: .fileExtension("tsx")
        )
        let request = TestFixtures.makePermissionRequest(
            sessionId: "s1",
            toolName: "Edit",
            toolInput: ["file_path": .string("/src/other/Component.tsx")]
        )
        #expect(rule.matches(request))
    }

    @Test("Does not match different file extension")
    func doesNotMatchDifferentExtension() {
        let rule = makeRule(
            sessionId: "s1", toolName: "Edit", matcher: .fileExtension("tsx")
        )
        let request = TestFixtures.makePermissionRequest(
            sessionId: "s1",
            toolName: "Edit",
            toolInput: ["file_path": .string("/src/styles.css")]
        )
        #expect(!rule.matches(request))
    }

    @Test("Matches same domain")
    func matchesDomain() {
        let rule = makeRule(
            sessionId: "s1", toolName: "WebFetch", matcher: .domain("docs.example.com")
        )
        let request = TestFixtures.makePermissionRequest(
            sessionId: "s1",
            toolName: "WebFetch",
            toolInput: ["url": .string("https://docs.example.com/other/page")]
        )
        #expect(rule.matches(request))
    }

    @Test("Does not match different domain")
    func doesNotMatchDifferentDomain() {
        let rule = makeRule(
            sessionId: "s1", toolName: "WebFetch", matcher: .domain("docs.example.com")
        )
        let request = TestFixtures.makePermissionRequest(
            sessionId: "s1",
            toolName: "WebFetch",
            toolInput: ["url": .string("https://evil.example.com/phish")]
        )
        #expect(!rule.matches(request))
    }

    @Test("Does not match different session")
    func doesNotMatchDifferentSession() {
        let rule = makeRule(
            sessionId: "s1", toolName: "Bash", matcher: .commandPrefix("npm")
        )
        let request = TestFixtures.makePermissionRequest(
            sessionId: "s2",
            toolName: "Bash",
            toolInput: ["command": .string("npm test")]
        )
        #expect(!rule.matches(request))
    }

    @Test("Does not match different tool name")
    func doesNotMatchDifferentTool() {
        let rule = makeRule(
            sessionId: "s1", toolName: "Edit", matcher: .fileExtension("tsx")
        )
        let request = TestFixtures.makePermissionRequest(
            sessionId: "s1",
            toolName: "Write",
            toolInput: ["file_path": .string("/src/new.tsx")]
        )
        #expect(!rule.matches(request))
    }

    @Test("Nil matcher matches any content for same tool and session")
    func nilMatcherMatchesAny() {
        let rule = makeRule(
            sessionId: "s1", toolName: "mcp__linear__save_issue", matcher: nil
        )
        let request = TestFixtures.makePermissionRequest(
            sessionId: "s1",
            toolName: "mcp__linear__save_issue",
            toolInput: ["title": .string("anything")]
        )
        #expect(rule.matches(request))
    }

    // MARK: - Helpers

    private func makeRule(
        sessionId: String,
        toolName: String,
        matcher: AllowRule.ContentMatcher?
    ) -> AllowRule {
        AllowRule(
            id: UUID(),
            sessionId: sessionId,
            label: "\(toolName)(*)",
            toolName: toolName,
            contentMatcher: matcher,
            grantedAt: Date()
        )
    }
}
