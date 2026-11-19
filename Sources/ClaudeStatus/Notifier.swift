import ClaudeStatusCore
import Foundation
import UserNotifications
import os

// Public on purpose: NSLog output is redacted in the unified log, which would hide the one
// thing worth reading here (why notifications are not arriving). Read with:
//   log show --last 5m --predicate 'subsystem == "local.claude-status"'
private let log = Logger(subsystem: "local.claude-status", category: "notifications")

/// Posts a macOS notification when a session starts needing the user.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called on the main queue with the pid of the session whose notification was clicked.
    var onClick: ((Int32) -> Void)?

    /// The user has turned notifications off for this app. Read on the main queue.
    private(set) var isDenied = false

    private let center: UNUserNotificationCenter

    /// Nil outside an app bundle (e.g. `swift run`), where asking for the notification center raises.
    init?(bundle: Bundle = .main) {
        guard bundle.bundleIdentifier != nil else { return nil }
        center = .current()
        super.init()
        center.delegate = self
        center.requestAuthorization(options: [.alert]) { [weak self] granted, error in
            if let error {
                log.error("authorization failed: \(error.localizedDescription, privacy: .public)")
            } else {
                log.notice("authorization granted: \(granted, privacy: .public)")
            }
            self?.refreshStatus()
        }
    }

    func refreshStatus() {
        center.getNotificationSettings { [weak self] settings in
            let denied = settings.authorizationStatus == .denied
            DispatchQueue.main.async { self?.isDenied = denied }
        }
    }

    func post(_ event: AttentionEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        // The session name tells apart several sessions in the same folder.
        if let name = event.session.name, !name.isEmpty { content.subtitle = name }
        content.body = event.body
        content.userInfo = ["pid": Int(event.session.pid)]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                log.error("could not post notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // Without this, notifications are swallowed while ClaudeStatus is the active app
    // (for example while its menu is open).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let pid = response.notification.request.content.userInfo["pid"] as? Int
        DispatchQueue.main.async { [weak self] in
            if let pid { self?.onClick?(Int32(pid)) }
            completionHandler()
        }
    }
}
