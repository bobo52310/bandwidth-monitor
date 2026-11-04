import Testing
import Foundation
@testable import BandwidthECGFeature

/// The fakes are shared by every later stage, so their own behaviour is pinned down here.
@Suite("Test support")
struct TestSupportTests {

    @Test func memoryDefaults_bridgeValuesLikeARealStore() {
        let defaults = MemoryDefaults.make()
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        defaults.set(date, forKey: "date")
        defaults.set([1.5, 2.5], forKey: "doubles")
        defaults.set(Data([1, 2, 3]), forKey: "data")
        defaults.set(true, forKey: "flag")
        defaults.set(42, forKey: "count")
        defaults.set(0.25, forKey: "ratio")
        defaults.set("text", forKey: "text")

        #expect(defaults.object(forKey: "date") as? Date == date)
        #expect(defaults.array(forKey: "doubles") as? [Double] == [1.5, 2.5])
        #expect(defaults.data(forKey: "data") == Data([1, 2, 3]))
        #expect(defaults.bool(forKey: "flag"))
        #expect(defaults.integer(forKey: "count") == 42)
        #expect(defaults.double(forKey: "ratio") == 0.25)
        #expect(defaults.string(forKey: "text") == "text")
        #expect(defaults.object(forKey: "missing") == nil)

        defaults.removeObject(forKey: "flag")
        #expect(defaults.object(forKey: "flag") == nil)
    }

    @Test func memoryDefaults_instancesAreIndependent() {
        let first = MemoryDefaults.make()
        let second = MemoryDefaults.make()

        first.set(1, forKey: "shared-key")

        #expect(second.object(forKey: "shared-key") == nil)
    }

    @Test func testClock_advanceMovesWallAndMonotonicTogether() {
        let clock = TestClock(2026, 10, 31, 12)
        let appClock = clock.appClock
        let start = appClock.now()

        clock.advance(by: 90)

        #expect(appClock.now().timeIntervalSince(start) == 90)
        #expect(appClock.monotonic() == 90)
    }

    @Test func testClock_setWallLeavesMonotonicAlone() {
        let clock = TestClock(2026, 10, 31, 12)
        let appClock = clock.appClock
        clock.advance(by: 10)

        clock.setWall(clock.now.addingTimeInterval(-86_400)) // the user sets the date back a day

        #expect(appClock.monotonic() == 10)
        #expect(DayKey.day(for: appClock.now(), calendar: appClock.calendar) == "2026-10-30")
    }

    @Test func testClock_usesTheRequestedTimeZone() {
        let clock = TestClock(2026, 10, 31, 23, 59)
        #expect(DayKey.day(for: clock.now, calendar: clock.calendar) == "2026-10-31")
        clock.advance(by: 120)
        #expect(DayKey.day(for: clock.now, calendar: clock.calendar) == "2026-11-01")
    }

    @Test func blobStoreFake_followsTheProtocolContract() throws {
        let store = InMemoryBlobStore()
        #expect(try store.read("a.json") == nil)

        try store.write(Data("one".utf8), named: "a.json")
        #expect(try store.read("a.json") == Data("one".utf8))
        #expect(store.writeCount == 1)

        store.failNextWrite = true
        #expect(throws: (any Error).self) { try store.write(Data("two".utf8), named: "a.json") }
        #expect(try store.read("a.json") == Data("one".utf8)) // failed write changed nothing
        #expect(store.writeCount == 1)
        try store.write(Data("two".utf8), named: "a.json")    // only the next write fails
        #expect(store.writeCount == 2)

        try store.quarantine("a.json")
        #expect(try store.read("a.json") == nil)
        #expect(store.quarantined == ["a.json"])
        #expect(store.fileNames.count == 1)
        #expect(store.fileNames.first?.hasPrefix("a.json.corrupt-") == true)
    }

    @Test func counterSourceFake_replaysThenRepeatsTheLastEntry() {
        let source = FakeCounterSource([
            ["en0": InterfaceCounters(rx: 1, tx: 1)],
            nil,
            ["en0": InterfaceCounters(rx: 3, tx: 3)],
        ])

        #expect(source.read()?["en0"]?.rx == 1)
        #expect(source.read() == nil)
        #expect(source.read()?["en0"]?.rx == 3)
        #expect(source.read()?["en0"]?.rx == 3)
        #expect(source.readCount == 4)
    }

    @Test func interfaceCounters_truncateToThirtyTwoBits() {
        let counters = InterfaceCounters(truncatingRx: UInt64(UInt32.max) + 5, truncatingTx: 7)
        #expect(counters.rx == 4)
        #expect(counters.tx == 7)
    }

    @Test func systemCounterSource_readsWithoutFailing() {
        // The live implementation talks to getifaddrs; it must return a dictionary, not nil, on a normal machine.
        let counters = SystemCounterSource().read()
        #expect(counters != nil)
        for name in (counters ?? [:]).keys {
            #expect(name.hasPrefix("en") || name.hasPrefix("wi"))
        }
    }
}
