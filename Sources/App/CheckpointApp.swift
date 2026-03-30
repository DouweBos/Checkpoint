import SwiftUI

@main
struct CheckpointApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            PermissionListView()
                .environment(appDelegate.permissionManager)
        } label: {
            MenuBarIconView(
                pendingCount: appDelegate.permissionManager.pendingCount,
                serverRunning: appDelegate.permissionManager.serverRunning,
                oldestRequestDate: appDelegate.permissionManager.pendingRequests.first?.receivedAt
            )
        }
        .menuBarExtraStyle(.window)
    }
}
