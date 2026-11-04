import Testing
import Foundation
@testable import BandwidthECGFeature

/// CORE-21, D11, UI-P2-15: the first probe on a cold connection includes the TLS handshake and
/// is dropped; a failure leaves nothing stale on screen; the probe can be switched off.
@MainActor
@Suite("LatencyMonitor behaviour")
struct LatencyMonitorBehaviorTests {

    private func makeMonitor(
        _ probe: any LatencyProbe,
        defaults: MemoryDefaults = .make()
    ) -> LatencyMonitor {
        LatencyMonitor(
            defaults: defaults,
            clock: TestClock(2026, 11, 3, 12).appClock,
            probe: probe
        )
    }

    private func close(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) < 0.001
    }

    private func latencies(_ measurements: [LatencyMeasurement]) -> [Double?] {
        measurements.map {
            if case .success(let latencyMs, _) = $0 { return latencyMs }
            return nil
        }
    }

    // MARK: - Warm-up

    /// The audit's measured sequence: 563 ms with the handshake, then 86 and 88 ms.
    @Test func warmupSample_discarded() async {
        let monitor = makeMonitor(FakeLatencyProbe(seconds: [0.563, 0.086, 0.088]))
        var received: [LatencyMeasurement] = []
        monitor.onMeasurement = { received.append($0) }

        for _ in 0..<3 { await monitor.measureLatency() }

        #expect(monitor.latencySamples.count == 2)
        #expect(close(monitor.latencySamples.first ?? 0, 86))
        #expect(close(monitor.latencySamples.last ?? 0, 88))
        let reported = latencies(received)
        #expect(reported.count == 2)
        #expect(close(reported.first.flatMap { $0 } ?? 0, 86))
        #expect(close(reported.last.flatMap { $0 } ?? 0, 88))
    }

    @Test func afterFailure_nextSampleIsWarmup() async {
        let probe = FakeLatencyProbe(seconds: [0.563, 0.086])
        probe.enqueueFailure()
        probe.enqueue(seconds: 0.400) // a new connection: handshake again
        probe.enqueue(seconds: 0.088)
        let monitor = makeMonitor(probe)
        var received: [LatencyMeasurement] = []
        monitor.onMeasurement = { received.append($0) }

        for _ in 0..<5 { await monitor.measureLatency() }

        #expect(probe.callCount == 5)
        #expect(monitor.latencySamples.count == 2)
        #expect(close(monitor.latencySamples.last ?? 0, 88))
        #expect(received.count == 3)
        #expect(received[safe: 1] == .failure)
        #expect(close(latencies(received).last.flatMap { $0 } ?? 0, 88))
    }

    @Test func jitter_ignoresWarmup() async throws {
        let monitor = makeMonitor(FakeLatencyProbe(seconds: [0.563, 0.086, 0.088]))

        for _ in 0..<3 { await monitor.measureLatency() }

        let jitter = try #require(monitor.currentJitter)
        #expect(jitter < 5, "got \(jitter)")
        #expect(monitor.qualityScore == .good)
    }

    /// The Mac's connections do not survive sleep, so the first probe after wake is cold too.
    @Test func wake_nextSampleIsWarmup() async {
        let monitor = makeMonitor(FakeLatencyProbe(seconds: [0.563, 0.086, 0.600, 0.088]))

        await monitor.measureLatency()
        await monitor.measureLatency()
        monitor.handleWake()
        await monitor.measureLatency()
        await monitor.measureLatency()

        #expect(monitor.latencySamples.count == 2)
        #expect(close(monitor.latencySamples.last ?? 0, 88))
    }

    // MARK: - Failures

    @Test func failure_noStaleValue() async {
        let probe = FakeLatencyProbe(seconds: [0.563, 0.086])
        probe.enqueueFailure()
        let monitor = makeMonitor(probe)
        var received: [LatencyMeasurement] = []
        monitor.onMeasurement = { received.append($0) }

        await monitor.measureLatency()
        await monitor.measureLatency()
        #expect(monitor.hasMeasurement)
        await monitor.measureLatency()

        #expect(received.last == .failure)
        #expect(monitor.hasMeasurement == false)
        #expect(monitor.qualityScore == .unknown)
        #expect(monitor.currentLatency == 0)
        #expect(monitor.currentJitter == nil)
    }

    /// Fix round 2: one sample has no spread, so there is no jitter to show yet (not 0.0 ms).
    @Test func jitter_unknownUntilTwoSamples() async throws {
        let monitor = makeMonitor(FakeLatencyProbe(seconds: [0.563, 0.086, 0.088]))

        await monitor.measureLatency()
        #expect(monitor.currentJitter == nil)
        await monitor.measureLatency()
        #expect(monitor.hasMeasurement)
        #expect(monitor.currentJitter == nil)
        await monitor.measureLatency()

        let jitter = try #require(monitor.currentJitter)
        #expect(abs(jitter - 1) < 0.001)
    }

    /// Switching off empties the window, so after switching on again the first value has no jitter.
    @Test func jitter_unknownAgainAfterReEnabling() async {
        let monitor = makeMonitor(FakeLatencyProbe(seconds: [0.563, 0.086, 0.088, 0.500, 0.090]))
        for _ in 0..<3 { await monitor.measureLatency() }
        #expect(monitor.currentJitter != nil)

        monitor.isEnabled = false
        #expect(monitor.currentJitter == nil)
        monitor.isEnabled = true
        await monitor.measureLatency()
        await monitor.measureLatency()

        #expect(monitor.hasMeasurement)
        #expect(monitor.currentJitter == nil)
    }

    @Test func noMeasurementYet_hasMeasurementIsFalse() async {
        let monitor = makeMonitor(FakeLatencyProbe(seconds: [0.563]))
        #expect(monitor.hasMeasurement == false)

        await monitor.measureLatency() // the warm-up alone is not a measurement

        #expect(monitor.hasMeasurement == false)
        #expect(monitor.qualityScore == .unknown)
    }

    @Test func consecutiveFailures_countsAndResets() async {
        let probe = FakeLatencyProbe(seconds: [0.563, 0.086])
        probe.enqueueFailure()
        probe.enqueueFailure()
        probe.enqueue(seconds: 0.400)
        probe.enqueue(seconds: 0.090)
        let monitor = makeMonitor(probe)

        await monitor.measureLatency()
        await monitor.measureLatency()
        #expect(monitor.consecutiveFailures == 0)
        await monitor.measureLatency()
        #expect(monitor.consecutiveFailures == 1)
        await monitor.measureLatency()
        #expect(monitor.consecutiveFailures == 2)
        await monitor.measureLatency() // warm-up: proves nothing yet
        #expect(monitor.consecutiveFailures == 2)
        await monitor.measureLatency()
        #expect(monitor.consecutiveFailures == 0)
    }

    // MARK: - Quality

    @Test(arguments: [
        (119.0, 9.0, ConnectionQuality.good),
        (120.0, 9.0, ConnectionQuality.fair),
        (86.0, 2.0, ConnectionQuality.good),
        (199.0, 29.0, ConnectionQuality.fair),
        (200.0, 29.0, ConnectionQuality.poor),
        (50.0, 10.0, ConnectionQuality.fair),
        (150.0, 30.0, ConnectionQuality.poor),
    ])
    func quality_thresholds(latency: Double, jitter: Double, expected: ConnectionQuality) {
        #expect(LatencyMonitor.calculateQualityScore(latency: latency, jitter: jitter) == expected)
    }

    // MARK: - Starting

    @Test func startMonitoring_runsAWarmupThenARealProbe() async {
        let probe = FakeLatencyProbe(seconds: [0.563, 0.086])
        let monitor = makeMonitor(probe)

        monitor.startMonitoring()
        let measured = await eventually { monitor.hasMeasurement }
        monitor.stopMonitoring()

        #expect(measured)
        #expect(probe.callCount == 2)
        #expect(close(monitor.currentLatency, 86))
    }

    // MARK: - Switching off (D11)

    @Test func disabled_sendsNoProbe() async {
        let probe = FakeLatencyProbe(seconds: [0.563, 0.086])
        let monitor = makeMonitor(probe)

        monitor.isEnabled = false
        monitor.startMonitoring()
        _ = await eventually(timeout: 0.2) { probe.callCount > 0 }
        await monitor.measureLatency()

        #expect(probe.callCount == 0)
        #expect(monitor.isMonitoring == false)
        #expect(monitor.qualityScore == .unknown)
        monitor.stopMonitoring()
    }

    @Test func toggle_persisted() {
        let defaults = MemoryDefaults.make()
        #expect(makeMonitor(FakeLatencyProbe(), defaults: defaults).isEnabled)

        let monitor = makeMonitor(FakeLatencyProbe(), defaults: defaults)
        monitor.isEnabled = false

        #expect(defaults.object(forKey: "latencyMonitoringEnabled") as? Bool == false)
        #expect(makeMonitor(FakeLatencyProbe(), defaults: defaults).isEnabled == false)
    }

    @Test func disabling_clearsTheShownValues() async {
        let monitor = makeMonitor(FakeLatencyProbe(seconds: [0.563, 0.086]))
        await monitor.measureLatency()
        await monitor.measureLatency()
        #expect(monitor.hasMeasurement)

        monitor.isEnabled = false

        #expect(monitor.hasMeasurement == false)
        #expect(monitor.qualityScore == .unknown)
        #expect(monitor.consecutiveFailures == 0)
    }

    /// Switching it back on resumes only if the app had asked for monitoring.
    @Test func enabling_afterStart_beginsProbing() async {
        let probe = FakeLatencyProbe(seconds: [0.563, 0.086])
        let monitor = makeMonitor(probe)
        monitor.isEnabled = false
        monitor.startMonitoring()

        monitor.isEnabled = true
        let measured = await eventually { monitor.hasMeasurement }
        monitor.stopMonitoring()

        #expect(measured)
        #expect(probe.callCount == 2)
    }

    @Test func enabling_withoutStart_staysIdle() async {
        let probe = FakeLatencyProbe(seconds: [0.563, 0.086])
        let monitor = makeMonitor(probe)
        monitor.isEnabled = false

        monitor.isEnabled = true
        _ = await eventually(timeout: 0.2) { probe.callCount > 0 }

        #expect(probe.callCount == 0)
        #expect(monitor.isMonitoring == false)
    }

    @Test func enabledChange_isReported() {
        let monitor = makeMonitor(FakeLatencyProbe())
        var changes: [Bool] = []
        monitor.onEnabledChange = { changes.append($0) }

        monitor.isEnabled = false
        monitor.isEnabled = false
        monitor.isEnabled = true

        #expect(changes == [false, true])
    }

    /// A probe that was already on the wire when monitoring was switched off must not
    /// put a value back on screen.
    @Test func disabling_discardsAProbeStillInFlight() async {
        let probe = HeldLatencyProbe()
        let monitor = makeMonitor(probe)
        var received: [LatencyMeasurement] = []
        monitor.onMeasurement = { received.append($0) }

        let warmup = Task { await monitor.measureLatency() }
        let warmupStarted = await eventually { probe.waitingCount == 1 }
        #expect(warmupStarted)
        probe.release(seconds: 0.563)
        _ = await warmup.value

        let inFlight = Task { await monitor.measureLatency() }
        let inFlightStarted = await eventually { probe.waitingCount == 1 }
        #expect(inFlightStarted)
        monitor.isEnabled = false
        probe.release(seconds: 0.086)
        _ = await inFlight.value

        #expect(received.isEmpty)
        #expect(monitor.hasMeasurement == false)
        #expect(monitor.qualityScore == .unknown)
        #expect(monitor.latencySamples.isEmpty)
    }
}

extension LatencyMonitorBehaviorTests {
    /// Off and straight back on while a probe is out: the probe belongs to the old run.
    @Test func offAndOnAgain_discardsAProbeStillInFlight() async {
        let probe = HeldLatencyProbe()
        let monitor = makeMonitor(probe)
        var received: [LatencyMeasurement] = []
        monitor.onMeasurement = { received.append($0) }

        let warmup = Task { await monitor.measureLatency() }
        let warmupStarted = await eventually { probe.waitingCount == 1 }
        #expect(warmupStarted)
        probe.release(seconds: 0.563)
        _ = await warmup.value

        let inFlight = Task { await monitor.measureLatency() }
        let inFlightStarted = await eventually { probe.waitingCount == 1 }
        #expect(inFlightStarted)
        monitor.isEnabled = false
        monitor.isEnabled = true
        probe.release(seconds: 0.086)
        _ = await inFlight.value

        #expect(received.isEmpty)
        #expect(monitor.hasMeasurement == false)
    }
}

/// Holds every call until the test releases it, so a probe can be "in flight" on purpose.
final class HeldLatencyProbe: LatencyProbe, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<TimeInterval, Error>] = []

    var waitingCount: Int { lock.withLock { waiting.count } }

    func measureSeconds() async throws -> TimeInterval {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { waiting.append(continuation) }
        }
    }

    func release(seconds: TimeInterval) {
        let next = lock.withLock { waiting.isEmpty ? nil : waiting.removeFirst() }
        next?.resume(returning: seconds)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
