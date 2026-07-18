import Foundation
import UserNotifications

@MainActor
protocol Notifying: AnyObject {
    func notify(title: String, body: String)
    func notify(title: String, body: String, destination: NotificationDestination?)
}

extension Notifying {
    func notify(title: String, body: String, destination _: NotificationDestination?) {
        notify(title: title, body: body)
    }
}

/// UserNotifications-backed notifier. Requests authorization lazily on first use.
@MainActor
final class Notifier: Notifying {
    private var authRequested = false

    func notify(title: String, body: String) {
        notify(title: title, body: body, destination: nil)
    }

    func notify(title: String, body: String, destination: NotificationDestination?) {
        let center = UNUserNotificationCenter.current()
        if !authRequested {
            authRequested = true
            center.requestAuthorization(options: [.alert]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let destination {
            content.userInfo = ["talkie.action": destination.action]
        }
        center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                         content: content, trigger: nil))
    }
}
