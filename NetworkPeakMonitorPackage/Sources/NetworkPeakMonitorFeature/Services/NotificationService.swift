import Foundation
import UserNotifications

@MainActor
public class NotificationService: ObservableObject {
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "notificationsEnabled")
        }
    }

    @Published public var threshold: Double {
        didSet {
            UserDefaults.standard.set(threshold, forKey: "notificationThreshold")
        }
    }

    private var lastNotificationTime: Date?
    private let cooldownInterval: TimeInterval = 3600 // 1 hour cooldown

    public init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        self.threshold = UserDefaults.standard.double(forKey: "notificationThreshold")

        // Set default threshold to 95% if not set
        if threshold == 0 {
            threshold = 0.95
        }

        Task {
            await requestAuthorization()
        }
    }

    /// Request notification authorization from the user
    private func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if !granted {
                print("Notification permission denied")
            }
        } catch {
            print("Error requesting notification authorization: \(error)")
        }
    }

    /// Check if should send notification based on cooldown
    private func shouldSendNotification() -> Bool {
        guard isEnabled else { return false }

        guard let lastTime = lastNotificationTime else {
            return true
        }

        let timeSinceLastNotification = Date().timeIntervalSince(lastTime)
        return timeSinceLastNotification >= cooldownInterval
    }

    /// Send notification when speed approaches plan limit
    public func checkAndNotify(
        downloadSpeed: Double,
        uploadSpeed: Double,
        downloadPlanSpeed: Double,
        uploadPlanSpeed: Double
    ) {
        guard shouldSendNotification() else { return }

        let downloadRatio = downloadSpeed / downloadPlanSpeed
        let uploadRatio = uploadSpeed / uploadPlanSpeed

        var shouldNotify = false
        var message = ""

        if downloadRatio >= threshold {
            shouldNotify = true
            let percentage = Int(downloadRatio * 100)
            message = "下載速度已達到方案上限的 \(percentage)% (\(String(format: "%.1f", downloadSpeed)) Mbps)"
        }

        if uploadRatio >= threshold {
            shouldNotify = true
            let percentage = Int(uploadRatio * 100)
            if !message.isEmpty {
                message += "\n"
            }
            message += "上傳速度已達到方案上限的 \(percentage)% (\(String(format: "%.1f", uploadSpeed)) Mbps)"
        }

        if shouldNotify {
            sendNotification(title: "網路速度接近上限", body: message)
            lastNotificationTime = Date()
        }
    }

    /// Send a notification with given title and body
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = 1

        // Create a time-based trigger (deliver immediately)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        // Create a unique identifier
        let identifier = "peak-speed-alert-\(Date().timeIntervalSince1970)"

        // Create the request
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        // Add the request to the notification center
        let center = UNUserNotificationCenter.current()
        center.add(request) { error in
            if let error = error {
                print("Error sending notification: \(error)")
            }
        }
    }

    /// Manually send a test notification
    public func sendTestNotification() {
        sendNotification(
            title: "測試通知",
            body: "這是一個測試通知，用來確認通知功能正常運作。"
        )
        lastNotificationTime = Date()
    }

    /// Clear notification badge
    public func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    /// Get available threshold options
    public static let thresholdOptions: [(label: String, value: Double)] = [
        ("90%", 0.90),
        ("95%", 0.95),
        ("98%", 0.98)
    ]

    /// Get formatted threshold percentage
    public var formattedThreshold: String {
        return "\(Int(threshold * 100))%"
    }
}
