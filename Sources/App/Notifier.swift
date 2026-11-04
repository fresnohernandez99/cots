import AppKit
import CotsCore
import UserNotifications

/// macOS notifications for session notes handed back when a new session starts in the
/// same project. Clicking one opens the note in the expanded window.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    var onOpen: ((String) -> Void)?

    /// Notifications need a bundle; dev binaries and snapshot runs skip them.
    private var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }

    func setUp() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ note: Note) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        let topic = note.meta.topic ?? ""
        content.title = String(localized: "Pendiente en \(topic)")
        content.subtitle = note.meta.session?.ended == nil
            ? String(localized: "La última sesión se interrumpió")
            : String(localized: "La última sesión se cerró")
        content.body = note.title
        content.sound = .default
        content.userInfo = ["id": note.id]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: note.id, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["id"] as? String else { return }
        await MainActor.run { onOpen?(id) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
