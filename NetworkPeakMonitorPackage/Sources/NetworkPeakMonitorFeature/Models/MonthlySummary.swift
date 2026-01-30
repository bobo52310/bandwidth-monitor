import Foundation

/// Monthly summary of network performance metrics used for plan recommendation reports.
public struct MonthlySummary: Codable, Identifiable, Sendable {
    public let id: UUID
    public let month: Date
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
        daysMonitored: Int
    ) {
        self.id = id
        self.month = month
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
    }

    // MARK: - Computed Properties

    /// Download plan utilization as a percentage (peakDownload / planDownload * 100).
    /// Returns 0 if planDownloadMbps is zero to avoid division by zero.
    public var downloadPlanUtilization: Double {
        guard planDownloadMbps > 0 else { return 0 }
        return peakDownloadMbps / planDownloadMbps * 100.0
    }

    /// Upload plan utilization as a percentage (peakUpload / planUpload * 100).
    /// Returns 0 if planUploadMbps is zero to avoid division by zero.
    public var uploadPlanUtilization: Double {
        guard planUploadMbps > 0 else { return 0 }
        return peakUploadMbps / planUploadMbps * 100.0
    }

    /// Formatted month string in yyyy/MM format.
    public var formattedMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM"
        return formatter.string(from: month)
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

    /// Computed recommendation based on usage thresholds.
    ///
    /// - If `daysMonitored < 7`: `.insufficientData`
    /// - If `peakApproachCount > 10` OR `downloadPlanUtilization > 90`: `.considerUpgrade`
    /// - If `downloadPlanUtilization < 30` AND `uploadPlanUtilization < 30` AND `peakApproachCount == 0`: `.considerDowngrade`
    /// - Otherwise: `.planFits`
    public var recommendation: PlanRecommendation {
        if daysMonitored < 7 {
            return .insufficientData
        }
        if peakApproachCount > 10 || downloadPlanUtilization > 90 {
            return .considerUpgrade
        }
        if downloadPlanUtilization < 30 && uploadPlanUtilization < 30 && peakApproachCount == 0 {
            return .considerDowngrade
        }
        return .planFits
    }
}
