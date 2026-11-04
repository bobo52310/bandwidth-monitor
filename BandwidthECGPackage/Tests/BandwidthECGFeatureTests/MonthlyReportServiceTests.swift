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

    @Test func dailyTakesPrecedenceOverLegacy() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let defaults = MemoryDefaults.make()
        try seedLegacy(defaults, [legacyEntry(month: monthStart(2026, 11), peak: 999)])
        let store = makeStore(clock)
        feed(store, clock, mbps: 50, seconds: 5)

        let service = makeService(store, clock, defaults: defaults)

        #expect(service.availableMonths == ["2026-11"])
        #expect(service.summary(for: "2026-11")?.peakDownloadMbps == 50)
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
}
