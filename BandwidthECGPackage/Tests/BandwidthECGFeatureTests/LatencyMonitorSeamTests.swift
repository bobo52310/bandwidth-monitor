import Testing
import Foundation
@testable import BandwidthECGFeature

/// `LatencyMonitor` driven through a fake `LatencyProbe`; no network involved.
///
/// The first probe on a cold connection is a warm-up and is dropped (CORE-21), so each script
/// starts with one throwaway value.
@MainActor
@Suite("LatencyMonitor probe seam")
struct LatencyMonitorSeamTests {
    private static let warmup: TimeInterval = 0.500

    private func makeMonitor(_ probe: FakeLatencyProbe) -> LatencyMonitor {
        LatencyMonitor(
            defaults: MemoryDefaults.make(),
            clock: TestClock(2026, 10, 31, 12).appClock,
            probe: probe
        )
    }

    @Test func measureLatency_recordsTheProbeResultInMilliseconds() async {
        let monitor = makeMonitor(FakeLatencyProbe(seconds: [Self.warmup, 0.030]))

        await monitor.measureLatency()
        await monitor.measureLatency()

        #expect(abs(monitor.currentLatency - 30) < 0.001)
        #expect(monitor.currentJitter == nil) // a single sample has no jitter
        #expect(monitor.qualityScore == .good)
    }

    @Test func measureLatency_computesJitterOverTheSamples() async {
        let monitor = makeMonitor(FakeLatencyProbe(seconds: [Self.warmup, 0.010, 0.200, 0.030, 0.180]))

        for _ in 0..<5 { await monitor.measureLatency() }

        #expect(abs(monitor.currentLatency - 180) < 0.001)
        #expect((monitor.currentJitter ?? 0) > 50)
        #expect(monitor.qualityScore == .poor)
    }

    /// A failure clears what is shown, but the samples measured before it stay in the window.
    @Test func measureLatency_failureKeepsEarlierSamplesInTheWindow() async {
        let probe = FakeLatencyProbe(seconds: [Self.warmup, 0.040])
        probe.enqueueFailure()
        probe.enqueue(seconds: Self.warmup)
        probe.enqueue(seconds: 0.050)
        let monitor = makeMonitor(probe)

        for _ in 0..<5 { await monitor.measureLatency() }

        #expect(probe.callCount == 5)
        #expect(monitor.latencySamples.count == 2)
        #expect(abs(monitor.currentLatency - 50) < 0.001)
        #expect(abs((monitor.currentJitter ?? 0) - 5) < 0.001)
    }

    @Test func onMeasurement_reportsEachResult() async {
        let probe = FakeLatencyProbe(seconds: [Self.warmup, 0.100, 0.200])
        probe.enqueueFailure()
        let monitor = makeMonitor(probe)
        var received: [LatencyMeasurement] = []
        monitor.onMeasurement = { received.append($0) }

        for _ in 0..<4 { await monitor.measureLatency() }

        #expect(received == [
            .success(latencyMs: 100, jitterMs: 0),
            .success(latencyMs: 200, jitterMs: 50),
            .failure,
        ])
    }

    /// The first probe runs from a task; stopping before it starts sends nothing at all.
    @Test func stopMonitoring_beforeTheFirstProbe_sendsNothing() async {
        let probe = FakeLatencyProbe(seconds: [Self.warmup, 0.025])
        let monitor = makeMonitor(probe)

        monitor.startMonitoring()
        monitor.stopMonitoring()
        _ = await eventually(timeout: 0.2) { probe.callCount > 0 }

        #expect(probe.callCount == 0)
        #expect(monitor.isMonitoring == false)
        #expect(monitor.hasMeasurement == false)
    }
}
