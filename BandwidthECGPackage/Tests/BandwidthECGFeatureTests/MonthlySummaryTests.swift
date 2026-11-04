import Testing
import Foundation
@testable import BandwidthECGFeature

@Test func monthlySummary_planUtilization_calculatesCorrectly() async throws {
    let summary = MonthlySummary(
        month: Date(),
        peakDownloadMbps: 250.0,
        peakUploadMbps: 200.0,
        avgDownloadMbps: 50.0,
        avgUploadMbps: 30.0,
        planDownloadMbps: 300.0,
        planUploadMbps: 300.0,
        peakApproachCount: 5,
        disconnectCount: 3,
        totalDowntimeSeconds: 180.0,
        avgLatencyMs: 25.0,
        avgJitterMs: 5.0,
        daysMonitored: 15
    )
    #expect(abs(summary.downloadPlanUtilization - 83.33) < 1.0)
    #expect(abs(summary.uploadPlanUtilization - 66.67) < 1.0)
}

@Test func monthlySummary_upgradeRecommendation_frequentApproaches() async throws {
    let summary = MonthlySummary(
        month: Date(),
        peakDownloadMbps: 290.0,
        peakUploadMbps: 280.0,
        avgDownloadMbps: 150.0,
        avgUploadMbps: 100.0,
        planDownloadMbps: 300.0,
        planUploadMbps: 300.0,
        peakApproachCount: 20,
        disconnectCount: 0,
        totalDowntimeSeconds: 0,
        avgLatencyMs: 15.0,
        avgJitterMs: 3.0,
        daysMonitored: 30,
        saturatedDays: 3,
        downloadDailyPeakP95Ratio: 0.95,
        uploadDailyPeakP95Ratio: 0.9
    )
    #expect(summary.recommendation == .considerUpgrade)
}

@Test func monthlySummary_downgradeRecommendation_lowUtilization() async throws {
    let summary = MonthlySummary(
        month: Date(),
        peakDownloadMbps: 80.0,
        peakUploadMbps: 40.0,
        avgDownloadMbps: 20.0,
        avgUploadMbps: 10.0,
        planDownloadMbps: 1000.0,
        planUploadMbps: 1000.0,
        peakApproachCount: 0,
        disconnectCount: 0,
        totalDowntimeSeconds: 0,
        avgLatencyMs: 10.0,
        avgJitterMs: 2.0,
        daysMonitored: 30,
        saturatedDays: 0,
        downloadDailyPeakP95Ratio: 0.08,
        uploadDailyPeakP95Ratio: 0.04
    )
    #expect(summary.recommendation == .considerDowngrade)
}

@Test func monthlySummary_planFits_moderateUsage() async throws {
    let summary = MonthlySummary(
        month: Date(),
        peakDownloadMbps: 200.0,
        peakUploadMbps: 150.0,
        avgDownloadMbps: 80.0,
        avgUploadMbps: 40.0,
        planDownloadMbps: 300.0,
        planUploadMbps: 300.0,
        peakApproachCount: 3,
        disconnectCount: 1,
        totalDowntimeSeconds: 30.0,
        avgLatencyMs: 20.0,
        avgJitterMs: 5.0,
        daysMonitored: 30,
        saturatedDays: 0,
        downloadDailyPeakP95Ratio: 0.66,
        uploadDailyPeakP95Ratio: 0.5
    )
    #expect(summary.recommendation == .planFits)
}

@Test func reportCollectingDays_showsBothNumbers() {
    let text = L10n.reportCollectingDays(3, 7)
    #expect(text.contains("3"))
    #expect(text.contains("7"))
}
