import Testing
import Foundation
import OSLog
@testable import BandwidthECGFeature

@Suite("PeakRecorder")
struct PeakRecorderTests {

    private let newYork = TimeZone(identifier: "America/New_York")!
    private let peakLogger = Logger(subsystem: "com.bandwidthecg", category: "Peaks")

    private func speed(_ downloadMbps: Double, _ uploadMbps: Double = 0) -> NetworkSpeed {
        NetworkSpeed(uploadSpeed: uploadMbps * 125_000, downloadSpeed: downloadMbps * 125_000)
    }

    private func makeRecorder(_ clock: TestClock, _ defaults: UserDefaults) -> PeakRecorder {
        PeakRecorder(defaults: defaults, clock: clock.appClock)
    }

    private func quarantine(in defaults: UserDefaults) -> [String: Double]? {
        defaults.dictionary(forKey: "peakQuarantine") as? [String: Double]
    }

    private func today(_ recorder: PeakRecorder, _ direction: PeakDirection) -> (peak: Double, time: Date?) {
        switch direction {
        case .download: (recorder.todayPeakDownload, recorder.todayPeakDownloadTime)
        case .upload: (recorder.todayPeakUpload, recorder.todayPeakUploadTime)
        }
    }

    private func allTime(_ recorder: PeakRecorder, _ direction: PeakDirection) -> (peak: Double, time: Date?) {
        switch direction {
        case .download: (recorder.allTimePeakDownload, recorder.allTimePeakDownloadTime)
        case .upload: (recorder.allTimePeakUpload, recorder.allTimePeakUploadTime)
        }
    }

    private func opposite(_ direction: PeakDirection) -> PeakDirection {
        direction == .download ? .upload : .download
    }

    /// The defaults key suffix of a direction, as in `todayPeakDownload`.
    private func keySuffix(_ direction: PeakDirection) -> String {
        direction == .download ? "Download" : "Upload"
    }

    /// What `body` logged to the "Peaks" category, in order. `body` must stay on one thread.
    ///
    /// Reading the log store back needs care, and each step below answers something it does:
    /// - Tests run in parallel, so entries from other threads are left out.
    /// - `position(date:)` can start earlier than the date, so `body` sits between two markers
    ///   and only what is between them counts.
    /// - The store can lag, so this reads until the closing marker shows up. A thread's entries
    ///   are ordered, so everything before that marker is present by then.
    ///
    /// Do not count the result directly. The store has been seen returning every entry twice, as
    /// adjacent pairs, which made `count == 1` fail about once in 50 runs. Compare with a marker
    /// logged inside `body` instead, because it is repeated the same way.
    private func peakLogMessages(during body: () -> Void) throws -> [String] {
        var thread: UInt64 = 0
        pthread_threadid_np(nil, &thread)
        let opening = "log capture opening \(UUID().uuidString)"
        let closing = "log capture closing \(UUID().uuidString)"
        let searchFrom = Date().addingTimeInterval(-1)

        peakLogger.warning("\(opening, privacy: .public)")
        body()
        peakLogger.warning("\(closing, privacy: .public)")

        let peaks = NSPredicate(format: "subsystem == %@ AND category == %@", "com.bandwidthecg", "Peaks")
        let deadline = Date().addingTimeInterval(30)
        repeat {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let messages = try store.getEntries(at: store.position(date: searchFrom), matching: peaks)
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.threadIdentifier == thread }
                .map(\.composedMessage)
            if let open = messages.lastIndex(of: opening), let close = messages[open...].firstIndex(of: closing) {
                return Array(messages[(open + 1)..<close])
            }
        } while Date() < deadline

        Issue.record("The log capture markers never reached the log store")
        return []
    }

    // MARK: - Sanity cap

    @Test func aboveCap_ignored() {
        let clock = TestClock(2026, 10, 31, 12)
        let recorder = makeRecorder(clock, MemoryDefaults.make())
        recorder.recordSpeed(speed(100, 20))

        clock.advance(by: 1)
        recorder.recordSpeed(speed(24_004, 30))

        #expect(recorder.todayPeakDownload == 100)
        #expect(recorder.allTimePeakDownload == 100)
        #expect(recorder.hourlyPeakDownload == 100)
        // The whole sample is dropped, so its plausible upload value is not recorded either.
        #expect(recorder.todayPeakUpload == 20)
        #expect(recorder.allTimePeakUpload == 20)
        #expect(recorder.hourlyPeakUpload == 20)
    }

    @Test func aboveCap_inTheUploadDirection_dropsTheWholeSample() {
        let clock = TestClock(2026, 10, 31, 12)
        let recorder = makeRecorder(clock, MemoryDefaults.make())
        recorder.recordSpeed(speed(100, 20))

        clock.advance(by: 1)
        recorder.recordSpeed(speed(200, 10_000.5))

        #expect(recorder.todayPeakUpload == 20)
        #expect(recorder.allTimePeakUpload == 20)
        #expect(recorder.hourlyPeakUpload == 20)
        #expect(recorder.todayPeakDownload == 100)
        #expect(recorder.allTimePeakDownload == 100)
        #expect(recorder.hourlyPeakDownload == 100)
    }

    @Test(arguments: [PeakDirection.download, .upload])
    func justAboveCap_dropsTheWholeSample(direction: PeakDirection) {
        let clock = TestClock(2026, 10, 31, 12)
        let recorder = makeRecorder(clock, MemoryDefaults.make())
        recorder.recordSpeed(speed(100, 20))

        clock.advance(by: 1)
        recorder.recordSpeed(direction == .download ? speed(10_000.01, 30) : speed(200, 10_000.01))

        #expect(recorder.todayPeakDownload == 100)
        #expect(recorder.allTimePeakDownload == 100)
        #expect(recorder.hourlyPeakDownload == 100)
        #expect(recorder.todayPeakUpload == 20)
        #expect(recorder.allTimePeakUpload == 20)
        #expect(recorder.hourlyPeakUpload == 20)
    }

    @Test func exactlyCap_accepted() {
        let clock = TestClock(2026, 10, 31, 12)
        let recorder = makeRecorder(clock, MemoryDefaults.make())

        recorder.recordSpeed(speed(10_000, 10_000))

        #expect(recorder.todayPeakDownload == 10_000)
        #expect(recorder.allTimePeakDownload == 10_000)
        #expect(recorder.hourlyPeakDownload == 10_000)
        #expect(recorder.allTimePeakUpload == 10_000)
    }

    // MARK: - Clearing one all-time peak

    @Test func clearAllTime_download_keepsUpload() {
        let clock = TestClock(2026, 10, 31, 12)
        let defaults = MemoryDefaults.make()
        let recorder = makeRecorder(clock, defaults)
        recorder.recordSpeed(speed(664, 40))

        recorder.clearAllTimePeak(.download)

        #expect(recorder.allTimePeakDownload == 0)
        #expect(recorder.allTimePeakDownloadTime == nil)
        #expect(recorder.allTimePeakUpload == 40)
        #expect(recorder.allTimePeakUploadTime != nil)
        #expect(defaults.object(forKey: "allTimePeakDownload") == nil)
        #expect(defaults.object(forKey: "allTimePeakDownloadTime") == nil)
        #expect(defaults.double(forKey: "allTimePeakUpload") == 40)

        let relaunched = makeRecorder(clock, defaults)
        #expect(relaunched.allTimePeakDownload == 0)
        #expect(relaunched.allTimePeakUpload == 40)
    }

    @Test func clearAllTime_upload_keepsDownload() {
        let clock = TestClock(2026, 10, 31, 12)
        let defaults = MemoryDefaults.make()
        let recorder = makeRecorder(clock, defaults)
        recorder.recordSpeed(speed(664, 40))

        recorder.clearAllTimePeak(.upload)

        #expect(recorder.allTimePeakUpload == 0)
        #expect(recorder.allTimePeakUploadTime == nil)
        #expect(recorder.allTimePeakDownload == 664)
        #expect(recorder.allTimePeakDownloadTime != nil)
        #expect(defaults.object(forKey: "allTimePeakUpload") == nil)
        #expect(defaults.object(forKey: "allTimePeakUploadTime") == nil)
    }

    /// A polluted all-time peak recorded today is also today's peak.
    @Test(arguments: [PeakDirection.download, .upload])
    func clearAllTime_alsoClearsMatchingToday(direction: PeakDirection) {
        let clock = TestClock(2026, 10, 31, 12)
        let defaults = MemoryDefaults.make()
        let recorder = makeRecorder(clock, defaults)
        recorder.recordSpeed(speed(664, 40))
        let untouched = today(recorder, opposite(direction)).peak

        recorder.clearAllTimePeak(direction)

        #expect(today(recorder, direction).peak == 0)
        #expect(today(recorder, direction).time == nil)
        #expect(defaults.object(forKey: "todayPeak\(keySuffix(direction))") == nil)
        #expect(defaults.object(forKey: "todayPeak\(keySuffix(direction))Time") == nil)
        #expect(today(recorder, opposite(direction)).peak == untouched)
    }

    @Test(arguments: [PeakDirection.download, .upload])
    func clearAllTime_keepsDifferentToday(direction: PeakDirection) {
        let clock = TestClock(2026, 10, 30, 12)
        let defaults = MemoryDefaults.make()
        let recorder = makeRecorder(clock, defaults)
        recorder.recordSpeed(speed(664, 664))

        clock.advance(by: 86_400)
        recorder.recordSpeed(speed(50, 50))

        recorder.clearAllTimePeak(direction)

        #expect(allTime(recorder, direction).peak == 0)
        #expect(allTime(recorder, opposite(direction)).peak == 664)
        #expect(today(recorder, direction).peak == 50)
        #expect(today(recorder, direction).time != nil)
        #expect(defaults.double(forKey: "todayPeak\(keySuffix(direction))") == 50)
    }

    @Test func clearAllTime_nextSampleResets() {
        let clock = TestClock(2026, 10, 31, 12)
        let recorder = makeRecorder(clock, MemoryDefaults.make())
        recorder.recordSpeed(speed(664))
        recorder.clearAllTimePeak(.download)

        clock.advance(by: 1)
        recorder.recordSpeed(speed(80))

        #expect(recorder.allTimePeakDownload == 80)
        #expect(recorder.allTimePeakDownloadTime == clock.now)
    }

    // MARK: - Loading

    @Test func load_pollutedAllTime_cleared() throws {
        let clock = TestClock(2026, 10, 31, 12)
        let defaults = MemoryDefaults.make()
        defaults.set(24_004.0, forKey: "allTimePeakDownload")
        defaults.set(clock.now.addingTimeInterval(-86_400), forKey: "allTimePeakDownloadTime")
        defaults.set(664.0, forKey: "allTimePeakUpload")
        let firstLoadDone = "first load done \(UUID().uuidString)"
        var firstRecorder: PeakRecorder?

        let logged = try peakLogMessages {
            firstRecorder = makeRecorder(clock, defaults)
            peakLogger.warning("\(firstLoadDone, privacy: .public)")
            _ = makeRecorder(clock, defaults) // nothing is left to clear, so this logs nothing more
        }

        let recorder = try #require(firstRecorder)
        #expect(recorder.allTimePeakDownload == 0)
        #expect(recorder.allTimePeakDownloadTime == nil)
        #expect(defaults.object(forKey: "allTimePeakDownload") == nil)
        #expect(defaults.object(forKey: "allTimePeakDownloadTime") == nil)
        #expect(recorder.allTimePeakUpload == 664)
        #expect(quarantine(in: defaults) == ["allTimePeakDownload": 24_004])

        let boundary = try #require(logged.firstIndex(of: firstLoadDone), "\(logged)")
        let firstLoad = logged[..<boundary]
        let secondLoad = logged[boundary...].filter { $0 != firstLoadDone }
        let timesTheStoreReturnsEachEntry = logged.filter { $0 == firstLoadDone }.count

        #expect(Set(firstLoad) == ["Cleared implausible allTimePeakDownload: 24004.000000 Mbps"], "\(logged)")
        #expect(firstLoad.count == timesTheStoreReturnsEachEntry, "\(logged)")
        #expect(secondLoad.isEmpty, "\(logged)")
    }

    @Test(arguments: ["allTimePeakDownload", "allTimePeakUpload", "todayPeakDownload", "todayPeakUpload"])
    func load_exactlyAtTheCap_kept(valueKey: String) {
        let clock = TestClock(2026, 10, 31, 12)
        let defaults = MemoryDefaults.make()
        defaults.set(10_000.0, forKey: valueKey)
        defaults.set(clock.now.addingTimeInterval(-60), forKey: valueKey + "Time")

        _ = makeRecorder(clock, defaults)

        #expect(defaults.double(forKey: valueKey) == 10_000)
        #expect(defaults.object(forKey: "peakQuarantine") == nil)
    }

    @Test(arguments: ["allTimePeakDownload", "allTimePeakUpload", "todayPeakDownload", "todayPeakUpload"])
    func load_justAboveTheCap_cleared(valueKey: String) {
        let clock = TestClock(2026, 10, 31, 12)
        let defaults = MemoryDefaults.make()
        defaults.set(10_000.01, forKey: valueKey)
        defaults.set(clock.now.addingTimeInterval(-60), forKey: valueKey + "Time")

        _ = makeRecorder(clock, defaults)

        #expect(defaults.object(forKey: valueKey) == nil)
        #expect(defaults.object(forKey: valueKey + "Time") == nil)
        #expect(quarantine(in: defaults) == [valueKey: 10_000.01])
    }

    /// The same bad sample also landed in today's peak. Left alone it would keep showing a
    /// today peak above the all-time peak until midnight.
    @Test func load_pollutedToday_cleared() throws {
        let clock = TestClock(2026, 10, 31, 12)
        let defaults = MemoryDefaults.make()
        defaults.set(24_005.0, forKey: "todayPeakDownload")
        defaults.set(clock.now.addingTimeInterval(-60), forKey: "todayPeakDownloadTime")
        defaults.set(clock.calendar.startOfDay(for: clock.now), forKey: "lastRecordDate")
        var firstRecorder: PeakRecorder?

        let logged = try peakLogMessages { firstRecorder = makeRecorder(clock, defaults) }

        let recorder = try #require(firstRecorder)
        #expect(recorder.todayPeakDownload == 0)
        #expect(recorder.todayPeakDownloadTime == nil)
        #expect(defaults.object(forKey: "todayPeakDownload") == nil)
        #expect(defaults.object(forKey: "todayPeakDownloadTime") == nil)
        #expect(quarantine(in: defaults) == ["todayPeakDownload": 24_005])

        #expect(Set(logged) == ["Cleared implausible todayPeakDownload: 24005.000000 Mbps"], "\(logged)")
    }

    @Test(arguments: ["allTimePeakDownload", "allTimePeakUpload", "todayPeakDownload", "todayPeakUpload"])
    func load_polluted_savesTheOriginalValueInQuarantine(valueKey: String) {
        let clock = TestClock(2026, 10, 31, 12)
        let defaults = MemoryDefaults.make()
        defaults.set(31_001.5, forKey: valueKey)
        defaults.set(clock.now.addingTimeInterval(-60), forKey: valueKey + "Time")

        _ = makeRecorder(clock, defaults)

        #expect(defaults.object(forKey: valueKey) == nil)
        #expect(defaults.object(forKey: valueKey + "Time") == nil)
        #expect(quarantine(in: defaults) == [valueKey: 31_001.5])
    }

    /// Old versions most likely left their bad value on a day that has already passed.
    @Test func load_pollutedTodayFromAnEarlierDay_stillQuarantined() {
        let clock = TestClock(2026, 11, 2, 12)
        let defaults = MemoryDefaults.make()
        defaults.set(24_004.0, forKey: "todayPeakUpload")
        defaults.set(TestClock(2026, 3, 3, 9).now, forKey: "todayPeakUploadTime")

        let recorder = makeRecorder(clock, defaults)

        #expect(recorder.todayPeakUpload == 0)
        #expect(defaults.object(forKey: "todayPeakUpload") == nil)
        #expect(quarantine(in: defaults) == ["todayPeakUpload": 24_004])
    }

    @Test func load_quarantine_mergesAndKeepsTheFirstValue() {
        let clock = TestClock(2026, 10, 31, 12)
        let defaults = MemoryDefaults.make()
        defaults.set(["allTimePeakDownload": 24_004.0], forKey: "peakQuarantine")
        defaults.set(30_000.0, forKey: "allTimePeakDownload")
        defaults.set(15_000.0, forKey: "allTimePeakUpload")

        _ = makeRecorder(clock, defaults)

        #expect(quarantine(in: defaults) == [
            "allTimePeakDownload": 24_004,
            "allTimePeakUpload": 15_000,
        ])
    }

    /// A stale today peak is cleared too, but it is a real measurement, so it is not quarantined.
    @Test func load_clean_writesNoQuarantine() {
        let clock = TestClock(2026, 10, 31, 12)
        let defaults = MemoryDefaults.make()
        defaults.set(10_000.0, forKey: "allTimePeakDownload")
        defaults.set(664.0, forKey: "allTimePeakUpload")
        defaults.set(120.0, forKey: "todayPeakDownload")
        defaults.set(clock.now.addingTimeInterval(-60), forKey: "todayPeakDownloadTime")
        defaults.set(33.0, forKey: "todayPeakUpload")
        defaults.set(TestClock(2026, 3, 3, 9).now, forKey: "todayPeakUploadTime")

        _ = makeRecorder(clock, defaults)

        #expect(defaults.object(forKey: "todayPeakUpload") == nil)
        #expect(defaults.object(forKey: "peakQuarantine") == nil)
    }

    /// CORE-06: a launch on the new day that records nothing used to leave yesterday's keys in
    /// place while moving `lastRecordDate` forward, so the next launch read them as today's.
    @Test func staleToday_afterEmptySession() {
        let clock = TestClock(2026, 10, 30, 12)
        let defaults = MemoryDefaults.make()
        makeRecorder(clock, defaults).recordSpeed(speed(280, 30))

        clock.advance(by: 86_400)
        _ = makeRecorder(clock, defaults) // launched on day 2, no samples

        let relaunched = makeRecorder(clock, defaults)
        #expect(relaunched.todayPeakDownload == 0)
        #expect(relaunched.todayPeakDownloadTime == nil)
        #expect(relaunched.todayPeakUpload == 0)
        #expect(relaunched.todayPeakUploadTime == nil)
        #expect(relaunched.allTimePeakDownload == 280)
    }

    /// Field data: `todayPeakUpload` was dated 2026-03-03 while `lastRecordDate` was today.
    @Test func staleToday_perDirection() {
        let clock = TestClock(2026, 11, 2, 12)
        let defaults = MemoryDefaults.make()
        let downloadTime = clock.now.addingTimeInterval(-3600)
        defaults.set(clock.calendar.startOfDay(for: clock.now), forKey: "lastRecordDate")
        defaults.set(120.0, forKey: "todayPeakDownload")
        defaults.set(downloadTime, forKey: "todayPeakDownloadTime")
        defaults.set(33.0, forKey: "todayPeakUpload")
        defaults.set(TestClock(2026, 3, 3, 9).now, forKey: "todayPeakUploadTime")

        let recorder = makeRecorder(clock, defaults)

        #expect(recorder.todayPeakDownload == 120)
        #expect(recorder.todayPeakDownloadTime == downloadTime)
        #expect(recorder.todayPeakUpload == 0)
        #expect(recorder.todayPeakUploadTime == nil)
        #expect(defaults.double(forKey: "todayPeakDownload") == 120)
        #expect(defaults.object(forKey: "todayPeakUpload") == nil)
        #expect(defaults.object(forKey: "todayPeakUploadTime") == nil)
    }

    /// The peak's own time decides, so an old `lastRecordDate` cannot wipe a peak from today.
    @Test func todayPeak_survivesAnOldLastRecordDate() {
        let clock = TestClock(2026, 11, 2, 12)
        let defaults = MemoryDefaults.make()
        defaults.set(TestClock(2026, 11, 1, 12).now, forKey: "lastRecordDate")
        defaults.set(120.0, forKey: "todayPeakDownload")
        defaults.set(clock.now.addingTimeInterval(-3600), forKey: "todayPeakDownloadTime")

        let recorder = makeRecorder(clock, defaults)
        #expect(recorder.todayPeakDownload == 120)

        clock.advance(by: 1)
        recorder.recordSpeed(speed(50))
        #expect(recorder.todayPeakDownload == 120)
    }

    // MARK: - Crossing midnight

    @Test func newDay_removesTodayKeys() {
        let clock = TestClock(2026, 10, 30, 12)
        let defaults = MemoryDefaults.make()
        let recorder = makeRecorder(clock, defaults)
        recorder.recordSpeed(speed(280, 30))

        clock.advance(by: 86_400)
        recorder.recordSpeed(speed(0, 0))

        #expect(recorder.todayPeakDownload == 0)
        #expect(recorder.todayPeakUpload == 0)
        #expect(defaults.object(forKey: "todayPeakDownload") == nil)
        #expect(defaults.object(forKey: "todayPeakDownloadTime") == nil)
        #expect(defaults.object(forKey: "todayPeakUpload") == nil)
        #expect(defaults.object(forKey: "todayPeakUploadTime") == nil)
    }

    /// 2026-03-08 has 23 hours in New York, so a fixed 24 hour day would end an hour late.
    @Test func dst_springForward_day() {
        let clock = TestClock(2026, 3, 7, 23, 59, timeZone: newYork)
        let recorder = makeRecorder(clock, MemoryDefaults.make())
        recorder.recordSpeed(speed(100))

        clock.advance(by: 120) // 03-08 00:01
        recorder.recordSpeed(speed(50))
        #expect(recorder.todayPeakDownload == 50)

        clock.advance(by: 22.5 * 3600) // 03-08 23:31, the clocks skipped 02:00 to 03:00
        recorder.recordSpeed(speed(40))
        #expect(recorder.todayPeakDownload == 50)

        clock.advance(by: 3600) // 03-09 00:31, 23.5 hours after 03-08 began
        recorder.recordSpeed(speed(30))
        #expect(recorder.todayPeakDownload == 30)
        #expect(recorder.allTimePeakDownload == 100)
    }
}
