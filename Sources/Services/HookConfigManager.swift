import Foundation

enum HookConfigManager {
    nonisolated(unsafe) static var settingsURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("settings.json")
    }()

    private static let hookIdentifier = "http://localhost"
    private static let hookPathSuffix = "/claude-permissions"

    static func install(port: UInt16) {
        var settings = readSettings()

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var preToolUse = hooks["PreToolUse"] as? [[String: Any]] ?? []

        preToolUse.removeAll { entry in
            isOurHookEntry(entry)
        }

        let hookEntry: [String: Any] = [
            "matcher": "*",
            "hooks": [
                [
                    "type": "http",
                    "url": "http://localhost:\(port)/claude-permissions",
                    "timeout": Constants.hookTimeout
                ] as [String: Any]
            ]
        ]
        preToolUse.append(hookEntry)

        hooks["PreToolUse"] = preToolUse
        settings["hooks"] = hooks

        writeSettings(settings)
    }

    static func uninstall() {
        var settings = readSettings()

        guard var hooks = settings["hooks"] as? [String: Any],
              var preToolUse = hooks["PreToolUse"] as? [[String: Any]] else {
            return
        }

        preToolUse.removeAll { entry in
            isOurHookEntry(entry)
        }

        if preToolUse.isEmpty {
            hooks.removeValue(forKey: "PreToolUse")
        } else {
            hooks["PreToolUse"] = preToolUse
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        writeSettings(settings)
    }

    static func isOurHookEntry(_ entry: [String: Any]) -> Bool {
        guard let hooksList = entry["hooks"] as? [[String: Any]] else { return false }
        return hooksList.contains { hook in
            guard let type = hook["type"] as? String, type == "http",
                  let url = hook["url"] as? String else { return false }
            return url.hasPrefix(hookIdentifier) && url.hasSuffix(hookPathSuffix)
        }
    }

    /// Removes any hook entry whose port is no longer listening.
    /// Call on launch to clean up after a previous crash or force-quit.
    static func removeStaleHooks() {
        let settings = readSettings()
        guard let hooks = settings["hooks"] as? [String: Any],
              let preToolUse = hooks["PreToolUse"] as? [[String: Any]] else {
            return
        }

        let hasStale = preToolUse.contains { entry in
            isOurHookEntry(entry) && !isHookPortListening(entry)
        }

        if hasStale {
            uninstall()
        }
    }

    private static func isHookPortListening(_ entry: [String: Any]) -> Bool {
        guard let hooksList = entry["hooks"] as? [[String: Any]],
              let url = hooksList.first(where: { ($0["type"] as? String) == "http" })?["url"] as? String,
              let urlComponents = URLComponents(string: url),
              let port = urlComponents.port else {
            return false
        }

        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    static func readSettings() -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    static func writeSettings(_ settings: [String: Any]) {
        let dir = settingsURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let data = try? JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return }

        try? data.write(to: settingsURL, options: .atomic)
    }
}
