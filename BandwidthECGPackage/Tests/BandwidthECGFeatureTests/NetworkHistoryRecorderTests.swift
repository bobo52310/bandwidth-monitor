import Testing
import Foundation
@testable import BandwidthECGFeature

/// The 24-hour history file (CORE-18, CORE-19, PERF-08): what survives a relaunch, how often it
/// is written, the move out of `UserDefaults`, and what happens to a file that cannot be read.
@MainActor
@Suite("History persistence")
struct NetworkHistoryRecorderTests {

    private static let bytesPerMbps = 125_000.0
    private static let oneHourKey = "networkHistory_oneHour"
    private static let legacyKeys = [
        "networkHistory_oneHour",
        "networkHistory_twentyFourHour",
        "networkHistory_lastRecordTime",
    ]

    private var fileName: String { NetworkHistoryRecorder.fileName }

    private func speed(_ downloadMbps: Double, _ uploadMbps: Double = 0) -> NetworkSpeed {
        NetworkSpeed(uploadSpeed: uploadMbps * Self.bytesPerMbps, downloadSpeed: downloadMbps * Self.bytesPerMbps)
    }

    private func makeRecorder(
        _ clock: TestClock,
        _ blobs: InMemoryBlobStore,
        defaults: UserDefaults = MemoryDefaults.make()
    ) -> NetworkHistoryRecorder {
        NetworkHistoryRecorder(defaults: defaults, clock: clock.appClock, store: blobs)
    }

    /// One sample per second; the clock advances after each, so the last one is `seconds - 1`
    /// seconds after the first.
    private func feed(_ recorder: NetworkHistoryRecorder, _ clock: TestClock, mbps: Double, seconds: Int) {
        for _ in 0..<seconds {
            recorder.recordSpeed(speed(mbps))
            clock.advance(by: 1)
        }
    }

    /// One sample every 10 seconds, so each sample closes the window the one before opened:
    /// `count + 1` samples make `count` points and leave one window open.
    private func feedPoints(_ recorder: NetworkHistoryRecorder, _ clock: TestClock, count: Int, mbps: Double) {
        for _ in 0...count {
            recorder.recordSpeed(speed(mbps))
            clock.advance(by: 10)
        }
    }

    private func legacyJSON(_ points: [NetworkDataPoint]) throws -> Data {
        try JSONEncoder().encode(points)
    }

    private func fileJSON(_ blobs: InMemoryBlobStore) throws -> [String: Any] {
        let data = try #require(blobs.contents(of: fileName))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Retention

    @Test func retention_24hAfterRelaunch() {
        // CORE-18: six hours of points, then a relaunch. The old load kept only the last hour (360).
        let clock = TestClock(2026, 11, 3, 3)
        let blobs = InMemoryBlobStore()
        let defaults = MemoryDefaults.make()
        let recorder = makeRecorder(clock, blobs, defaults: defaults)
        feedPoints(recorder, clock, count: 2160, mbps: 40)
        #expect(recorder.oneHourData.count == 2160)

        recorder.flush()
        let relaunched = makeRecorder(clock, blobs, defaults: defaults)

        #expect(relaunched.oneHourData.count == 2160)
        #expect(relaunched.oneHourData.map(\.timestamp) == recorder.oneHourData.map(\.timestamp))
        #expect(relaunched.oneHourData.allSatisfy { $0.downloadMbps == 40 && $0.maxDownloadMbps == 40 })
    }

    @Test func olderThan24h_dropped() {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let defaults = MemoryDefaults.make()
        let recorder = makeRecorder(clock, blobs, defaults: defaults)
        feedPoints(recorder, clock, count: 3, mbps: 10)
        clock.advance(by: 2 * 3600)
        feedPoints(recorder, clock, count: 3, mbps: 20) // its first sample closes the last 10 Mbps window
        recorder.flush()
        #expect(recorder.oneHourData.count == 7)

        clock.advance(by: 23 * 3600) // the 10 Mbps points are now 25 hours old, the 20 Mbps ones 23
        let relaunched = makeRecorder(clock, blobs, defaults: defaults)

        #expect(relaunched.oneHourData.count == 3)
        #expect(relaunched.oneHourData.allSatisfy { $0.downloadMbps == 20 })
    }

    @Test func olderThan24h_droppedWhileRunning() {
        let clock = TestClock(2026, 11, 3, 9)
        let recorder = makeRecorder(clock, InMemoryBlobStore())
        let start = clock.now
        feedPoints(recorder, clock, count: 1, mbps: 10) // a point at 0 s and a window open from 10 s
        clock.advance(by: 24 * 3600 - 20 + 5)           // 24 h 5 s after the first point

        recorder.recordSpeed(speed(20)) // closes the window from 10 s, now 23 h 59 min 55 s old

        #expect(recorder.oneHourData.map(\.timestamp) == [start.addingTimeInterval(10)])
    }

    @Test func maxPoints_capped() throws {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let defaults = MemoryDefaults.make()
        // 9000 points inside the last 24 hours, 9 seconds apart.
        let seed = (0..<9000).map { index in
            NetworkDataPoint(
                timestamp: clock.now.addingTimeInterval(-9 * Double(8999 - index)),
                downloadSpeed: Double(index),
                uploadSpeed: 0
            )
        }
        defaults.set(try legacyJSON(seed), forKey: Self.oneHourKey)

        let recorder = makeRecorder(clock, blobs, defaults: defaults)

        #expect(recorder.oneHourData.count == 8640)
        #expect(recorder.oneHourData.first?.downloadSpeed == 360) // the oldest 360 were dropped
        #expect(recorder.oneHourData.last?.downloadSpeed == 8999)
        let relaunched = makeRecorder(clock, blobs)
        #expect(relaunched.oneHourData.count == 8640)
    }

    // MARK: - When it writes

    @Test func writes_atMostEvery600s() {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let recorder = makeRecorder(clock, blobs)

        feed(recorder, clock, mbps: 10, seconds: 6000)

        #expect(blobs.writeCount <= 10)
        #expect(blobs.writeCount >= 9)
    }

    /// Literal seconds on purpose: this pins the interval, not just the comparison.
    @Test func automaticWrite_noWriteAt599Seconds_writesAt600() {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let recorder = makeRecorder(clock, blobs)

        feed(recorder, clock, mbps: 10, seconds: 600) // the last sample is 599 s after the start
        #expect(blobs.writeCount == 0)

        recorder.recordSpeed(speed(10)) // 600 s
        #expect(blobs.writeCount == 1)
    }

    /// PERF-08: the old recorder rewrote the whole history into the preferences plist every 10 s.
    @Test func samples_neverWriteUserDefaults() {
        let clock = TestClock(2026, 11, 3, 9)
        let defaults = MemoryDefaults.make()
        let recorder = makeRecorder(clock, InMemoryBlobStore(), defaults: defaults)

        feed(recorder, clock, mbps: 10, seconds: 700)
        recorder.flush()

        for key in Self.legacyKeys {
            #expect(defaults.object(forKey: key) == nil)
        }
    }

    @Test func flush_writesPending() {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let recorder = makeRecorder(clock, blobs)
        recorder.flush()
        #expect(blobs.writeCount == 0) // nothing recorded yet

        feedPoints(recorder, clock, count: 2, mbps: 10)
        recorder.flush()
        #expect(blobs.writeCount == 1)

        recorder.flush()
        #expect(blobs.writeCount == 1) // nothing new since
    }

    /// A sample that does not close a window changes nothing on disk, so it does not make a flush write.
    @Test func flush_afterSamplesInsideOneWindow_writesNothing() {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let recorder = makeRecorder(clock, blobs)

        feed(recorder, clock, mbps: 10, seconds: 9)
        recorder.flush()

        #expect(blobs.writeCount == 0)
    }

    // MARK: - Format

    @Test func file_hasTheVersionedFormat() throws {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let recorder = makeRecorder(clock, blobs)
        feedPoints(recorder, clock, count: 1, mbps: 8)
        recorder.flush()

        let json = try fileJSON(blobs)
        #expect(json["schemaVersion"] as? Int == 1)
        let points = try #require(json["points"] as? [[String: Any]])
        #expect(points.count == 1)
        #expect(Set(points[0].keys) == ["t", "d", "u", "dm", "um"])
        #expect(points[0]["d"] as? Double == 1_000_000)
        #expect(points[0]["t"] as? Double == clock.now.addingTimeInterval(-20).timeIntervalSinceReferenceDate)
    }

    @Test func roundTrip_withinRounding() {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let recorder = makeRecorder(clock, blobs)
        for index in 0..<30 {
            recorder.recordSpeed(NetworkSpeed(
                uploadSpeed: 12_345.678_9 + Double(index) * 0.37,
                downloadSpeed: 98_765_432.123_456 + Double(index) * 1.91
            ))
            clock.advance(by: 1.000_123_456)
        }
        recorder.flush()

        let relaunched = makeRecorder(clock, blobs)

        #expect(relaunched.oneHourData.count == recorder.oneHourData.count)
        for (saved, live) in zip(relaunched.oneHourData, recorder.oneHourData) {
            #expect(abs(saved.timestamp.timeIntervalSince(live.timestamp)) <= 0.0005)
            #expect(abs(saved.downloadSpeed - live.downloadSpeed) <= 0.5)
            #expect(abs(saved.uploadSpeed - live.uploadSpeed) <= 0.5)
            #expect(abs(saved.maxDownloadSpeed - live.maxDownloadSpeed) <= 0.5)
            #expect(abs(saved.maxUploadSpeed - live.maxUploadSpeed) <= 0.5)
        }
    }

    /// Worst case: full-precision averages near the 10 Gbps cap and fractional timestamps.
    /// The Stage 5 `NetworkDataPoint` encoding of the same points is about 1.5 MB.
    @Test func encodedSize_8640_under1MB() throws {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let defaults = MemoryDefaults.make()
        let cap = SampleGuard.maxPlausibleBytesPerSecond
        let start = clock.now.addingTimeInterval(-86_390.876_543_21)
        let seed = (0..<8640).map { index in
            let offset = Double(index)
            return NetworkDataPoint(
                timestamp: start.addingTimeInterval(offset * 10.000_123_7),
                downloadSpeed: cap - 0.123_456_789 - offset * 1.37,
                uploadSpeed: cap * 0.79 + 0.987_654_321 + offset * 0.71,
                maxDownloadSpeed: cap - 0.000_123_4,
                maxUploadSpeed: cap * 0.89 + 0.111_111_1
            )
        }
        defaults.set(try legacyJSON(seed), forKey: Self.oneHourKey)

        let recorder = makeRecorder(clock, blobs, defaults: defaults)
        #expect(recorder.oneHourData.count == 8640)

        let data = try #require(blobs.contents(of: fileName))
        #expect(data.count < 1_000_000)
    }

    // MARK: - Moving out of UserDefaults

    @Test func migration_fromDefaults() throws {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let defaults = MemoryDefaults.make()
        // The format before Stage 5, with ids. Two hours old, which the old load threw away.
        let first = clock.now.addingTimeInterval(-7200).timeIntervalSinceReferenceDate
        let json = """
            [{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","timestamp":\(first),"downloadSpeed":1250000,"uploadSpeed":250000},\
            {"id":"F621E1F8-C36C-495A-93FC-0C247A3E6E5F","timestamp":\(first + 10),"downloadSpeed":2500000,"uploadSpeed":500000}]
            """
        defaults.set(Data(json.utf8), forKey: Self.oneHourKey)
        defaults.set(Data("[]".utf8), forKey: "networkHistory_twentyFourHour")
        defaults.set(clock.now.addingTimeInterval(-60), forKey: "networkHistory_lastRecordTime")

        let recorder = makeRecorder(clock, blobs, defaults: defaults)

        #expect(recorder.oneHourData.map(\.downloadMbps) == [10, 20])
        #expect(blobs.writeCount == 1)
        for key in Self.legacyKeys {
            #expect(defaults.object(forKey: key) == nil)
        }
        let fromFileAlone = makeRecorder(clock, blobs)
        #expect(fromFileAlone.oneHourData.map(\.downloadMbps) == [10, 20])
        #expect(fromFileAlone.oneHourData.map(\.maxUploadMbps) == [2, 4])
    }

    /// The old keys are the only copy until the file is written, so they stay until it is.
    @Test func migration_writeFailure_keepsTheOldKeysUntilWritten() throws {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let defaults = MemoryDefaults.make()
        let seed = [NetworkDataPoint(timestamp: clock.now.addingTimeInterval(-60), downloadSpeed: 1_000_000, uploadSpeed: 0)]
        defaults.set(try legacyJSON(seed), forKey: Self.oneHourKey)
        blobs.failNextWrite = true

        let recorder = makeRecorder(clock, blobs, defaults: defaults)
        #expect(recorder.oneHourData.count == 1)
        #expect(blobs.writeCount == 0)
        #expect(defaults.data(forKey: Self.oneHourKey) != nil)

        recorder.flush()

        #expect(blobs.writeCount == 1)
        #expect(defaults.object(forKey: Self.oneHourKey) == nil)
    }

    @Test func migration_badBlob_preservedAndCleared() {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let defaults = MemoryDefaults.make()
        let bad = Data(#"[{"timestamp":783820800,"downloadSp"#.utf8)
        defaults.set(bad, forKey: Self.oneHourKey)
        defaults.set(Data("[]".utf8), forKey: "networkHistory_twentyFourHour")

        let recorder = makeRecorder(clock, blobs, defaults: defaults)

        #expect(recorder.oneHourData.isEmpty)
        #expect(blobs.contents(of: NetworkHistoryRecorder.legacyBackupFileName) == bad)
        for key in Self.legacyKeys {
            #expect(defaults.object(forKey: key) == nil)
        }

        // The next launch finds nothing to back up, so the backup and its log line happen once.
        let writes = blobs.writeCount
        _ = makeRecorder(clock, blobs, defaults: defaults)
        #expect(blobs.writeCount == writes)
        #expect(blobs.contents(of: NetworkHistoryRecorder.legacyBackupFileName) == bad)
    }

    /// Old keys next to a file can only come from an older version run afterwards. The file wins.
    @Test func fileAndOldKeys_fileWins() throws {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let writer = makeRecorder(clock, blobs)
        feedPoints(writer, clock, count: 2, mbps: 10)
        writer.flush()
        let defaults = MemoryDefaults.make()
        let stale = [NetworkDataPoint(timestamp: clock.now.addingTimeInterval(-5), downloadSpeed: 99_000_000, uploadSpeed: 0)]
        defaults.set(try legacyJSON(stale), forKey: Self.oneHourKey)
        defaults.set(Data("[]".utf8), forKey: "networkHistory_twentyFourHour")

        let recorder = makeRecorder(clock, blobs, defaults: defaults)

        #expect(recorder.oneHourData.map(\.downloadMbps) == [10, 10])
        for key in Self.legacyKeys {
            #expect(defaults.object(forKey: key) == nil)
        }
        #expect(blobs.writeCount == 1) // the file is not rewritten
    }

    /// Without a backup the old blob is the only copy, so it stays for the next launch to try again.
    @Test func migration_badBlob_backupFailure_keepsTheBlob() {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let defaults = MemoryDefaults.make()
        let bad = Data("not json".utf8)
        defaults.set(bad, forKey: Self.oneHourKey)
        blobs.failNextWrite = true

        let recorder = makeRecorder(clock, blobs, defaults: defaults)

        #expect(recorder.oneHourData.isEmpty)
        #expect(defaults.data(forKey: Self.oneHourKey) == bad)

        _ = makeRecorder(clock, blobs, defaults: defaults)
        #expect(blobs.contents(of: NetworkHistoryRecorder.legacyBackupFileName) == bad)
        #expect(defaults.object(forKey: Self.oneHourKey) == nil)
    }

    // MARK: - Damaged files

    @Test func truncatedFile_quarantined() {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let truncated = Data(#"{"schemaVersion":1,"points":[{"t":783820800,"d":12"#.utf8)
        blobs.seed(truncated, named: fileName)

        let recorder = makeRecorder(clock, blobs)
        #expect(blobs.quarantined == [fileName])
        #expect(blobs.contents(of: "\(fileName).corrupt-1") == truncated)
        #expect(recorder.oneHourData.isEmpty)

        feedPoints(recorder, clock, count: 1, mbps: 10)
        recorder.flush()

        #expect(blobs.writeCount == 1)
        #expect(makeRecorder(clock, blobs).oneHourData.count == 1)
    }

    @Test func futureSchema_quarantined() {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let future = Data(#"{"schemaVersion":99,"points":[{"t":783820800,"d":1,"u":2,"dm":3,"um":4}]}"#.utf8)
        blobs.seed(future, named: fileName)

        let recorder = makeRecorder(clock, blobs)
        #expect(blobs.quarantined == [fileName])
        #expect(recorder.oneHourData.isEmpty)

        feedPoints(recorder, clock, count: 1, mbps: 10)
        recorder.flush()

        #expect(blobs.contents(of: "\(fileName).corrupt-1") == future) // kept, not overwritten
        #expect(blobs.contents(of: fileName) != future)
    }

    /// The file is intact, so writing a new one over it would lose everything in it.
    @Test func unreadableFile_quarantinedNotOverwritten() throws {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let writer = makeRecorder(clock, blobs)
        feedPoints(writer, clock, count: 2, mbps: 10)
        writer.flush()
        let good = try #require(blobs.contents(of: fileName))
        blobs.failNextRead = true

        let recorder = makeRecorder(clock, blobs)
        feedPoints(recorder, clock, count: 1, mbps: 20)
        recorder.flush()

        #expect(blobs.contents(of: "\(fileName).corrupt-1") == good)
    }

    /// A bad file that cannot be moved aside is still the live file, so it must not be replaced.
    @Test func quarantineFailure_neverOverwritesTheBadFile() throws {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let bad = Data("half a file".utf8)
        blobs.seed(bad, named: fileName)
        blobs.failQuarantine = true

        let recorder = makeRecorder(clock, blobs)
        feedPoints(recorder, clock, count: 1, mbps: 10)
        recorder.flush()

        #expect(blobs.writeCount == 0)
        #expect(blobs.contents(of: fileName) == bad)
        #expect(recorder.oneHourData.count == 1)

        blobs.failQuarantine = false
        recorder.flush()

        #expect(blobs.contents(of: "\(fileName).corrupt-1") == bad)
        #expect(blobs.writeCount == 1)
        #expect(try fileJSON(blobs)["schemaVersion"] as? Int == 1)
    }

    @Test func writeFailure_keepsDataAndRetries() {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let recorder = makeRecorder(clock, blobs)
        feedPoints(recorder, clock, count: 3, mbps: 10)

        blobs.failNextWrite = true
        recorder.flush()
        #expect(blobs.writeCount == 0)
        #expect(recorder.oneHourData.count == 3)

        recorder.flush()
        #expect(blobs.writeCount == 1)
        #expect(makeRecorder(clock, blobs).oneHourData.count == 3)
    }

    /// A failing disk is retried at the normal pace, not with every sample.
    @Test func writeFailure_automatic_retriesAfterTheInterval() {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let recorder = makeRecorder(clock, blobs)
        blobs.failNextWrite = true

        feed(recorder, clock, mbps: 10, seconds: 601) // the write at 600 s fails
        #expect(blobs.failNextWrite == false)
        #expect(blobs.writeCount == 0)

        feed(recorder, clock, mbps: 10, seconds: 599) // up to 1199 s
        #expect(blobs.writeCount == 0)

        recorder.recordSpeed(speed(10)) // 1200 s
        #expect(blobs.writeCount == 1)
    }

    // MARK: - Clearing

    @Test func clearHistory_persistsEmpty() {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let defaults = MemoryDefaults.make()
        let recorder = makeRecorder(clock, blobs, defaults: defaults)
        feedPoints(recorder, clock, count: 3, mbps: 10)
        recorder.flush()

        recorder.clearHistory() // no flush after it: clearing writes at once

        #expect(makeRecorder(clock, blobs, defaults: defaults).oneHourData.isEmpty)
    }

    /// Clearing must not leave old keys behind for the next launch to bring back.
    @Test func clearHistory_removesTheOldKeys() throws {
        let clock = TestClock(2026, 11, 3, 9)
        let blobs = InMemoryBlobStore()
        let defaults = MemoryDefaults.make()
        let seed = [NetworkDataPoint(timestamp: clock.now.addingTimeInterval(-60), downloadSpeed: 1_000_000, uploadSpeed: 0)]
        defaults.set(try legacyJSON(seed), forKey: Self.oneHourKey)
        blobs.failNextWrite = true // the move fails, so the old keys stay
        let recorder = makeRecorder(clock, blobs, defaults: defaults)
        blobs.failNextWrite = true // and so does the write that records the clearing

        recorder.clearHistory()

        #expect(defaults.object(forKey: Self.oneHourKey) == nil)
        #expect(makeRecorder(clock, blobs, defaults: defaults).oneHourData.isEmpty)
    }
}
