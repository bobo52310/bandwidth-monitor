import Testing
import Foundation
@testable import BandwidthECGFeature

/// The CSV files: the numbers in the unit the user reads, a Gregorian timestamp whatever the
/// system calendar, headers from `L10n`, and a write that reports its failure (CORE-11, CORE-29).
@MainActor
@Suite("Data export")
struct DataExportTests {
    private static let bytesPerMbps = 125_000.0

    private func speed(_ downloadMbps: Double, _ uploadMbps: Double = 0) -> NetworkSpeed {
        NetworkSpeed(
            uploadSpeed: uploadMbps * Self.bytesPerMbps,
            downloadSpeed: downloadMbps * Self.bytesPerMbps
        )
    }

    private func makeHistory(_ clock: TestClock) -> NetworkHistoryRecorder {
        NetworkHistoryRecorder(defaults: MemoryDefaults.make(), clock: clock.appClock, store: InMemoryBlobStore())
    }

    private func makePeaks(_ clock: TestClock) -> PeakRecorder {
        PeakRecorder(defaults: MemoryDefaults.make(), clock: clock.appClock)
    }

    /// `count` closed 10-second points of constant speed, plus one window left open.
    private func feedPoints(
        _ history: NetworkHistoryRecorder, _ clock: TestClock,
        count: Int, download: Double, upload: Double = 0
    ) {
        for _ in 0...count {
            history.recordSpeed(speed(download, upload))
            clock.advance(by: 10)
        }
    }

    private func recent24h(
        _ history: NetworkHistoryRecorder,
        _ clock: TestClock,
        unit: UserPreferences.SpeedUnit = .mbps,
        appClock: AppClock? = nil
    ) -> [[String]] {
        let csv = DataExportService.csv(
            .recent24Hours,
            history: history,
            peaks: makePeaks(clock),
            unit: unit,
            clock: appClock ?? clock.appClock
        )
        return csv.split(separator: "\n", omittingEmptySubsequences: true).map {
            $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        }
    }

    // MARK: - Recent 24 hours

    /// The history is kept in bytes per second. The old export wrote that number under a Mbps
    /// heading, five orders of magnitude too large.
    @Test func recent24h_mbps() {
        let clock = TestClock(2026, 11, 2, 9)
        let history = makeHistory(clock)
        feedPoints(history, clock, count: 2, download: 100, upload: 20)

        let rows = recent24h(history, clock)

        #expect(rows.count == 3) // header and two points
        #expect(rows[1][1] == "100.00")
        #expect(rows[1][3] == "20.00")
        #expect(!rows.flatMap { $0 }.contains("12500000.00"))
    }

    @Test func recent24h_mbytes() {
        let clock = TestClock(2026, 11, 2, 9)
        let history = makeHistory(clock)
        feedPoints(history, clock, count: 1, download: 100, upload: 16)

        let rows = recent24h(history, clock, unit: .mbps_lower)

        #expect(rows[1][1] == "12.50")
        #expect(rows[1][3] == "2.00")
    }

    /// Columns: time, average and peak download, average and peak upload. A window of 10, 20
    /// and 60 Mbps averages 30 and peaks at 60.
    @Test func recent24h_includesPeakColumns() {
        let clock = TestClock(2026, 11, 2, 9)
        let history = makeHistory(clock)
        for (download, upload) in [(10.0, 1.0), (20.0, 2.0), (60.0, 3.0)] {
            history.recordSpeed(speed(download, upload))
            clock.advance(by: 1)
        }
        clock.advance(by: 7)
        history.recordSpeed(speed(0)) // 10 seconds after the window opened: closes it
        clock.advance(by: 1)

        let rows = recent24h(history, clock)

        #expect(rows.count == 2)
        #expect(rows[0].count == 5)
        #expect(rows[1].count == 5)
        #expect(rows[1][0] == "2026-11-02 09:00:00")
        #expect(rows[1][1] == "30.00") // average download
        #expect(rows[1][2] == "60.00") // peak download
        #expect(rows[1][3] == "2.00")  // average upload
        #expect(rows[1][4] == "3.00")  // peak upload
    }

    @Test func recent24h_leavesOutPointsOlderThan24Hours() {
        let clock = TestClock(2026, 11, 2, 9)
        let history = makeHistory(clock)
        feedPoints(history, clock, count: 1, download: 50)
        clock.advance(by: 25 * 3600)

        let rows = recent24h(history, clock)

        #expect(rows.count == 1) // the header alone
    }

    @Test func headers_useL10n() {
        let clock = TestClock(2026, 11, 2, 9)
        let history = makeHistory(clock)
        let peaks = makePeaks(clock)
        peaks.recordSpeed(speed(100, 10))

        for unit in UserPreferences.SpeedUnit.allCases {
            let name = unit.displayName
            let recent = DataExportService.csv(.recent24Hours, history: history, peaks: peaks, unit: unit, clock: clock.appClock)
            #expect(recent.components(separatedBy: "\n")[0] == [
                L10n.exportColumnTime,
                L10n.exportColumnAvgDownload(name),
                L10n.exportColumnMaxDownload(name),
                L10n.exportColumnAvgUpload(name),
                L10n.exportColumnMaxUpload(name),
            ].joined(separator: ","))

            let peak = DataExportService.csv(.peakHistory, history: history, peaks: peaks, unit: unit, clock: clock.appClock)
            let lines = peak.components(separatedBy: "\n")
            #expect(lines[0] == [
                L10n.exportColumnType,
                L10n.exportColumnPeakSpeed(name),
                L10n.exportColumnPeakTime,
            ].joined(separator: ","))
            #expect(lines[1].hasPrefix(L10n.exportRowTodayDownload + ","))
        }
    }

    // MARK: - Peak history

    @Test func peakHistory_unchanged() {
        let clock = TestClock(2026, 11, 2, 9)
        let peaks = makePeaks(clock)
        peaks.recordSpeed(speed(100, 20))

        func lines(_ unit: UserPreferences.SpeedUnit) -> [String] {
            DataExportService.csv(
                .peakHistory, history: makeHistory(clock), peaks: peaks, unit: unit, clock: clock.appClock
            ).split(separator: "\n").map(String.init)
        }

        let mbps = lines(.mbps)
        #expect(mbps.count == 7) // header, then today, all-time and last-hour peaks per direction
        #expect(mbps[1] == "\(L10n.exportRowTodayDownload),100.00,2026-11-02 09:00:00")
        #expect(mbps[2] == "\(L10n.exportRowTodayUpload),20.00,2026-11-02 09:00:00")
        #expect(mbps[3] == "\(L10n.exportRowAllTimeDownload),100.00,2026-11-02 09:00:00")
        #expect(mbps[4] == "\(L10n.exportRowAllTimeUpload),20.00,2026-11-02 09:00:00")
        #expect(mbps[5] == "\(L10n.exportRowHourDownload),100.00,2026-11-02 09:00:00")
        #expect(mbps[6] == "\(L10n.exportRowHourUpload),20.00,2026-11-02 09:00:00")

        let mbytes = lines(.mbps_lower)
        #expect(mbytes[1] == "\(L10n.exportRowTodayDownload),12.50,2026-11-02 09:00:00")
        #expect(mbytes[2] == "\(L10n.exportRowTodayUpload),2.50,2026-11-02 09:00:00")
    }

    @Test func peakHistory_withNoPeaks_hasOnlyTheHeader() {
        let clock = TestClock(2026, 11, 2, 9)

        let csv = DataExportService.csv(
            .peakHistory, history: makeHistory(clock), peaks: makePeaks(clock), unit: .mbps, clock: clock.appClock
        )

        #expect(csv.split(separator: "\n").count == 1)
    }

    // MARK: - Calendars

    /// Under a Minguo or Buddhist system calendar a plain `DateFormatter` writes 115 or 2569.
    @Test func timestamp_rocCalendar() {
        let clock = TestClock(2026, 11, 2, 15, 30)
        let history = makeHistory(clock)
        feedPoints(history, clock, count: 1, download: 10)
        var minguo = Calendar(identifier: .republicOfChina)
        minguo.timeZone = clock.calendar.timeZone
        let minguoClock = AppClock(now: { clock.now }, monotonic: { clock.monotonic }, calendar: minguo)

        let rows = recent24h(history, clock, appClock: minguoClock)

        #expect(rows[1][0] == "2026-11-02 15:30:00")
        // The test means something only if the calendar would have changed the year.
        let plain = DateFormatter()
        plain.calendar = minguo
        plain.timeZone = minguo.timeZone
        plain.dateFormat = "yyyy"
        #expect(plain.string(from: clock.now) == "0115")
    }

    @Test func timestamp_buddhistCalendar() {
        let clock = TestClock(2026, 11, 2, 15, 30)
        let history = makeHistory(clock)
        feedPoints(history, clock, count: 1, download: 10)
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = clock.calendar.timeZone
        let buddhistClock = AppClock(now: { clock.now }, monotonic: { clock.monotonic }, calendar: buddhist)

        let rows = recent24h(history, clock, appClock: buddhistClock)

        #expect(rows[1][0] == "2026-11-02 15:30:00")
        let plain = DateFormatter()
        plain.calendar = buddhist
        plain.timeZone = buddhist.timeZone
        plain.dateFormat = "yyyy"
        #expect(plain.string(from: clock.now) == "2569")
    }

    @Test func timestampFormatter_isPOSIXGregorianAnd24Hour() {
        let clock = TestClock(2026, 11, 2, 15, 30, 5)

        let formatter = DataExportService.makeTimestampFormatter(timeZone: clock.calendar.timeZone)

        #expect(formatter.locale.identifier == "en_US_POSIX")
        #expect(formatter.calendar.identifier == .gregorian)
        #expect(formatter.string(from: clock.now) == "2026-11-02 15:30:05")
    }

    @Test func timestamp_followsTheClocksTimeZone() {
        let clock = TestClock(2026, 11, 2, 15, 30, timeZone: TimeZone(identifier: "Asia/Taipei")!)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!

        let formatter = DataExportService.makeTimestampFormatter(timeZone: tokyo)

        #expect(formatter.string(from: clock.now) == "2026-11-02 16:30:00")
    }

    @Test func filename_isGregorianWhateverTheCalendar() {
        let clock = TestClock(2026, 11, 2, 9, 5)
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = clock.calendar.timeZone
        let buddhistClock = AppClock(now: { clock.now }, monotonic: { clock.monotonic }, calendar: buddhist)

        #expect(DataExportService.filename(for: .recent24Hours, clock: buddhistClock) == "network_recent24h_2026-11-02_0905.csv")
        #expect(DataExportService.filename(for: .peakHistory, clock: buddhistClock) == "network_peaks_2026-11-02_0905.csv")
    }

    // MARK: - Writing

    @Test func write_savesTheContent() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("out.csv")

        try DataExportService.write("a,b\n1,2\n", to: url)

        #expect(try String(contentsOf: url, encoding: .utf8) == "a,b\n1,2\n")
    }

    @Test func write_failure_throws() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("no-such-folder").appendingPathComponent("out.csv")

        #expect(throws: (any Error).self) {
            try DataExportService.write("a,b\n", to: missing)
        }
    }

    /// A sandboxed app may write the file the user chose in the save panel without being allowed
    /// to create the temporary file an atomic write puts next to it. A folder that cannot take
    /// new files, holding a file that can be written, is the same situation.
    @Test func write_toAnExistingFileInAFolderThatTakesNoNewFiles_stillWrites() throws {
        let directory = try Self.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("chosen.csv")
        try Data().write(to: url) // the save panel has created the empty file
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }

        try DataExportService.write("a,b\n1,2\n", to: url)

        #expect(try String(contentsOf: url, encoding: .utf8) == "a,b\n1,2\n")
    }

    static func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bandwidth-ecg-export-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
