import Testing
import Foundation
@testable import BandwidthECGFeature

/// What reaches the daily record from a latency probe. A reading made from a single sample has
/// no jitter; recording 0 for it would pull the month's average jitter down.
@MainActor
@Suite("Latency recording")
struct LatencyRecordingTests {
    private static let warmup: TimeInterval = 0.500

    private func today(_ viewModel: NetworkMonitorViewModel, _ clock: TestClock) -> DailyRecord? {
        viewModel.dailyStore.records[DayKey.day(for: clock.now, calendar: clock.calendar)]
    }

    @Test func viewModel_singleSampleReading_recordsLatencyButNotJitter() async throws {
        let clock = TestClock(2026, 11, 2, 9)
        let probe = FakeLatencyProbe(seconds: [Self.warmup, 0.040])
        let viewModel = NetworkMonitorViewModel(dependencies: .test(clock: clock, latencyProbe: probe))

        await viewModel.latencyMonitor.measureLatency() // warm-up, dropped
        await viewModel.latencyMonitor.measureLatency() // first real sample

        let record = try #require(today(viewModel, clock))
        #expect(record.latencyCount == 1)
        #expect(abs(record.latencySum - 40) < 0.001)
        #expect(record.jitterCount == 0)
        #expect(record.jitterSum == 0)
    }

    @Test func viewModel_secondReading_recordsJitter() async throws {
        let clock = TestClock(2026, 11, 2, 9)
        let probe = FakeLatencyProbe(seconds: [Self.warmup, 0.040, 0.060])
        let viewModel = NetworkMonitorViewModel(dependencies: .test(clock: clock, latencyProbe: probe))

        for _ in 0..<3 { await viewModel.latencyMonitor.measureLatency() }

        let record = try #require(today(viewModel, clock))
        #expect(record.latencyCount == 2)
        // Only the second reading had two samples to take a jitter from.
        #expect(record.jitterCount == 1)
        #expect(record.jitterSum > 0)
    }
}
