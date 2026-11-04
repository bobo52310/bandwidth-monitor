import Testing
import Foundation
@testable import BandwidthECGFeature

/// CORE-20: a timer scheduled the default way stops firing while a menu is open or a window is
/// being dragged, because AppKit runs the main run loop in event tracking mode for that time.
@MainActor
@Suite("RepeatingTimer")
struct RepeatingTimerTests {

    /// Runs the main run loop in `mode` until `seconds` have passed.
    private func runMainLoop(_ mode: RunLoop.Mode, for seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(mode: mode, before: deadline)
        }
    }

    /// `NSApplication` adds event tracking to the common modes when it starts. These tests run
    /// without an application object, so the mode has to be added by hand to match a real app.
    private func addEventTrackingToCommonModes() {
        CFRunLoopAddCommonMode(
            CFRunLoopGetMain(),
            CFRunLoopMode(rawValue: RunLoop.Mode.eventTracking.rawValue as CFString)
        )
    }

    @Test func firesDuringEventTracking() {
        addEventTrackingToCommonModes()
        var fires = 0
        let timer = RepeatingTimer.schedule(interval: 0.1, tolerance: 0.02) { fires += 1 }
        defer { timer.invalidate() }

        runMainLoop(.eventTracking, for: 0.55)

        #expect(fires >= 3)
    }

    @Test func networkMonitor_keepsSamplingDuringEventTracking() {
        addEventTrackingToCommonModes()
        let source = FakeCounterSource([["en0": InterfaceCounters(rx: 0, tx: 0)]])
        let monitor = NetworkMonitor(source: source, clock: TestClock(2026, 10, 31, 12).appClock)

        monitor.startMonitoring()
        defer { monitor.stopMonitoring() }
        #expect(source.readCount == 1) // the baseline

        runMainLoop(.eventTracking, for: 1.5)

        #expect(source.readCount >= 2) // the timer kept reading the counters
    }

    @Test func appliesTheTolerance() {
        let timer = RepeatingTimer.schedule(interval: 60, tolerance: 2) {}
        defer { timer.invalidate() }

        #expect(timer.tolerance == 2)
        #expect(timer.timeInterval == 60)
    }

    @Test func stopsFiringOnceInvalidated() {
        var fires = 0
        let timer = RepeatingTimer.schedule(interval: 0.05, tolerance: 0.01) { fires += 1 }
        timer.invalidate()

        runMainLoop(.default, for: 0.2)

        #expect(fires == 0)
    }
}
