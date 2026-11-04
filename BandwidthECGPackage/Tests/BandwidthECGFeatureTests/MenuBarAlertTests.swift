import Testing
import Foundation
@testable import BandwidthECGFeature

/// D18: the menu bar shows how close the speed is to the plan. Colour alone cannot carry that
/// (an orange title is about 2:1 on a light menu bar), so every level also has a text prefix and
/// a VoiceOver value.
@Suite("Menu bar alert")
struct MenuBarAlertTests {

    private func level(
        download: Double = 0,
        upload: Double = 0,
        planDownload: Double = 100,
        planUpload: Double = 100,
        warningRatio: Double = 0.95
    ) -> MenuBarAlertLevel {
        MenuBarAlertLevel.evaluate(
            downloadMbps: download,
            uploadMbps: upload,
            planDownloadMbps: planDownload,
            planUploadMbps: planUpload,
            warningRatio: warningRatio
        )
    }

    // MARK: - Level

    @Test func belowThreshold_normal() {
        #expect(level(download: 94) == .normal)
    }

    @Test func atThreshold_warning() {
        #expect(level(download: 95) == .warning)
    }

    @Test func at100Percent_critical() {
        #expect(level(download: 100) == .critical)
    }

    @Test func uploadAlone_triggers() {
        #expect(level(download: 0, upload: 95) == .warning)
        #expect(level(download: 0, upload: 100) == .critical)
    }

    @Test func overThePlan_isStillCritical() {
        #expect(level(download: 160) == .critical)
    }

    @Test func theHigherDirectionWins() {
        #expect(level(download: 96, upload: 100) == .critical)
        #expect(level(download: 100, upload: 96) == .critical)
    }

    @Test func eachDirectionUsesItsOwnPlan() {
        // 30 Mbps up is the whole of a 30 Mbps upload plan, even though the download plan is 300.
        #expect(level(download: 10, upload: 30, planDownload: 300, planUpload: 30) == .critical)
        #expect(level(download: 30, upload: 10, planDownload: 300, planUpload: 30) == .normal)
    }

    @Test func theConfiguredThresholdMovesTheWarning() {
        #expect(level(download: 92, warningRatio: 0.90) == .warning)
        #expect(level(download: 96, warningRatio: 0.98) == .normal)
        #expect(level(download: 98, warningRatio: 0.98) == .warning)
    }

    @Test func anUnusablePlan_neverAlerts() {
        #expect(level(download: 500, planDownload: 0, planUpload: 100) == .normal)
        #expect(level(download: 500, planDownload: -1, planUpload: 100) == .normal)
        #expect(level(download: 500, planDownload: .nan, planUpload: 100) == .normal)
        #expect(level(download: 500, planDownload: .infinity, planUpload: 100) == .normal)
    }

    @Test func aNonFiniteSpeed_neverAlerts() {
        #expect(level(download: .nan) == .normal)
        #expect(level(download: -5) == .normal)
    }

    @Test func levelsAreOrdered() {
        #expect(MenuBarAlertLevel.normal < .warning)
        #expect(MenuBarAlertLevel.warning < .critical)
        #expect([MenuBarAlertLevel.warning, .critical, .normal].max() == .critical)
    }

    // MARK: - Tracker

    @Test func tracker_holds3Seconds() {
        var tracker = MenuBarAlertTracker()

        #expect(tracker.update(.critical, at: 0) == .critical)
        #expect(tracker.update(.normal, at: 2.9) == .critical)
        #expect(tracker.update(.normal, at: 3.0) == .normal)
    }

    @Test func tracker_risesAtOnce() {
        var tracker = MenuBarAlertTracker()

        #expect(tracker.update(.normal, at: 0) == .normal)
        #expect(tracker.update(.warning, at: 1) == .warning)
        #expect(tracker.update(.critical, at: 2) == .critical)
    }

    @Test func tracker_holdsTheHighestLevelOfTheLastThreeSeconds() {
        var tracker = MenuBarAlertTracker()

        #expect(tracker.update(.critical, at: 0) == .critical)
        #expect(tracker.update(.warning, at: 1) == .critical)
        #expect(tracker.update(.warning, at: 2) == .critical)
        // The critical sample is 3 s old and gone; the warnings are not.
        #expect(tracker.update(.normal, at: 3) == .warning)
        #expect(tracker.update(.normal, at: 4) == .warning)
        #expect(tracker.update(.normal, at: 5) == .normal)
    }

    @Test func tracker_anotherHitRestartsTheHold() {
        var tracker = MenuBarAlertTracker()

        #expect(tracker.update(.critical, at: 0) == .critical)
        #expect(tracker.update(.critical, at: 2) == .critical)
        #expect(tracker.update(.normal, at: 4) == .critical)
        #expect(tracker.update(.normal, at: 5) == .normal)
    }

    @Test func tracker_afterALongGap_holdsNothing() {
        var tracker = MenuBarAlertTracker()

        #expect(tracker.update(.critical, at: 10) == .critical)
        // The Mac slept: the monotonic clock kept counting.
        #expect(tracker.update(.normal, at: 4_000) == .normal)
    }

    @Test func tracker_ifTheClockGoesBack_startsOver() {
        var tracker = MenuBarAlertTracker()

        #expect(tracker.update(.critical, at: 100) == .critical)
        #expect(tracker.update(.normal, at: 5) == .normal)
    }

    // MARK: - Title

    @Test func title_hasTextCue() {
        let base = "↓ 288.9 ↑ 15.2 Mbps"
        let warning = MenuBarTitle.make(base: base, level: .warning)
        let critical = MenuBarTitle.make(base: base, level: .critical)
        let normal = MenuBarTitle.make(base: base, level: .normal)

        #expect(warning.text == "▲ " + base)
        #expect(critical.text == "▲▲ " + base)
        #expect(normal.text == base)
        #expect(!normal.text.contains("▲"))
        #expect(warning.level == .warning)
        #expect(critical.level == .critical)
    }

    @Test func title_accessibilityValue() {
        let base = "↓ 1.0 ↑ 1.0 Mbps"

        #expect(MenuBarTitle.make(base: base, level: .warning).accessibilityValue == L10n.menuBarAlertWarning)
        #expect(MenuBarTitle.make(base: base, level: .critical).accessibilityValue == L10n.menuBarAlertCritical)
        #expect(MenuBarTitle.make(base: base, level: .normal).accessibilityValue == nil)
        #expect(L10n.menuBarAlertWarning != L10n.menuBarAlertCritical)
    }

    @Test func title_equalTitlesAreEqual() {
        // The controller skips `setTitle` when nothing changed (PERF-16.1).
        let a = MenuBarTitle.make(base: "↓ 0.0 ↑ 0.0 Mbps", level: .normal)
        let b = MenuBarTitle.make(base: "↓ 0.0 ↑ 0.0 Mbps", level: .normal)
        let c = MenuBarTitle.make(base: "↓ 0.0 ↑ 0.0 Mbps", level: .warning)

        #expect(a == b)
        #expect(a != c)
    }
}

/// The menu bar text and the alert as the view model produces them from real samples.
@MainActor
@Suite("Menu bar view model")
struct MenuBarViewModelTests {

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

    private func makeViewModel(
        _ clock: TestClock,
        steps: [(download: Double, upload: Double)] = []
    ) -> NetworkMonitorViewModel {
        let viewModel = NetworkMonitorViewModel(dependencies: .test(
            clock: clock,
            counterSource: FakeCounterSource(Self.script(steps))
        ))
        viewModel.networkMonitor.startMonitoring()
        viewModel.networkMonitor.stopMonitoring()
        return viewModel
    }

    private func feed(_ viewModel: NetworkMonitorViewModel, _ clock: TestClock, samples: Int) {
        for _ in 0..<samples {
            clock.advance(by: 1)
            viewModel.networkMonitor.tick()
        }
    }

    // MARK: - Text

    @Test func compactMode_hasArrows() {
        let viewModel = NetworkMonitorViewModel(dependencies: .test(clock: TestClock(2026, 11, 3, 9)))
        viewModel.preferences.menuBarDisplayMode = .compact
        // Bytes per second for 288.9 and 15.2 Mbps.
        viewModel.currentSpeed = NetworkSpeed(uploadSpeed: 15.2e6 / 8, downloadSpeed: 288.9e6 / 8)

        #expect(viewModel.menuBarText == "↓288.9/↑15.2 Mbps")
    }

    @Test func otherModes_areUnchanged() {
        let viewModel = NetworkMonitorViewModel(dependencies: .test(clock: TestClock(2026, 11, 3, 9)))
        viewModel.currentSpeed = NetworkSpeed(uploadSpeed: 14.8e6 / 8, downloadSpeed: 182.4e6 / 8)

        viewModel.preferences.menuBarDisplayMode = .both
        #expect(viewModel.menuBarText == "↓ 182.4 ↑ 14.8 Mbps")
        viewModel.preferences.menuBarDisplayMode = .downloadOnly
        #expect(viewModel.menuBarText == "↓ 182.4 Mbps")
        viewModel.preferences.menuBarDisplayMode = .uploadOnly
        #expect(viewModel.menuBarText == "↑ 14.8 Mbps")
    }

    // MARK: - isPeakConcerning (R12)

    @Test func isPeakConcerning_usesConfiguredThreshold() {
        let viewModel = NetworkMonitorViewModel(dependencies: .test(clock: TestClock(2026, 11, 3, 9)))
        viewModel.notificationService.threshold = 0.98

        #expect(!viewModel.isPeakConcerning(speed: 96, planSpeed: 100))
        #expect(viewModel.isPeakConcerning(speed: 98, planSpeed: 100))

        viewModel.notificationService.threshold = 0.90
        #expect(viewModel.isPeakConcerning(speed: 92, planSpeed: 100))
        #expect(!viewModel.isPeakConcerning(speed: 89, planSpeed: 100))
    }

    @Test func isPeakConcerning_rejectsAnUnusablePlan() {
        let viewModel = NetworkMonitorViewModel(dependencies: .test(clock: TestClock(2026, 11, 3, 9)))

        #expect(!viewModel.isPeakConcerning(speed: 50, planSpeed: 0))
        #expect(!viewModel.isPeakConcerning(speed: 50, planSpeed: -10))
        #expect(!viewModel.isPeakConcerning(speed: 50, planSpeed: .nan))
    }

    // MARK: - Alert from samples

    @Test func title_startsNormal() {
        let viewModel = NetworkMonitorViewModel(dependencies: .test(clock: TestClock(2026, 11, 3, 9)))

        #expect(viewModel.menuBarTitle.level == .normal)
        #expect(viewModel.menuBarTitle.text == viewModel.menuBarText)
    }

    @Test func nearThePlan_warnsAndHoldsForThreeSeconds() {
        let clock = TestClock(2026, 11, 3, 10)
        // The default plan is 300 Mbps; 295 Mbps is 98% of it: over the default 95% threshold,
        // under 100%.
        let viewModel = makeViewModel(clock, steps: [
            (download: 295, upload: 0), (download: 0, upload: 0), (download: 0, upload: 0),
            (download: 0, upload: 0), (download: 0, upload: 0),
        ])

        feed(viewModel, clock, samples: 1)
        #expect(viewModel.menuBarTitle.level == .warning)
        #expect(viewModel.menuBarTitle.text.hasPrefix("▲ "))
        #expect(viewModel.menuBarTitle.accessibilityValue == L10n.menuBarAlertWarning)

        // Quiet again, but a flicker back to normal at 1 Hz is held off for 3 s.
        feed(viewModel, clock, samples: 2)
        #expect(viewModel.menuBarTitle.level == .warning)

        feed(viewModel, clock, samples: 1)
        #expect(viewModel.menuBarTitle.level == .normal)
        #expect(viewModel.menuBarTitle.text == viewModel.menuBarText)
    }

    @Test func atThePlan_isCritical() {
        let clock = TestClock(2026, 11, 3, 10)
        let viewModel = makeViewModel(clock, steps: [(download: 310, upload: 0)])

        feed(viewModel, clock, samples: 1)

        #expect(viewModel.menuBarTitle.level == .critical)
        #expect(viewModel.menuBarTitle.text.hasPrefix("▲▲ "))
    }

    @Test func aLowerThreshold_warnsEarlier() {
        let clock = TestClock(2026, 11, 3, 10)
        let viewModel = makeViewModel(clock, steps: [(download: 275, upload: 0), (download: 275, upload: 0)])
        viewModel.notificationService.threshold = 0.90

        feed(viewModel, clock, samples: 1)

        // 275 of 300 is 92%: under the default 95%, over 90%.
        #expect(viewModel.menuBarTitle.level == .warning)
    }

    @Test func aSampleOverTheCap_leavesTheTitleAlone() {
        let clock = TestClock(2026, 11, 3, 10)
        // 25 000 Mbps is past the plausibility cap (`SampleGuard`).
        let viewModel = makeViewModel(clock, steps: [(download: 295, upload: 0), (download: 25_000, upload: 0)])

        feed(viewModel, clock, samples: 1)
        let before = viewModel.menuBarTitle
        feed(viewModel, clock, samples: 1)

        #expect(viewModel.menuBarTitle == before)
    }
}
