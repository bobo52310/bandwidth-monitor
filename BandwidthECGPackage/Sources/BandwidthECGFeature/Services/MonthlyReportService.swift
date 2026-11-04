import Foundation

/// Derives monthly reports from the daily records, so there is nothing to keep up to date and
/// nothing to lose: a report always reflects the samples recorded so far, today's included.
/// Months from before the daily records existed are shown from what older versions stored, and
/// merged with the daily records for the month that was in progress when the user upgraded.
@MainActor
public class MonthlyReportService {
    private let dailyStore: DailyRecordStore
    private let clock: AppClock
    private let legacySummaries: [String: MonthlySummary]

    public init(userDefaults: UserDefaults = .standard, dailyStore: DailyRecordStore, clock: AppClock = .live) {
        self.dailyStore = dailyStore
        self.clock = clock
        // Stored summaries come first, so they win over accumulators for the same month.
        self.legacySummaries = Dictionary(
            LegacyMonthlyImporter.load(defaults: userDefaults).map { ($0.monthKey, $0) }
        ) { first, _ in first }
    }

    // MARK: - Public API

    public var currentMonthKey: String {
        DayKey.month(for: clock.now(), calendar: clock.calendar)
    }

    /// Every month that has a report, newest first.
    public var availableMonths: [String] {
        Set(dailyStore.monthKeys).union(legacySummaries.keys).sorted(by: >)
    }

    /// The month a report opens on: the current one, or the newest with data if it has none.
    public var defaultMonthKey: String? {
        let months = availableMonths
        return months.contains(currentMonthKey) ? currentMonthKey : months.first
    }

    /// A month that an older version had started and this one continued shows both: the old
    /// data is merged in, never hidden (final review F1).
    public func summary(for monthKey: String) -> MonthlySummary? {
        let days = dailyStore.records(inMonth: monthKey)
        let legacy = legacySummaries[monthKey]
        guard !days.isEmpty else { return legacy }
        let recorded = MonthlySummary.make(monthKey: monthKey, month: firstInstant(of: monthKey), days: days)
        guard let legacy else { return recorded }
        let recordedDays = days.filter { $0.sampleCount > 0 }
        return recorded.merging(
            legacy: legacy,
            recordedDays: recordedDays.count,
            legacyDayLimit: Self.legacyDayLimit(firstRecordedDay: recordedDays.min { $0.dayKey < $1.dayKey })
        )
    }

    /// The most old-version days that can be distinct from the counted daily days (re-review N1).
    ///
    /// The old format kept a day count and no dates, so the overlap cannot be seen directly. It
    /// can only hold days up to the first day this version recorded: (that day of month - 1)
    /// before it, plus that day itself when it is not a counted daily day. This is the tightest
    /// bound the data allows; the upgrade day is then counted once.
    static func legacyDayLimit(firstRecordedDay: DailyRecord?) -> Int? {
        guard let first = firstRecordedDay,
              let dayOfMonth = first.dayKey.split(separator: "-").last.flatMap({ Int($0) }) else { return nil }
        return dayOfMonth - 1 + (first.isCounted ? 0 : 1)
    }

    /// Generate a CSV string export of the given monthly summary.
    public func exportToCSV(_ summary: MonthlySummary) -> String {
        var csv = "Metric,Value\n"
        csv += "Month,\(summary.formattedMonth)\n"
        csv += "Scope,This Mac only; includes LAN traffic\n"
        csv += "Days Monitored,\(summary.daysMonitored)\n"
        csv += "Peak Download (Mbps),\(String(format: "%.1f", summary.peakDownloadMbps))\n"
        csv += "Peak Upload (Mbps),\(String(format: "%.1f", summary.peakUploadMbps))\n"
        csv += "Avg Download (Mbps),\(String(format: "%.1f", summary.avgDownloadMbps))\n"
        csv += "Avg Upload (Mbps),\(String(format: "%.1f", summary.avgUploadMbps))\n"
        csv += "Plan Download (Mbps),\(String(format: "%.0f", summary.planDownloadMbps))\n"
        csv += "Plan Upload (Mbps),\(String(format: "%.0f", summary.planUploadMbps))\n"
        csv += "Download Utilization (%),\(String(format: "%.1f", summary.downloadPlanUtilization))\n"
        csv += "Upload Utilization (%),\(String(format: "%.1f", summary.uploadPlanUtilization))\n"
        csv += "Peak Approach Count,\(summary.peakApproachCount)\n"
        csv += "Disconnect Count,\(summary.disconnectCount)\n"
        csv += "Total Downtime (seconds),\(String(format: "%.0f", summary.totalDowntimeSeconds))\n"
        // A month without a successful probe has no latency: the cells stay empty rather than
        // reading 0.0, which no real round trip can be and a spreadsheet would average in.
        let hasLatency = summary.avgLatencyMs > 0
        let hasJitter = hasLatency && summary.avgJitterMs > 0
        csv += "Avg Latency (ms),\(hasLatency ? String(format: "%.1f", summary.avgLatencyMs) : "")\n"
        csv += "Avg Jitter (ms),\(hasJitter ? String(format: "%.1f", summary.avgJitterMs) : "")\n"
        csv += "Latency Probe Failures,\(summary.latencyFailureCount.map(String.init) ?? "N/A")\n"
        csv += "Recommendation,\(summary.recommendation.csvValue)\n"
        return csv
    }

    /// Start of a "yyyy-MM" month in the current time zone. Month keys are always Gregorian.
    private func firstInstant(of monthKey: String) -> Date {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = clock.calendar.timeZone
        let parts = monthKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2,
              let start = gregorian.date(from: DateComponents(year: parts[0], month: parts[1], day: 1)) else {
            return clock.now()
        }
        return start
    }
}
