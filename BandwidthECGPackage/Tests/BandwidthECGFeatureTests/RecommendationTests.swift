import Testing
import Foundation
@testable import BandwidthECGFeature

/// D2 and R13, with `MonthlySummary.make` fed by daily records. Plan 300/300 unless noted.
@Suite("Plan recommendation")
struct RecommendationTests {

    private func day(
        _ number: Int,
        down: Double,
        up: Double = 0,
        planDown: Double = 300,
        planUp: Double = 300,
        samples: Int = ReportRules.minDailySamples
    ) -> DailyRecord {
        var record = DailyRecord(
            dayKey: String(format: "2026-11-%02d", number),
            planDownloadMbps: planDown,
            planUploadMbps: planUp
        )
        record.sustainedPeakDownloadMbps = down
        record.sustainedPeakUploadMbps = up
        record.sampleCount = samples
        return record
    }

    private func days(_ range: ClosedRange<Int>, down: Double, up: Double = 0) -> [DailyRecord] {
        range.map { day($0, down: down, up: up) }
    }

    private func summary(_ days: [DailyRecord]) -> MonthlySummary {
        MonthlySummary.make(monthKey: "2026-11", month: Date(timeIntervalSince1970: 0), days: days)
    }

    @Test func sixDays_insufficient() {
        #expect(summary(days(1...6, down: 280)).recommendation == .insufficientData)
    }

    @Test func sevenDays_noSaturation_fits() {
        #expect(summary(days(1...7, down: 150)).recommendation == .planFits)
    }

    @Test func twoSaturatedDays_fits() {
        let report = summary(days(1...2, down: 280) + days(3...30, down: 150))
        #expect(report.saturatedDays == 2)
        #expect(report.recommendation == .planFits)
    }

    @Test func threeSaturatedDays_upgrade() {
        let report = summary(days(1...3, down: 280) + days(4...30, down: 150))
        #expect(report.saturatedDays == 3)
        #expect(report.recommendation == .considerUpgrade)
    }

    @Test func threeSaturatedUploadOnly_upgrade() {
        let report = summary(days(1...3, down: 150, up: 285) + days(4...30, down: 150, up: 30))
        #expect(report.recommendation == .considerUpgrade)
    }

    @Test func exactly90Percent_notSaturated() {
        let report = summary(days(1...3, down: 270) + days(4...30, down: 150))
        #expect(report.saturatedDays == 0)
        #expect(report.recommendation == .planFits)
    }

    @Test func oneSpeedTest_notUpgrade() {
        let report = summary(days(1...29, down: 5) + [day(30, down: 276)])
        #expect(report.saturatedDays == 1)
        #expect(report.recommendation == .planFits)
    }

    @Test func low_14days_downgrade() {
        #expect(summary(days(1...14, down: 87, up: 87)).recommendation == .considerDowngrade)
    }

    @Test func low_13days_fits() {
        #expect(summary(days(1...13, down: 87, up: 87)).recommendation == .planFits)
    }

    @Test func p95Exactly30_fits() {
        #expect(summary(days(1...14, down: 90)).recommendation == .planFits)
    }

    @Test func uploadHigh_blocksDowngrade() {
        #expect(summary(days(1...14, down: 30, up: 150)).recommendation == .planFits)
    }

    @Test func saturatedDay_blocksDowngrade() {
        let report = summary(days(1...19, down: 30) + [day(20, down: 285)])
        #expect(report.downloadDailyPeakP95Ratio == 0.1)
        #expect(report.saturatedDays == 1)
        #expect(report.recommendation == .planFits)
    }

    @Test func uncountedDays_ignored() {
        let short = (1...3).map { day($0, down: 285, samples: 500) }
        let report = summary(short + days(4...23, down: 30))
        #expect(report.daysMonitored == 20)
        #expect(report.saturatedDays == 0)
        #expect(report.recommendation == .considerDowngrade)
    }

    @Test func planChangedMidMonth_usesPerDayRatio() {
        let early = (1...15).map { day($0, down: 280) }
        let late = (16...30).map { day($0, down: 280, planDown: 1000) }

        let report = summary(early + late)

        #expect(report.saturatedDays == 15)
        #expect(report.recommendation == .considerUpgrade)
    }

    /// Review Focus 4: the utilization bar must not contradict the recommendation.
    @Test func planChangedMidMonth_utilizationUsesTheDaysOwnPlan() {
        let early = (1...15).map { day($0, down: 280, up: 150) }
        let late = (16...30).map { day($0, down: 280, up: 150, planDown: 1000, planUp: 1000) }

        let report = summary(early + late)

        #expect(report.planDownloadMbps == 1000)
        #expect(abs(report.downloadPlanUtilization - 93.33) < 0.01)
        #expect(abs(report.uploadPlanUtilization - 50) < 0.01)
    }

    @Test func legacySummary_insufficient() {
        let legacy = MonthlySummary(
            month: Date(timeIntervalSince1970: 0),
            peakDownloadMbps: 280, peakUploadMbps: 280,
            avgDownloadMbps: 100, avgUploadMbps: 100,
            planDownloadMbps: 300, planUploadMbps: 300,
            peakApproachCount: 0, disconnectCount: 0, totalDowntimeSeconds: 0,
            avgLatencyMs: 0, avgJitterMs: 0,
            daysMonitored: 30,
            saturatedDays: nil
        )
        #expect(legacy.recommendation == .insufficientData)
    }

    @Test func anyMissingNewField_insufficient() {
        func make(_ saturated: Int?, _ down: Double?, _ up: Double?) -> MonthlySummary {
            MonthlySummary(
                month: Date(timeIntervalSince1970: 0),
                peakDownloadMbps: 10, peakUploadMbps: 10,
                avgDownloadMbps: 1, avgUploadMbps: 1,
                planDownloadMbps: 300, planUploadMbps: 300,
                peakApproachCount: 0, disconnectCount: 0, totalDowntimeSeconds: 0,
                avgLatencyMs: 0, avgJitterMs: 0,
                daysMonitored: 30,
                saturatedDays: saturated,
                downloadDailyPeakP95Ratio: down,
                uploadDailyPeakP95Ratio: up
            )
        }
        #expect(make(0, 0.1, 0.1).recommendation == .considerDowngrade)
        #expect(make(nil, 0.1, 0.1).recommendation == .insufficientData)
        #expect(make(0, nil, 0.1).recommendation == .insufficientData)
        #expect(make(0, 0.1, nil).recommendation == .insufficientData)
    }

    @Test func promoScenario_downgrade() {
        let quiet = (1...29).map { day($0, down: 120, up: 40, planDown: 1000, planUp: 600) }
        let busiest = day(30, down: 284.6, up: 96.2, planDown: 1000, planUp: 600)

        let report = summary(quiet + [busiest])

        #expect(report.peakDownloadMbps == 284.6)
        #expect(report.peakUploadMbps == 96.2)
        #expect(report.recommendation == .considerDowngrade)
    }
}

@Suite("MonthlySummary.make")
struct MonthlySummaryMakeTests {

    private func make(_ days: [DailyRecord], monthKey: String = "2026-11") -> MonthlySummary {
        MonthlySummary.make(monthKey: monthKey, month: Date(timeIntervalSince1970: 0), days: days)
    }

    @Test func percentile95_nearestRank() {
        #expect(MonthlySummary.percentile95((1...20).map(Double.init)) == 19)
        #expect(MonthlySummary.percentile95((1...14).map(Double.init)) == 14)
        #expect(MonthlySummary.percentile95([]) == nil)
        #expect(MonthlySummary.percentile95([7]) == 7)
    }

    @Test func percentile95_wholeRanksStayExact() {
        for count in stride(from: 20, through: 400, by: 20) {
            let values = (1...count).map(Double.init)
            #expect(MonthlySummary.percentile95(values) == Double(count * 95 / 100))
        }
    }

    @Test func percentile95_ignoresInputOrder() {
        #expect(MonthlySummary.percentile95((1...20).reversed().map(Double.init)) == 19)
    }

    @Test func peaks_includeShortDays_andTakeTheirTimes() {
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)
        var short = DailyRecord(dayKey: "2026-11-01", planDownloadMbps: 300, planUploadMbps: 300)
        short.sustainedPeakDownloadMbps = 280
        short.sustainedPeakDownloadTime = early
        short.sustainedPeakUploadMbps = 20
        short.sustainedPeakUploadTime = early
        short.sampleCount = 10
        var counted = DailyRecord(dayKey: "2026-11-02", planDownloadMbps: 300, planUploadMbps: 300)
        counted.sustainedPeakDownloadMbps = 100
        counted.sustainedPeakDownloadTime = late
        counted.sustainedPeakUploadMbps = 90
        counted.sustainedPeakUploadTime = late
        counted.sampleCount = 600

        let report = make([short, counted])

        #expect(report.peakDownloadMbps == 280)
        #expect(report.peakDownloadTime == early)
        #expect(report.peakUploadMbps == 90)
        #expect(report.peakUploadTime == late)
        #expect(report.daysMonitored == 1)
    }

    @Test func averages_areSumOverCount_acrossAllDays() {
        var first = DailyRecord(dayKey: "2026-11-01")
        first.downloadSum = 1_000
        first.uploadSum = 500
        first.sampleCount = 100
        first.latencySum = 300
        first.latencyCount = 3
        first.jitterSum = 30
        first.jitterCount = 3
        var second = DailyRecord(dayKey: "2026-11-02")
        second.downloadSum = 3_000
        second.uploadSum = 500
        second.sampleCount = 300
        second.latencySum = 100
        second.latencyCount = 1
        second.jitterSum = 10
        second.jitterCount = 1

        let report = make([first, second])

        #expect(report.avgDownloadMbps == 10)
        #expect(report.avgUploadMbps == 2.5)
        #expect(report.avgLatencyMs == 100)
        #expect(report.avgJitterMs == 10)
    }

    @Test func countsAreSummed() {
        var first = DailyRecord(dayKey: "2026-11-01")
        first.approachCount = 2
        first.disconnectCount = 1
        first.downtimeSeconds = 30
        first.latencyFailures = 4
        var second = DailyRecord(dayKey: "2026-11-02")
        second.approachCount = 3
        second.disconnectCount = 5
        second.downtimeSeconds = 90
        second.latencyFailures = 6

        let report = make([first, second])

        #expect(report.peakApproachCount == 5)
        #expect(report.disconnectCount == 6)
        #expect(report.totalDowntimeSeconds == 120)
        #expect(report.latencyFailureCount == 10)
    }

    @Test func plan_comesFromTheLastDayWithSamples_whateverTheOrder() {
        var early = DailyRecord(dayKey: "2026-11-01", planDownloadMbps: 300, planUploadMbps: 100)
        early.sampleCount = 10
        var late = DailyRecord(dayKey: "2026-11-02", planDownloadMbps: 500, planUploadMbps: 200)
        late.sampleCount = 10
        var noSamples = DailyRecord(dayKey: "2026-11-03", planDownloadMbps: 900, planUploadMbps: 900)
        noSamples.disconnectCount = 1

        let report = make([late, noSamples, early])

        #expect(report.planDownloadMbps == 500)
        #expect(report.planUploadMbps == 200)
    }

    @Test func noDays_isAnEmptyInsufficientSummary() {
        let report = make([])

        #expect(report.daysMonitored == 0)
        #expect(report.peakDownloadMbps == 0)
        #expect(report.avgDownloadMbps == 0)
        #expect(report.downloadPlanUtilization == 0)
        #expect(report.recommendation == .insufficientData)
    }

    @Test func formattedMonth_comesFromTheKeyNotTheDate() {
        #expect(make([], monthKey: "2026-11").formattedMonth == "2026/11")
    }

    @Test func memberwiseInit_derivesTheKeyFromTheDate() {
        var taipei = Calendar(identifier: .gregorian)
        taipei.timeZone = .current
        let date = taipei.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12))!

        let summary = MonthlySummary(
            month: date,
            peakDownloadMbps: 0, peakUploadMbps: 0, avgDownloadMbps: 0, avgUploadMbps: 0,
            planDownloadMbps: 0, planUploadMbps: 0, peakApproachCount: 0, disconnectCount: 0,
            totalDowntimeSeconds: 0, avgLatencyMs: 0, avgJitterMs: 0, daysMonitored: 0
        )

        #expect(summary.monthKey == "2026-03")
    }

    /// A legacy `month` is the first instant of the month where the user was at the time. Read
    /// further west that instant is still the previous month, which must not relabel the report.
    @Test func legacyMonthKey_survivesAMoveWest() {
        var taipei = Calendar(identifier: .gregorian)
        taipei.timeZone = TimeZone(identifier: "Asia/Taipei")!
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let monthStart = taipei.date(from: DateComponents(year: 2026, month: 10, day: 1))!

        #expect(MonthlySummary.legacyMonthKey(for: monthStart, calendar: taipei) == "2026-10")
        #expect(MonthlySummary.legacyMonthKey(for: monthStart, calendar: losAngeles) == "2026-10")
    }

    @Test func legacyMonthKey_survivesAMoveEast() {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var kiritimati = Calendar(identifier: .gregorian)
        kiritimati.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        let monthStart = losAngeles.date(from: DateComponents(year: 2026, month: 10, day: 1))!

        #expect(MonthlySummary.legacyMonthKey(for: monthStart, calendar: kiritimati) == "2026-10")
    }

    @Test func decode_legacyFormat_hasNoNewFields() throws {
        let json = #"""
        {"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","month":815000000,"peakDownloadMbps":280,
         "peakUploadMbps":90,"avgDownloadMbps":50,"avgUploadMbps":20,"planDownloadMbps":300,
         "planUploadMbps":300,"peakApproachCount":3,"disconnectCount":1,"totalDowntimeSeconds":60,
         "avgLatencyMs":20,"avgJitterMs":4,"daysMonitored":30}
        """#

        let summary = try JSONDecoder().decode(MonthlySummary.self, from: Data(json.utf8))

        #expect(summary.peakDownloadMbps == 280)
        #expect(summary.daysMonitored == 30)
        #expect(summary.monthKey.count == 7)
        #expect(summary.saturatedDays == nil)
        #expect(summary.downloadDailyPeakP95Ratio == nil)
        #expect(summary.uploadDailyPeakP95Ratio == nil)
        #expect(summary.latencyFailureCount == nil)
        #expect(summary.peakDownloadTime == nil)
        #expect(summary.recommendation == .insufficientData)
    }

    @Test func decode_missingOldField_throws() {
        let json = #"{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","month":815000000}"#
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(MonthlySummary.self, from: Data(json.utf8))
        }
    }

    @Test func codable_roundTripKeepsTheNewFields() throws {
        var record = DailyRecord(dayKey: "2026-11-01", planDownloadMbps: 300, planUploadMbps: 300)
        record.sustainedPeakDownloadMbps = 150
        record.sustainedPeakDownloadTime = Date(timeIntervalSince1970: 1_000)
        record.sampleCount = 600
        record.latencyFailures = 2
        let original = make([record])

        let decoded = try JSONDecoder().decode(MonthlySummary.self, from: JSONEncoder().encode(original))

        #expect(decoded.monthKey == "2026-11")
        #expect(decoded.saturatedDays == 0)
        #expect(decoded.downloadDailyPeakP95Ratio == 0.5)
        #expect(decoded.uploadDailyPeakP95Ratio == 0)
        #expect(decoded.latencyFailureCount == 2)
        #expect(decoded.peakDownloadTime == record.sustainedPeakDownloadTime)
        #expect(decoded.downloadPlanUtilization == original.downloadPlanUtilization)
    }
}
