import Testing
import Foundation
@testable import BandwidthECGFeature

@Suite("PeakApproachTracker")
struct PeakApproachTrackerTests {

    private func makeTracker(_ clock: TestClock, _ defaults: UserDefaults) -> PeakApproachTracker {
        PeakApproachTracker(defaults: defaults, clock: clock.appClock)
    }

    private func speed(download: Double, upload: Double = 0) -> NetworkSpeed {
        NetworkSpeed(uploadSpeed: upload * 125_000, downloadSpeed: download * 125_000)
    }

    /// One sample against a 300/300 plan.
    private func check(_ tracker: PeakApproachTracker, download: Double, upload: Double = 0) -> Bool {
        tracker.checkForApproach(speed(download: download, upload: upload), downloadPlanSpeed: 300, uploadPlanSpeed: 300)
    }

    /// Samples at 1 Hz whose first and last are `seconds` apart, against a 300/300 plan.
    /// The clock ends one second after the last sample. Returns how many fired an event.
    @discardableResult
    private func feed(
        _ tracker: PeakApproachTracker,
        _ clock: TestClock,
        download: Double,
        upload: Double = 0,
        seconds: Int
    ) -> Int {
        var fired = 0
        for _ in 0...seconds {
            if check(tracker, download: download, upload: upload) { fired += 1 }
            clock.advance(by: 1)
        }
        return fired
    }

    /// CORE-06, field data: `todayApproachCount=2` left over from an old date.
    @Test func staleApproach_afterEmptySession() {
        let clock = TestClock(2026, 11, 2, 12)
        let oldDay = TestClock(2026, 3, 3, 9).now
        let defaults = MemoryDefaults.make()
        defaults.set(2, forKey: "todayApproachCount")
        defaults.set([oldDay.timeIntervalSince1970], forKey: "approachTimestamps")
        defaults.set(oldDay, forKey: "lastApproachRecordDate")

        let tracker = makeTracker(clock, defaults) // launched today, no samples

        #expect(tracker.todayApproachCount == 0)
        #expect(tracker.approachTimestamps.isEmpty)
        #expect(defaults.object(forKey: "todayApproachCount") == nil)
        #expect(defaults.object(forKey: "approachTimestamps") == nil)

        let relaunched = makeTracker(clock, defaults)
        #expect(relaunched.todayApproachCount == 0)
        #expect(relaunched.approachTimestamps.isEmpty)
    }

    @Test func newDay_removesApproachKeys() {
        let clock = TestClock(2026, 10, 30, 12)
        let defaults = MemoryDefaults.make()
        let tracker = makeTracker(clock, defaults)
        feed(tracker, clock, download: 240, seconds: 30)
        #expect(tracker.todayApproachCount == 1)

        clock.advance(by: 86_400)
        tracker.checkForApproach(speed(download: 0), downloadPlanSpeed: 300, uploadPlanSpeed: 300)

        #expect(tracker.todayApproachCount == 0)
        #expect(tracker.approachTimestamps.isEmpty)
        #expect(defaults.object(forKey: "todayApproachCount") == nil)
        #expect(defaults.object(forKey: "approachTimestamps") == nil)
    }

    @Test func sameDay_keepsTheCountAcrossLaunches() {
        let clock = TestClock(2026, 10, 30, 12)
        let defaults = MemoryDefaults.make()
        feed(makeTracker(clock, defaults), clock, download: 240, seconds: 30)

        clock.advance(by: 60)
        let relaunched = makeTracker(clock, defaults)

        #expect(relaunched.todayApproachCount == 1)
        #expect(relaunched.approachTimestamps.count == 1)
    }

    // MARK: - Event counting. "N seconds" means first to last sample, so N+1 samples at 1 Hz.

    @Test func singleSecondSpike_zero() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        #expect(feed(tracker, clock, download: 280, seconds: 0) == 0)
        #expect(tracker.todayApproachCount == 0)
    }

    @Test func sustained29s_zero() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        #expect(feed(tracker, clock, download: 240, seconds: 29) == 0)
        #expect(tracker.todayApproachCount == 0)
    }

    @Test func sustained30s_one() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())
        let expectedTime = clock.now.addingTimeInterval(30)

        var results: [Bool] = []
        for _ in 0...30 {
            results.append(check(tracker, download: 240))
            clock.advance(by: 1)
        }

        #expect(results.dropLast().allSatisfy { $0 == false })
        #expect(results.last == true)
        #expect(tracker.todayApproachCount == 1)
        #expect(tracker.approachTimestamps == [expectedTime])
    }

    @Test func sixtyMinuteDownload_one() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        feed(tracker, clock, download: 280, seconds: 3600)

        #expect(tracker.todayApproachCount == 1)
    }

    @Test func rearmAfter60sBelow60Percent() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        feed(tracker, clock, download: 280, seconds: 30)
        feed(tracker, clock, download: 100, seconds: 60)
        feed(tracker, clock, download: 280, seconds: 30)

        #expect(tracker.todayApproachCount == 2)
    }

    @Test func notRearmed_59s() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        feed(tracker, clock, download: 280, seconds: 30)
        feed(tracker, clock, download: 100, seconds: 59)
        feed(tracker, clock, download: 280, seconds: 30)

        #expect(tracker.todayApproachCount == 1)
    }

    @Test func dipTo70Percent_doesNotRearm() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        feed(tracker, clock, download: 280, seconds: 30)
        feed(tracker, clock, download: 210, seconds: 120)
        feed(tracker, clock, download: 280, seconds: 30)

        #expect(tracker.todayApproachCount == 1)
    }

    @Test func rearm_needsBothDirectionsBelow60Percent() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        feed(tracker, clock, download: 280, seconds: 30)
        feed(tracker, clock, download: 100, upload: 180, seconds: 120) // upload is exactly 60%
        feed(tracker, clock, download: 280, seconds: 30)

        #expect(tracker.todayApproachCount == 1)
    }

    @Test func rearmTimer_restartsWhenASampleComesBackUp() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        feed(tracker, clock, download: 280, seconds: 30)
        feed(tracker, clock, download: 100, seconds: 40)
        feed(tracker, clock, download: 210, seconds: 0)
        feed(tracker, clock, download: 100, seconds: 40)
        feed(tracker, clock, download: 280, seconds: 30)

        #expect(tracker.todayApproachCount == 1)
    }

    @Test func sustainTimer_restartsWhenASampleDropsBelow80Percent() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        feed(tracker, clock, download: 240, seconds: 20)
        feed(tracker, clock, download: 239, seconds: 0)
        feed(tracker, clock, download: 240, seconds: 20)

        #expect(tracker.todayApproachCount == 0)
    }

    @Test func exactly80Percent_counts() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        feed(tracker, clock, download: 240, seconds: 30)

        #expect(tracker.todayApproachCount == 1)
    }

    @Test func uploadAlsoCounts() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        feed(tracker, clock, download: 0, upload: 240, seconds: 30)

        #expect(tracker.todayApproachCount == 1)
    }

    @Test func eachDirectionUsesItsOwnPlan() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        for _ in 0...30 {
            tracker.checkForApproach(speed(download: 240, upload: 0), downloadPlanSpeed: 1000, uploadPlanSpeed: 100)
            clock.advance(by: 1)
        }
        #expect(tracker.todayApproachCount == 0)

        for _ in 0...30 {
            tracker.checkForApproach(speed(download: 0, upload: 80), downloadPlanSpeed: 1000, uploadPlanSpeed: 100)
            clock.advance(by: 1)
        }
        #expect(tracker.todayApproachCount == 1)
    }

    @Test func approachGap_resetsSustainTimer() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        feed(tracker, clock, download: 280, seconds: 20)
        clock.advance(by: 10)
        feed(tracker, clock, download: 280, seconds: 15)

        #expect(tracker.todayApproachCount == 0)
    }

    @Test func gapOfExactlyTheLimit_keepsTheSustainTimer() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        feed(tracker, clock, download: 280, seconds: 15)
        clock.advance(by: ReportRules.approachMaxGapSeconds - 1) // the feed already moved 1 second on
        feed(tracker, clock, download: 280, seconds: 15)

        #expect(tracker.todayApproachCount == 1)
    }

    @Test func gap_resetsTheRearmTimer() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        feed(tracker, clock, download: 280, seconds: 30)
        feed(tracker, clock, download: 100, seconds: 30)
        clock.advance(by: 10)
        feed(tracker, clock, download: 100, seconds: 29)
        feed(tracker, clock, download: 280, seconds: 30)

        #expect(tracker.todayApproachCount == 1)
    }

    /// The sample after a sleep covers the whole sleep. It only starts a timer.
    @Test func sampleAfterASleep_doesNotCountAsSustained() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        feed(tracker, clock, download: 280, seconds: 5)
        clock.advance(by: 3_600)

        #expect(feed(tracker, clock, download: 280, seconds: 1) == 0)
    }

    @Test func gapWhileLatched_stayLatched() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        feed(tracker, clock, download: 280, seconds: 30)
        clock.advance(by: 3_600)
        feed(tracker, clock, download: 280, seconds: 30)

        #expect(tracker.todayApproachCount == 1)
    }

    @Test func wallClockChange_doesNotAffectTheTimers() {
        let clock = TestClock(2026, 11, 2, 12)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        feed(tracker, clock, download: 280, seconds: 20)
        clock.setWall(clock.now.addingTimeInterval(1_800)) // same day, monotonic time unchanged
        feed(tracker, clock, download: 280, seconds: 8)    // 29 seconds since the first sample
        #expect(tracker.todayApproachCount == 0)

        feed(tracker, clock, download: 280, seconds: 0)
        #expect(tracker.todayApproachCount == 1)
    }

    @Test func longDownloadAcrossMidnight_notDoubleCounted() {
        let clock = TestClock(2026, 11, 1, 23, 50)
        let tracker = makeTracker(clock, MemoryDefaults.make())

        let beforeMidnight = feed(tracker, clock, download: 280, seconds: 599) // ends 23:59:59
        #expect(beforeMidnight == 1)
        #expect(tracker.todayApproachCount == 1)

        let afterMidnight = feed(tracker, clock, download: 280, seconds: 600)  // ends 00:10:00

        #expect(afterMidnight == 0)
        #expect(tracker.todayApproachCount == 0)
        #expect(tracker.approachTimestamps.isEmpty)
    }

    @Test func sameKeysStillLoad() {
        let clock = TestClock(2026, 11, 2, 12)
        let defaults = MemoryDefaults.make()
        let earlier = clock.now.addingTimeInterval(-3_600)
        defaults.set(2, forKey: "todayApproachCount")
        defaults.set([earlier.timeIntervalSince1970], forKey: "approachTimestamps")
        defaults.set(clock.calendar.startOfDay(for: clock.now), forKey: "lastApproachRecordDate")

        let tracker = makeTracker(clock, defaults)

        #expect(tracker.todayApproachCount == 2)
        #expect(tracker.approachTimestamps == [earlier])
    }

    @Test func eventsArePersistedUnderTheSameKeys() {
        let clock = TestClock(2026, 11, 2, 12)
        let defaults = MemoryDefaults.make()
        let tracker = makeTracker(clock, defaults)

        feed(tracker, clock, download: 280, seconds: 30)

        #expect(defaults.integer(forKey: "todayApproachCount") == 1)
        #expect((defaults.array(forKey: "approachTimestamps") as? [Double])?.count == 1)
    }
}
