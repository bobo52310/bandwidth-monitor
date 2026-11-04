import Testing
import Foundation
@testable import BandwidthECGFeature

/// The sampling step, driven through the `CounterSource` and `AppClock` seams: `tick()` is called
/// by hand after each `clock.advance(by:)` and results are collected from `onSpeedUpdate`.
@MainActor
@Suite("NetworkMonitor Tests")
struct NetworkMonitorTests {

    private func counters(rx: UInt32, tx: UInt32) -> [String: InterfaceCounters] {
        ["en0": InterfaceCounters(rx: rx, tx: tx)]
    }

    /// Starts the monitor so it takes its baseline, then stops it at once so the real
    /// 1 second timer never fires and the test drives `tick()` by hand.
    private func makeMonitor(source: FakeCounterSource, clock: TestClock) -> NetworkMonitor {
        let monitor = NetworkMonitor(source: source, clock: clock.appClock)
        monitor.startMonitoring()
        monitor.stopMonitoring()
        return monitor
    }

    @Test func tick_computesSpeedFromCountersAndElapsedClockTime() {
        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([
            counters(rx: 1_000_000, tx: 500_000),
            counters(rx: 3_000_000, tx: 1_500_000),
        ])
        let monitor = makeMonitor(source: source, clock: clock)
        var received: [NetworkSpeed] = []
        monitor.onSpeedUpdate = { received.append($0) }

        clock.advance(by: 2)
        monitor.tick()

        #expect(received.count == 1)
        #expect(monitor.currentSpeed.downloadSpeed == 1_000_000) // 2 MB over 2 s
        #expect(monitor.currentSpeed.uploadSpeed == 500_000)     // 1 MB over 2 s
        #expect(monitor.currentSpeed.downloadMbps == 8)
    }

    @Test func tick_sumsEveryInterfaceTheSourceReports() {
        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([
            ["en0": InterfaceCounters(rx: 1000, tx: 100), "en1": InterfaceCounters(rx: 2000, tx: 200)],
            ["en0": InterfaceCounters(rx: 2000, tx: 200), "en1": InterfaceCounters(rx: 4000, tx: 400)],
        ])
        let monitor = makeMonitor(source: source, clock: clock)

        clock.advance(by: 1)
        monitor.tick()

        #expect(monitor.currentSpeed.downloadSpeed == 3000)
        #expect(monitor.currentSpeed.uploadSpeed == 300)
    }

    @Test func tick_whenTheReadFails_keepsTheBaselineAndReportsNothing() {
        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([
            counters(rx: 1_000, tx: 1_000),
            nil,
            counters(rx: 3_000, tx: 5_000),
        ])
        let monitor = makeMonitor(source: source, clock: clock)
        var updates = 0
        monitor.onSpeedUpdate = { _ in updates += 1 }

        clock.advance(by: 1)
        monitor.tick() // read fails
        #expect(updates == 0)
        #expect(monitor.currentSpeed.downloadSpeed == 0)

        // The next good read is measured against the original baseline over the full 2 seconds,
        // not against a zero reading (which would look like a huge spike).
        clock.advance(by: 1)
        monitor.tick()
        #expect(updates == 1)
        #expect(monitor.currentSpeed.downloadSpeed == 1000)
        #expect(monitor.currentSpeed.uploadSpeed == 2000)
    }

    @Test func tick_withNoElapsedTime_reportsNothing() {
        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([
            counters(rx: 1_000, tx: 1_000),
            counters(rx: 9_000, tx: 9_000),
        ])
        let monitor = makeMonitor(source: source, clock: clock)
        var updates = 0
        monitor.onSpeedUpdate = { _ in updates += 1 }

        monitor.tick() // the injected clock has not moved

        #expect(updates == 0)
    }

    // MARK: - Read failures

    @Test func readFailure_keepsBaseline() {
        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([
            counters(rx: 1000, tx: 0),
            nil,
            counters(rx: 1000 + 250_000, tx: 0),
        ])
        let monitor = makeMonitor(source: source, clock: clock)
        var samples: [NetworkSpeed] = []
        monitor.onSpeedUpdate = { samples.append($0) }

        clock.advance(by: 1)
        monitor.tick()
        #expect(samples.isEmpty)

        clock.advance(by: 1)
        monitor.tick()
        #expect(samples.count == 1)
        #expect(samples.first?.downloadSpeed == 125_000) // 250 kB over the full 2 seconds
    }

    /// CORE-03(a): a counter near 3 GB on an idle 1 Mbps link used to read as 24,004 Mbps after
    /// one failed read, because the failure wrote zero into the baseline.
    @Test func oneMbpsLink_readFailure_noGiantSpike() {
        let clock = TestClock(2026, 10, 31, 12)
        let start: UInt32 = 3_000_000_000
        let perSecond: UInt32 = 125_000 // 1 Mbps
        let source = FakeCounterSource([
            counters(rx: start, tx: 0),
            counters(rx: start + perSecond, tx: 0),
            counters(rx: start + 2 * perSecond, tx: 0),
            nil,
            counters(rx: start + 4 * perSecond, tx: 0),
            counters(rx: start + 5 * perSecond, tx: 0),
        ])
        let monitor = makeMonitor(source: source, clock: clock)
        var downloadMbps: [Double] = []
        monitor.onSpeedUpdate = { downloadMbps.append($0.downloadMbps) }

        for _ in 0..<5 {
            clock.advance(by: 1)
            monitor.tick()
        }

        #expect(downloadMbps.count == 4) // the failed read reports nothing
        #expect(downloadMbps.allSatisfy { $0 <= 1.1 })
        #expect(downloadMbps.allSatisfy { $0 > 0.9 })
    }

    // MARK: - Clock

    /// CORE-03(b): the elapsed time comes from the monotonic clock, so an NTP step or a manual
    /// clock change can neither freeze the readings nor inflate them.
    @Test func wallClockBackward_noEffect() {
        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([
            counters(rx: 0, tx: 0),
            counters(rx: 12_500_000, tx: 0),
            counters(rx: 25_000_000, tx: 0),
        ])
        let monitor = makeMonitor(source: source, clock: clock)
        var samples: [NetworkSpeed] = []
        monitor.onSpeedUpdate = { samples.append($0) }

        clock.advance(by: 1)
        clock.setWall(clock.now.addingTimeInterval(-60))
        monitor.tick()

        clock.advance(by: 1)
        monitor.tick()

        #expect(samples.map(\.downloadMbps) == [100, 100])
    }

    @Test func wallClockForward_noEffect() {
        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([
            counters(rx: 0, tx: 0),
            counters(rx: 12_500_000, tx: 0),
        ])
        let monitor = makeMonitor(source: source, clock: clock)

        clock.advance(by: 1)
        clock.setWall(clock.now.addingTimeInterval(3600))
        monitor.tick()

        #expect(monitor.currentSpeed.downloadMbps == 100)
    }

    /// CORE-28: a stalled main thread can make the next tick arrive early. A short window
    /// inflates the peak, so the bytes wait for the next tick instead.
    @Test func shortInterval_skippedThenAccumulated() {
        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([
            counters(rx: 1000, tx: 0),
            counters(rx: 1500, tx: 0),
            counters(rx: 2000, tx: 0),
        ])
        let monitor = makeMonitor(source: source, clock: clock)
        var samples: [NetworkSpeed] = []
        monitor.onSpeedUpdate = { samples.append($0) }

        clock.advance(by: 0.25)
        monitor.tick()
        #expect(samples.isEmpty)

        clock.advance(by: 0.75)
        monitor.tick()
        #expect(samples.count == 1)
        #expect(samples.first?.downloadSpeed == 1000) // 1000 bytes over the whole second
    }

    @Test func interval_exactlyAtTheMinimum_isSampled() {
        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([
            counters(rx: 1000, tx: 0),
            counters(rx: 1500, tx: 0),
        ])
        let monitor = makeMonitor(source: source, clock: clock)
        var samples: [NetworkSpeed] = []
        monitor.onSpeedUpdate = { samples.append($0) }

        clock.advance(by: SampleGuard.minSampleInterval)
        monitor.tick()

        #expect(samples.first?.downloadSpeed == 1000)
    }

    @Test func longSleep_noSpike() {
        let clock = TestClock(2026, 10, 31, 23)
        let source = FakeCounterSource([
            counters(rx: 3_000_000_000, tx: 0),
            counters(rx: 3_000_001_000, tx: 0),
        ])
        let monitor = makeMonitor(source: source, clock: clock)
        var samples: [NetworkSpeed] = []
        monitor.onSpeedUpdate = { samples.append($0) }

        clock.advance(by: 28_800)
        monitor.tick()

        #expect(samples.count == 1)
        #expect(monitor.currentSpeed.downloadMbps < 1)
    }

    @Test func sampleTimestamp_comesFromTheInjectedClock() {
        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([
            counters(rx: 0, tx: 0),
            counters(rx: 1000, tx: 0),
        ])
        let monitor = makeMonitor(source: source, clock: clock)

        clock.advance(by: 1)
        monitor.tick()

        #expect(monitor.currentSpeed.timestamp == clock.now)
    }

    // MARK: - Wrap-around

    @Test func wrap_singleInterface() {
        #expect(SampleGuard.delta(previous: 4_294_967_000, current: 1000, elapsed: 1) == 1296)

        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([
            counters(rx: 4_294_967_000, tx: 0),
            counters(rx: 1000, tx: 0),
        ])
        let monitor = makeMonitor(source: source, clock: clock)

        clock.advance(by: 1)
        monitor.tick()

        #expect(monitor.currentSpeed.downloadSpeed == 1296)
    }

    /// CORE-16: at 1 Gbps the 32-bit counter wraps every 34 seconds or so.
    @Test func wrap_atOneGbps_noZeroDips() {
        let clock = TestClock(2026, 10, 31, 12)
        let raw = (0...300).map { 3_000_000_000 + UInt64($0) * 125_000_000 }
        let script = raw.map { ["en0": InterfaceCounters(truncatingRx: $0, truncatingTx: 0)] }
        let wraps = zip(script.dropFirst(), script).filter { $0["en0"]!.rx < $1["en0"]!.rx }.count
        #expect(wraps >= 8) // the script really does cross the 32-bit boundary

        let monitor = makeMonitor(source: FakeCounterSource(script), clock: clock)
        var downloadMbps: [Double] = []
        monitor.onSpeedUpdate = { downloadMbps.append($0.downloadMbps) }

        for _ in 0..<300 {
            clock.advance(by: 1)
            monitor.tick()
        }

        #expect(downloadMbps.count == 300)
        #expect(downloadMbps.allSatisfy { abs($0 - 1000) < 0.001 })
    }

    /// Comparing the sum of all interfaces hides one interface's wrap: the sum falls, so the
    /// whole sample used to read as 0.
    @Test func wrap_isPerInterface() {
        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([
            ["en0": InterfaceCounters(rx: 4_294_967_000, tx: 5000),
             "en1": InterfaceCounters(rx: 5000, tx: 4_294_967_000)],
            ["en0": InterfaceCounters(rx: 1000, tx: 9000),
             "en1": InterfaceCounters(rx: 9000, tx: 1000)],
        ])
        let monitor = makeMonitor(source: source, clock: clock)

        clock.advance(by: 1)
        monitor.tick()

        #expect(monitor.currentSpeed.downloadSpeed == 1296 + 4000)
        #expect(monitor.currentSpeed.uploadSpeed == 4000 + 1296)
    }

    // MARK: - Interfaces coming and going

    @Test func newInterface_firstTickContributesZero() {
        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([
            ["en0": InterfaceCounters(rx: 1000, tx: 0)],
            ["en0": InterfaceCounters(rx: 2000, tx: 0), "en5": InterfaceCounters(rx: 9_000_000, tx: 0)],
            ["en0": InterfaceCounters(rx: 3000, tx: 0), "en5": InterfaceCounters(rx: 9_001_000, tx: 0)],
        ])
        let monitor = makeMonitor(source: source, clock: clock)
        var samples: [Double] = []
        monitor.onSpeedUpdate = { samples.append($0.downloadSpeed) }

        clock.advance(by: 1)
        monitor.tick()
        clock.advance(by: 1)
        monitor.tick()

        #expect(samples == [1000, 2000]) // en5 only counts from its second tick on
    }

    /// CORE-03(c): an interface that returns with its old, higher counter must not read as a jump.
    @Test func interfaceRemovedAndBack_rebaselines() {
        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([
            ["en0": InterfaceCounters(rx: 1000, tx: 0), "en1": InterfaceCounters(rx: 5_000_000, tx: 0)],
            ["en0": InterfaceCounters(rx: 2000, tx: 0)],
            ["en0": InterfaceCounters(rx: 3000, tx: 0), "en1": InterfaceCounters(rx: 2_000_000_000, tx: 0)],
            ["en0": InterfaceCounters(rx: 4000, tx: 0), "en1": InterfaceCounters(rx: 2_000_001_000, tx: 0)],
        ])
        let monitor = makeMonitor(source: source, clock: clock)
        var samples: [Double] = []
        monitor.onSpeedUpdate = { samples.append($0.downloadSpeed) }

        for _ in 0..<3 {
            clock.advance(by: 1)
            monitor.tick()
        }

        #expect(samples == [1000, 1000, 2000])
    }

    @Test func counterReset_implausible_rebaselined() {
        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([
            counters(rx: 1_000_000_000, tx: 0),
            counters(rx: 5_000, tx: 0),
            counters(rx: 6_000, tx: 0),
        ])
        let monitor = makeMonitor(source: source, clock: clock)
        var samples: [Double] = []
        monitor.onSpeedUpdate = { samples.append($0.downloadSpeed) }

        clock.advance(by: 1)
        monitor.tick()
        clock.advance(by: 1)
        monitor.tick()

        #expect(samples == [0, 1000]) // 0 and not 26 Gbps, then measured from the new counter value
    }

    /// `rx` wraps on every interface and `tx` does not, so both arithmetic paths are covered.
    @Test func manyInterfaces_noOverflow() {
        let clock = TestClock(2026, 10, 31, 12)
        let names = (0..<8).map { "en\($0)" }
        let delta: UInt64 = 4_000_000_000
        let before = Dictionary(uniqueKeysWithValues: names.map {
            ($0, InterfaceCounters(rx: 1_000_000_000, tx: 100_000_000))
        })
        let after = Dictionary(uniqueKeysWithValues: names.map {
            ($0, InterfaceCounters(truncatingRx: 1_000_000_000 + delta, truncatingTx: 100_000_000 + delta))
        })
        let monitor = makeMonitor(source: FakeCounterSource([before, after]), clock: clock)

        clock.advance(by: 8)
        monitor.tick()

        #expect(monitor.currentSpeed.downloadSpeed == 4_000_000_000) // 32 GB over 8 s
        #expect(monitor.currentSpeed.uploadSpeed == 4_000_000_000)
    }

    @Test func truncatingInit_handlesUInt64Max() {
        let counters = InterfaceCounters(truncatingRx: .max, truncatingTx: 0x1_0000_0005)

        #expect(counters.rx == UInt32.max)
        #expect(counters.tx == 5)
    }

    // MARK: - Baseline

    @Test func firstTick_baselineOnly_noSpike() {
        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([counters(rx: 3_000_000_000, tx: 1_000_000_000)])
        let monitor = makeMonitor(source: source, clock: clock)

        clock.advance(by: 1)
        monitor.tick()

        #expect(monitor.currentSpeed.downloadSpeed == 0)
        #expect(monitor.currentSpeed.uploadSpeed == 0)
    }

    /// With no baseline at all, the first good read must not be measured against zero.
    @Test func firstTick_afterFailedBaselineRead_noSpike() {
        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([
            nil,
            counters(rx: 3_000_000_000, tx: 1_000_000_000),
            counters(rx: 3_000_001_000, tx: 1_000_000_000),
        ])
        let monitor = makeMonitor(source: source, clock: clock)

        clock.advance(by: 1)
        monitor.tick()
        #expect(monitor.currentSpeed.downloadSpeed == 0)

        clock.advance(by: 1)
        monitor.tick()
        #expect(monitor.currentSpeed.downloadSpeed == 1000)
    }

    /// The time spent stopped is not part of the first sample's window, or the speed would
    /// be spread over the whole stop.
    @Test func restart_measuresFromTheNewBaselineTime() {
        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([
            counters(rx: 1_000, tx: 1_000),
            counters(rx: 5_000_000, tx: 7_000_000),
            counters(rx: 5_002_000, tx: 7_004_000),
        ])
        let monitor = makeMonitor(source: source, clock: clock)

        clock.advance(by: 3600)
        monitor.startMonitoring()
        monitor.stopMonitoring()

        clock.advance(by: 2)
        monitor.tick()

        #expect(monitor.currentSpeed.downloadSpeed == 1000) // 2000 bytes over 2 s, not 3602 s
        #expect(monitor.currentSpeed.uploadSpeed == 2000)
    }

    /// Traffic while stopped must not land on the first sample after a restart whose baseline
    /// read failed: measured against the old baseline it would all fall into one second.
    @Test func restart_afterFailedBaselineRead_doesNotReuseTheOldBaseline() {
        let clock = TestClock(2026, 10, 31, 12)
        let source = FakeCounterSource([
            counters(rx: 1_000, tx: 0),
            nil,
            counters(rx: 1_000_000_000, tx: 0),
            counters(rx: 1_000_001_000, tx: 0),
        ])
        let monitor = makeMonitor(source: source, clock: clock)
        var samples: [Double] = []
        monitor.onSpeedUpdate = { samples.append($0.downloadSpeed) }

        clock.advance(by: 3600)
        monitor.startMonitoring() // this baseline read fails
        monitor.stopMonitoring()

        clock.advance(by: 1)
        monitor.tick()
        clock.advance(by: 1)
        monitor.tick()

        #expect(samples == [0, 1000])
    }

    // MARK: - Sanity limit on backward counters

    @Test func delta_backwardJumpAtTheLimit_countsAsWrap() {
        let previous: UInt32 = 4_000_000_000
        let current = previous &+ 1_250_000_000 // exactly 10 Gbps over one second

        #expect(current < previous)
        #expect(SampleGuard.delta(previous: previous, current: current, elapsed: 1) == 1_250_000_000)
    }

    @Test func delta_backwardJumpAboveTheLimit_countsAsReset() {
        let previous: UInt32 = 4_000_000_000
        let current = previous &+ 1_250_000_001

        #expect(SampleGuard.delta(previous: previous, current: current, elapsed: 1) == 0)
    }

    @Test func delta_limitScalesWithElapsedTime() {
        let previous: UInt32 = 1_000_000_000
        let current: UInt32 = 5_000 // about 3.29 GB if it were a wrap

        #expect(SampleGuard.delta(previous: previous, current: current, elapsed: 1) == 0)
        #expect(SampleGuard.delta(previous: previous, current: current, elapsed: 3) == 3_294_972_296)
    }

    @Test func delta_forwardJumpIsTakenAsIs() {
        #expect(SampleGuard.delta(previous: 0, current: .max, elapsed: 1) == UInt64(UInt32.max))
    }

    @Test func maxPlausibleBytesPerSecond_is10GbpsInBytes() {
        #expect(SampleGuard.maxPlausibleMbps == 10_000)
        #expect(SampleGuard.maxPlausibleBytesPerSecond == 1_250_000_000)
        #expect(SampleGuard.minSampleInterval == 0.5)
    }
}
