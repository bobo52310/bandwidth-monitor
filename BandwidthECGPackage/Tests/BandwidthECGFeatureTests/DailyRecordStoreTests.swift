import Testing
import Foundation
@testable import BandwidthECGFeature

@MainActor
@Suite("DailyRecordStore")
struct DailyRecordStoreTests {
    private static let taipei = TimeZone(identifier: "Asia/Taipei")!
    private static let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private static let newYork = TimeZone(identifier: "America/New_York")!

    private func speed(_ downloadMbps: Double, up uploadMbps: Double = 0) -> NetworkSpeed {
        NetworkSpeed(uploadSpeed: uploadMbps * 125_000, downloadSpeed: downloadMbps * 125_000)
    }

    private func makeStore(_ clock: TestClock, _ blobs: InMemoryBlobStore = InMemoryBlobStore()) -> DailyRecordStore {
        DailyRecordStore(store: blobs, clock: clock.appClock)
    }

    /// Ingests one sample, plan 300/300 unless given.
    private func ingest(
        _ store: DailyRecordStore,
        _ mbps: Double,
        up: Double = 0,
        planDown: Double = 300,
        planUp: Double = 300
    ) {
        store.ingest(speed(mbps, up: up), planDownloadMbps: planDown, planUploadMbps: planUp)
    }

    /// One sample per second. The clock ends one second after the last sample.
    private func feed(
        _ store: DailyRecordStore,
        _ clock: TestClock,
        mbps: Double,
        up: Double = 0,
        seconds: Int,
        planDown: Double = 300,
        planUp: Double = 300
    ) {
        for _ in 0..<seconds {
            ingest(store, mbps, up: up, planDown: planDown, planUp: planUp)
            clock.advance(by: 1)
        }
    }

    private func today(_ store: DailyRecordStore, _ clock: TestClock) -> DailyRecord? {
        store.records[DayKey.day(for: clock.now, calendar: clock.calendar)]
    }

    private func summary(_ store: DailyRecordStore, _ monthKey: String) -> MonthlySummary {
        MonthlySummary.make(monthKey: monthKey, month: Date(timeIntervalSince1970: 0), days: store.records(inMonth: monthKey))
    }

    private func fileJSON(_ blobs: InMemoryBlobStore) throws -> [String: Any] {
        let data = try #require(blobs.contents(of: DailyRecordStore.fileName))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - The failures this rewrite exists to fix

    /// CORE-02. The old daily snapshot reported peak 1.0, utilization 0.3% and "downgrade".
    @Test func eveningPeak_entersDailyRecord() {
        let clock = TestClock(2026, 10, 1, 20, 50)
        let store = makeStore(clock)

        for _ in 1...31 {
            feed(store, clock, mbps: 1, seconds: 600)
            feed(store, clock, mbps: 280, seconds: 10)
            clock.advance(by: 86_400 - 610)
        }

        let report = summary(store, "2026-10")
        #expect(report.peakDownloadMbps == 280)
        #expect(abs(report.downloadPlanUtilization - 93.3) < 0.1)
        #expect(report.daysMonitored == 31)
        #expect(report.saturatedDays == 31)
        #expect(report.recommendation == .considerUpgrade)
    }

    @Test func laptopShortSession_recorded() {
        let clock = TestClock(2026, 11, 1, 9)
        let store = makeStore(clock)

        for _ in 1...30 {
            feed(store, clock, mbps: 20, seconds: 50 * 60)
            clock.advance(by: 86_400 - 50 * 60)
        }

        #expect(summary(store, "2026-11").daysMonitored == 30)
    }

    @Test func midnightNoTraffic_attributesToPreviousDay() throws {
        let clock = TestClock(2026, 11, 1, 23, 59, 59)
        let store = makeStore(clock)
        ingest(store, 50)
        let previous = try #require(store.records["2026-11-01"])

        clock.advance(by: 601) // 00:10:00
        ingest(store, 5)

        #expect(store.records.count == 2)
        #expect(store.records["2026-11-01"] == previous)
        #expect(store.records["2026-11-02"]?.sampleCount == 1)
    }

    @Test func closedAtMidnight_nextLaunchKeepsRecord() {
        let clock = TestClock(2026, 11, 1, 23, 50)
        let blobs = InMemoryBlobStore()
        let store = makeStore(clock, blobs)
        feed(store, clock, mbps: 280, seconds: 5)
        store.flush()

        clock.advance(by: 86_400)
        let relaunched = makeStore(clock, blobs)
        ingest(relaunched, 1)

        #expect(relaunched.records["2026-11-01"]?.sustainedPeakDownloadMbps == 280)
        #expect(relaunched.records["2026-11-01"]?.sampleCount == 5)
        #expect(relaunched.records["2026-11-02"]?.sampleCount == 1)
    }

    @Test func sameDayRelaunch_oneRecord() {
        let clock = TestClock(2026, 11, 2, 9)
        let blobs = InMemoryBlobStore()

        for _ in 1...3 {
            let store = makeStore(clock, blobs)
            feed(store, clock, mbps: 10, seconds: 100)
            store.flush()
        }

        let store = makeStore(clock, blobs)
        #expect(store.records.count == 1)
        #expect(store.records["2026-11-02"]?.sampleCount == 300)
    }

    /// CORE-09: the old report averaged duplicated rows.
    @Test func monthlyAvg_isTrueMean() {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)

        feed(store, clock, mbps: 10, seconds: 1200)
        feed(store, clock, mbps: 90, seconds: 400)

        #expect(abs(summary(store, "2026-11").avgDownloadMbps - 30.0) < 1e-9)
    }

    @Test func monthBoundary_splits() {
        let clock = TestClock(2026, 10, 31, 23, 59)
        let store = makeStore(clock)
        ingest(store, 10)

        clock.advance(by: 120) // 11/01 00:01
        ingest(store, 20)

        #expect(store.records(inMonth: "2026-10").map(\.dayKey) == ["2026-10-31"])
        #expect(store.records(inMonth: "2026-11").map(\.dayKey) == ["2026-11-01"])
    }

    @Test(arguments: [(3, 8, 23), (11, 1, 25)])
    func dstDay_newYork(month: Int, day: Int, hours: Int) {
        let clock = TestClock(2026, month, day, 0, 30, 0, timeZone: Self.newYork)
        let store = makeStore(clock)

        for _ in 0..<hours {
            ingest(store, 10)
            clock.advance(by: 3_600)
        }

        #expect(store.records.count == 1)
        #expect(store.records.values.first?.sampleCount == hours)
    }

    /// Flying west while the app runs moves the date back. The existing record must continue.
    @Test func timezoneBackwards_resumesExistingRecord() throws {
        let clock = TestClock(2026, 11, 14, 23, 30)
        let store = makeStore(clock)
        feed(store, clock, mbps: 50, seconds: 10)
        let before = try #require(store.records["2026-11-14"])

        clock.advance(by: 3_600) // 11/15 00:30 in Taipei
        ingest(store, 5)
        #expect(store.records["2026-11-15"] != nil)

        store.clock = clock.appClock(in: Self.losAngeles) // 11/14 08:30 in Los Angeles
        ingest(store, 5)

        let after = try #require(store.records["2026-11-14"])
        #expect(after.sampleCount == before.sampleCount + 1)
        #expect(after.downloadSum == before.downloadSum + 5)
        #expect(after.sustainedPeakDownloadMbps == before.sustainedPeakDownloadMbps)
    }

    @Test func planChange_doesNotRewritePreviousDay() {
        let clock = TestClock(2026, 10, 31, 22)
        let store = makeStore(clock)
        feed(store, clock, mbps: 240, seconds: 700)
        let october = summary(store, "2026-10")

        clock.advance(by: 86_400)
        feed(store, clock, mbps: 240, seconds: 700, planDown: 1000)

        let later = summary(store, "2026-10")
        #expect(later.planDownloadMbps == 300)
        #expect(later.downloadPlanUtilization == october.downloadPlanUtilization)
        #expect(summary(store, "2026-11").planDownloadMbps == 1000)
    }

    // MARK: - Sustained peak

    @Test func spike_neverBecomesTheSustainedPeak() {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)

        for mbps in [1.0, 276, 1] {
            ingest(store, mbps)
            clock.advance(by: 1)
        }

        #expect(today(store, clock)?.sustainedPeakDownloadMbps == 1)
    }

    @Test func downloadAndUpload_haveSeparateWindows() {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)

        feed(store, clock, mbps: 200, up: 40, seconds: 3)

        #expect(today(store, clock)?.sustainedPeakDownloadMbps == 200)
        #expect(today(store, clock)?.sustainedPeakUploadMbps == 40)
    }

    /// A single sample after a long gap spans the whole gap. It must not raise the peak by
    /// completing the two samples from before the gap.
    @Test func sampleAfterALongGap_cannotBridgeTwoEarlierSamples() {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)
        feed(store, clock, mbps: 280, seconds: 2)

        clock.advance(by: 3_600)
        ingest(store, 280)

        #expect(today(store, clock)?.sustainedPeakDownloadMbps == 0)
    }

    @Test func sampleAfterALongGap_cannotExtendAFinishedWindow() {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)
        feed(store, clock, mbps: 100, seconds: 3)
        #expect(today(store, clock)?.sustainedPeakDownloadMbps == 100)

        clock.advance(by: 3_600)
        ingest(store, 280)
        clock.advance(by: 1)
        ingest(store, 280)

        #expect(today(store, clock)?.sustainedPeakDownloadMbps == 100)
    }

    @Test func gapOfThreeSeconds_resetsTheWindowInBothDirections() {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)
        feed(store, clock, mbps: 280, up: 280, seconds: 2)

        clock.advance(by: 2) // 3 seconds after the previous sample
        ingest(store, 280, up: 280)

        #expect(today(store, clock)?.sustainedPeakDownloadMbps == 0)
        #expect(today(store, clock)?.sustainedPeakUploadMbps == 0)
    }

    @Test func gapOfTwoSeconds_keepsTheWindow() {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)
        feed(store, clock, mbps: 280, seconds: 2)

        clock.advance(by: 1) // 2 seconds after the previous sample
        ingest(store, 280)

        #expect(today(store, clock)?.sustainedPeakDownloadMbps == 280)
    }

    @Test func wallClockJump_doesNotLookLikeAGap() {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)
        feed(store, clock, mbps: 280, seconds: 2)

        clock.setWall(clock.now.addingTimeInterval(600)) // same day, monotonic time unchanged
        ingest(store, 280)

        #expect(today(store, clock)?.sustainedPeakDownloadMbps == 280)
    }

    // MARK: - Peak times

    @Test func peakTime_isWhenTheSustainedPeakWasReached() throws {
        let clock = TestClock(2026, 11, 2, 21)
        let store = makeStore(clock)
        feed(store, clock, mbps: 100, up: 60, seconds: 2)
        let reachedAt = clock.now
        feed(store, clock, mbps: 100, up: 60, seconds: 1)

        clock.advance(by: 600)
        feed(store, clock, mbps: 50, up: 20, seconds: 5) // lower, so it must not move the time

        let record = try #require(today(store, clock))
        #expect(record.sustainedPeakDownloadMbps == 100)
        #expect(record.sustainedPeakDownloadTime == reachedAt)
        #expect(record.sustainedPeakUploadTime == reachedAt)
    }

    @Test func peakTime_movesWithANewPeak_perDirection() throws {
        let clock = TestClock(2026, 11, 2, 21)
        let store = makeStore(clock)
        feed(store, clock, mbps: 100, up: 60, seconds: 3)
        let uploadTime = clock.now.addingTimeInterval(-1)

        clock.advance(by: 600)
        feed(store, clock, mbps: 200, up: 10, seconds: 2)
        let downloadTime = clock.now
        feed(store, clock, mbps: 200, up: 10, seconds: 1)

        let record = try #require(today(store, clock))
        #expect(record.sustainedPeakDownloadTime == downloadTime)
        #expect(record.sustainedPeakUploadTime == uploadTime)
    }

    @Test func noSustainedPeak_noPeakTime() throws {
        let clock = TestClock(2026, 11, 2, 21)
        let store = makeStore(clock)

        feed(store, clock, mbps: 280, up: 280, seconds: 2)

        let record = try #require(today(store, clock))
        #expect(record.sustainedPeakDownloadTime == nil)
        #expect(record.sustainedPeakUploadTime == nil)
    }

    @Test func peakTimes_surviveARelaunch() throws {
        let clock = TestClock(2026, 11, 2, 21)
        let blobs = InMemoryBlobStore()
        let store = makeStore(clock, blobs)
        feed(store, clock, mbps: 100, up: 60, seconds: 3)
        store.flush()

        let relaunched = makeStore(clock, blobs)

        #expect(relaunched.records == store.records)
        #expect(try #require(today(relaunched, clock)).sustainedPeakDownloadTime != nil)
    }

    /// A file from before the peak times existed still loads, and new peaks can fill them in.
    @Test func recordWithoutPeakTimes_loadsAndCanGainThem() throws {
        let clock = TestClock(2026, 11, 2, 21)
        let blobs = InMemoryBlobStore()
        blobs.seed(
            Data(#"{"schemaVersion":1,"records":[{"dayKey":"2026-11-02","sustainedPeakDownloadMbps":50,"sampleCount":700}]}"#.utf8),
            named: DailyRecordStore.fileName
        )

        let store = makeStore(clock, blobs)
        let loaded = try #require(store.records["2026-11-02"])
        #expect(loaded.sustainedPeakDownloadMbps == 50)
        #expect(loaded.sustainedPeakDownloadTime == nil)
        #expect(blobs.quarantined.isEmpty)

        feed(store, clock, mbps: 100, seconds: 3)

        #expect(store.records["2026-11-02"]?.sustainedPeakDownloadMbps == 100)
        #expect(store.records["2026-11-02"]?.sustainedPeakDownloadTime != nil)
    }

    // MARK: - Implausible samples

    @Test func sampleAboveTheCap_isDropped() {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)

        feed(store, clock, mbps: SampleGuard.maxPlausibleMbps + 1, seconds: 5)
        feed(store, clock, mbps: 1, up: SampleGuard.maxPlausibleMbps + 1, seconds: 5)

        #expect(store.records.isEmpty)
    }

    @Test func sampleAtTheCap_isKept() {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)

        feed(store, clock, mbps: SampleGuard.maxPlausibleMbps, up: SampleGuard.maxPlausibleMbps, seconds: 3)

        #expect(today(store, clock)?.sampleCount == 3)
        #expect(today(store, clock)?.sustainedPeakDownloadMbps == SampleGuard.maxPlausibleMbps)
        #expect(today(store, clock)?.sustainedPeakUploadMbps == SampleGuard.maxPlausibleMbps)
    }

    @Test func notANumberSample_isDropped_soTheFileStaysEncodable() {
        let clock = TestClock(2026, 11, 2, 9)
        let blobs = InMemoryBlobStore()
        let store = makeStore(clock, blobs)

        store.ingest(NetworkSpeed(uploadSpeed: 0, downloadSpeed: .nan), planDownloadMbps: 300, planUploadMbps: 300)
        store.ingest(NetworkSpeed(uploadSpeed: .infinity, downloadSpeed: 0), planDownloadMbps: 300, planUploadMbps: 300)

        #expect(store.records.isEmpty)
    }

    // MARK: - Persistence

    @Test func flush_atMostOncePerInterval() {
        let clock = TestClock(2026, 11, 2, 9)
        let blobs = InMemoryBlobStore()
        let store = makeStore(clock, blobs)

        feed(store, clock, mbps: 10, seconds: 600)
        #expect(blobs.writeCount <= 2)
        #expect(blobs.writeCount >= 1)

        let automatic = blobs.writeCount
        store.flush()
        #expect(blobs.writeCount == automatic + 1)
    }

    /// Literal seconds on purpose: this pins the interval, not just the comparison.
    @Test func automaticFlush_noWriteAt299Seconds_writesAt300() {
        let clock = TestClock(2026, 11, 2, 9)
        let blobs = InMemoryBlobStore()
        let store = makeStore(clock, blobs)

        feed(store, clock, mbps: 10, seconds: 300) // the last sample is 299 s after the start
        #expect(blobs.writeCount == 0)

        ingest(store, 10) // 300 s
        #expect(blobs.writeCount == 1)
    }

    @Test func flush_withNothingNew_writesNothing() {
        let clock = TestClock(2026, 11, 2, 9)
        let blobs = InMemoryBlobStore()
        let store = makeStore(clock, blobs)

        store.flush()

        #expect(blobs.writeCount == 0)
    }

    @Test func flush_twice_writesOnce() {
        let clock = TestClock(2026, 11, 2, 9)
        let blobs = InMemoryBlobStore()
        let store = makeStore(clock, blobs)
        ingest(store, 10)

        store.flush()
        store.flush()

        #expect(blobs.writeCount == 1)
    }

    @Test func file_hasTheVersionedFormat() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let blobs = InMemoryBlobStore()
        let store = makeStore(clock, blobs)
        ingest(store, 10)
        store.flush()

        let json = try fileJSON(blobs)
        #expect(json["schemaVersion"] as? Int == 1)
        let records = try #require(json["records"] as? [[String: Any]])
        #expect(records.map { $0["dayKey"] as? String } == ["2026-11-02"])
    }

    @Test func truncatedFile_quarantined() {
        let clock = TestClock(2026, 11, 2, 9)
        let blobs = InMemoryBlobStore()
        blobs.seed(Data(#"{"schemaVersion":1,"records":[{"dayK"#.utf8), named: DailyRecordStore.fileName)

        let store = makeStore(clock, blobs)
        #expect(blobs.quarantined == [DailyRecordStore.fileName])
        #expect(store.records.isEmpty)

        ingest(store, 10)
        store.flush()

        #expect(blobs.writeCount == 1)
        #expect(makeStore(clock, blobs).records.count == 1)
    }

    @Test func futureSchema_quarantined() {
        let clock = TestClock(2026, 11, 2, 9)
        let blobs = InMemoryBlobStore()
        let future = Data(#"{"schemaVersion":99,"records":[{"dayKey":"2026-11-02","sampleCount":5}]}"#.utf8)
        blobs.seed(future, named: DailyRecordStore.fileName)

        let store = makeStore(clock, blobs)

        #expect(blobs.quarantined == [DailyRecordStore.fileName])
        #expect(store.records.isEmpty)
        #expect(blobs.contents(of: "\(DailyRecordStore.fileName).corrupt-1") == future)
    }

    /// The file is intact, so writing an empty one over it would lose everything.
    @Test func unreadableFile_quarantinedNotOverwritten() {
        let clock = TestClock(2026, 11, 2, 9)
        let blobs = InMemoryBlobStore()
        let good = Data(#"{"schemaVersion":1,"records":[{"dayKey":"2026-11-01","sampleCount":5}]}"#.utf8)
        blobs.seed(good, named: DailyRecordStore.fileName)
        blobs.failNextRead = true

        let store = makeStore(clock, blobs)
        ingest(store, 10)
        store.flush()

        #expect(blobs.contents(of: "\(DailyRecordStore.fileName).corrupt-1") == good)
    }

    /// A bad file that cannot be moved aside is still the live file, so it must not be replaced.
    @Test func quarantineFailure_neverOverwritesTheBadFile() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let blobs = InMemoryBlobStore()
        let bad = Data("half a file".utf8)
        blobs.seed(bad, named: DailyRecordStore.fileName)
        blobs.failQuarantine = true

        let store = makeStore(clock, blobs)
        ingest(store, 10)
        store.flush()

        #expect(blobs.writeCount == 0)
        #expect(blobs.contents(of: DailyRecordStore.fileName) == bad)
        #expect(store.records.count == 1)

        blobs.failQuarantine = false
        store.flush()

        #expect(blobs.contents(of: "\(DailyRecordStore.fileName).corrupt-1") == bad)
        #expect(blobs.writeCount == 1)
        #expect(try fileJSON(blobs)["schemaVersion"] as? Int == 1)
    }

    @Test func duplicateDayKeys_doNotCrash() {
        let clock = TestClock(2026, 11, 2, 9)
        let blobs = InMemoryBlobStore()
        blobs.seed(
            Data(#"{"schemaVersion":1,"records":[{"dayKey":"2026-11-02","sampleCount":5},{"dayKey":"2026-11-02","sampleCount":9}]}"#.utf8),
            named: DailyRecordStore.fileName
        )

        let store = makeStore(clock, blobs)

        #expect(store.records.count == 1)
        #expect(blobs.quarantined.isEmpty)
    }

    @Test func writeFailure_keepsDataAndRetries() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let blobs = InMemoryBlobStore()
        let store = makeStore(clock, blobs)
        ingest(store, 10)

        blobs.failNextWrite = true
        store.flush()
        #expect(blobs.writeCount == 0)
        #expect(store.records.count == 1)

        store.flush()
        #expect(blobs.writeCount == 1)
        #expect(makeStore(clock, blobs).records == store.records)
    }

    /// A failing disk is retried at the normal pace, not once per sample.
    @Test func writeFailure_duringIngest_retriesAfterTheInterval() {
        let clock = TestClock(2026, 11, 2, 9)
        let blobs = InMemoryBlobStore()
        let store = makeStore(clock, blobs)
        blobs.failNextWrite = true

        feed(store, clock, mbps: 10, seconds: 302) // the write at 300 s fails
        #expect(blobs.failNextWrite == false)
        #expect(blobs.writeCount == 0)

        feed(store, clock, mbps: 10, seconds: 300) // retried at 600 s
        #expect(blobs.writeCount == 1)
    }

    @Test func retention_prunes400Days() {
        let clock = TestClock(2026, 11, 2, 9)
        let blobs = InMemoryBlobStore()
        let oldest = clock.calendar.date(byAdding: .day, value: -400, to: clock.now)!
        let expired = clock.calendar.date(byAdding: .day, value: -401, to: clock.now)!
        let kept = DayKey.day(for: oldest, calendar: clock.calendar)
        let removed = DayKey.day(for: expired, calendar: clock.calendar)
        blobs.seed(
            Data(#"{"schemaVersion":1,"records":[{"dayKey":"\#(kept)"},{"dayKey":"\#(removed)"}]}"#.utf8),
            named: DailyRecordStore.fileName
        )

        let store = makeStore(clock, blobs)

        #expect(store.records[removed] == nil)
        #expect(store.records[kept] != nil)
    }

    /// Pruning at launch counts as a change, so a run without a single sample still persists it.
    @Test func retention_atLaunch_reachesTheFile() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let blobs = InMemoryBlobStore()
        blobs.seed(
            Data(#"{"schemaVersion":1,"records":[{"dayKey":"2020-01-01"},{"dayKey":"2026-11-01"}]}"#.utf8),
            named: DailyRecordStore.fileName
        )

        makeStore(clock, blobs).flush()

        let records = try #require(try fileJSON(blobs)["records"] as? [[String: Any]])
        #expect(records.map { $0["dayKey"] as? String } == ["2026-11-01"])
    }

    @Test func retention_alsoRunsWhileTheAppKeepsRunning() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let blobs = InMemoryBlobStore()
        let store = makeStore(clock, blobs)
        ingest(store, 10)
        store.flush()

        clock.advance(by: 401 * 86_400)
        ingest(store, 10)
        store.flush()

        #expect(store.records["2026-11-02"] == nil)
        let records = try #require(try fileJSON(blobs)["records"] as? [[String: Any]])
        #expect(records.count == 1)
    }

    // MARK: - Other sources

    @Test func latency_dailyAverage() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)

        store.recordLatency(latencyMs: 100, jitterMs: 10)
        store.recordLatency(latencyMs: 200, jitterMs: 20)
        store.recordLatency(latencyMs: 300, jitterMs: 30)
        store.recordLatencyFailure()

        let record = try #require(today(store, clock))
        #expect(record.latencySum / Double(record.latencyCount) == 200)
        #expect(record.latencyCount == 3)
        #expect(record.latencyFailures == 1)
        #expect(record.jitterSum / Double(record.jitterCount) == 20)
    }

    /// A reading made from a single sample has no jitter. It still counts for the latency, but
    /// must not enter the jitter average as a 0.
    @Test func latency_withoutJitter_isNotAveragedIntoJitter() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)

        store.recordLatency(latencyMs: 100, jitterMs: nil)
        store.recordLatency(latencyMs: 200, jitterMs: 20)
        store.recordLatency(latencyMs: 300, jitterMs: 40)

        let record = try #require(today(store, clock))
        #expect(record.latencyCount == 3)
        #expect(record.latencySum / Double(record.latencyCount) == 200)
        #expect(record.jitterCount == 2)
        #expect(record.jitterSum / Double(record.jitterCount) == 30)
    }

    @Test func approachEvent_goesToTheCurrentDay() {
        let clock = TestClock(2026, 11, 2, 9)
        let store = makeStore(clock)

        store.recordApproachEvent()
        store.recordApproachEvent()

        #expect(today(store, clock)?.approachCount == 2)
    }

    @Test func disconnect_acrossMidnight_splits() {
        let clock = TestClock(2026, 11, 2, 0, 30)
        let store = makeStore(clock)
        let start = TestClock(2026, 11, 1, 23, 50).now
        let end = TestClock(2026, 11, 2, 0, 20).now

        store.recordDisconnect(start: start, end: end)

        #expect(store.records["2026-11-01"]?.downtimeSeconds == 600)
        #expect(store.records["2026-11-02"]?.downtimeSeconds == 1200)
        #expect(store.records["2026-11-01"]?.disconnectCount == 1)
        #expect(store.records["2026-11-02"]?.disconnectCount == 1)
    }

    @Test func disconnect_withinOneDay_isOneEntry() {
        let clock = TestClock(2026, 11, 2, 12)
        let store = makeStore(clock)
        let start = TestClock(2026, 11, 2, 11).now

        store.recordDisconnect(start: start, end: start.addingTimeInterval(90))

        #expect(store.records.count == 1)
        #expect(store.records["2026-11-02"]?.downtimeSeconds == 90)
        #expect(store.records["2026-11-02"]?.disconnectCount == 1)
    }

    @Test func disconnect_acrossSeveralDays_fillsTheDaysBetween() {
        let clock = TestClock(2026, 11, 4, 12)
        let store = makeStore(clock)
        let start = TestClock(2026, 11, 1, 23).now
        let end = TestClock(2026, 11, 3, 1).now

        store.recordDisconnect(start: start, end: end)

        #expect(store.records["2026-11-01"]?.downtimeSeconds == 3_600)
        #expect(store.records["2026-11-02"]?.downtimeSeconds == 86_400)
        #expect(store.records["2026-11-03"]?.downtimeSeconds == 3_600)
    }

    @Test func disconnect_acrossMonths_landsInBoth() {
        let clock = TestClock(2026, 11, 1, 1)
        let store = makeStore(clock)

        store.recordDisconnect(start: TestClock(2026, 10, 31, 23).now, end: TestClock(2026, 11, 1, 1).now)

        #expect(summary(store, "2026-10").totalDowntimeSeconds == 3_600)
        #expect(summary(store, "2026-11").totalDowntimeSeconds == 3_600)
    }

    /// `DisconnectTracker` uses the wall clock. If that moved back during the outage the event
    /// happened but has no usable length.
    @Test func disconnect_endingBeforeItStarts_countsWithoutDowntime() {
        let clock = TestClock(2026, 11, 2, 12)
        let store = makeStore(clock)
        let start = TestClock(2026, 11, 2, 11).now

        store.recordDisconnect(start: start, end: start.addingTimeInterval(-60))

        #expect(store.records["2026-11-02"]?.disconnectCount == 1)
        #expect(store.records["2026-11-02"]?.downtimeSeconds == 0)
    }

    // MARK: - Queries

    @Test func monthKeys_newestFirstWithoutDuplicates() {
        let clock = TestClock(2026, 9, 30, 12)
        let store = makeStore(clock)
        for _ in 0..<3 {
            ingest(store, 1)
            clock.advance(by: 86_400)
        }
        clock.advance(by: 31 * 86_400)
        ingest(store, 1)

        #expect(store.monthKeys == ["2026-11", "2026-10", "2026-09"])
    }

    @Test func recordsInMonth_oldestFirst() {
        let clock = TestClock(2026, 11, 1, 12)
        let store = makeStore(clock)
        for _ in 0..<8 { // enough days that dictionary order cannot pass by luck
            ingest(store, 1)
            clock.advance(by: 86_400)
        }

        let expected = (1...8).map { String(format: "2026-11-%02d", $0) }
        #expect(store.records(inMonth: "2026-11").map(\.dayKey) == expected)
        #expect(store.records(inMonth: "2026-10").isEmpty)
    }
}
