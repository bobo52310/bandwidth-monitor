import Testing
import Foundation
@testable import BandwidthECGFeature

/// Before the seams existed, creating the view model in a host-less test run aborted the
/// process, because `NotificationService` called `UNUserNotificationCenter.current()`.
@MainActor
@Suite("ViewModel smoke tests")
struct ViewModelSmokeTests {

    @Test func init_withFakes_doesNotTouchNotificationCenter() async {
        let clock = TestClock(2026, 10, 31, 12)
        let notifications = FakeNotificationDelivery()
        let viewModel = NetworkMonitorViewModel(
            dependencies: .test(clock: clock, notifications: notifications)
        )

        // The service asks for permission from a task started in its init.
        await viewModel.notificationService.authorizationTask?.value

        #expect(notifications.authorizationRequested)
        #expect(viewModel.notificationService.isEnabled)
    }

    @Test func init_usesTheInjectedDefaultsEverywhere() {
        let clock = TestClock(2026, 10, 31, 12)
        let defaults = MemoryDefaults.make()
        let viewModel = NetworkMonitorViewModel(dependencies: .test(clock: clock, defaults: defaults))

        viewModel.preferences.downloadPlanSpeed = 750
        viewModel.notificationService.threshold = 0.9

        #expect(defaults.double(forKey: "downloadPlanSpeed") == 750)
        #expect(defaults.double(forKey: "notificationThreshold") == 0.9)
    }

    @Test func initializeAndStop_runThroughTheSeams() async {
        let clock = TestClock(2026, 10, 31, 12)
        let counters = FakeCounterSource([["en0": InterfaceCounters(rx: 0, tx: 0)]])
        let probe = FakeLatencyProbe(seconds: [0.020])
        let pathSource = FakePathSource()
        let viewModel = NetworkMonitorViewModel(
            dependencies: .test(
                clock: clock,
                counterSource: counters,
                latencyProbe: probe,
                pathSource: pathSource
            )
        )

        viewModel.initialize()

        #expect(counters.readCount >= 1)           // baseline read through CounterSource
        #expect(pathSource.startCount == 1)        // path monitoring through PathStatusSource
        let measured = await eventually { probe.callCount >= 1 }
        #expect(measured)                          // first latency probe through LatencyProbe

        viewModel.stopMonitoring()
        #expect(pathSource.stopCount == 1)
    }

    /// D10: the popover's views are released on close, so the chart choices live here.
    @Test func chartChoices_startAsThePopoverDid() {
        let viewModel = NetworkMonitorViewModel(dependencies: .test(clock: TestClock(2026, 11, 3, 9)))

        #expect(viewModel.chartRange == .oneHour)
        #expect(viewModel.showDownload)
        #expect(viewModel.showUpload)
        #expect(!viewModel.chartBannerDismissed)
    }

    @Test func formatRelativeTime_usesTheInjectedClock() {
        let clock = TestClock(2026, 10, 31, 12)
        let viewModel = NetworkMonitorViewModel(dependencies: .test(clock: clock))

        let threeDaysTwoHoursAgo = clock.now.addingTimeInterval(-(3 * 86400 + 2 * 3600))

        #expect(viewModel.formatRelativeTime(threeDaysTwoHoursAgo) == L10n.timeDaysHoursAgo(3, 2))
    }
}
