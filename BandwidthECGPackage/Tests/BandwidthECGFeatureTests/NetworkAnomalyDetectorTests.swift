import Testing
import Foundation
@testable import BandwidthECGFeature

/// CORE-10, CORE-22. The scenarios follow anomaly (a) to (e) of the audit harness
/// (`audit/core/h1/main.swift`): sleep and timer stalls, a real outage, a download that simply
/// ends, chunked streaming, and an idle link that reads exactly 0.
@MainActor
@Suite("NetworkAnomalyDetector")
struct NetworkAnomalyDetectorTests {
    private let clock = TestClock(2026, 11, 3, 12)

    private func makeDetector() -> NetworkAnomalyDetector {
        NetworkAnomalyDetector(defaults: MemoryDefaults.make(), clock: clock.appClock)
    }

    /// Feeds `count` samples one `step` apart.
    private func feed(
        _ detector: NetworkAnomalyDetector,
        download: Double,
        upload: Double = 0,
        count: Int = 1,
        step: TimeInterval = 1
    ) {
        for _ in 0..<count {
            clock.advance(by: step)
            detector.analyzeSpeed(NetworkSpeed(
                uploadSpeed: upload * 125_000,
                downloadSpeed: download * 125_000,
                timestamp: clock.now
            ))
        }
    }

    private func summary(_ detector: NetworkAnomalyDetector) -> AnomalySummary {
        detector.getAnomalySummary()
    }

    // MARK: - Connection state

    /// (b) A real 10-minute outage used to leave the status at "stable" with no drop recorded.
    @Test func realOutage_notStable_oneDrop() {
        let detector = makeDetector()

        detector.updateConnectivity(pathSatisfied: false, probeFailures: 0)
        #expect(detector.isConnectionStable == false)
        detector.recordConnectionDrop(duration: 600)

        #expect(summary(detector).connectionDrops == 1)
        #expect(detector.recentAnomalies.first?.type.severity == .high)

        detector.updateConnectivity(pathSatisfied: true, probeFailures: 0)
        #expect(detector.isConnectionStable)
    }

    @Test func probeFailures_twoMakeItUnstable() {
        let detector = makeDetector()

        detector.updateConnectivity(pathSatisfied: true, probeFailures: 1)
        #expect(detector.isConnectionStable)
        detector.updateConnectivity(pathSatisfied: true, probeFailures: 2)
        #expect(detector.isConnectionStable == false)
    }

    /// Every finished outage is its own drop, even two within a minute.
    @Test func connectionDrops_areNotMerged() {
        let detector = makeDetector()

        detector.recordConnectionDrop(duration: 12)
        clock.advance(by: 20)
        detector.recordConnectionDrop(duration: 5)

        #expect(summary(detector).connectionDrops == 2)
    }

    // MARK: - Gaps between samples (a)

    @Test func sampleGap_noAnomaly() {
        let detector = makeDetector()
        feed(detector, download: 1, count: 5)

        feed(detector, download: 1, step: 28_800) // the Mac slept for 8 hours

        #expect(detector.recentAnomalies.isEmpty)
        #expect(detector.isConnectionStable)
    }

    @Test func timerStall6s_noAnomaly() {
        let detector = makeDetector()
        feed(detector, download: 1, count: 5)

        feed(detector, download: 1, step: 6) // a menu was open, the timer waited

        #expect(detector.recentAnomalies.isEmpty)
        #expect(detector.isConnectionStable)
    }

    // MARK: - Normal traffic (c) (d) (e)

    @Test func downloadEnds_noSpeedDrop() {
        let detector = makeDetector()
        feed(detector, download: 100, count: 12)

        feed(detector, download: 0, count: 10)

        #expect(detector.recentAnomalies.isEmpty)
    }

    @Test func streaming_noAnomalies() {
        let detector = makeDetector()

        for second in 0..<600 {
            feed(detector, download: second % 4 == 0 ? 20 : 0.1)
        }

        #expect(detector.recentAnomalies.isEmpty)
    }

    @Test func idleZero_noAnomaly() {
        let detector = makeDetector()
        detector.updateConnectivity(pathSatisfied: true, probeFailures: 0)

        feed(detector, download: 0, count: 120)

        #expect(detector.recentAnomalies.isEmpty)
    }

    // MARK: - Zero speed

    @Test func pathDown_30sZero_zeroSpeed() {
        let detector = makeDetector()
        detector.updateConnectivity(pathSatisfied: false, probeFailures: 0)

        feed(detector, download: 0, count: 30)

        #expect(summary(detector).zeroSpeedEvents == 1)
        #expect(summary(detector).totalCount == 1)
    }

    @Test func pathDown_29sZero_none() {
        let detector = makeDetector()
        detector.updateConnectivity(pathSatisfied: false, probeFailures: 0)

        feed(detector, download: 0, count: 29)

        #expect(detector.recentAnomalies.isEmpty)
    }

    /// Probe failures alone do not make a zero-speed event; it needs the path to be down.
    @Test func probeFailing_zeroSpeedNeedsThePathDown() {
        let detector = makeDetector()
        detector.updateConnectivity(pathSatisfied: true, probeFailures: 3)

        feed(detector, download: 0, count: 40)

        #expect(summary(detector).zeroSpeedEvents == 0)
    }

    /// "30 seconds in a row" means 30 seconds, not 30 samples spread around a sleep.
    @Test func zeroStreak_restartsAfterAGap() {
        let detector = makeDetector()
        detector.updateConnectivity(pathSatisfied: false, probeFailures: 0)

        feed(detector, download: 0, count: 20)
        feed(detector, download: 0, step: 3) // more than 2.5 s after the last one
        feed(detector, download: 0, count: 28)

        #expect(detector.recentAnomalies.isEmpty)
    }

    @Test func zeroStreak_restartsAfterTraffic() {
        let detector = makeDetector()
        detector.updateConnectivity(pathSatisfied: false, probeFailures: 0)

        feed(detector, download: 0, count: 20)
        feed(detector, download: 0.5)
        feed(detector, download: 0, count: 20)

        #expect(detector.recentAnomalies.isEmpty)
    }

    // MARK: - Speed drop

    @Test func drop_withProbeFailing_recorded() throws {
        let detector = makeDetector()
        feed(detector, download: 100, count: 10)
        detector.updateConnectivity(pathSatisfied: true, probeFailures: 2)

        feed(detector, download: 10, count: 5)

        #expect(summary(detector).speedDrops == 1)
        #expect(summary(detector).totalCount == 1)
        let anomaly = try #require(detector.recentAnomalies.first)
        guard case .speedDrop(let direction, let from, let to, _) = anomaly.type else {
            Issue.record("expected a speed drop, got \(anomaly.type)")
            return
        }
        #expect(direction == .download)
        #expect(abs(from - 100) < 0.01)
        #expect(abs(to - 10) < 0.01)
    }

    @Test func drop_fourSeconds_none() {
        let detector = makeDetector()
        feed(detector, download: 100, count: 10)
        detector.updateConnectivity(pathSatisfied: true, probeFailures: 2)

        feed(detector, download: 10, count: 4)
        feed(detector, download: 100) // recovered: the next low sample starts over
        feed(detector, download: 10)

        #expect(detector.recentAnomalies.isEmpty)
    }

    @Test func drop_connectionFine_none() {
        let detector = makeDetector()
        feed(detector, download: 100, count: 10)
        detector.updateConnectivity(pathSatisfied: true, probeFailures: 1)

        feed(detector, download: 10, count: 8)

        #expect(detector.recentAnomalies.isEmpty)
    }

    @Test func uploadDrop_withPathDown_recorded() throws {
        let detector = makeDetector()
        feed(detector, download: 0.2, upload: 50, count: 10)
        detector.updateConnectivity(pathSatisfied: false, probeFailures: 0)

        feed(detector, download: 0.2, upload: 5, count: 5)

        #expect(summary(detector).speedDrops == 1)
        let anomaly = try #require(detector.recentAnomalies.first)
        guard case .speedDrop(let direction, _, _, _) = anomaly.type else {
            Issue.record("expected a speed drop, got \(anomaly.type)")
            return
        }
        #expect(direction == .upload)
    }

    /// One long drop is one anomaly, however many seconds it lasts.
    @Test func drop_isRecordedOncePerStreak() {
        let detector = makeDetector()
        feed(detector, download: 100, count: 10)
        detector.updateConnectivity(pathSatisfied: true, probeFailures: 2)

        feed(detector, download: 5, count: 9)

        #expect(summary(detector).speedDrops == 1)
    }

    // MARK: - Switched off

    @Test func detectionDisabled_recordsNothing() {
        let detector = makeDetector()
        detector.isDetectionEnabled = false
        detector.updateConnectivity(pathSatisfied: false, probeFailures: 2)

        detector.recordConnectionDrop(duration: 600)
        feed(detector, download: 0, count: 40)

        #expect(detector.recentAnomalies.isEmpty)
    }
}
