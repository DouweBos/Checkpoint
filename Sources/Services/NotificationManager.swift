import Foundation
import UserNotifications

protocol NotificationPosting: Sendable {
    func postPermissionNotification(for request: PermissionRequest)
}

final class NotificationManager: NSObject, @unchecked Sendable, UNUserNotificationCenterDelegate,
    NotificationPosting {
    static let shared = NotificationManager()

    static let approveAction = "APPROVE"
    static let approveSessionAction = "APPROVE_SESSION"
    static let denyAction = "DENY"
    static let categoryId = "PERMISSION_REQUEST"

    private var onApprove: ((String) -> Void)?
    private var onCreateRule: ((String) -> Void)?
    private var onDeny: ((String) -> Void)?
    private var onTap: (() -> Void)?

    func setup(
        onApprove: @escaping (String) -> Void,
        onCreateRule: @escaping (_ toolUseId: String) -> Void,
        onDeny: @escaping (String) -> Void,
        onTap: @escaping () -> Void
    ) {
        self.onApprove = onApprove
        self.onCreateRule = onCreateRule
        self.onDeny = onDeny
        self.onTap = onTap

        // UNUserNotificationCenter requires a valid bundle identifier
        guard Bundle.main.bundleIdentifier != nil else { return }

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let approve = UNNotificationAction(
            identifier: Self.approveAction,
            title: "Allow",
            options: []
        )
        let approveSession = UNNotificationAction(
            identifier: Self.approveSessionAction,
            title: "Always Allow",
            options: []
        )
        let deny = UNNotificationAction(
            identifier: Self.denyAction,
            title: "Deny",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [approve, approveSession, deny],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { _, _ in }
    }

    func postPermissionNotification(for request: PermissionRequest) {
        guard Bundle.main.bundleIdentifier != nil else { return }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted {
                        self.deliverNotification(for: request)
                    }
                }
            case .authorized, .provisional:
                self.deliverNotification(for: request)
            default:
                break
            }
        }
    }

    private func deliverNotification(for request: PermissionRequest) {
        let content = UNMutableNotificationContent()
        content.title = "Permission: \(request.toolName)"
        content.body = summaryForRequest(request)
        content.categoryIdentifier = Self.categoryId
        content.userInfo = [
            "toolUseId": request.toolUseId,
            "ruleLabel": request.allowRuleLabel
        ]
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let notifRequest = UNNotificationRequest(
            identifier: request.toolUseId,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(notifRequest)
    }

    func summaryForRequest(_ request: PermissionRequest) -> String {
        let input = request.toolInput
        let tool = request.toolName

        if let summary = toolSpecificSummary(tool: tool, input: input) {
            return summary
        }
        return "\(tool) in \(request.cwd)"
    }

    private func toolSpecificSummary(tool: String, input: [String: JSONValue]) -> String? {
        switch tool {
        case "Bash":
            return input["command"]?.stringValue.map { truncate($0, to: 80) }
        case "Edit", "MultiEdit", "Write":
            return input["file_path"]?.stringValue.map { "\(tool) \($0)" }
        case "Grep", "Glob":
            return input["pattern"]?.stringValue.map { "\(tool): \($0)" }
        case "WebFetch":
            return input["url"]?.stringValue.map { "WebFetch: \(truncate($0, to: 60))" }
        case "WebSearch":
            return input["query"]?.stringValue.map { "WebSearch: \($0)" }
        case "Agent":
            return agentSummary(input: input)
        default:
            return nil
        }
    }

    private func agentSummary(input: [String: JSONValue]) -> String {
        let agentType = input["subagent_type"]?.stringValue ?? "Agent"
        if let desc = input["description"]?.stringValue {
            return "\(agentType): \(truncate(desc, to: 80))"
        }
        return agentType
    }

    private func truncate(_ string: String, to limit: Int) -> String {
        string.count > limit ? String(string.prefix(limit - 3)) + "..." : string
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let toolUseId = userInfo["toolUseId"] as? String ?? ""

        switch response.actionIdentifier {
        case Self.approveAction:
            onApprove?(toolUseId)
        case Self.approveSessionAction:
            onCreateRule?(toolUseId)
        case Self.denyAction:
            onDeny?(toolUseId)
        default:
            onTap?()
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
