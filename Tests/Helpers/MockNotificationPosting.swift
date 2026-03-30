@testable import Checkpoint
import Foundation

final class MockNotificationPosting: NotificationPosting, @unchecked Sendable {
    private(set) var postedRequests: [PermissionRequest] = []
    private let lock = NSLock()

    func postPermissionNotification(for request: PermissionRequest) {
        lock.lock()
        postedRequests.append(request)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        postedRequests.removeAll()
        lock.unlock()
    }
}
