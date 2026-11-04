import Testing
import Foundation
@testable import BandwidthECGFeature

@Test func disconnectEvent_hasDuration() async throws {
    let start = Date().addingTimeInterval(-60)
    let end = Date()
    let event = DisconnectEvent(startTime: start, endTime: end, interfaceType: "wifi")
    #expect(abs(event.duration - 60.0) < 1.0)
}

@Test func disconnectEvent_formattedDuration_seconds() async throws {
    let start = Date()
    let end = start.addingTimeInterval(45)
    let event = DisconnectEvent(startTime: start, endTime: end, interfaceType: "wifi")
    #expect(event.formattedDuration.contains("45"))
}

@Test func disconnectEvent_formattedDuration_minutes() async throws {
    let start = Date()
    let end = start.addingTimeInterval(130)
    let event = DisconnectEvent(startTime: start, endTime: end, interfaceType: "wifi")
    #expect(event.formattedDuration.contains("2"))
}

@MainActor
@Test func tracker_todayEvents_filtersCorrectly() async throws {
    let clock = TestClock(2026, 10, 31, 12)
    let tracker = DisconnectTracker(
        defaults: MemoryDefaults.make(),
        clock: clock.appClock,
        pathSource: FakePathSource()
    )
    let today = clock.now
    let yesterday = clock.calendar.date(byAdding: .day, value: -1, to: today)!

    let todayEvent = DisconnectEvent(startTime: today.addingTimeInterval(-60), endTime: today, interfaceType: "wifi")
    let yesterdayEvent = DisconnectEvent(startTime: yesterday.addingTimeInterval(-60), endTime: yesterday, interfaceType: "wifi")

    tracker.addEventForTesting(todayEvent)
    tracker.addEventForTesting(yesterdayEvent)

    #expect(tracker.todayEvents.count == 1)
}

@MainActor
@Test func tracker_totalDowntimeToday_calculatesCorrectly() async throws {
    let clock = TestClock(2026, 10, 31, 12)
    let tracker = DisconnectTracker(
        defaults: MemoryDefaults.make(),
        clock: clock.appClock,
        pathSource: FakePathSource()
    )
    let now = clock.now

    let event1 = DisconnectEvent(startTime: now.addingTimeInterval(-120), endTime: now.addingTimeInterval(-60), interfaceType: "wifi")
    let event2 = DisconnectEvent(startTime: now.addingTimeInterval(-30), endTime: now, interfaceType: "wifi")

    tracker.addEventForTesting(event1)
    tracker.addEventForTesting(event2)

    #expect(abs(tracker.totalDowntimeToday - 90.0) < 1.0)
}

/// "Today" follows the injected clock's time zone, not the machine's: the same instant is
/// today in Taipei and yesterday in New York.
@MainActor
@Test func tracker_todayEvents_followsClockTimeZone() async throws {
    let taipei = TimeZone(identifier: "Asia/Taipei")!
    let newYork = TimeZone(identifier: "America/New_York")!

    // "Now" is 2026-10-31 23:30 in Taipei, which is 11:30 the same day in New York.
    let taipeiClock = TestClock(2026, 10, 31, 23, 30, timeZone: taipei)
    let newYorkClock = TestClock(start: taipeiClock.now, timeZone: newYork)
    // The event is 2026-10-31 02:00 in Taipei, which is 2026-10-30 14:00 in New York.
    let eventStart = taipeiClock.now.addingTimeInterval(-21.5 * 3600)
    let event = DisconnectEvent(startTime: eventStart, endTime: eventStart.addingTimeInterval(10), interfaceType: "wifi")

    let taipeiTracker = DisconnectTracker(defaults: MemoryDefaults.make(), clock: taipeiClock.appClock, pathSource: FakePathSource())
    let newYorkTracker = DisconnectTracker(defaults: MemoryDefaults.make(), clock: newYorkClock.appClock, pathSource: FakePathSource())
    taipeiTracker.addEventForTesting(event)
    newYorkTracker.addEventForTesting(event)

    #expect(taipeiTracker.todayEvents.count == 1)
    #expect(newYorkTracker.todayEvents.count == 0)
}

// MARK: - Path source seam

@MainActor
@Suite("DisconnectTracker path handling")
struct DisconnectTrackerPathTests {

    private func makeTracker(
        clock: TestClock = TestClock(2026, 10, 31, 12),
        defaults: MemoryDefaults = .make(),
        source: FakePathSource = FakePathSource()
    ) -> DisconnectTracker {
        DisconnectTracker(defaults: defaults, clock: clock.appClock, pathSource: source)
    }

    @Test func handle_disconnectThenReconnect_recordsOneEvent() {
        let clock = TestClock(2026, 10, 31, 12)
        let tracker = makeTracker(clock: clock)

        tracker.handle(PathSnapshot(isSatisfied: false, interfaceType: "wifi"))
        #expect(tracker.isConnected == false)
        #expect(tracker.events.isEmpty)

        clock.advance(by: 45)
        tracker.handle(PathSnapshot(isSatisfied: true, interfaceType: "wifi"))

        #expect(tracker.isConnected)
        #expect(tracker.events.count == 1)
        #expect(tracker.events.first?.duration == 45)
        #expect(tracker.events.first?.interfaceType == "wifi")
        #expect(tracker.todayEvents.count == 1)
    }

    @Test func handle_repeatedConnectedSnapshots_recordNothing() {
        let tracker = makeTracker()

        tracker.handle(PathSnapshot(isSatisfied: true, interfaceType: "wifi"))
        tracker.handle(PathSnapshot(isSatisfied: true, interfaceType: "ethernet"))

        #expect(tracker.events.isEmpty)
        #expect(tracker.currentInterfaceType == "ethernet")
    }

    @Test func events_persistThroughInjectedDefaults() {
        let clock = TestClock(2026, 10, 31, 12)
        let defaults = MemoryDefaults.make()
        let tracker = makeTracker(clock: clock, defaults: defaults)

        tracker.handle(PathSnapshot(isSatisfied: false, interfaceType: "wifi"))
        clock.advance(by: 20)
        tracker.handle(PathSnapshot(isSatisfied: true, interfaceType: "wifi"))

        let reloaded = makeTracker(clock: clock, defaults: defaults)
        #expect(reloaded.events.count == 1)
        #expect(reloaded.events.first?.duration == 20)
    }

    @Test func eventsOlderThanThirtyDays_areDroppedOnLoad() {
        let clock = TestClock(2026, 10, 31, 12)
        let defaults = MemoryDefaults.make()
        let tracker = makeTracker(clock: clock, defaults: defaults)

        // Record one event now, then move the clock 31 days ahead and reload.
        tracker.handle(PathSnapshot(isSatisfied: false, interfaceType: "wifi"))
        clock.advance(by: 20)
        tracker.handle(PathSnapshot(isSatisfied: true, interfaceType: "wifi"))
        clock.advance(by: 31 * 24 * 3600)

        let reloaded = makeTracker(clock: clock, defaults: defaults)
        #expect(reloaded.events.isEmpty)
    }

    @Test func startAndStop_goThroughThePathSource() {
        let source = FakePathSource()
        let tracker = makeTracker(source: source)

        tracker.startMonitoring()
        tracker.startMonitoring() // second start is ignored
        #expect(source.startCount == 1)
        #expect(source.isStarted)

        tracker.stopMonitoring()
        tracker.stopMonitoring() // second stop is ignored
        #expect(source.stopCount == 1)
        #expect(source.isStarted == false)

        // It can be started again after a stop.
        tracker.startMonitoring()
        #expect(source.startCount == 2)
    }

    @Test func pathSourceCallback_reachesTheTracker() async {
        let source = FakePathSource()
        let tracker = makeTracker(source: source)
        tracker.startMonitoring()

        source.emit(PathSnapshot(isSatisfied: false, interfaceType: "ethernet"))

        // The source calls back off the main actor; the tracker hops back before handling.
        let reached = await eventually { tracker.isConnected == false }
        #expect(reached)
        #expect(tracker.currentInterfaceType == "ethernet")
    }
}

@MainActor
@Test func tracker_onEvent_reportsARestoredConnection() async throws {
    let clock = TestClock(2026, 10, 31, 12)
    let tracker = DisconnectTracker(
        defaults: MemoryDefaults.make(),
        clock: clock.appClock,
        pathSource: FakePathSource()
    )
    var received: [DisconnectEvent] = []
    tracker.onEvent = { received.append($0) }
    let start = clock.now

    tracker.handle(PathSnapshot(isSatisfied: false, interfaceType: "wifi"))
    #expect(received.isEmpty)

    clock.advance(by: 45)
    tracker.handle(PathSnapshot(isSatisfied: true, interfaceType: "wifi"))

    #expect(received.count == 1)
    #expect(received.first?.startTime == start)
    #expect(received.first?.duration == 45)
    #expect(received.first?.id == tracker.events.last?.id)
}

// MARK: - Outages from the path, the probe, and sleep (CORE-23, CORE-31)

@MainActor
@Suite("DisconnectTracker outages")
struct DisconnectTrackerOutageTests {
    private let clock = TestClock(2026, 11, 3, 12)
    private let wifi = PathSnapshot(isSatisfied: true, interfaceType: "wifi")
    /// At the moment of loss the path often has no interface left, so it reads as "other".
    private let lost = PathSnapshot(isSatisfied: false, interfaceType: "other")

    private func makeTracker() -> DisconnectTracker {
        DisconnectTracker(defaults: MemoryDefaults.make(), clock: clock.appClock, pathSource: FakePathSource())
    }

    private func at(_ seconds: TimeInterval, from start: Date) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test func pathLostThenRestored_oneEvent() throws {
        let tracker = makeTracker()
        var received: [DisconnectEvent] = []
        tracker.onEvent = { received.append($0) }
        tracker.handle(wifi)
        let t0 = clock.now

        tracker.handle(lost)
        #expect(tracker.isConnected == false)
        clock.advance(by: 45)
        tracker.handle(wifi)

        let event = try #require(tracker.events.first)
        #expect(tracker.events.count == 1)
        #expect(event.startTime == t0)
        #expect(event.endTime == at(45, from: t0))
        #expect(event.duration == 45)
        #expect(received.count == 1)
        #expect(tracker.isConnected)
    }

    /// The router keeps the Wi-Fi up, so the path stays satisfied while the internet is gone.
    @Test func ispOutage_twoProbeFailures_oneEvent() throws {
        let tracker = makeTracker()
        var received: [DisconnectEvent] = []
        tracker.onEvent = { received.append($0) }
        tracker.handle(wifi)
        let t0 = clock.now

        tracker.noteProbe(success: false)
        #expect(tracker.isConnected) // one failure is not an outage yet
        clock.advance(by: 30)
        tracker.noteProbe(success: false)
        #expect(tracker.isConnected == false)
        #expect(tracker.events.isEmpty)
        clock.advance(by: 270)
        tracker.noteProbe(success: true)

        let event = try #require(tracker.events.first)
        #expect(tracker.events.count == 1)
        #expect(event.startTime == t0)
        #expect(event.endTime == at(300, from: t0))
        #expect(event.interfaceType == "wifi")
        #expect(received.count == 1)
        #expect(tracker.isConnected)
    }

    @Test func singleProbeFailure_noEvent() {
        let tracker = makeTracker()
        tracker.handle(wifi)

        tracker.noteProbe(success: false)
        clock.advance(by: 30)
        tracker.noteProbe(success: true)
        clock.advance(by: 30)
        tracker.noteProbe(success: false) // the count starts over after a success
        clock.advance(by: 30)
        tracker.noteProbe(success: true)

        #expect(tracker.events.isEmpty)
        #expect(tracker.isConnected)
    }

    /// Probe failures first, then the path drops and returns while the probe is still failing.
    @Test func pathAndProbeOverlap_oneEvent() throws {
        let tracker = makeTracker()
        tracker.handle(wifi)
        let t0 = clock.now

        tracker.noteProbe(success: false)
        clock.advance(by: 30)
        tracker.noteProbe(success: false)
        clock.advance(by: 10)
        tracker.handle(lost)
        clock.advance(by: 20)
        tracker.handle(wifi)
        #expect(tracker.isConnected == false) // the probe has not recovered yet
        clock.advance(by: 30)
        tracker.noteProbe(success: true)

        let event = try #require(tracker.events.first)
        #expect(tracker.events.count == 1)
        #expect(event.startTime == t0)
        #expect(event.endTime == at(90, from: t0))
    }

    /// With no path the probe is bound to fail; those failures must not keep the outage open
    /// after the path comes back.
    @Test func probeFailuresWhilePathDown_doNotExtendOutage() throws {
        let tracker = makeTracker()
        tracker.handle(wifi)
        let t0 = clock.now

        tracker.handle(lost)
        clock.advance(by: 10)
        tracker.noteProbe(success: false)
        clock.advance(by: 30)
        tracker.noteProbe(success: false)
        clock.advance(by: 10)
        tracker.handle(wifi)

        let event = try #require(tracker.events.first)
        #expect(tracker.events.count == 1)
        #expect(event.startTime == t0)
        #expect(event.endTime == at(50, from: t0))
        #expect(tracker.isConnected)
        #expect(tracker.consecutiveProbeFailures == 0)
    }

    @Test func clearProbeFailures_endsAProbeOutage() throws {
        let tracker = makeTracker()
        tracker.handle(wifi)
        let t0 = clock.now
        tracker.noteProbe(success: false)
        clock.advance(by: 30)
        tracker.noteProbe(success: false)
        clock.advance(by: 30)

        tracker.clearProbeFailures()

        let event = try #require(tracker.events.first)
        #expect(event.startTime == t0)
        #expect(event.endTime == at(60, from: t0))
        #expect(tracker.isConnected)
        #expect(tracker.consecutiveProbeFailures == 0)
    }

    // MARK: Sleep

    @Test func sleep_closesOpenOutage() throws {
        let tracker = makeTracker()
        var received: [DisconnectEvent] = []
        tracker.onEvent = { received.append($0) }
        tracker.handle(wifi)
        let t0 = clock.now

        tracker.handle(lost)
        clock.advance(by: 10)
        tracker.handleSleep()

        let event = try #require(tracker.events.first)
        #expect(tracker.events.count == 1)
        #expect(event.startTime == t0)
        #expect(event.endTime == at(10, from: t0))
        #expect(received.count == 1)
    }

    // Fix round 1: a path loss in the last seconds before sleep is the sleep itself taking the
    // network down (if it is reported before willSleep), so it is not a disconnect.

    @Test func pathLossJustBeforeSleep_notCounted() {
        let tracker = makeTracker()
        var received: [DisconnectEvent] = []
        tracker.onEvent = { received.append($0) }
        tracker.handle(wifi)

        tracker.handle(lost)
        clock.advance(by: 1)
        tracker.handleSleep()

        #expect(tracker.events.isEmpty)
        #expect(received.isEmpty)
        #expect(tracker.isConnected)
    }

    @Test func pathLossSixSecondsBeforeSleep_counted() throws {
        let tracker = makeTracker()
        tracker.handle(wifi)
        let t0 = clock.now

        tracker.handle(lost)
        clock.advance(by: 6)
        tracker.handleSleep()

        let event = try #require(tracker.events.first)
        #expect(tracker.events.count == 1)
        #expect(event.startTime == t0)
        #expect(event.duration == 6)
    }

    /// The boundary is pinned on the counted side: 5 s or more before sleep is a disconnect.
    @Test func pathLossExactlyFiveSecondsBeforeSleep_counted() throws {
        let tracker = makeTracker()
        tracker.handle(wifi)

        tracker.handle(lost)
        clock.advance(by: 5)
        tracker.handleSleep()

        let event = try #require(tracker.events.first)
        #expect(tracker.events.count == 1)
        #expect(event.duration == 5)
    }

    @Test func pathLossJustUnderFiveSecondsBeforeSleep_notCounted() {
        let tracker = makeTracker()
        tracker.handle(wifi)

        tracker.handle(lost)
        clock.advance(by: 4.9)
        tracker.handleSleep()

        #expect(tracker.events.isEmpty)
    }

    /// A probe outage opens at the second failure but began at the first, 30 s earlier.
    @Test func probeOutageOpenedJustBeforeSleep_countsFromTheFirstFailure() throws {
        let tracker = makeTracker()
        tracker.handle(wifi)
        let t0 = clock.now
        tracker.noteProbe(success: false)
        clock.advance(by: 30)
        tracker.noteProbe(success: false)
        clock.advance(by: 1)

        tracker.handleSleep()

        let event = try #require(tracker.events.first)
        #expect(event.startTime == t0)
        #expect(event.duration == 31)
    }

    /// The 5 s are measured on the monotonic clock: a wall-clock jump in between changes nothing.
    @Test func pathLossJustBeforeSleep_usesMonotonicTime() {
        let tracker = makeTracker()
        tracker.handle(wifi)

        tracker.handle(lost)
        clock.setWall(clock.now.addingTimeInterval(3600))
        clock.advance(by: 1)
        tracker.handleSleep()

        #expect(tracker.events.isEmpty)
    }

    @Test func sleep_closesAProbeOutage() throws {
        let tracker = makeTracker()
        tracker.handle(wifi)
        let t0 = clock.now
        tracker.noteProbe(success: false)
        clock.advance(by: 30)
        tracker.noteProbe(success: false)
        clock.advance(by: 5)

        tracker.handleSleep()

        let event = try #require(tracker.events.first)
        #expect(event.endTime == at(35, from: t0))
        #expect(tracker.consecutiveProbeFailures == 0)
    }

    @Test func pathLossDuringSleep_ignored() {
        let tracker = makeTracker()
        tracker.handle(wifi)

        tracker.handleSleep()
        clock.advance(by: 5)
        tracker.handle(lost)
        tracker.noteProbe(success: false)
        clock.advance(by: 30)
        tracker.noteProbe(success: false)
        clock.advance(by: 3600)
        tracker.handle(wifi)
        clock.advance(by: 60)
        tracker.handleWake()
        clock.advance(by: 60)

        #expect(tracker.events.isEmpty)
        #expect(tracker.isConnected)
    }

    /// The probe fails while the Mac sleeps even with the path still up; it says nothing.
    @Test func probeFailuresDuringSleep_ignored() {
        let tracker = makeTracker()
        tracker.handle(wifi)

        tracker.handleSleep()
        tracker.noteProbe(success: false)
        clock.advance(by: 30)
        tracker.noteProbe(success: false)
        clock.advance(by: 600)
        tracker.handleWake()
        #expect(tracker.isConnected)
        #expect(tracker.consecutiveProbeFailures == 0)
        clock.advance(by: 30)
        tracker.noteProbe(success: true)

        #expect(tracker.events.isEmpty)
    }

    /// Stage 4 left this open: the path drops during sleep and is still down at wake. Sleep is
    /// not downtime, so the outage starts at wake.
    @Test func pathDownAcrossWake_countsFromWake() throws {
        let tracker = makeTracker()
        tracker.handle(wifi)

        tracker.handleSleep()
        clock.advance(by: 5)
        tracker.handle(lost)
        clock.advance(by: 3600)
        let wake = clock.now
        tracker.handleWake()
        #expect(tracker.isConnected == false)
        clock.advance(by: 30)
        tracker.handle(wifi)

        let event = try #require(tracker.events.first)
        #expect(tracker.events.count == 1)
        #expect(event.startTime == wake)
        #expect(event.duration == 30)
    }

    @Test func wakeGrace_10s() throws {
        let tracker = makeTracker()
        tracker.handle(wifi)
        tracker.handleSleep()
        clock.advance(by: 600)
        tracker.handleWake()

        clock.advance(by: 3)
        tracker.handle(lost)
        clock.advance(by: 6)
        tracker.handle(wifi) // back at wake + 9 s
        #expect(tracker.events.isEmpty)

        // Once the grace is over, a loss counts again.
        clock.advance(by: 60)
        let t1 = clock.now
        tracker.handle(lost)
        clock.advance(by: 4)
        tracker.handle(wifi)

        let event = try #require(tracker.events.first)
        #expect(tracker.events.count == 1)
        #expect(event.startTime == t1)
    }

    /// An outage that begins in the grace period but is still going when it ends is real.
    @Test func wakeGrace_lossThatOutlastsIt_isRecorded() throws {
        let tracker = makeTracker()
        tracker.handle(wifi)
        tracker.handleSleep()
        clock.advance(by: 600)
        tracker.handleWake()

        clock.advance(by: 3)
        let t1 = clock.now
        tracker.handle(lost)
        clock.advance(by: 9)
        tracker.handle(wifi) // back at wake + 12 s, just past the grace

        let event = try #require(tracker.events.first)
        #expect(event.startTime == t1)
        #expect(event.duration == 9)
    }

    /// One failed probe just before the path drops is put down to the drop, so it cannot pair
    /// with a later failure into an outage that starts before the path loss.
    @Test func probeFailureJustBeforePathLoss_doesNotCarryOver() throws {
        let tracker = makeTracker()
        tracker.handle(wifi)

        tracker.noteProbe(success: false)
        clock.advance(by: 10)
        let lostAt = clock.now
        tracker.handle(lost)
        clock.advance(by: 10)
        tracker.handle(wifi)
        clock.advance(by: 10)
        tracker.noteProbe(success: false)
        #expect(tracker.isConnected)
        clock.advance(by: 30)
        tracker.noteProbe(success: true)

        let event = try #require(tracker.events.first)
        #expect(tracker.events.count == 1)
        #expect(event.startTime == lostAt)
        #expect(event.duration == 10)
    }

    // MARK: Interface type and callbacks

    @Test func interfaceType_keepsLastKnown() throws {
        let tracker = makeTracker()
        tracker.handle(wifi)

        tracker.handle(lost)
        clock.advance(by: 20)
        tracker.handle(wifi)

        let event = try #require(tracker.events.first)
        #expect(event.interfaceType == "wifi")
        #expect(tracker.lastKnownInterfaceType == "wifi")
    }

    @Test func interfaceType_unsatisfiedSnapshotDoesNotOverwriteLastKnown() {
        let tracker = makeTracker()
        tracker.handle(PathSnapshot(isSatisfied: true, interfaceType: "ethernet"))

        tracker.handle(PathSnapshot(isSatisfied: false, interfaceType: "other"))

        #expect(tracker.lastKnownInterfaceType == "ethernet")
    }

    @Test func onConnectivityChange_reportsPathChanges() {
        let tracker = makeTracker()
        var changes: [Bool] = []
        tracker.onConnectivityChange = { changes.append($0) }

        tracker.handle(wifi)
        tracker.handle(lost)
        tracker.handle(lost)
        tracker.handle(wifi)
        tracker.handle(PathSnapshot(isSatisfied: true, interfaceType: "ethernet"))

        #expect(changes == [false, true])
        #expect(tracker.isPathSatisfied)
    }
}
