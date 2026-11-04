import Foundation
import Observation

/// Counts events, not samples: staying near the plan for `approachSustainSeconds` is one event,
/// however long it lasts, and the next one needs the speed to fall well below first.
@Observable
public class PeakApproachTracker {
    public var todayApproachCount: Int = 0
    public var approachTimestamps: [Date] = []

    private enum State {
        /// Waiting for an event. `overSince` is when the current run of samples near the plan began.
        case armed(overSince: TimeInterval?)
        /// An event was counted. `underSince` is when the current run of low samples began.
        case latched(underSince: TimeInterval?)
    }

    private let userDefaults: UserDefaults
    private let clock: AppClock
    // Kept in memory only: a relaunch starts armed.
    @ObservationIgnored private var state = State.armed(overSince: nil)
    @ObservationIgnored private var lastSampleTime: TimeInterval?

    public init(defaults: UserDefaults = .standard, clock: AppClock = .live) {
        self.userDefaults = defaults
        self.clock = clock
        loadApproachData()
    }

    /// Feeds one sample. Returns `true` when this sample completes an approach event.
    @discardableResult
    public func checkForApproach(_ speed: NetworkSpeed, downloadPlanSpeed: Double, uploadPlanSpeed: Double) -> Bool {
        let now = clock.now()
        let calendar = clock.calendar
        let today = calendar.startOfDay(for: now)
        let lastRecordDate = userDefaults.object(forKey: "lastApproachRecordDate") as? Date ?? Date.distantPast

        // A new day resets the count only. A download running through midnight stays one event.
        if !calendar.isDate(lastRecordDate, inSameDayAs: today) {
            startNewDay(today)
        }

        let monotonic = clock.monotonic()
        if let lastSampleTime, monotonic - lastSampleTime > ReportRules.approachMaxGapSeconds {
            clearTimer()
        }
        lastSampleTime = monotonic

        let downloadRatio = speed.downloadMbps / downloadPlanSpeed
        let uploadRatio = speed.uploadMbps / uploadPlanSpeed

        switch state {
        case .armed(let overSince):
            guard downloadRatio >= ReportRules.approachRatio || uploadRatio >= ReportRules.approachRatio else {
                state = .armed(overSince: nil)
                return false
            }
            let start = overSince ?? monotonic
            guard monotonic - start >= ReportRules.approachSustainSeconds else {
                state = .armed(overSince: start)
                return false
            }
            state = .latched(underSince: nil)
            todayApproachCount += 1
            approachTimestamps.append(now)
            saveApproachData()
            return true

        case .latched(let underSince):
            guard downloadRatio < ReportRules.approachRearmRatio, uploadRatio < ReportRules.approachRearmRatio else {
                state = .latched(underSince: nil)
                return false
            }
            let start = underSince ?? monotonic
            let hasRearmed = monotonic - start >= ReportRules.approachRearmSeconds
            state = hasRearmed ? .armed(overSince: nil) : .latched(underSince: start)
            return false
        }
    }

    /// After a gap the timer in progress no longer describes consecutive samples.
    private func clearTimer() {
        switch state {
        case .armed: state = .armed(overSince: nil)
        case .latched: state = .latched(underSince: nil)
        }
    }

    public func resetApproachData() {
        todayApproachCount = 0
        approachTimestamps.removeAll()

        userDefaults.removeObject(forKey: "todayApproachCount")
        userDefaults.removeObject(forKey: "approachTimestamps")
        userDefaults.removeObject(forKey: "lastApproachRecordDate")
    }

    private func saveApproachData() {
        userDefaults.set(todayApproachCount, forKey: "todayApproachCount")

        // Save timestamps as array of TimeInterval
        let timestampIntervals = approachTimestamps.map { $0.timeIntervalSince1970 }
        userDefaults.set(timestampIntervals, forKey: "approachTimestamps")
    }

    private func loadApproachData() {
        let calendar = clock.calendar
        let today = calendar.startOfDay(for: clock.now())
        let lastRecordDate = userDefaults.object(forKey: "lastApproachRecordDate") as? Date ?? Date.distantPast

        // Load approach data if it's the same day
        if calendar.isDate(lastRecordDate, inSameDayAs: today) {
            todayApproachCount = userDefaults.integer(forKey: "todayApproachCount")

            // Load timestamps
            if let timestampIntervals = userDefaults.array(forKey: "approachTimestamps") as? [Double] {
                approachTimestamps = timestampIntervals.map { Date(timeIntervalSince1970: $0) }
            }
        } else {
            startNewDay(today)
        }
    }

    /// Yesterday's keys go too. If they stayed, a launch that records nothing would move the
    /// date forward and the next launch would read them as today's.
    private func startNewDay(_ today: Date) {
        todayApproachCount = 0
        approachTimestamps.removeAll()
        userDefaults.removeObject(forKey: "todayApproachCount")
        userDefaults.removeObject(forKey: "approachTimestamps")
        userDefaults.set(today, forKey: "lastApproachRecordDate")
    }

    /// One formatter for every call: the popover asks for these on each redraw.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()

    public func getFormattedApproachTimes() -> [String] {
        approachTimestamps.map { Self.timeFormatter.string(from: $0) }
    }
}