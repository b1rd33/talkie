import Foundation
import UserNotifications

@MainActor
protocol Notifying: AnyObject {
    func notify(title: String, body: String)
}

/// UserNotifications-backed notifier. Requests authorization lazily on first use.
@MainActor
final class Notifier: Notifying {
    private var authRequested = false

    func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        if !authRequested {
            authRequested = true
            center.requestAuthorization(options: [.alert]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                         content: content, trigger: nil))
    }
}
