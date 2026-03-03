import Testing
@testable import BandwidthECGFeature

@Suite("LatencyMonitor Tests")
struct LatencyMonitorTests {

    // MARK: - Quality Score Tests

    @Test("Quality score returns .good for low latency and low jitter")
    func qualityScoreGoodForLowLatencyAndLowJitter() {
        let quality = LatencyMonitor.calculateQualityScore(latency: 30, jitter: 5)
        #expect(quality == .good)
    }

    @Test("Quality score returns .poor for high latency and high jitter")
    func qualityScorePoorForHighLatencyAndHighJitter() {
        let quality = LatencyMonitor.calculateQualityScore(latency: 150, jitter: 50)
        #expect(quality == .poor)
    }

    @Test("Quality score returns .fair for medium latency and medium jitter")
    func qualityScoreFairForMediumValues() {
        let quality = LatencyMonitor.calculateQualityScore(latency: 70, jitter: 20)
        #expect(quality == .fair)
    }

    // MARK: - Jitter Calculation Tests

    @Test("Jitter calculation returns low value for stable samples")
    func jitterCalculationLowForStableSamples() {
        let stableSamples = [50.0, 51.0, 49.0, 50.5, 50.2, 49.8, 50.1, 50.3]
        let jitter = LatencyMonitor.calculateJitter(from: stableSamples)
        #expect(jitter < 2.0, "Jitter for stable samples should be low (< 2ms), got \(jitter)")
    }

    @Test("Jitter calculation returns high value for unstable samples")
    func jitterCalculationHighForUnstableSamples() {
        let unstableSamples = [10.0, 200.0, 30.0, 180.0, 15.0, 250.0, 40.0, 190.0]
        let jitter = LatencyMonitor.calculateJitter(from: unstableSamples)
        #expect(jitter > 50.0, "Jitter for unstable samples should be high (> 50ms), got \(jitter)")
    }
}
