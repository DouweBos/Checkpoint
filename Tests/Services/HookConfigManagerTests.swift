@testable import Checkpoint
import Foundation
import Testing

@Suite("HookConfigManager", .serialized)
struct HookConfigManagerTests {
    private let tempDir: URL
    private let settingsURL: URL
    private let originalURL: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-permissions-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        settingsURL = tempDir.appendingPathComponent("settings.json")

        originalURL = HookConfigManager.settingsURL
        HookConfigManager.settingsURL = settingsURL
    }

    // MARK: - Install

    @Test("Install creates settings file when none exists")
    func installCreatesFile() {
        HookConfigManager.install(port: 19275)

        let settings = HookConfigManager.readSettings()
        let hooks = settings["hooks"] as? [String: Any]
        let preToolUse = hooks?["PreToolUse"] as? [[String: Any]]

        #expect(preToolUse?.count == 1)

        let entry = preToolUse?.first
        let hooksList = entry?["hooks"] as? [[String: Any]]
        let hook = hooksList?.first

        #expect(hook?["type"] as? String == "http")
        #expect(hook?["url"] as? String == "http://localhost:19275/claude-permissions")
        #expect(hook?["timeout"] as? Int == Constants.hookTimeout)
        #expect(entry?["matcher"] as? String == "*")

        cleanup()
    }

    @Test("Install preserves existing settings")
    func installPreservesExisting() throws {
        let existing: [String: Any] = [
            "permissions": ["allow": ["Bash(git:*)"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: existing)
        try data.write(to: settingsURL)

        HookConfigManager.install(port: 19275)

        let settings = HookConfigManager.readSettings()
        let permissions = settings["permissions"] as? [String: Any]
        let allow = permissions?["allow"] as? [String]
        #expect(allow == ["Bash(git:*)"])
        #expect(settings["hooks"] != nil)

        cleanup()
    }

    @Test("Install replaces existing hook entry")
    func installReplacesExisting() {
        HookConfigManager.install(port: 19275)
        HookConfigManager.install(port: 19276)

        let settings = HookConfigManager.readSettings()
        let hooks = settings["hooks"] as? [String: Any]
        let preToolUse = hooks?["PreToolUse"] as? [[String: Any]]

        #expect(preToolUse?.count == 1)

        let hooksList = preToolUse?.first?["hooks"] as? [[String: Any]]
        #expect(hooksList?.first?["url"] as? String == "http://localhost:19276/claude-permissions")

        cleanup()
    }

    @Test("Install preserves other PreToolUse hooks")
    func installPreservesOtherHooks() throws {
        let existing: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    [
                        "matcher": "Write",
                        "hooks": [
                            ["type": "command", "command": "echo test"]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: existing)
        try data.write(to: settingsURL)

        HookConfigManager.install(port: 19275)

        let settings = HookConfigManager.readSettings()
        let hooks = settings["hooks"] as? [String: Any]
        let preToolUse = hooks?["PreToolUse"] as? [[String: Any]]

        #expect(preToolUse?.count == 2)

        cleanup()
    }

    // MARK: - Uninstall

    @Test("Uninstall removes hook entry")
    func uninstallRemovesEntry() {
        HookConfigManager.install(port: 19275)
        HookConfigManager.uninstall()

        let settings = HookConfigManager.readSettings()
        #expect(settings["hooks"] == nil)

        cleanup()
    }

    @Test("Uninstall preserves other hooks")
    func uninstallPreservesOthers() throws {
        let existing: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    [
                        "matcher": "Write",
                        "hooks": [
                            ["type": "command", "command": "echo test"]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: existing)
        try data.write(to: settingsURL)

        HookConfigManager.install(port: 19275)
        HookConfigManager.uninstall()

        let settings = HookConfigManager.readSettings()
        let hooks = settings["hooks"] as? [String: Any]
        let preToolUse = hooks?["PreToolUse"] as? [[String: Any]]
        #expect(preToolUse?.count == 1)

        let entry = preToolUse?.first
        let hooksList = entry?["hooks"] as? [[String: Any]]
        #expect(hooksList?.first?["type"] as? String == "command")

        cleanup()
    }

    @Test("Uninstall does nothing when no settings file")
    func uninstallNoFile() {
        HookConfigManager.uninstall()
        #expect(!FileManager.default.fileExists(atPath: settingsURL.path))

        cleanup()
    }

    // MARK: - isOurHookEntry

    @Test("Identifies our hook entry")
    func identifiesOurEntry() {
        let entry: [String: Any] = [
            "matcher": "*",
            "hooks": [
                ["type": "http", "url": "http://localhost:19275/claude-permissions", "timeout": Constants.hookTimeout]
            ]
        ]
        #expect(HookConfigManager.isOurHookEntry(entry))

        cleanup()
    }

    @Test("Does not match command hooks")
    func doesNotMatchCommandHooks() {
        let entry: [String: Any] = [
            "matcher": "Write",
            "hooks": [
                ["type": "command", "command": "echo test"]
            ]
        ]
        #expect(!HookConfigManager.isOurHookEntry(entry))

        cleanup()
    }

    // MARK: - removeStaleHooks

    @Test("removeStaleHooks removes hook when port is not listening")
    func removeStaleHooksRemovesWhenNotListening() {
        // Install a hook on a port that nothing is listening on
        HookConfigManager.install(port: 19299)

        let before = HookConfigManager.readSettings()
        let hooksBefore = before["hooks"] as? [String: Any]
        #expect(hooksBefore?["PreToolUse"] != nil)

        HookConfigManager.removeStaleHooks()

        let after = HookConfigManager.readSettings()
        #expect(after["hooks"] == nil)

        cleanup()
    }

    @Test("removeStaleHooks keeps hook when port is listening")
    func removeStaleHooksKeepsWhenListening() throws {
        let server = try HookServer(port: 19298)
        server.start()

        HookConfigManager.install(port: 19298)

        HookConfigManager.removeStaleHooks()

        let settings = HookConfigManager.readSettings()
        let hooks = settings["hooks"] as? [String: Any]
        let preToolUse = hooks?["PreToolUse"] as? [[String: Any]]
        #expect(preToolUse?.count == 1)

        server.stop()
        cleanup()
    }

    @Test("removeStaleHooks preserves non-hook settings")
    func removeStaleHooksPreservesOtherSettings() throws {
        let existing: [String: Any] = [
            "permissions": ["allow": ["Bash(git:*)"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: existing)
        try data.write(to: settingsURL)

        HookConfigManager.install(port: 19299)
        HookConfigManager.removeStaleHooks()

        let settings = HookConfigManager.readSettings()
        let permissions = settings["permissions"] as? [String: Any]
        let allow = permissions?["allow"] as? [String]
        #expect(allow == ["Bash(git:*)"])

        cleanup()
    }

    @Test("removeStaleHooks does nothing when no hooks exist")
    func removeStaleHooksNoHooks() {
        HookConfigManager.removeStaleHooks()
        #expect(!FileManager.default.fileExists(atPath: settingsURL.path))

        cleanup()
    }

    // MARK: - Cleanup

    private func cleanup() {
        HookConfigManager.settingsURL = originalURL
        try? FileManager.default.removeItem(at: tempDir)
    }
}
