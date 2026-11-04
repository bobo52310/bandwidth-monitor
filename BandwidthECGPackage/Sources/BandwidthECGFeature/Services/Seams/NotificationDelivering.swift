import Foundation
import OSLog
import UserNotifications

/// Delivers user notifications. The production implementation talks to
/// `UNUserNotificationCenter`, which aborts the process when there is no app bundle
/// (as in a host-less test run), so services only ever see this protocol.
public protocol NotificationDelivering: Sendable {
    /// Asks the user for permission. Returns whether alerts are allowed.
    func requestAuthorization() async -> Bool
    func deliver(title: String, body: String, identifier: String) async throws
}

/// `UNUserNotificationCenter` is looked up inside each call, never stored, so merely creating
/// this value is safe in any environment.
public struct SystemNotificationDelivery: NotificationDelivering {
    private static let logger = Logger(subsystem: "com.bandwidthecg", category: "Notifications")

    public init() {}

    public func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.logger.error("Error requesting notification authorization: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    public func deliver(title: String, body: String, identifier: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Time-based trigger, delivered right away.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }
}

/// Shows notifications while the app is in front. Without a delegate the system shows nothing
/// then, which is exactly when "send test notification" is pressed (UI-P2-16).
/// `AppDelegate` sets one as the notification center's delegate at launch and keeps it.
public final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    public static let foregroundOptions: UNNotificationPresentationOptions = [.banner, .sound]

    public override init() {
        super.init()
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.foregroundOptions)
    }
}
