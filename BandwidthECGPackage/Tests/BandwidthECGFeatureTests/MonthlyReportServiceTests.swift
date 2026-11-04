import Testing
import Foundation
@testable import BandwidthECGFeature

@MainActor
@Suite("MonthlyReportService")
struct MonthlyReportServiceTests {
    private static let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    private func speed(_ mbps: Double) -> NetworkSpeed {
        NetworkSpeed(uploadSpeed: 0, downloadSpeed: mbps * 125_000)
    }

    private func feed(_ store: DailyRecordStore, _ clock: TestClock, mbps: Double = 10, seconds: Int) {
        for _ in 0..<seconds {
            store.ingest(speed(mbps), planDownloadMbps: 300, planUploadMbps: 300)
            clock.advance(by: 1)
        }
    }

    private func makeStore(_ clock: TestClock, _ blobs: InMemoryBlobStore = InMemoryBlobStore()) -> DailyRecordStore {
        DailyRecordStore(store: blobs, clock: clock.appClock)
    }

    private func makeService(
        _ store: DailyRecordStore,
        _ clock: TestClock,
        defaults: UserDefaults = MemoryDefaults.make()
    ) -> MonthlyReportService {
        MonthlyReportService(userDefaults: defaults, dailyStore: store, clock: clock.appClock)
    }

    /// The first instant of a month in the current time zone, which is how old versions stored it.
    private func monthStart(_ year: Int, _ month: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    /// One entry of the old `monthlySummaries` blob, field for field as old versions wrote it.
    private func legacyEntry(month: Date, daysMonitored: Int = 30, peak: Double = 280) -> [String: Any] {
        [
            "id": UUID().uuidString,
            "month": month.timeIntervalSinceReferenceDate,
            "peakDownloadMbps": peak,
            "peakUploadMbps": 90.0,
            "avgDownloadMbps": 50.0,
            "avgUploadMbps": 20.0,
            "planDownloadMbps": 300.0,
            "planUploadMbps": 300.0,
            "peakApproachCount": 3,
            "disconnectCount": 1,
            "totalDowntimeSeconds": 60.0,
            "avgLatencyMs": 20.0,
            "avgJitterMs": 4.0,
            "daysMonitored": daysMonitored,
        ]
    }

    private func seedLegacy(_ defaults: UserDefaults, _ entries: [[String: Any]]) throws {
        defaults.set(try JSONSerialization.data(withJSONObject: entries), forKey: "monthlySummaries")
    }

    private func seedAccumulators(_ defaults: UserDefaults, month: Date, daysRecorded: Int = 2) {
        defaults.set([
            "dailyPeakDownloads": [100.0, 200.0],
            "dailyPeakUploads": [10.0, 20.0],
            "dailyAvgDownloads": [10.0, 30.0],
            "dailyAvgUploads": [2.0, 4.0],
            "monthlyPeakApproachCount": 4,
            "monthlyDisconnectCount": 2,
            "monthlyTotalDowntime": 90.0,
            "dailyLatencies": [10.0, 20.0],
            "dailyJitters": [2.0, 6.0],
            "daysRecorded": daysRecorded,
            "currentMonthStart": month.timeIntervalSince1970,
        ] as [String: Any], forKey: "monthlyReportAccumulators")
    }

    // MARK: - Daily data

    @Test func reopenShowsReportImmediately() {
        let clock = TestClock(2026, 11, 2, 9)
        let blobs = InMemoryBlobStore()
        let store = makeStore(clock, blobs)
        feed(store, clock, seconds: 700)
        store.flush()

        let reopened = makeService(makeStore(clock, blobs), clock)

        #expect(reopened.summary(for: reopened.currentMonthKey) != nil)
        #expect(reopened.summary(for: reopened.currentMonthKey)?.daysMonitored == 1)
    }

    @Test func pastMonthStillAvailable() {
        let clock = TestClock(2026, 10, 31, 9)
        let store = makeStore(clock)
        feed(store, clock, seconds: 10)
        clock.advance(by: 2 * 86_400) // 11/02
        feed(store, clock, seconds: 10)

        let service = makeService(store, clock)

        #expect(service.availableMonths == ["2026-11", "2026-10"])
        #expect(service.summary(for: "2026-10") != nil)
    }

    @Test func todayPartialIncluded() {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)
        feed(store, clock, seconds: ReportRules.minDailySamples)

        #expect(makeService(store, clock).summary(for: "2026-11")?.daysMonitored == 1)
    }

    @Test func monthWithOnlyShortDays_summaryExists() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)
        feed(store, clock, seconds: ReportRules.minDailySamples - 1)

        let summary = try #require(makeService(store, clock).summary(for: "2026-11"))

        #expect(summary.daysMonitored == 0)
        #expect(summary.recommendation == .insufficientData)
    }

    @Test func summary_ofAnUnknownMonth_isNil() {
        let clock = TestClock(2026, 11, 2, 9)
        #expect(makeService(makeStore(clock), clock).summary(for: "2026-11") == nil)
    }

    @Test func summary_followsNewSamples() {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)
        let service = makeService(store, clock)
        feed(store, clock, mbps: 100, seconds: 3)
        #expect(service.summary(for: "2026-11")?.peakDownloadMbps == 100)

        feed(store, clock, mbps: 200, seconds: 3)

        #expect(service.summary(for: "2026-11")?.peakDownloadMbps == 200)
    }

    @Test func currentMonthKey_usesTheInjectedClock() {
        let clock = TestClock(2026, 3, 15, 12)
        #expect(makeService(makeStore(clock), clock).currentMonthKey == "2026-03")
    }

    // MARK: - Which month opens first

    @Test func defaultMonth_isTheCurrentOneWhenItHasData() {
        let clock = TestClock(2026, 10, 31, 9)
        let store = makeStore(clock)
        feed(store, clock, seconds: 10)
        clock.advance(by: 2 * 86_400)
        feed(store, clock, seconds: 10)

        #expect(makeService(store, clock).defaultMonthKey == "2026-11")
    }

    /// After flying west the current month can be older than the newest record.
    @Test func defaultMonth_prefersTheCurrentOneOverANewerOne() {
        let clock = TestClock(2026, 10, 31, 23, 50) // Taipei
        let store = makeStore(clock)
        feed(store, clock, seconds: 10)
        clock.advance(by: 1_200) // 11/01 00:10 in Taipei
        feed(store, clock, seconds: 10)

        let losAngeles = clock.appClock(in: Self.losAngeles) // still 10/31 there
        let service = MonthlyReportService(userDefaults: MemoryDefaults.make(), dailyStore: store, clock: losAngeles)

        #expect(service.availableMonths == ["2026-11", "2026-10"])
        #expect(service.defaultMonthKey == "2026-10")
    }

    @Test func defaultMonth_isTheNewestWhenTheCurrentOneHasNoData() {
        let clock = TestClock(2026, 10, 31, 9)
        let store = makeStore(clock)
        feed(store, clock, seconds: 10)
        clock.advance(by: 2 * 86_400)

        #expect(makeService(store, clock).defaultMonthKey == "2026-10")
    }

    @Test func defaultMonth_isNilWithNoData() {
        let clock = TestClock(2026, 11, 2, 9)
        #expect(makeService(makeStore(clock), clock).defaultMonthKey == nil)
    }

    // MARK: - Old data

    @Test func legacyBlob_decodes() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let defaults = MemoryDefaults.make()
        try seedLegacy(defaults, [legacyEntry(month: monthStart(2026, 9), daysMonitored: 30)])

        let service = makeService(makeStore(clock), clock, defaults: defaults)

        #expect(service.availableMonths == ["2026-09"])
        let summary = try #require(service.summary(for: "2026-09"))
        #expect(summary.peakDownloadMbps == 280)
        #expect(summary.daysMonitored == 30)
        #expect(summary.recommendation == .insufficientData)
        #expect(summary.formattedMonth == "2026/09")
    }

    @Test func legacyBlob_missingField_backedUp() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let defaults = MemoryDefaults.make()
        var entry = legacyEntry(month: monthStart(2026, 9))
        entry.removeValue(forKey: "peakDownloadMbps")
        try seedLegacy(defaults, [entry])
        let original = try #require(defaults.data(forKey: "monthlySummaries"))

        let service = makeService(makeStore(clock), clock, defaults: defaults)

        #expect(service.availableMonths.isEmpty)
        #expect(defaults.data(forKey: "monthlySummaries.corrupt") == original)
        #expect(defaults.data(forKey: "monthlySummaries") == original)
    }

    @Test func legacyBlob_garbage_backedUp() {
        let clock = TestClock(2026, 11, 2, 9)
        let defaults = MemoryDefaults.make()
        let garbage = Data("not json".utf8)
        defaults.set(garbage, forKey: "monthlySummaries")

        _ = makeService(makeStore(clock), clock, defaults: defaults)

        #expect(defaults.data(forKey: "monthlySummaries.corrupt") == garbage)
    }

    /// A later launch reads the same bad blob. An older backup that differs is not replaced by
    /// accident, because it is only rewritten when the bytes changed.
    @Test func legacyBlob_secondLaunch_keepsTheBackup() {
        let clock = TestClock(2026, 11, 2, 9)
        let defaults = MemoryDefaults.make()
        let garbage = Data("not json".utf8)
        defaults.set(garbage, forKey: "monthlySummaries")

        _ = makeService(makeStore(clock), clock, defaults: defaults)
        _ = makeService(makeStore(clock), clock, defaults: defaults)

        #expect(defaults.data(forKey: "monthlySummaries.corrupt") == garbage)
    }

    @Test func legacyAccumulators_imported() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let defaults = MemoryDefaults.make()
        defaults.set(300.0, forKey: "downloadPlanSpeed")
        defaults.set(100.0, forKey: "uploadPlanSpeed")
        seedAccumulators(defaults, month: monthStart(2026, 10))
        let original = defaults.object(forKey: "monthlyReportAccumulators") as? NSDictionary

        let service = makeService(makeStore(clock), clock, defaults: defaults)

        #expect(service.availableMonths == ["2026-10"])
        let summary = try #require(service.summary(for: "2026-10"))
        #expect(summary.peakDownloadMbps == 200)
        #expect(summary.peakUploadMbps == 20)
        #expect(summary.avgDownloadMbps == 20)
        #expect(summary.avgUploadMbps == 3)
        #expect(summary.peakApproachCount == 4)
        #expect(summary.disconnectCount == 2)
        #expect(summary.totalDowntimeSeconds == 90)
        #expect(summary.avgLatencyMs == 15)
        #expect(summary.avgJitterMs == 4)
        #expect(summary.daysMonitored == 2)
        #expect(summary.planDownloadMbps == 300)
        #expect(summary.planUploadMbps == 100)
        #expect(summary.recommendation == .insufficientData)
        #expect(defaults.object(forKey: "monthlyReportAccumulators") as? NSDictionary == original)
    }

    @Test func legacyAccumulators_withNoDays_addNothing() {
        let clock = TestClock(2026, 11, 2, 9)
        let defaults = MemoryDefaults.make()
        seedAccumulators(defaults, month: monthStart(2026, 10), daysRecorded: 0)

        #expect(makeService(makeStore(clock), clock, defaults: defaults).availableMonths.isEmpty)
    }

    @Test func legacyAccumulators_forAMonthAlreadyInTheBlob_doNotCrash() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let defaults = MemoryDefaults.make()
        try seedLegacy(defaults, [legacyEntry(month: monthStart(2026, 10), peak: 280)])
        seedAccumulators(defaults, month: monthStart(2026, 10))

        let service = makeService(makeStore(clock), clock, defaults: defaults)

        #expect(service.availableMonths == ["2026-10"])
        #expect(service.summary(for: "2026-10")?.peakDownloadMbps == 280)
    }

    /// Final review F1: a month with both old data and daily records shows both, merged.
    @Test func legacyAndDailyForTheSameMonth_areMerged() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let defaults = MemoryDefaults.make()
        try seedLegacy(defaults, [legacyEntry(month: monthStart(2026, 11), daysMonitored: 1, peak: 999)])
        let store = makeStore(clock)
        feed(store, clock, mbps: 50, seconds: 5)

        let service = makeService(store, clock, defaults: defaults)

        #expect(service.availableMonths == ["2026-11"])
        let summary = try #require(service.summary(for: "2026-11"))
        #expect(summary.peakDownloadMbps == 999)
        #expect(summary.daysMonitored == 1)
        #expect(summary.disconnectCount == 1)
    }

    @Test func availableMonths_mergesDailyAndLegacy_newestFirst() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let defaults = MemoryDefaults.make()
        try seedLegacy(defaults, [legacyEntry(month: monthStart(2026, 8)), legacyEntry(month: monthStart(2026, 10))])
        let store = makeStore(clock)
        feed(store, clock, seconds: 1)

        #expect(makeService(store, clock, defaults: defaults).availableMonths == ["2026-11", "2026-10", "2026-08"])
    }

    @Test func newCode_neverWritesLegacyKeys() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let defaults = MemoryDefaults.make()
        try seedLegacy(defaults, [legacyEntry(month: monthStart(2026, 9))])
        seedAccumulators(defaults, month: monthStart(2026, 10))
        let blob = try #require(defaults.data(forKey: "monthlySummaries"))
        let accumulators = defaults.object(forKey: "monthlyReportAccumulators") as? NSDictionary

        let store = makeStore(clock)
        let service = makeService(store, clock, defaults: defaults)
        feed(store, clock, seconds: 700)
        store.flush()
        _ = service.availableMonths
        for month in service.availableMonths {
            _ = service.summary(for: month).map(service.exportToCSV)
        }

        #expect(defaults.data(forKey: "monthlySummaries") == blob)
        #expect(defaults.object(forKey: "monthlyReportAccumulators") as? NSDictionary == accumulators)
    }

    // MARK: - Calendars and time zones

    @Test func tzMonthKey_stable() throws {
        let clock = TestClock(2026, 11, 1, 0, 30) // Taipei
        let store = makeStore(clock)
        feed(store, clock, seconds: 700)

        let losAngeles = clock.appClock(in: Self.losAngeles) // still 10/31 there
        let service = MonthlyReportService(userDefaults: MemoryDefaults.make(), dailyStore: store, clock: losAngeles)

        #expect(service.currentMonthKey == "2026-10")
        #expect(service.availableMonths == ["2026-11"])
        #expect(service.defaultMonthKey == "2026-11")
        let summary = try #require(service.summary(for: "2026-11"))
        #expect(summary.monthKey == "2026-11")
        #expect(summary.formattedMonth == "2026/11")
        #expect(service.summary(for: "2026-10") == nil)
    }

    @Test func formattedMonth_rocCalendar() throws {
        let clock = TestClock(2026, 11, 2, 9)
        var minguo = Calendar(identifier: .republicOfChina)
        minguo.timeZone = clock.calendar.timeZone
        let appClock = AppClock(now: { clock.now }, monotonic: { clock.monotonic }, calendar: minguo)
        let store = DailyRecordStore(store: InMemoryBlobStore(), clock: appClock)
        store.ingest(speed(10), planDownloadMbps: 300, planUploadMbps: 300)

        let service = MonthlyReportService(userDefaults: MemoryDefaults.make(), dailyStore: store, clock: appClock)

        #expect(service.currentMonthKey == "2026-11")
        #expect(try #require(service.summary(for: "2026-11")).formattedMonth == "2026/11")
    }

    // MARK: - CSV

    @Test func csv_containsScopeNote() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)
        feed(store, clock, seconds: 5)
        store.recordLatencyFailure()
        store.recordLatencyFailure()

        let service = makeService(store, clock)
        let csv = service.exportToCSV(try #require(service.summary(for: "2026-11")))
        let rows = csv.components(separatedBy: "\n")

        #expect(rows.contains("Scope,This Mac only; includes LAN traffic"))
        #expect(rows.contains("Latency Probe Failures,2"))
        #expect(rows.contains("Month,2026/11"))
    }

    /// A month with no successful probe has no latency: the cells are empty, so a spreadsheet
    /// does not read 0.0 ms as a measurement and average it in.
    @Test func csv_withoutLatencyData_hasEmptyLatencyAndJitterCells() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)
        feed(store, clock, seconds: 5)
        store.recordLatencyFailure()

        let service = makeService(store, clock)
        let rows = service.exportToCSV(try #require(service.summary(for: "2026-11")))
            .components(separatedBy: "\n")

        #expect(rows.contains("Avg Latency (ms),"))
        #expect(rows.contains("Avg Jitter (ms),"))
        #expect(!rows.contains { $0.hasPrefix("Avg Latency") && $0.contains("0.0") })
        #expect(!rows.contains { $0.hasPrefix("Avg Jitter") && $0.contains("0.0") })
    }

    @Test func csv_withLatencyData_hasTheAverages() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)
        feed(store, clock, seconds: 5)
        store.recordLatency(latencyMs: 40, jitterMs: 4)
        store.recordLatency(latencyMs: 60, jitterMs: 6)

        let service = makeService(store, clock)
        let rows = service.exportToCSV(try #require(service.summary(for: "2026-11")))
            .components(separatedBy: "\n")

        #expect(rows.contains("Avg Latency (ms),50.0"))
        #expect(rows.contains("Avg Jitter (ms),5.0"))
    }

    @Test func csv_ofALegacySummary_hasNoFailureCount() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let defaults = MemoryDefaults.make()
        try seedLegacy(defaults, [legacyEntry(month: monthStart(2026, 9))])
        let service = makeService(makeStore(clock), clock, defaults: defaults)

        let csv = service.exportToCSV(try #require(service.summary(for: "2026-09")))

        #expect(csv.components(separatedBy: "\n").contains("Latency Probe Failures,N/A"))
    }

    // MARK: - The month in progress when the user upgraded (final review F1)

    /// The old version's accumulators for November: 20 days, every one with a 290 Mbps peak.
    private func seedNovemberInProgress(_ defaults: UserDefaults) {
        defaults.set([
            "dailyPeakDownloads": Array(repeating: 290.0, count: 20),
            "dailyPeakUploads": Array(repeating: 20.0, count: 20),
            "dailyAvgDownloads": Array(repeating: 30.0, count: 20),
            "dailyAvgUploads": Array(repeating: 3.0, count: 20),
            "monthlyPeakApproachCount": 4,
            "monthlyDisconnectCount": 2,
            "monthlyTotalDowntime": 90.0,
            "dailyLatencies": Array(repeating: 20.0, count: 20),
            "dailyJitters": Array(repeating: 4.0, count: 20),
            "daysRecorded": 20,
            "currentMonthStart": monthStart(2026, 11).timeIntervalSince1970,
        ] as [String: Any], forKey: "monthlyReportAccumulators")
    }

    /// Feeds `days` counted days (600 samples each) starting today, one calendar day apart.
    private func feedCountedDays(_ store: DailyRecordStore, _ clock: TestClock, mbps: Double, days: Int) {
        for day in 0..<days {
            feed(store, clock, mbps: mbps, seconds: ReportRules.minDailySamples)
            if day < days - 1 { clock.advance(by: 86_400 - Double(ReportRules.minDailySamples)) }
        }
    }

    @Test func legacyCurrentMonth_survivesFirstSample() throws {
        let clock = TestClock(2026, 11, 21, 9)
        let defaults = MemoryDefaults.make()
        seedNovemberInProgress(defaults)
        let store = makeStore(clock)
        let service = makeService(store, clock, defaults: defaults)
        let before = try #require(service.summary(for: "2026-11"))
        #expect(before.daysMonitored == 20)
        #expect(before.peakDownloadMbps == 290)

        store.ingest(speed(5), planDownloadMbps: 300, planUploadMbps: 300)

        let after = try #require(service.summary(for: "2026-11"))
        #expect(after.daysMonitored == 20, "legacy days hidden: \(after.daysMonitored)")
        #expect(after.peakDownloadMbps == 290, "legacy peak hidden: \(after.peakDownloadMbps)")
        #expect(after.peakApproachCount == 4)
        #expect(after.disconnectCount == 2)
        #expect(after.totalDowntimeSeconds == 90)
        #expect(after.avgLatencyMs == 20)
        #expect(after.avgJitterMs == 4)
    }

    @Test func legacyCurrentMonth_mergesWithCountedDays() throws {
        let clock = TestClock(2026, 11, 21, 9)
        let defaults = MemoryDefaults.make()
        seedNovemberInProgress(defaults)
        let store = makeStore(clock)
        feedCountedDays(store, clock, mbps: 100, days: 1)

        let summary = try #require(makeService(store, clock, defaults: defaults).summary(for: "2026-11"))

        #expect(summary.daysMonitored == 21)
        #expect(summary.peakDownloadMbps == 290)
        // The legacy peak has no time; the time shown belongs to the daily peak only when it wins.
        #expect(summary.peakDownloadTime == nil)
        // Averages are weighted by days: 20 days at 30, 1 day at 100.
        #expect(abs(summary.avgDownloadMbps - (30.0 * 20 + 100) / 21) < 0.001)
        #expect(summary.disconnectCount == 2)
        #expect(summary.totalDowntimeSeconds == 90)
        // No probe in the daily record: the legacy latency stands alone.
        #expect(summary.avgLatencyMs == 20)
        #expect(summary.planDownloadMbps == 300)
        #expect(abs(summary.downloadPlanUtilization - 290.0 / 300 * 100) < 0.001)
        // The recommendation rests on the daily records alone: 1 counted day is not enough.
        #expect(summary.recommendationDayCount == 1)
        #expect(summary.recommendation == .insufficientData)
    }

    @Test func legacyCurrentMonth_higherDailyPeakWins() throws {
        let clock = TestClock(2026, 11, 21, 9)
        let defaults = MemoryDefaults.make()
        seedNovemberInProgress(defaults)
        let store = makeStore(clock)
        feed(store, clock, mbps: 400, seconds: 5)

        let summary = try #require(makeService(store, clock, defaults: defaults).summary(for: "2026-11"))

        #expect(summary.peakDownloadMbps == 400)
        #expect(summary.peakDownloadTime != nil)
    }

    /// Legacy days never count towards the 14 days a downgrade needs.
    @Test func legacyCurrentMonth_legacyDaysDoNotUnlockADowngrade() throws {
        let clock = TestClock(2026, 11, 21, 9)
        let defaults = MemoryDefaults.make()
        seedNovemberInProgress(defaults)
        let store = makeStore(clock)
        feedCountedDays(store, clock, mbps: 10, days: ReportRules.minDaysForRecommendation)

        let summary = try #require(makeService(store, clock, defaults: defaults).summary(for: "2026-11"))

        #expect(summary.daysMonitored == 20 + ReportRules.minDaysForRecommendation)
        #expect(summary.recommendationDayCount == ReportRules.minDaysForRecommendation)
        #expect(summary.recommendation == .planFits)
    }

    /// The old data is read, never written, so a second launch shows the same month.
    @Test func legacyCurrentMonth_secondLaunch_countsOnce() throws {
        let clock = TestClock(2026, 11, 21, 9)
        let defaults = MemoryDefaults.make()
        seedNovemberInProgress(defaults)
        let blobs = InMemoryBlobStore()
        let store = makeStore(clock, blobs)
        feedCountedDays(store, clock, mbps: 100, days: 1)
        let first = try #require(makeService(store, clock, defaults: defaults).summary(for: "2026-11"))
        store.flush()

        let second = try #require(makeService(makeStore(clock, blobs), clock, defaults: defaults).summary(for: "2026-11"))

        #expect(second.daysMonitored == first.daysMonitored)
        #expect(second.daysMonitored == 21)
        #expect(second.peakApproachCount == first.peakApproachCount)
        #expect(second.disconnectCount == first.disconnectCount)
        #expect(second.totalDowntimeSeconds == first.totalDowntimeSeconds)
        #expect(second.avgDownloadMbps == first.avgDownloadMbps)
    }

    // MARK: - The upgrade day counted once (re-review N1)

    /// The old format keeps a day count, not dates. Legacy days can only lie on or before the
    /// first daily day, so with the first daily day counted they add at most (its day of month
    /// - 1) days: November 1-21 by the old version plus November 21-30 by the new one is 30 days.
    @Test func legacyThroughTheUpgradeDay_countsThatDayOnce() throws {
        let clock = TestClock(2026, 11, 21, 9)
        let defaults = MemoryDefaults.make()
        seedNovemberInProgress(defaults)
        var stored = try #require(defaults.dictionary(forKey: "monthlyReportAccumulators"))
        stored["daysRecorded"] = 21  // the old version also snapshotted November 21
        defaults.set(stored, forKey: "monthlyReportAccumulators")
        let store = makeStore(clock)
        feedCountedDays(store, clock, mbps: 100, days: 10)  // November 21-30

        let summary = try #require(makeService(store, clock, defaults: defaults).summary(for: "2026-11"))

        #expect(summary.daysMonitored == 30, "upgrade day counted twice: \(summary.daysMonitored)")
        #expect(summary.recommendationDayCount == 10)
    }

    /// When the first daily day is not counted yet, a legacy day may still be the only record
    /// of it, so it can count.
    @Test func legacyThroughTheUpgradeDay_uncountedFirstDay_keepsTheLegacyDay() throws {
        let clock = TestClock(2026, 11, 21, 9)
        let defaults = MemoryDefaults.make()
        seedNovemberInProgress(defaults)
        var stored = try #require(defaults.dictionary(forKey: "monthlyReportAccumulators"))
        stored["daysRecorded"] = 22  // more than November 1-21 can hold
        defaults.set(stored, forKey: "monthlyReportAccumulators")
        let store = makeStore(clock)
        feed(store, clock, mbps: 5, seconds: 5)

        let summary = try #require(makeService(store, clock, defaults: defaults).summary(for: "2026-11"))

        #expect(summary.daysMonitored == 21)
    }

    /// A legacy month that ended before the upgrade day is untouched.
    @Test func legacyBeforeTheUpgradeDay_keepsEveryDay() throws {
        let clock = TestClock(2026, 11, 21, 9)
        let defaults = MemoryDefaults.make()
        seedNovemberInProgress(defaults)
        let store = makeStore(clock)
        feedCountedDays(store, clock, mbps: 100, days: 10)

        let summary = try #require(makeService(store, clock, defaults: defaults).summary(for: "2026-11"))

        #expect(summary.daysMonitored == 30)
    }
}
