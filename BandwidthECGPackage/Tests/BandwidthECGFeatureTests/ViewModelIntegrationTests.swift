import Testing
import Foundation
@testable import BandwidthECGFeature

/// The whole sample path, from counters through `tick()` to everything the view model feeds.
@MainActor
@Suite("ViewModel integration")
struct ViewModelIntegrationTests {
    private struct Step {
        var download: Double
        var upload: Double = 0
    }

    private static func reading(rx: UInt32, tx: UInt32) -> [String: InterfaceCounters] {
        let counters = InterfaceCounters(rx: rx, tx: tx)
        return ["en0": counters, "en1": counters, "en2": counters]
    }

    /// Counter readings for one sample per second: a baseline, then one reading per step.
    /// The speed is split over three interfaces, so an implausible one needs no counter to wrap.
    private static func script(_ steps: [Step]) -> [[String: InterfaceCounters]?] {
        var rx: UInt32 = 0
        var tx: UInt32 = 0
        var readings: [[String: InterfaceCounters]?] = [reading(rx: rx, tx: tx)]
        for step in steps {
            rx &+= UInt32(step.download * 125_000 / 3)
            tx &+= UInt32(step.upload * 125_000 / 3)
            readings.append(reading(rx: rx, tx: tx))
        }
        return readings
    }

    /// Takes the baseline without leaving the real 1 second timer running.
    private func makeViewModel(
        _ clock: TestClock,
        steps: [Step] = [],
        counters: FakeCounterSource? = nil,
        notifications: FakeNotificationDelivery = FakeNotificationDelivery(),
        probe: FakeLatencyProbe = FakeLatencyProbe(),
        pathSource: FakePathSource = FakePathSource(),
        blobs: InMemoryBlobStore = InMemoryBlobStore()
    ) -> NetworkMonitorViewModel {
        let viewModel = NetworkMonitorViewModel(dependencies: .test(
            clock: clock,
            counterSource: counters ?? FakeCounterSource(Self.script(steps)),
            notifications: notifications,
            latencyProbe: probe,
            pathSource: pathSource,
            blobStore: blobs
        ))
        viewModel.networkMonitor.startMonitoring()
        viewModel.networkMonitor.stopMonitoring()
        return viewModel
    }

    private func tick(_ viewModel: NetworkMonitorViewModel, _ clock: TestClock, times: Int) {
        for _ in 0..<times {
            clock.advance(by: 1)
            viewModel.networkMonitor.tick()
        }
    }

    private func today(_ viewModel: NetworkMonitorViewModel, _ clock: TestClock) -> DailyRecord? {
        viewModel.dailyStore.records[DayKey.day(for: clock.now, calendar: clock.calendar)]
    }

    // MARK: - Reaching the daily store

    @Test func speedSamples_reachDailyStore() throws {
        let clock = TestClock(2026, 11, 2, 21)
        let viewModel = makeViewModel(clock, steps: Array(repeating: Step(download: 280, upload: 60), count: 3))
        viewModel.preferences.downloadPlanSpeed = 500
        viewModel.preferences.uploadPlanSpeed = 100

        tick(viewModel, clock, times: 3)

        let record = try #require(today(viewModel, clock))
        #expect(abs(record.sustainedPeakDownloadMbps - 280) < 0.01)
        #expect(abs(record.sustainedPeakUploadMbps - 60) < 0.01)
        #expect(record.sampleCount == 3)
        #expect(record.planDownloadMbps == 500)
        #expect(record.planUploadMbps == 100)
    }

    @Test func approachEvent_reachesDailyStore() {
        let clock = TestClock(2026, 11, 2, 21)
        let viewModel = makeViewModel(clock, steps: Array(repeating: Step(download: 240), count: 40))
        viewModel.preferences.downloadPlanSpeed = 300

        tick(viewModel, clock, times: 40)

        #expect(today(viewModel, clock)?.approachCount == 1)
        #expect(viewModel.peakApproachTracker.todayApproachCount == 1)
    }

    @Test func latencyMeasurement_reachesDailyStore() async throws {
        let clock = TestClock(2026, 11, 2, 21)
        // The first probe only warms the connection up and is never recorded.
        let probe = FakeLatencyProbe(seconds: [0.500, 0.040])
        probe.enqueueFailure()
        let viewModel = makeViewModel(clock, probe: probe)

        await viewModel.latencyMonitor.measureLatency()
        await viewModel.latencyMonitor.measureLatency()
        await viewModel.latencyMonitor.measureLatency()

        let record = try #require(today(viewModel, clock))
        #expect(abs(record.latencySum - 40) < 0.001)
        #expect(record.latencyCount == 1)
        #expect(record.latencyFailures == 1)
    }

    @Test func disconnect_reachesDailyStore() throws {
        let clock = TestClock(2026, 11, 2, 21)
        let viewModel = makeViewModel(clock)

        viewModel.disconnectTracker.handle(PathSnapshot(isSatisfied: false, interfaceType: "wifi"))
        clock.advance(by: 90)
        viewModel.disconnectTracker.handle(PathSnapshot(isSatisfied: true, interfaceType: "wifi"))

        let record = try #require(today(viewModel, clock))
        #expect(record.disconnectCount == 1)
        #expect(record.downtimeSeconds == 90)
    }

    /// `tick()` has no way to tell the store how long a sample took. The sample after a gap
    /// averages the whole gap, and the time between calls is all that gives it away.
    @Test func sampleSpanningAGap_cannotCompleteAWindow() throws {
        let clock = TestClock(2026, 11, 2, 21)
        var script = Self.script([Step(download: 280), Step(download: 280)])
        script.append(Self.reading(rx: 4_000_000_000, tx: 0))
        let viewModel = makeViewModel(clock, counters: FakeCounterSource(script))

        tick(viewModel, clock, times: 2)
        clock.advance(by: 3_599)
        tick(viewModel, clock, times: 1)

        let record = try #require(today(viewModel, clock))
        #expect(record.sampleCount == 3)
        #expect(record.sustainedPeakDownloadMbps == 0)
    }

    @Test func speedSamples_reachTheChartHistory() {
        let clock = TestClock(2026, 11, 2, 21)
        let viewModel = makeViewModel(clock, steps: Array(repeating: Step(download: 100, upload: 20), count: 3))

        tick(viewModel, clock, times: 3)

        let samples = viewModel.historyRecorder.recentSamples
        #expect(samples.count == 3)
        #expect(abs((samples.last?.downloadMbps ?? 0) - 100) < 0.01)
        #expect(abs((samples.last?.uploadMbps ?? 0) - 20) < 0.01)
    }

    @Test func reportService_readsTheSameDailyStore() {
        let clock = TestClock(2026, 11, 2, 21)
        let viewModel = makeViewModel(clock, steps: Array(repeating: Step(download: 100), count: 3))
        viewModel.preferences.downloadPlanSpeed = 300

        tick(viewModel, clock, times: 3)

        let summary = viewModel.monthlyReportService.summary(for: "2026-11")
        #expect(abs((summary?.peakDownloadMbps ?? 0) - 100) < 0.01)
    }

    // MARK: - Persistence

    @Test func flushPersistence_writesPendingRecords() throws {
        let clock = TestClock(2026, 11, 2, 21)
        let blobs = InMemoryBlobStore()
        let viewModel = makeViewModel(clock, steps: [Step(download: 10)], blobs: blobs)
        tick(viewModel, clock, times: 1)
        #expect(blobs.writeCount == 0)

        viewModel.flushPersistence()

        #expect(blobs.writeCount == 1)
        let reloaded = DailyRecordStore(store: blobs, clock: clock.appClock)
        #expect(reloaded.records == viewModel.dailyStore.records)
    }

    /// The sleep and quit hooks call `flushPersistence`, so it must reach the history file too.
    @Test func flushPersistence_writesTheHistory() {
        let clock = TestClock(2026, 11, 2, 21)
        let blobs = InMemoryBlobStore()
        let viewModel = makeViewModel(clock, steps: Array(repeating: Step(download: 50), count: 11), blobs: blobs)
        tick(viewModel, clock, times: 11) // the 11th sample closes the first 10-second point
        #expect(viewModel.historyRecorder.oneHourData.count == 1)
        #expect(blobs.contents(of: NetworkHistoryRecorder.fileName) == nil)

        viewModel.flushPersistence()

        let second = makeViewModel(clock, blobs: blobs)
        #expect(second.historyRecorder.oneHourData.count == 1)
        #expect(abs((second.historyRecorder.oneHourData.first?.maxDownloadMbps ?? 0) - 50) < 0.01)
    }

    @Test func newViewModel_loadsTheRecordsOfTheLastRun() {
        let clock = TestClock(2026, 11, 2, 21)
        let blobs = InMemoryBlobStore()
        let first = makeViewModel(clock, steps: [Step(download: 10)], blobs: blobs)
        tick(first, clock, times: 1)
        first.flushPersistence()

        let second = makeViewModel(clock, blobs: blobs)

        #expect(second.dailyStore.records == first.dailyStore.records)
    }

    /// "Reset peaks" clears the live counters. The report's history is a separate record.
    @Test func resetPeaks_keepsTheDailyRecords() {
        let clock = TestClock(2026, 11, 2, 21)
        let viewModel = makeViewModel(clock, steps: Array(repeating: Step(download: 100), count: 3))
        tick(viewModel, clock, times: 3)
        let before = viewModel.dailyStore.records

        viewModel.resetPeaks()

        #expect(viewModel.dailyStore.records == before)
    }

    // MARK: - Implausible samples

    private let overCap = Step(download: 24_000)
    private let overCapUpload = Step(download: 1, upload: 24_000)

    @Test func overCapSample_staysOutOfTheDisplay() {
        let clock = TestClock(2026, 11, 2, 21)
        let viewModel = makeViewModel(clock, steps: [Step(download: 100), overCap, overCapUpload])

        tick(viewModel, clock, times: 3)

        #expect(viewModel.networkMonitor.currentSpeed.uploadMbps > SampleGuard.maxPlausibleMbps) // it was measured
        #expect(abs(viewModel.currentSpeed.downloadMbps - 100) < 0.01)
        #expect(viewModel.currentSpeed.uploadMbps == 0)
    }

    @Test func overCapSample_staysOutOfTheHistory() {
        let clock = TestClock(2026, 11, 2, 21)
        let viewModel = makeViewModel(clock, steps: [overCap, overCapUpload])

        tick(viewModel, clock, times: 2)

        #expect(viewModel.historyRecorder.oneHourData.isEmpty)
        #expect(viewModel.historyRecorder.recentSamples.isEmpty)
    }

    @Test func overCapSample_staysOutOfTheDailyRecord() {
        let clock = TestClock(2026, 11, 2, 21)
        let viewModel = makeViewModel(clock, steps: [overCap, overCapUpload])

        tick(viewModel, clock, times: 2)

        #expect(viewModel.dailyStore.records.isEmpty)
    }

    @Test func overCapSamples_neverCountAsAnApproach() {
        let clock = TestClock(2026, 11, 2, 21)
        let viewModel = makeViewModel(clock, steps: Array(repeating: overCap, count: 31))
        viewModel.preferences.downloadPlanSpeed = 300

        tick(viewModel, clock, times: 31)

        #expect(viewModel.peakApproachTracker.todayApproachCount == 0)
    }

    @Test func overCapUploadSamples_neverCountAsAnApproach() {
        let clock = TestClock(2026, 11, 2, 21)
        let viewModel = makeViewModel(clock, steps: Array(repeating: overCapUpload, count: 31))
        viewModel.preferences.uploadPlanSpeed = 300

        tick(viewModel, clock, times: 31)

        #expect(viewModel.peakApproachTracker.todayApproachCount == 0)
    }

    /// The real sample that follows proves notifications were live, and the one-hour cooldown
    /// proves the over-cap sample before it did not use up the only notification.
    @Test func overCapSample_doesNotNotify() async {
        let clock = TestClock(2026, 11, 2, 21)
        let notifications = FakeNotificationDelivery()
        let viewModel = makeViewModel(clock, steps: [overCap, Step(download: 299)], notifications: notifications)
        await viewModel.notificationService.authorizationTask?.value
        viewModel.preferences.downloadPlanSpeed = 300

        tick(viewModel, clock, times: 2)

        let delivered = await eventually { notifications.delivered.count == 1 }
        #expect(delivered)
        #expect(notifications.delivered.first?.body.contains("299") == true)
    }

    /// In the detector's average an over-cap sample would make the next real one look like a crash.
    @Test func overCapSample_doesNotReachAnomalyDetection() {
        let clock = TestClock(2026, 11, 2, 21)
        let steady = Array(repeating: Step(download: 100), count: 6)
        let viewModel = makeViewModel(clock, steps: steady + [overCap] + [Step(download: 100)])

        tick(viewModel, clock, times: 8)

        #expect(viewModel.anomalyDetector.recentAnomalies.isEmpty)
    }

    @Test func overCapSample_doesNotInterruptTheSampleAfterIt() throws {
        let clock = TestClock(2026, 11, 2, 21)
        let viewModel = makeViewModel(clock, steps: [overCap, Step(download: 100)])

        tick(viewModel, clock, times: 2)

        #expect(abs(viewModel.currentSpeed.downloadMbps - 100) < 0.01)
        #expect(try #require(today(viewModel, clock)).sampleCount == 1)
    }

    /// One second of `bytes`, split over two interfaces so no single counter has to wrap.
    private func oneSecondOf(bytes: UInt32) -> FakeCounterSource {
        FakeCounterSource([
            ["en0": InterfaceCounters(rx: 0, tx: 0), "en1": InterfaceCounters(rx: 0, tx: 0)],
            [
                "en0": InterfaceCounters(rx: bytes / 2, tx: 0),
                "en1": InterfaceCounters(rx: bytes - bytes / 2, tx: 0),
            ],
        ])
    }

    @Test func sampleAtTheCap_isStillDisplayed() {
        let clock = TestClock(2026, 11, 2, 21)
        let viewModel = makeViewModel(clock, counters: oneSecondOf(bytes: 1_250_000_000))

        tick(viewModel, clock, times: 1)

        #expect(viewModel.currentSpeed.downloadMbps == SampleGuard.maxPlausibleMbps)
    }

    @Test func sampleJustAboveTheCap_isDropped() {
        let clock = TestClock(2026, 11, 2, 21)
        let viewModel = makeViewModel(clock, counters: oneSecondOf(bytes: 1_250_000_001))

        tick(viewModel, clock, times: 1)

        #expect(viewModel.currentSpeed.downloadMbps == 0)
        #expect(viewModel.dailyStore.records.isEmpty)
    }

    // MARK: - Connection state (Stage 7)

    private let pathUp = PathSnapshot(isSatisfied: true, interfaceType: "wifi")
    private let pathDown = PathSnapshot(isSatisfied: false, interfaceType: "other")

    /// Two failed probes with the path up: the tracker opens an outage and "stable" turns off.
    /// The probe's recovery closes it and the drop reaches the report and the anomaly list.
    @Test func probeFailures_reachTrackerDetectorAndReport() async throws {
        let clock = TestClock(2026, 11, 2, 21)
        let probe = FakeLatencyProbe(seconds: [0.500, 0.040])
        probe.enqueueFailure()
        probe.enqueueFailure()
        probe.enqueue(seconds: 0.500)
        probe.enqueue(seconds: 0.040)
        let viewModel = makeViewModel(clock, probe: probe)
        viewModel.disconnectTracker.handle(pathUp)

        await viewModel.latencyMonitor.measureLatency()
        await viewModel.latencyMonitor.measureLatency()
        #expect(viewModel.anomalyDetector.isConnectionStable)
        await viewModel.latencyMonitor.measureLatency()
        clock.advance(by: 30)
        await viewModel.latencyMonitor.measureLatency()

        #expect(viewModel.disconnectTracker.isConnected == false)
        #expect(viewModel.anomalyDetector.isConnectionStable == false)

        clock.advance(by: 30)
        await viewModel.latencyMonitor.measureLatency() // warm-up after the failures
        await viewModel.latencyMonitor.measureLatency()

        #expect(viewModel.disconnectTracker.isConnected)
        #expect(viewModel.anomalyDetector.isConnectionStable)
        #expect(viewModel.anomalyDetector.getAnomalySummary().connectionDrops == 1)
        let record = try #require(today(viewModel, clock))
        #expect(record.disconnectCount == 1)
        #expect(record.downtimeSeconds == 60)
    }

    @Test func pathLoss_reachesTheAnomalyDetector() {
        let clock = TestClock(2026, 11, 2, 21)
        let viewModel = makeViewModel(clock)
        viewModel.disconnectTracker.handle(pathUp)

        viewModel.disconnectTracker.handle(pathDown)
        #expect(viewModel.anomalyDetector.isConnectionStable == false)
        clock.advance(by: 20)
        viewModel.disconnectTracker.handle(pathUp)

        #expect(viewModel.anomalyDetector.isConnectionStable)
        #expect(viewModel.anomalyDetector.getAnomalySummary().connectionDrops == 1)
    }

    /// The sleep hook closes the outage first, so the flush that follows already holds it.
    @Test func handleSleep_writesTheOutageItClosed() throws {
        let clock = TestClock(2026, 11, 2, 21)
        let blobs = InMemoryBlobStore()
        let viewModel = makeViewModel(clock, blobs: blobs)
        viewModel.disconnectTracker.handle(pathUp)
        viewModel.disconnectTracker.handle(pathDown)
        clock.advance(by: 10)

        viewModel.handleSleep()

        let reloaded = DailyRecordStore(store: blobs, clock: clock.appClock)
        let record = try #require(reloaded.records[DayKey.day(for: clock.now, calendar: clock.calendar)])
        #expect(record.disconnectCount == 1)
        #expect(record.downtimeSeconds == 10)
    }

    /// Fix round 1: an outage that began under 5 s before sleep never reaches the report.
    @Test func handleSleep_discardsAnOutageThatBeganJustBefore() {
        let clock = TestClock(2026, 11, 2, 21)
        let blobs = InMemoryBlobStore()
        let viewModel = makeViewModel(clock, blobs: blobs)
        viewModel.disconnectTracker.handle(pathUp)
        viewModel.disconnectTracker.handle(pathDown)
        clock.advance(by: 1)

        viewModel.handleSleep()

        #expect(viewModel.disconnectTracker.events.isEmpty)
        #expect(today(viewModel, clock)?.disconnectCount ?? 0 == 0)
        #expect(today(viewModel, clock)?.downtimeSeconds ?? 0 == 0)
        #expect(viewModel.monthlyReportService.summary(for: "2026-11")?.disconnectCount ?? 0 == 0)
        #expect(viewModel.anomalyDetector.getAnomalySummary().connectionDrops == 0)
        let reloaded = DailyRecordStore(store: blobs, clock: clock.appClock)
        #expect(reloaded.records[DayKey.day(for: clock.now, calendar: clock.calendar)]?.disconnectCount ?? 0 == 0)
    }

    // MARK: - Quit (final review F2)

    /// An outage still open when the app quits is recorded, ending at quit, and reaches the file.
    @Test func quit_recordsTheOpenOutage() async throws {
        let clock = TestClock(2026, 11, 4, 9)
        let path = FakePathSource()
        let blobs = InMemoryBlobStore()
        let viewModel = makeViewModel(clock, pathSource: path, blobs: blobs)
        viewModel.disconnectTracker.startMonitoring()
        path.emit(pathUp)
        path.emit(pathDown)
        #expect(await eventually { !viewModel.disconnectTracker.isConnected })
        clock.advance(by: 600)

        viewModel.prepareForQuit()

        let day = DayKey.day(for: clock.now, calendar: clock.calendar)
        #expect(viewModel.dailyStore.records[day]?.disconnectCount == 1, "open outage dropped at quit")
        #expect(viewModel.dailyStore.records[day]?.downtimeSeconds == 600)
        let reloaded = DailyRecordStore(store: blobs, clock: clock.appClock)
        #expect(reloaded.records[day]?.disconnectCount == 1)
        #expect(reloaded.records[day]?.downtimeSeconds == 600)
        #expect(path.stopCount == 1)
    }

    /// The path can drop as the Mac shuts down, just before the app is told to quit; that is
    /// not an outage, as it is not one before sleep.
    @Test func quit_discardsAnOutageThatBeganJustBefore() {
        let clock = TestClock(2026, 11, 4, 9)
        let viewModel = makeViewModel(clock)
        viewModel.disconnectTracker.handle(pathUp)
        viewModel.disconnectTracker.handle(pathDown)
        clock.advance(by: 1)

        viewModel.prepareForQuit()

        #expect(viewModel.disconnectTracker.events.isEmpty)
        #expect(today(viewModel, clock)?.disconnectCount ?? 0 == 0)
    }

    /// Deferred minor: both the sleep hook and the quit hook leave the daily records and the
    /// chart history written.
    @Test func sleepAndQuit_bothWriteTheDailyRecordsAndTheHistory() {
        for hook in ["sleep", "quit"] {
            let clock = TestClock(2026, 11, 4, 9)
            let blobs = InMemoryBlobStore()
            let viewModel = makeViewModel(clock, steps: Array(repeating: Step(download: 50), count: 11), blobs: blobs)
            tick(viewModel, clock, times: 11)
            #expect(blobs.contents(of: DailyRecordStore.fileName) == nil, "\(hook)")
            #expect(blobs.contents(of: NetworkHistoryRecorder.fileName) == nil, "\(hook)")

            if hook == "sleep" { viewModel.handleSleep() } else { viewModel.prepareForQuit() }

            let reloaded = DailyRecordStore(store: blobs, clock: clock.appClock)
            #expect(reloaded.records == viewModel.dailyStore.records, "\(hook)")
            #expect(!reloaded.records.isEmpty, "\(hook)")
            let history = makeViewModel(clock, blobs: blobs).historyRecorder.oneHourData
            #expect(history.count == 1, "\(hook)")
        }
    }

    @Test func sleepAndWake_reachTrackerAndLatency() async throws {
        let clock = TestClock(2026, 11, 2, 21)
        let probe = FakeLatencyProbe(seconds: [0.500, 0.080, 0.600, 0.090])
        let viewModel = makeViewModel(clock, probe: probe)
        viewModel.disconnectTracker.handle(pathUp)
        await viewModel.latencyMonitor.measureLatency()
        await viewModel.latencyMonitor.measureLatency()

        viewModel.handleSleep()
        viewModel.disconnectTracker.handle(pathDown)  // ignored: asleep
        clock.advance(by: 3600)
        viewModel.handleWake()
        clock.advance(by: 4)
        viewModel.disconnectTracker.handle(pathUp)    // back within the wake grace
        await viewModel.latencyMonitor.measureLatency() // cold again after wake
        await viewModel.latencyMonitor.measureLatency()

        #expect(viewModel.disconnectTracker.events.isEmpty)
        #expect(viewModel.latencyMonitor.latencySamples.count == 2)
        #expect(abs((viewModel.latencyMonitor.latencySamples.last ?? 0) - 90) < 0.001)
    }

    /// With latency switched off only the path counts, so an outage the probe was holding
    /// open ends there.
    @Test func disablingLatency_endsAProbeOutage() async throws {
        let clock = TestClock(2026, 11, 2, 21)
        let probe = FakeLatencyProbe(seconds: [0.500, 0.040])
        probe.enqueueFailure()
        probe.enqueueFailure()
        let viewModel = makeViewModel(clock, probe: probe)
        viewModel.disconnectTracker.handle(pathUp)
        for _ in 0..<4 { await viewModel.latencyMonitor.measureLatency() }
        #expect(viewModel.disconnectTracker.isConnected == false)
        clock.advance(by: 15)

        viewModel.latencyMonitor.isEnabled = false

        #expect(viewModel.disconnectTracker.isConnected)
        #expect(viewModel.disconnectTracker.events.count == 1)
        #expect(viewModel.anomalyDetector.isConnectionStable)
    }
}
