import Foundation

/// Everything a service needs from the outside world, gathered in one value so tests can
/// replace it wholesale. `NetworkMonitorViewModel(dependencies:)` hands the parts to the
/// services it creates; every service init also accepts its own parts with live defaults.
public struct AppDependencies {
    public var defaults: UserDefaults
    public var clock: AppClock
    public var counterSource: any CounterSource
    public var notifications: any NotificationDelivering
    public var latencyProbe: any LatencyProbe
    public var pathSource: any PathStatusSource
    public var loginItems: any LoginItemControlling
    public var blobStore: any BlobStore
    /// Whether `ErrorHandler` mirrors its log into a file under Application Support.
    public var logToFile: Bool

    public init(
        defaults: UserDefaults,
        clock: AppClock,
        counterSource: any CounterSource,
        notifications: any NotificationDelivering,
        latencyProbe: any LatencyProbe,
        pathSource: any PathStatusSource,
        loginItems: any LoginItemControlling,
        blobStore: any BlobStore,
        logToFile: Bool
    ) {
        self.defaults = defaults
        self.clock = clock
        self.counterSource = counterSource
        self.notifications = notifications
        self.latencyProbe = latencyProbe
        self.pathSource = pathSource
        self.loginItems = loginItems
        self.blobStore = blobStore
        self.logToFile = logToFile
    }

    /// Production wiring. Computed, so each caller gets its own stateful `pathSource`.
    public static var live: AppDependencies {
        AppDependencies(
            defaults: .standard,
            clock: .live,
            counterSource: SystemCounterSource(),
            notifications: SystemNotificationDelivery(),
            latencyProbe: HTTPHeadProbe(),
            pathSource: SystemPathStatusSource(),
            loginItems: SystemLoginItemController(),
            blobStore: AppSupportBlobStore(),
            logToFile: true
        )
    }
}
