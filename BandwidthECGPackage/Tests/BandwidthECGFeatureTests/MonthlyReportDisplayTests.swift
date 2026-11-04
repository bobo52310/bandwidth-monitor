import Testing
import Foundation
@testable import BandwidthECGFeature

/// What the monthly report shows beside the numbers (final review F3 part 1 and F5).
@Suite("Monthly report display")
struct MonthlyReportDisplayTests {

    private func summary(
        planDown: Double = 500,
        planUp: Double = 50,
        latency: Double = 20,
        jitter: Double = 4
    ) -> MonthlySummary {
        MonthlySummary(
            month: Date(timeIntervalSince1970: 1_793_000_000),
            peakDownloadMbps: 100, peakUploadMbps: 10,
            avgDownloadMbps: 10, avgUploadMbps: 1,
            planDownloadMbps: planDown, planUploadMbps: planUp,
            peakApproachCount: 0, disconnectCount: 0, totalDowntimeSeconds: 0,
            avgLatencyMs: latency, avgJitterMs: jitter,
            daysMonitored: 10, monthKey: "2026-11"
        )
    }

    // MARK: - F3: the plan the advice was judged against

    @Test func planText_namesBothPlanSpeeds() throws {
        let text = try #require(MonthlyReportText.plan(summary(planDown: 500, planUp: 50)))

        #expect(text == L10n.reportPlanSpeeds("500", "50"))
        #expect(text.contains("500"))
        #expect(text.contains("50"))
    }

    @Test func planText_roundsToWholeMbps() throws {
        let text = try #require(MonthlyReportText.plan(summary(planDown: 299.6, planUp: 20.2)))

        #expect(text == L10n.reportPlanSpeeds("300", "20"))
    }

    @Test func planText_withoutAPlan_isNil() {
        #expect(MonthlyReportText.plan(summary(planDown: 0, planUp: 0)) == nil)
    }

    // MARK: - F5: no jitter sample is not 0.0 ms

    @Test func jitterText_withoutAJitterSample_isADash() {
        #expect(MonthlyReportText.jitter(summary(latency: 20, jitter: 0)) == "—")
    }

    @Test func jitterText_withoutLatency_isADash() {
        #expect(MonthlyReportText.jitter(summary(latency: 0, jitter: 0)) == "—")
    }

    @Test func jitterText_withASample_showsIt() {
        #expect(MonthlyReportText.jitter(summary(latency: 20, jitter: 4)) == "4.0 ms")
    }

    @Test func latencyText_matchesTheCSVRule() {
        #expect(MonthlyReportText.latency(summary(latency: 0)) == "—")
        #expect(MonthlyReportText.latency(summary(latency: 20)) == "20 ms")
    }
}
