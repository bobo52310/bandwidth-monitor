import Foundation

/// Monthly summary of network performance metrics used for plan recommendation reports.
public struct MonthlySummary: Codable, Identifiable, Sendable {
    public let id: UUID
    public let month: Date
    /// "2026-11". The month this summary belongs to, whatever time zone reads it later.
    public let monthKey: String
    /// Sustained 3-second peaks. The instantaneous peaks live in `PeakRecorder`.
    public let peakDownloadMbps: Double
    public let peakUploadMbps: Double
    public let avgDownloadMbps: Double
    public let avgUploadMbps: Double
    public let planDownloadMbps: Double
    public let planUploadMbps: Double
    public let peakApproachCount: Int
    public let disconnectCount: Int
    public let totalDowntimeSeconds: Double
    public let avgLatencyMs: Double
    public let avgJitterMs: Double
    public let daysMonitored: Int
    /// `nil` on a summary stored by an older version, which has no daily data behind it.
    public let saturatedDays: Int?
    public let downloadDailyPeakP95Ratio: Double?
    public let uploadDailyPeakP95Ratio: Double?
    public let latencyFailureCount: Int?
    public let peakDownloadTime: Date?
    public let peakUploadTime: Date?
    /// The highest of the daily peaks, each against the plan of its own day.
    public let highestDownloadDayRatio: Double?
    public let highestUploadDayRatio: Double?

    public init(
        id: UUID = UUID(),
        month: Date,
        peakDownloadMbps: Double,
        peakUploadMbps: Double,
        avgDownloadMbps: Double,
        avgUploadMbps: Double,
        planDownloadMbps: Double,
        planUploadMbps: Double,
        peakApproachCount: Int,
        disconnectCount: Int,
        totalDowntimeSeconds: Double,
        avgLatencyMs: Double,
        avgJitterMs: Double,
        daysMonitored: Int,
        monthKey: String? = nil,
        saturatedDays: Int? = nil,
        downloadDailyPeakP95Ratio: Double? = nil,
        uploadDailyPeakP95Ratio: Double? = nil,
        latencyFailureCount: Int? = nil,
        peakDownloadTime: Date? = nil,
        peakUploadTime: Date? = nil,
        highestDownloadDayRatio: Double? = nil,
        highestUploadDayRatio: Double? = nil
    ) {
        self.id = id
        self.month = month
        self.monthKey = monthKey ?? DayKey.month(for: month, calendar: .current)
        self.peakDownloadMbps = peakDownloadMbps
        self.peakUploadMbps = peakUploadMbps
        self.avgDownloadMbps = avgDownloadMbps
        self.avgUploadMbps = avgUploadMbps
        self.planDownloadMbps = planDownloadMbps
        self.planUploadMbps = planUploadMbps
        self.peakApproachCount = peakApproachCount
        self.disconnectCount = disconnectCount
        self.totalDowntimeSeconds = totalDowntimeSeconds
        self.avgLatencyMs = avgLatencyMs
        self.avgJitterMs = avgJitterMs
        self.daysMonitored = daysMonitored
        self.saturatedDays = saturatedDays
        self.downloadDailyPeakP95Ratio = downloadDailyPeakP95Ratio
        self.uploadDailyPeakP95Ratio = uploadDailyPeakP95Ratio
        self.latencyFailureCount = latencyFailureCount
        self.peakDownloadTime = peakDownloadTime
        self.peakUploadTime = peakUploadTime
        self.highestDownloadDayRatio = highestDownloadDayRatio
        self.highestUploadDayRatio = highestUploadDayRatio
    }

    /// Reads every format this type has been stored in. The fields of the first version are
    /// required; everything added since may be missing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        month = try container.decode(Date.self, forKey: .month)
        peakDownloadMbps = try container.decode(Double.self, forKey: .peakDownloadMbps)
        peakUploadMbps = try container.decode(Double.self, forKey: .peakUploadMbps)
        avgDownloadMbps = try container.decode(Double.self, forKey: .avgDownloadMbps)
        avgUploadMbps = try container.decode(Double.self, forKey: .avgUploadMbps)
        planDownloadMbps = try container.decode(Double.self, forKey: .planDownloadMbps)
        planUploadMbps = try container.decode(Double.self, forKey: .planUploadMbps)
        peakApproachCount = try container.decode(Int.self, forKey: .peakApproachCount)
        disconnectCount = try container.decode(Int.self, forKey: .disconnectCount)
        totalDowntimeSeconds = try container.decode(Double.self, forKey: .totalDowntimeSeconds)
        avgLatencyMs = try container.decode(Double.self, forKey: .avgLatencyMs)
        avgJitterMs = try container.decode(Double.self, forKey: .avgJitterMs)
        daysMonitored = try container.decode(Int.self, forKey: .daysMonitored)
        monthKey = try container.decodeIfPresent(String.self, forKey: .monthKey)
            ?? Self.legacyMonthKey(for: month, calendar: .current)
        saturatedDays = try container.decodeIfPresent(Int.self, forKey: .saturatedDays)
        downloadDailyPeakP95Ratio = try container.decodeIfPresent(Double.self, forKey: .downloadDailyPeakP95Ratio)
        uploadDailyPeakP95Ratio = try container.decodeIfPresent(Double.self, forKey: .uploadDailyPeakP95Ratio)
        latencyFailureCount = try container.decodeIfPresent(Int.self, forKey: .latencyFailureCount)
        peakDownloadTime = try container.decodeIfPresent(Date.self, forKey: .peakDownloadTime)
        peakUploadTime = try container.decodeIfPresent(Date.self, forKey: .peakUploadTime)
        highestDownloadDayRatio = try container.decodeIfPresent(Double.self, forKey: .highestDownloadDayRatio)
        highestUploadDayRatio = try container.decodeIfPresent(Double.self, forKey: .highestUploadDayRatio)
    }

    // MARK: - Building from Daily Records

    /// Derives a month's summary from its daily records.
    ///
    /// Peaks and averages use every day. `daysMonitored`, saturation and the P95 only use days
    /// with enough monitoring. The plan shown is the last one in use that month, while
    /// saturation and utilization compare each day with its own plan.
    public static func make(monthKey: String, month: Date, days: [DailyRecord]) -> MonthlySummary {
        let ordered = days.sorted { $0.dayKey < $1.dayKey }
        let counted = ordered.filter(\.isCounted)
        let planDay = ordered.last { $0.sampleCount > 0 }
        let downloadPeakDay = ordered.max { $0.sustainedPeakDownloadMbps < $1.sustainedPeakDownloadMbps }
        let uploadPeakDay = ordered.max { $0.sustainedPeakUploadMbps < $1.sustainedPeakUploadMbps }

        func total<Value: AdditiveArithmetic>(_ field: KeyPath<DailyRecord, Value>) -> Value {
            ordered.reduce(.zero) { $0 + $1[keyPath: field] }
        }
        func mean(_ sum: Double, over count: Int) -> Double {
            count > 0 ? sum / Double(count) : 0
        }

        return MonthlySummary(
            month: month,
            peakDownloadMbps: downloadPeakDay?.sustainedPeakDownloadMbps ?? 0,
            peakUploadMbps: uploadPeakDay?.sustainedPeakUploadMbps ?? 0,
            avgDownloadMbps: mean(total(\.downloadSum), over: total(\.sampleCount)),
            avgUploadMbps: mean(total(\.uploadSum), over: total(\.sampleCount)),
            planDownloadMbps: planDay?.planDownloadMbps ?? 0,
            planUploadMbps: planDay?.planUploadMbps ?? 0,
            peakApproachCount: total(\.approachCount),
            disconnectCount: total(\.disconnectCount),
            totalDowntimeSeconds: total(\.downtimeSeconds),
            avgLatencyMs: mean(total(\.latencySum), over: total(\.latencyCount)),
            avgJitterMs: mean(total(\.jitterSum), over: total(\.jitterCount)),
            daysMonitored: counted.count,
            monthKey: monthKey,
            saturatedDays: counted.filter(\.isSaturated).count,
            downloadDailyPeakP95Ratio: percentile95(counted.map(\.downloadPeakRatio)),
            uploadDailyPeakP95Ratio: percentile95(counted.map(\.uploadPeakRatio)),
            latencyFailureCount: total(\.latencyFailures),
            peakDownloadTime: downloadPeakDay?.sustainedPeakDownloadTime,
            peakUploadTime: uploadPeakDay?.sustainedPeakUploadTime,
            highestDownloadDayRatio: ordered.map(\.downloadPeakRatio).max(),
            highestUploadDayRatio: ordered.map(\.uploadPeakRatio).max()
        )
    }

    /// Nearest-rank 95th percentile: the value at index `ceil(0.95 * n) - 1` of the sorted values.
    public static func percentile95(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let rank = Int((0.95 * Double(values.count)).rounded(.up))
        return values.sorted()[rank - 1]
    }

    /// The key of a month stored by an older version as its first instant in the user's time
    /// zone at that time. One day later is inside that month in every time zone, so the
    /// label holds after the user moves.
    static func legacyMonthKey(for monthStart: Date, calendar: Calendar) -> String {
        DayKey.month(for: monthStart.addingTimeInterval(86_400), calendar: calendar)
    }

    // MARK: - Computed Properties

    /// Download plan utilization as a percentage. Uses each day's own plan when the summary
    /// was built from daily records, otherwise peakDownload / planDownload * 100.
    /// Returns 0 if planDownloadMbps is zero to avoid division by zero.
    public var downloadPlanUtilization: Double {
        if let highestDownloadDayRatio { return highestDownloadDayRatio * 100.0 }
        guard planDownloadMbps > 0 else { return 0 }
        return peakDownloadMbps / planDownloadMbps * 100.0
    }

    /// Upload plan utilization as a percentage. Uses each day's own plan when the summary
    /// was built from daily records, otherwise peakUpload / planUpload * 100.
    /// Returns 0 if planUploadMbps is zero to avoid division by zero.
    public var uploadPlanUtilization: Double {
        if let highestUploadDayRatio { return highestUploadDayRatio * 100.0 }
        guard planUploadMbps > 0 else { return 0 }
        return peakUploadMbps / planUploadMbps * 100.0
    }

    /// Formatted month string in yyyy/MM format, always Gregorian.
    public var formattedMonth: String {
        monthKey.replacingOccurrences(of: "-", with: "/")
    }

    // MARK: - Plan Recommendation

    /// Recommendation based on monthly network usage patterns.
    public enum PlanRecommendation: Codable, Sendable, Equatable {
        case considerUpgrade
        case planFits
        case considerDowngrade
        case insufficientData

        /// Localized display name for the recommendation.
        public var displayName: String {
            switch self {
            case .considerUpgrade:
                return L10n.reportRecommendUpgrade
            case .planFits:
                return L10n.reportRecommendFits
            case .considerDowngrade:
                return L10n.reportRecommendDowngrade
            case .insufficientData:
                return L10n.reportRecommendInsufficientData
            }
        }

        /// Stable English value for CSV export (non-localized).
        public var csvValue: String {
            switch self {
            case .considerUpgrade:
                return "Consider Upgrade"
            case .planFits:
                return "Plan Fits"
            case .considerDowngrade:
                return "Consider Downgrade"
            case .insufficientData:
                return "Insufficient Data"
            }
        }

        /// SF Symbol icon name for the recommendation.
        public var icon: String {
            switch self {
            case .considerUpgrade:
                return "arrow.up.circle.fill"
            case .planFits:
                return "checkmark.circle.fill"
            case .considerDowngrade:
                return "arrow.down.circle.fill"
            case .insufficientData:
                return "questionmark.circle.fill"
            }
        }
    }

    /// Recommendation from the month's daily sustained peaks, using `ReportRules`.
    ///
    /// - Too few counted days, or a summary with no daily data: `.insufficientData`
    /// - Enough distinct days saturated in either direction: `.considerUpgrade`
    /// - Both directions' P95 low over enough days, with no saturated day: `.considerDowngrade`
    /// - Otherwise: `.planFits`
    public var recommendation: PlanRecommendation {
        guard daysMonitored >= ReportRules.minDaysForRecommendation,
              let saturatedDays,
              let downloadDailyPeakP95Ratio,
              let uploadDailyPeakP95Ratio else {
            return .insufficientData
        }
        if saturatedDays >= ReportRules.saturatedDaysForUpgrade {
            return .considerUpgrade
        }
        if daysMonitored >= ReportRules.minDaysForDowngrade,
           saturatedDays == 0,
           downloadDailyPeakP95Ratio < ReportRules.downgradeP95Ratio,
           uploadDailyPeakP95Ratio < ReportRules.downgradeP95Ratio {
            return .considerDowngrade
        }
        return .planFits
    }
}
