import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let permissionManager = PermissionManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installSignalHandlers()
        NotificationManager.shared.setup(
            onApprove: { [weak self] toolUseId in
                Task { @MainActor in
                    self?.permissionManager.approveById(toolUseId)
                }
            },
            onCreateRule: { [weak self] toolUseId in
                Task { @MainActor in
                    self?.permissionManager.createRuleById(toolUseId)
                }
            },
            onDeny: { [weak self] toolUseId in
                Task { @MainActor in
                    self?.permissionManager.denyById(toolUseId)
                }
            },
            onTap: {
                Task { @MainActor in
                    NSApp.activate(ignoringOtherApps: true)
                    // The MenuBarExtra(.window) panel is an NSPanel in NSApp.windows
                    for window in NSApp.windows where window is NSPanel {
                        window.makeKeyAndOrderFront(nil)
                        break
                    }
                }
            }
        )
        HookConfigManager.removeStaleHooks()
        permissionManager.startServer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionManager.stopServer()
    }

    private func installSignalHandlers() {
        let handler: @convention(c) (Int32) -> Void = { _ in
            HookConfigManager.uninstall()
            exit(0)
        }
        signal(SIGTERM, handler)
        signal(SIGINT, handler)
    }
}
