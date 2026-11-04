import Foundation

/// Every threshold behind the monthly report and the plan recommendation, kept in one place.
public enum ReportRules {
    public static let sustainedPeakSamples = 3
    public static let sustainedMaxGapSeconds: TimeInterval = 2.5
    public static let minDailySamples = 600     // D4: 10 minutes at 1 Hz
    public static let minDaysForRecommendation = 7
    public static let minDaysForDowngrade = 14
    public static let saturationRatio = 0.90
    public static let saturatedDaysForUpgrade = 3
    public static let downgradeP95Ratio = 0.30
    public static let approachRatio = 0.80
    public static let approachSustainSeconds: TimeInterval = 30
    public static let approachRearmRatio = 0.60
    public static let approachRearmSeconds: TimeInterval = 60
    public static let approachMaxGapSeconds: TimeInterval = 5
    public static let retentionDays = 400
    public static let flushIntervalSeconds: TimeInterval = 300
}
