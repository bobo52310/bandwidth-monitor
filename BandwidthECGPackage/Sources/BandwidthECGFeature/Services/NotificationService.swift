import Foundation
import Observation
import OSLog

@MainActor
@Observable
public class NotificationService {
    public var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: "notificationsEnabled")
        }
    }

    public var threshold: Double {
        didSet {
            defaults.set(threshold, forKey: "notificationThreshold")
        }
    }

    /// Whether the system lets the app show alerts. Assumed until the first answer arrives.
    public private(set) var isAuthorized: Bool = true
    /// Why the last delivery failed; cleared by the next one that works.
    public private(set) var lastDeliveryError: String?

    private let defaults: UserDefaults
    private let clock: AppClock
    private let delivery: any NotificationDelivering
    private let logger = Logger(subsystem: "com.bandwidthecg", category: "Notifications")

    /// `clock.monotonic()` of the last alert. Elapsed time, not the wall clock: setting the clock
    /// back must not hold alerts back, and setting it forward must not end the cooldown.
    private var lastNotificationMonotonic: TimeInterval?
    private let cooldownInterval: TimeInterval = 3600 // 1 hour cooldown

    /// The authorization request started by `init`. Internal so tests can await it.
    @ObservationIgnored
    private(set) var authorizationTask: Task<Void, Never>?
    /// The most recent delivery started by this service. Internal so tests can await it.
    @ObservationIgnored
    private(set) var lastDeliveryTask: Task<Void, Never>?

    public init(
        defaults: UserDefaults = .standard,
        clock: AppClock = .live,
        delivery: any NotificationDelivering = SystemNotificationDelivery()
    ) {
        self.defaults = defaults
        self.clock = clock
        self.delivery = delivery
        self.isEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        self.threshold = defaults.double(forKey: "notificationThreshold")

        // Set default threshold to 95% if not set
        if threshold == 0 {
            threshold = 0.95
        }

        authorizationTask = Task { [weak self] in
            await self?.refreshAuthorization()
        }
    }

    /// Asks the system whether alerts are allowed. Once the user has answered, this does not
    /// prompt again; it picks up a change made in System Settings since.
    public func refreshAuthorization() async {
        let granted = await delivery.requestAuthorization()
        isAuthorized = granted
        if !granted {
            logger.notice("Notification permission denied")
        }
    }

    /// Check if should send notification based on cooldown
    private func shouldSendNotification() -> Bool {
        guard isEnabled else { return false }

        guard let lastTime = lastNotificationMonotonic else {
            return true
        }

        return clock.monotonic() - lastTime >= cooldownInterval
    }

    /// A plan speed that is safe to divide by and to convert to `Int`: finite and positive,
    /// capped at `UserPreferences.planSpeedRange.upperBound`. `nil` when the plan is unusable.
    private static func usablePlan(_ plan: Double) -> Double? {
        guard plan.isFinite, plan > 0 else { return nil }
        return min(plan, UserPreferences.planSpeedRange.upperBound)
    }

    /// Whole percent for display, capped at 9999 so an absurd ratio never reaches `Int()` unbounded.
    /// The caller has already established that `ratio` is not NaN.
    private static func displayPercentage(_ ratio: Double) -> Int {
        Int(min(ratio * 100, 9999))
    }

    /// Send notification when speed approaches plan limit
    public func checkAndNotify(
        downloadSpeed: Double,
        uploadSpeed: Double,
        downloadPlanSpeed: Double,
        uploadPlanSpeed: Double
    ) {
        guard shouldSendNotification() else { return }

        // A direction whose plan is zero, negative or not finite is skipped, never divided by.
        let downloadPlan = Self.usablePlan(downloadPlanSpeed)
        let uploadPlan = Self.usablePlan(uploadPlanSpeed)

        // The plans of the directions that reached the threshold; the title names one of them.
        var triggeredPlans: [Double] = []
        var message = ""

        if let downloadPlan {
            let downloadRatio = downloadSpeed / downloadPlan
            // NaN compares false here, so it can never reach the Int conversion.
            if downloadRatio >= threshold {
                triggeredPlans.append(downloadPlan)
                let percentage = Self.displayPercentage(downloadRatio)
                message = L10n.notificationDownloadReached(percentage, String(format: "%.1f", downloadSpeed))
            }
        }

        if let uploadPlan {
            let uploadRatio = uploadSpeed / uploadPlan
            if uploadRatio >= threshold {
                triggeredPlans.append(uploadPlan)
                let percentage = Self.displayPercentage(uploadRatio)
                if !message.isEmpty {
                    message += "\n"
                }
                message += L10n.notificationUploadReached(percentage, String(format: "%.1f", uploadSpeed))
            }
        }

        // The plan of the direction that was reached; the larger one when both were.
        if let titlePlan = triggeredPlans.max() {
            let title = L10n.notificationApproachingLimit(Int(titlePlan))
            sendNotification(title: title, body: message)
            lastNotificationMonotonic = clock.monotonic()
        }
    }

    /// Send a notification with given title and body
    private func sendNotification(title: String, body: String) {
        // Create a unique identifier
        let identifier = "peak-speed-alert-\(clock.now().timeIntervalSince1970)"

        lastDeliveryTask = Task { [weak self, delivery] in
            do {
                try await delivery.deliver(title: title, body: body, identifier: identifier)
                self?.lastDeliveryError = nil
            } catch {
                self?.logger.error("Error sending notification: \(String(describing: error), privacy: .public)")
                self?.lastDeliveryError = error.localizedDescription
            }
        }
    }

    /// Sends a test notification. It does not start the cooldown, so a real alert can still
    /// follow straight after it.
    public func sendTestNotification() {
        sendNotification(
            title: L10n.notificationTestTitle,
            body: L10n.notificationTestBody
        )
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
