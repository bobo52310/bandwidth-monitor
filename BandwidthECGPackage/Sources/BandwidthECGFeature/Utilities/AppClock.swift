import Foundation

/// Injectable time source shared by every service.
///
/// `now` is wall-clock time (changes when the user changes the system clock or time zone),
/// `monotonic` is seconds since an arbitrary origin and keeps counting while the Mac sleeps
/// (so it can be used to detect sleep gaps), and `calendar` decides where a day starts.
public struct AppClock: Sendable {
    public var now: @Sendable () -> Date
    /// Seconds since an arbitrary origin, including time spent asleep.
    public var monotonic: @Sendable () -> TimeInterval
    public var calendar: Calendar

    public init(
        now: @escaping @Sendable () -> Date,
        monotonic: @escaping @Sendable () -> TimeInterval,
        calendar: Calendar
    ) {
        self.now = now
        self.monotonic = monotonic
        self.calendar = calendar
    }

    public static let live: AppClock = {
        let origin = ContinuousClock.now
        return AppClock(
            now: { Date() },
            monotonic: {
                let elapsed = ContinuousClock.now - origin
                return Double(elapsed.components.seconds)
                    + Double(elapsed.components.attoseconds) / 1e18
            },
            calendar: .autoupdatingCurrent
        )
    }()
}
