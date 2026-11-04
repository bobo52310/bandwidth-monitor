import Foundation

/// One calendar day of measurements, accumulated sample by sample.
///
/// Stores the plan that applied that day, so changing the plan later never rewrites history.
public struct DailyRecord: Codable, Sendable, Equatable {
    public let dayKey: String
    public var sustainedPeakDownloadMbps: Double
    public var sustainedPeakUploadMbps: Double
    /// When the day's sustained peak was reached. `nil` when no peak has been recorded.
    public var sustainedPeakDownloadTime: Date?
    public var sustainedPeakUploadTime: Date?
    /// Mbps added up per sample; divide by `sampleCount` for the true mean.
    public var downloadSum: Double
    public var uploadSum: Double
    public var sampleCount: Int
    public var approachCount: Int
    public var latencySum: Double
    public var latencyCount: Int
    public var latencyFailures: Int
    public var jitterSum: Double
    public var jitterCount: Int
    public var disconnectCount: Int
    public var downtimeSeconds: Double
    public var planDownloadMbps: Double
    public var planUploadMbps: Double

    public init(dayKey: String, planDownloadMbps: Double = 0, planUploadMbps: Double = 0) {
        self.dayKey = dayKey
        self.sustainedPeakDownloadMbps = 0
        self.sustainedPeakUploadMbps = 0
        self.sustainedPeakDownloadTime = nil
        self.sustainedPeakUploadTime = nil
        self.downloadSum = 0
        self.uploadSum = 0
        self.sampleCount = 0
        self.approachCount = 0
        self.latencySum = 0
        self.latencyCount = 0
        self.latencyFailures = 0
        self.jitterSum = 0
        self.jitterCount = 0
        self.disconnectCount = 0
        self.downtimeSeconds = 0
        self.planDownloadMbps = planDownloadMbps
        self.planUploadMbps = planUploadMbps
    }

    /// Only `dayKey` is required, so a field added later never makes older records unreadable.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        sustainedPeakDownloadMbps = try container.decodeIfPresent(Double.self, forKey: .sustainedPeakDownloadMbps) ?? 0
        sustainedPeakUploadMbps = try container.decodeIfPresent(Double.self, forKey: .sustainedPeakUploadMbps) ?? 0
        sustainedPeakDownloadTime = try container.decodeIfPresent(Date.self, forKey: .sustainedPeakDownloadTime)
        sustainedPeakUploadTime = try container.decodeIfPresent(Date.self, forKey: .sustainedPeakUploadTime)
        downloadSum = try container.decodeIfPresent(Double.self, forKey: .downloadSum) ?? 0
        uploadSum = try container.decodeIfPresent(Double.self, forKey: .uploadSum) ?? 0
        sampleCount = try container.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 0
        approachCount = try container.decodeIfPresent(Int.self, forKey: .approachCount) ?? 0
        latencySum = try container.decodeIfPresent(Double.self, forKey: .latencySum) ?? 0
        latencyCount = try container.decodeIfPresent(Int.self, forKey: .latencyCount) ?? 0
        latencyFailures = try container.decodeIfPresent(Int.self, forKey: .latencyFailures) ?? 0
        jitterSum = try container.decodeIfPresent(Double.self, forKey: .jitterSum) ?? 0
        jitterCount = try container.decodeIfPresent(Int.self, forKey: .jitterCount) ?? 0
        disconnectCount = try container.decodeIfPresent(Int.self, forKey: .disconnectCount) ?? 0
        downtimeSeconds = try container.decodeIfPresent(Double.self, forKey: .downtimeSeconds) ?? 0
        planDownloadMbps = try container.decodeIfPresent(Double.self, forKey: .planDownloadMbps) ?? 0
        planUploadMbps = try container.decodeIfPresent(Double.self, forKey: .planUploadMbps) ?? 0
    }

    /// Days with too little monitoring stay in the peaks and averages, but not in
    /// `daysMonitored` or the recommendation.
    public var isCounted: Bool {
        sampleCount >= ReportRules.minDailySamples
    }

    public var downloadPeakRatio: Double {
        planDownloadMbps > 0 ? sustainedPeakDownloadMbps / planDownloadMbps : 0
    }

    public var uploadPeakRatio: Double {
        planUploadMbps > 0 ? sustainedPeakUploadMbps / planUploadMbps : 0
    }

    public var isSaturated: Bool {
        downloadPeakRatio > ReportRules.saturationRatio || uploadPeakRatio > ReportRules.saturationRatio
    }
}
