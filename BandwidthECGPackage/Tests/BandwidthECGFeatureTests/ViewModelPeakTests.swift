import Testing
import Foundation
@testable import BandwidthECGFeature

/// UI-P2-5 and D5: peaks can be cleared one at a time, and a full reset leaves the monthly
/// report's data alone.
@MainActor
@Suite("ViewModel peaks")
struct ViewModelPeakTests {

    private static func reading(rx: UInt32, tx: UInt32) -> [String: InterfaceCounters] {
        let counters = InterfaceCounters(rx: rx, tx: tx)
        return ["en0": counters, "en1": counters, "en2": counters]
    }

    /// One reading per second: a baseline, then a step per `(download, upload)` pair in Mbps.
    private static func script(_ steps: [(download: Double, upload: Double)]) -> [[String: InterfaceCounters]?] {
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

    /// A view model that has already seen `steps`, one sample per second.
    private func makeViewModel(
        _ clock: TestClock,
        steps: [(download: Double, upload: Double)]
    ) -> NetworkMonitorViewModel {
        let viewModel = NetworkMonitorViewModel(dependencies: .test(
            clock: clock,
            counterSource: FakeCounterSource(Self.script(steps))
        ))
        viewModel.networkMonitor.startMonitoring()
        viewModel.networkMonitor.stopMonitoring()
        for _ in steps {
            clock.advance(by: 1)
            viewModel.networkMonitor.tick()
        }
        return viewModel
    }

    private let steps: [(download: Double, upload: Double)] = [
        (download: 200, upload: 40), (download: 250, upload: 40), (download: 250, upload: 40),
    ]

    @Test func clearAllTimePeak_forwards() {
        let clock = TestClock(2026, 11, 3, 10)
        let viewModel = makeViewModel(clock, steps: steps)
        let uploadBefore = viewModel.peakRecorder.allTimePeakUpload
        #expect(viewModel.peakRecorder.allTimePeakDownload > 240)
        #expect(uploadBefore > 30)

        viewModel.clearAllTimePeak(.download)

        // Only the chosen direction goes. The sample that set the all-time peak also set today's.
        #expect(viewModel.peakRecorder.allTimePeakDownload == 0)
        #expect(viewModel.peakRecorder.allTimePeakDownloadTime == nil)
        #expect(viewModel.peakRecorder.todayPeakDownload == 0)
        #expect(viewModel.peakRecorder.allTimePeakUpload == uploadBefore)
        #expect(viewModel.peakRecorder.todayPeakUpload == uploadBefore)

        viewModel.clearAllTimePeak(.upload)

        #expect(viewModel.peakRecorder.allTimePeakUpload == 0)
        #expect(viewModel.peakRecorder.todayPeakUpload == 0)
    }

    /// The monthly report is derived from the daily records. Clearing a polluted peak must not
    /// rewrite them.
    @Test func clearAllTimePeak_keepsDailyRecords() {
        let clock = TestClock(2026, 11, 3, 10)
        let viewModel = makeViewModel(clock, steps: steps)
        let recordsBefore = viewModel.dailyStore.records
        #expect(!recordsBefore.isEmpty)

        viewModel.clearAllTimePeak(.download)

        #expect(viewModel.dailyStore.records == recordsBefore)
    }

    @Test func resetPeaks_keepsDailyRecords() {
        let clock = TestClock(2026, 11, 3, 10)
        let viewModel = makeViewModel(clock, steps: steps)
        let recordsBefore = viewModel.dailyStore.records
        #expect(!recordsBefore.isEmpty)
        #expect(viewModel.peakRecorder.allTimePeakDownload > 0)
        #expect(!viewModel.historyRecorder.recentSamples.isEmpty)

        viewModel.resetPeaks()

        #expect(viewModel.peakRecorder.allTimePeakDownload == 0)
        #expect(viewModel.peakRecorder.allTimePeakUpload == 0)
        #expect(viewModel.peakRecorder.todayPeakDownload == 0)
        #expect(viewModel.historyRecorder.recentSamples.isEmpty)
        #expect(viewModel.dailyStore.records == recordsBefore)
        let key = DayKey.day(for: clock.now, calendar: clock.calendar)
        #expect(viewModel.dailyStore.records[key]?.sampleCount == 3)
    }

    /// The view model hands out the defaults it was built with, so the status bar controller
    /// reads and writes onboarding and panel state in the same store as everything else.
    @Test func defaults_isTheInjectedStore() {
        let defaults = MemoryDefaults.make()
        let viewModel = NetworkMonitorViewModel(
            dependencies: .test(clock: TestClock(2026, 11, 3, 10), defaults: defaults)
        )

        #expect(viewModel.defaults === defaults)
    }
}
