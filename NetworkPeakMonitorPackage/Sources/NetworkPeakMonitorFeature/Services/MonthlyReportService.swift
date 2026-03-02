import Foundation
import Observation

/// Service that accumulates daily network data snapshots and generates monthly summaries.
///
/// Call `recordDailySnapshot(...)` once per day (or on app launch) to feed in that day's
/// aggregated metrics. When the calendar month changes, the service automatically finalizes
/// the previous month's summary and begins accumulating for the new month.
///
/// Accumulators are persisted to UserDefaults so that in-progress month data survives
/// app restarts and crashes.
@MainActor
@Observable
public class MonthlyReportService {

    // MARK: - Properties

    public var currentMonthSummary: MonthlySummary?
    public var pastSummaries: [MonthlySummary] = []

    // MARK: - Configuration

    private let userDefaults: UserDefaults
    private let storageKey = "monthlySummaries"
    private let accumulatorKey = "monthlyReportAccumulators"
    private let maxMonths = 12

    // MARK: - Accumulators for Current Month

    private var dailyPeakDownloads: [Double] = []
    private var dailyPeakUploads: [Double] = []
    private var dailyAvgDownloads: [Double] = []
    private var dailyAvgUploads: [Double] = []
    private var monthlyPeakApproachCount: Int = 0
    private var monthlyDisconnectCount: Int = 0
    private var monthlyTotalDowntime: Double = 0
    private var dailyLatencies: [Double] = []
    private var dailyJitters: [Double] = []
    private var currentMonthStart: Date?
    private var daysRecorded: Int = 0

    // MARK: - Initialization

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadSummaries()
        loadAccumulators()
    }

    // MARK: - Public API

    /// Record daily snapshot data. Call once per day or on app launch with the day's aggregated metrics.
    ///
    /// If the current date is in a different calendar month from the previous recording,
    /// the previous month is finalized and added to `pastSummaries` before accumulating
    /// the new data.
    public func recordDailySnapshot(
        peakDownload: Double,
        peakUpload: Double,
        avgDownload: Double,
        avgUpload: Double,
        peakApproachCount: Int,
        disconnectCount: Int,
        totalDowntime: Double,
        avgLatency: Double,
        avgJitter: Double,
        planDownload: Double,
        planUpload: Double
    ) {
        let calendar = Calendar.current
        let now = Date()

        // Check if we crossed into a new month
        if let monthStart = currentMonthStart,
           !calendar.isDate(monthStart, equalTo: now, toGranularity: .month) {
            finalizeMonthlySummary(planDownload: planDownload, planUpload: planUpload)
        }

        // Set current month start if not set or if month changed
        if currentMonthStart == nil ||
            !calendar.isDate(currentMonthStart!, equalTo: now, toGranularity: .month) {
            currentMonthStart = calendar.dateInterval(of: .month, for: now)?.start
            resetAccumulators()
        }

        // Accumulate daily data
        dailyPeakDownloads.append(peakDownload)
        dailyPeakUploads.append(peakUpload)
        dailyAvgDownloads.append(avgDownload)
        dailyAvgUploads.append(avgUpload)
        monthlyPeakApproachCount += peakApproachCount
        monthlyDisconnectCount += disconnectCount
        monthlyTotalDowntime += totalDowntime
        if avgLatency > 0 { dailyLatencies.append(avgLatency) }
        if avgJitter > 0 { dailyJitters.append(avgJitter) }
        daysRecorded += 1

        updateCurrentMonthSummary(planDownload: planDownload, planUpload: planUpload)
        saveAccumulators()
    }

    /// Generate a CSV string export of the given monthly summary.
    public func exportToCSV(_ summary: MonthlySummary) -> String {
        var csv = "Metric,Value\n"
        csv += "Month,\(summary.formattedMonth)\n"
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
        csv += "Avg Latency (ms),\(String(format: "%.1f", summary.avgLatencyMs))\n"
        csv += "Avg Jitter (ms),\(String(format: "%.1f", summary.avgJitterMs))\n"
        csv += "Recommendation,\(summary.recommendation.csvValue)\n"
        return csv
    }

    // MARK: - Internal Logic

    private func updateCurrentMonthSummary(planDownload: Double, planUpload: Double) {
        guard let monthStart = currentMonthStart else { return }

        currentMonthSummary = MonthlySummary(
            month: monthStart,
            peakDownloadMbps: dailyPeakDownloads.max() ?? 0,
            peakUploadMbps: dailyPeakUploads.max() ?? 0,
            avgDownloadMbps: dailyAvgDownloads.isEmpty
                ? 0
                : dailyAvgDownloads.reduce(0, +) / Double(dailyAvgDownloads.count),
            avgUploadMbps: dailyAvgUploads.isEmpty
                ? 0
                : dailyAvgUploads.reduce(0, +) / Double(dailyAvgUploads.count),
            planDownloadMbps: planDownload,
            planUploadMbps: planUpload,
            peakApproachCount: monthlyPeakApproachCount,
            disconnectCount: monthlyDisconnectCount,
            totalDowntimeSeconds: monthlyTotalDowntime,
            avgLatencyMs: dailyLatencies.isEmpty
                ? 0
                : dailyLatencies.reduce(0, +) / Double(dailyLatencies.count),
            avgJitterMs: dailyJitters.isEmpty
                ? 0
                : dailyJitters.reduce(0, +) / Double(dailyJitters.count),
            daysMonitored: daysRecorded
        )
    }

    private func finalizeMonthlySummary(planDownload: Double, planUpload: Double) {
        guard let monthStart = currentMonthStart, daysRecorded > 0 else { return }

        let summary = MonthlySummary(
            month: monthStart,
            peakDownloadMbps: dailyPeakDownloads.max() ?? 0,
            peakUploadMbps: dailyPeakUploads.max() ?? 0,
            avgDownloadMbps: dailyAvgDownloads.reduce(0, +) / Double(dailyAvgDownloads.count),
            avgUploadMbps: dailyAvgUploads.reduce(0, +) / Double(dailyAvgUploads.count),
            planDownloadMbps: planDownload,
            planUploadMbps: planUpload,
            peakApproachCount: monthlyPeakApproachCount,
            disconnectCount: monthlyDisconnectCount,
            totalDowntimeSeconds: monthlyTotalDowntime,
            avgLatencyMs: dailyLatencies.isEmpty
                ? 0
                : dailyLatencies.reduce(0, +) / Double(dailyLatencies.count),
            avgJitterMs: dailyJitters.isEmpty
                ? 0
                : dailyJitters.reduce(0, +) / Double(dailyJitters.count),
            daysMonitored: daysRecorded
        )

        pastSummaries.insert(summary, at: 0)
        if pastSummaries.count > maxMonths {
            pastSummaries = Array(pastSummaries.prefix(maxMonths))
        }

        saveSummaries()
    }

    private func resetAccumulators() {
        dailyPeakDownloads = []
        dailyPeakUploads = []
        dailyAvgDownloads = []
        dailyAvgUploads = []
        monthlyPeakApproachCount = 0
        monthlyDisconnectCount = 0
        monthlyTotalDowntime = 0
        dailyLatencies = []
        dailyJitters = []
        daysRecorded = 0
    }

    // MARK: - Persistence

    private func saveSummaries() {
        if let encoded = try? JSONEncoder().encode(pastSummaries) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }

    private func loadSummaries() {
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([MonthlySummary].self, from: data) {
            pastSummaries = decoded
        }
    }

    private func saveAccumulators() {
        let accumulatorData: [String: Any] = [
            "dailyPeakDownloads": dailyPeakDownloads,
            "dailyPeakUploads": dailyPeakUploads,
            "dailyAvgDownloads": dailyAvgDownloads,
            "dailyAvgUploads": dailyAvgUploads,
            "monthlyPeakApproachCount": monthlyPeakApproachCount,
            "monthlyDisconnectCount": monthlyDisconnectCount,
            "monthlyTotalDowntime": monthlyTotalDowntime,
            "dailyLatencies": dailyLatencies,
            "dailyJitters": dailyJitters,
            "daysRecorded": daysRecorded,
            "currentMonthStart": currentMonthStart?.timeIntervalSince1970 ?? 0
        ]
        userDefaults.set(accumulatorData, forKey: accumulatorKey)
    }

    private func loadAccumulators() {
        guard let data = userDefaults.dictionary(forKey: accumulatorKey) else { return }

        dailyPeakDownloads = data["dailyPeakDownloads"] as? [Double] ?? []
        dailyPeakUploads = data["dailyPeakUploads"] as? [Double] ?? []
        dailyAvgDownloads = data["dailyAvgDownloads"] as? [Double] ?? []
        dailyAvgUploads = data["dailyAvgUploads"] as? [Double] ?? []
        monthlyPeakApproachCount = data["monthlyPeakApproachCount"] as? Int ?? 0
        monthlyDisconnectCount = data["monthlyDisconnectCount"] as? Int ?? 0
        monthlyTotalDowntime = data["monthlyTotalDowntime"] as? Double ?? 0
        dailyLatencies = data["dailyLatencies"] as? [Double] ?? []
        dailyJitters = data["dailyJitters"] as? [Double] ?? []
        daysRecorded = data["daysRecorded"] as? Int ?? 0

        if let timestamp = data["currentMonthStart"] as? Double, timestamp > 0 {
            currentMonthStart = Date(timeIntervalSince1970: timestamp)
        }
    }
}
