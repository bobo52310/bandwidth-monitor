import Foundation
import OSLog

/// Reads the monthly data older versions kept in `UserDefaults`.
///
/// Nothing here writes those keys, and nothing else does any more, so the old data stays
/// exactly as it was. The only write is a backup of a blob that can no longer be decoded.
enum LegacyMonthlyImporter {
    private static let summariesKey = "monthlySummaries"
    private static let accumulatorsKey = "monthlyReportAccumulators"
    private static let corruptBackupKey = "monthlySummaries.corrupt"
    private static let logger = Logger(subsystem: "com.bandwidthecg", category: "MonthlyReport")

    static func load(defaults: UserDefaults) -> [MonthlySummary] {
        var summaries = decodedSummaries(defaults)
        if let inProgress = accumulatedSummary(defaults) {
            summaries.append(inProgress)
        }
        return summaries
    }

    private static func decodedSummaries(_ defaults: UserDefaults) -> [MonthlySummary] {
        guard let data = defaults.data(forKey: summariesKey) else { return [] }
        do {
            return try JSONDecoder().decode([MonthlySummary].self, from: data)
        } catch {
            // The blob stays in place too, so this runs on every launch; once is enough.
            if defaults.data(forKey: corruptBackupKey) != data {
                defaults.set(data, forKey: corruptBackupKey)
                logger.error("Could not decode \(summariesKey, privacy: .public), backed up: \(String(describing: error), privacy: .public)")
            }
            return []
        }
    }

    /// The month that was in progress when the old version last ran. The old format never
    /// stored its plan, so the current plan stands in, as it did in the old report.
    private static func accumulatedSummary(_ defaults: UserDefaults) -> MonthlySummary? {
        guard let stored = defaults.dictionary(forKey: accumulatorsKey),
              let daysRecorded = stored["daysRecorded"] as? Int, daysRecorded > 0,
              let monthStart = stored["currentMonthStart"] as? Double, monthStart > 0 else {
            return nil
        }

        func values(_ key: String) -> [Double] { stored[key] as? [Double] ?? [] }
        func mean(_ key: String) -> Double {
            let numbers = values(key)
            return numbers.isEmpty ? 0 : numbers.reduce(0, +) / Double(numbers.count)
        }

        let month = Date(timeIntervalSince1970: monthStart)
        return MonthlySummary(
            month: month,
            peakDownloadMbps: values("dailyPeakDownloads").max() ?? 0,
            peakUploadMbps: values("dailyPeakUploads").max() ?? 0,
            avgDownloadMbps: mean("dailyAvgDownloads"),
            avgUploadMbps: mean("dailyAvgUploads"),
            planDownloadMbps: defaults.double(forKey: "downloadPlanSpeed"),
            planUploadMbps: defaults.double(forKey: "uploadPlanSpeed"),
            peakApproachCount: stored["monthlyPeakApproachCount"] as? Int ?? 0,
            disconnectCount: stored["monthlyDisconnectCount"] as? Int ?? 0,
            totalDowntimeSeconds: stored["monthlyTotalDowntime"] as? Double ?? 0,
            avgLatencyMs: mean("dailyLatencies"),
            avgJitterMs: mean("dailyJitters"),
            daysMonitored: daysRecorded,
            monthKey: MonthlySummary.legacyMonthKey(for: month, calendar: .current)
        )
    }
}
