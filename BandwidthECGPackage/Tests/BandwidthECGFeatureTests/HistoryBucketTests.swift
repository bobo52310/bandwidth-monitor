import Testing
import Foundation
@testable import BandwidthECGFeature

/// The history recorder's 10-second points (CORE-17) and its per-second ring (UI-P2-14).
@MainActor
@Suite("History buckets")
struct HistoryBucketTests {

    private static let bytesPerMbps = 125_000.0

    private func speed(_ downloadMbps: Double, _ uploadMbps: Double = 0) -> NetworkSpeed {
        NetworkSpeed(uploadSpeed: uploadMbps * Self.bytesPerMbps, downloadSpeed: downloadMbps * Self.bytesPerMbps)
    }

    /// Always an in-memory store: the default one is the real Application Support directory.
    private func makeRecorder(_ clock: TestClock, defaults: UserDefaults = MemoryDefaults.make()) -> NetworkHistoryRecorder {
        NetworkHistoryRecorder(defaults: defaults, clock: clock.appClock, store: InMemoryBlobStore())
    }

    /// Records one sample per second, advancing the clock after each.
    private func record(_ recorder: NetworkHistoryRecorder, _ clock: TestClock, _ downloads: [Double], uploads: [Double]? = nil) {
        for (index, download) in downloads.enumerated() {
            recorder.recordSpeed(speed(download, uploads?[index] ?? 0))
            clock.advance(by: 1)
        }
    }

    private func isStrictlyIncreasing(_ dates: [Date]) -> Bool {
        zip(dates, dates.dropFirst()).allSatisfy { $0 < $1 }
    }

    // MARK: - 10-second points

    @Test func pulse_maxPreserved() {
        // CORE-17 worst phase: an 8-second burst each minute that falls between the old spot samples.
        let clock = TestClock(2026, 11, 3, 9)
        let recorder = makeRecorder(clock)
        let fiveMinutes = (0..<300).map { second in (1...8).contains(second % 60) ? 280.0 : 1.0 }
        let uploads = fiveMinutes.map { $0 == 280 ? 60.0 : 1.0 }

        record(recorder, clock, fiveMinutes + [1], uploads: uploads + [1]) // the 301st sample closes the last window

        let points = recorder.oneHourData
        #expect(points.count == 30)
        #expect(points.map(\.maxDownloadMbps).max() == 280)
        let mean = points.map(\.downloadMbps).reduce(0, +) / Double(points.count)
        #expect(abs(mean - 38.2) <= 0.5)
        #expect(points.map(\.maxUploadMbps).max() == 60)
        let uploadMean = points.map(\.uploadMbps).reduce(0, +) / Double(points.count)
        #expect(abs(uploadMean - 8.87) <= 0.05) // (8 x 60 + 52 x 1) / 60
    }

    @Test func sleepGap_closesThePointWhereItStarted() {
        let clock = TestClock(2026, 11, 3, 9)
        let recorder = makeRecorder(clock)
        let start = clock.now

        record(recorder, clock, [40, 40, 40, 40])
        clock.advance(by: 3600) // the Mac sleeps mid-window
        recorder.recordSpeed(speed(10))

        #expect(recorder.oneHourData.count == 1)
        #expect(recorder.oneHourData.first?.timestamp == start)
        #expect(recorder.oneHourData.first?.downloadMbps == 40) // the sample after the gap starts a new point
    }

    @Test func wallClockSetBack_keepsMakingPoints() {
        let clock = TestClock(2026, 11, 3, 9)
        let recorder = makeRecorder(clock)

        record(recorder, clock, Array(repeating: 10, count: 5))
        clock.setWall(clock.now.addingTimeInterval(-3600)) // the user sets the clock back an hour
        record(recorder, clock, Array(repeating: 10, count: 20))

        // 25 samples over 25 real seconds close two windows, clock change or not.
        #expect(recorder.oneHourData.count == 2)
    }

    @Test func clearHistory_dropsPointsSamplesAndTheOpenWindow() {
        let clock = TestClock(2026, 11, 3, 9)
        let recorder = makeRecorder(clock)
        record(recorder, clock, Array(repeating: 500, count: 15))
        let revisionBefore = recorder.revision

        recorder.clearHistory()

        #expect(recorder.oneHourData.isEmpty)
        #expect(recorder.recentSamples.isEmpty)
        #expect(recorder.revision > revisionBefore) // a chart showing the old history redraws

        record(recorder, clock, Array(repeating: 20, count: 11))
        #expect(recorder.oneHourData.count == 1)
        #expect(recorder.oneHourData.first?.maxDownloadMbps == 20) // nothing from before the reset
    }

    @Test func revision_advancesAtCap() throws {
        let clock = TestClock(2026, 11, 3, 9)
        let defaults = MemoryDefaults.make()
        // A full history, brought in through the old UserDefaults key, packed into the last hour.
        let seed = (0..<8640).map { index in
            NetworkDataPoint(
                timestamp: clock.now.addingTimeInterval(-3500 + Double(index) * 0.4),
                downloadSpeed: Self.bytesPerMbps,
                uploadSpeed: Self.bytesPerMbps
            )
        }
        defaults.set(try JSONEncoder().encode(seed), forKey: "networkHistory_oneHour")
        let recorder = makeRecorder(clock, defaults: defaults)
        #expect(recorder.oneHourData.count == 8640)
        let revisionBefore = recorder.revision

        record(recorder, clock, Array(repeating: 50, count: 11)) // the 11th sample closes the window

        #expect(recorder.oneHourData.count == 8640) // the count no longer moves...
        #expect(recorder.revision == revisionBefore + 1) // ...but the revision does (R4)
        #expect(recorder.oneHourData.last?.downloadMbps == 50)
    }

    // MARK: - Saved format

    @Test func oldFormat_decodes() throws {
        let json = #"[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","timestamp":783820800,"downloadSpeed":1250000,"uploadSpeed":250000}]"#

        let points = try JSONDecoder().decode([NetworkDataPoint].self, from: Data(json.utf8))

        #expect(points.count == 1)
        #expect(points.first?.timestamp == Date(timeIntervalSinceReferenceDate: 783_820_800))
        #expect(points.first?.downloadSpeed == 1_250_000)
        #expect(points.first?.maxDownloadSpeed == 1_250_000)
        #expect(points.first?.maxUploadSpeed == 250_000)
    }

    @Test func oldFormat_loadsFromTheSavedHistory() {
        let clock = TestClock(2026, 11, 3, 9)
        let defaults = MemoryDefaults.make()
        let timestamp = clock.now.addingTimeInterval(-60).timeIntervalSinceReferenceDate
        let json = #"[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","timestamp":\#(timestamp),"downloadSpeed":1250000,"uploadSpeed":250000}]"#
        defaults.set(Data(json.utf8), forKey: "networkHistory_oneHour")

        let recorder = makeRecorder(clock, defaults: defaults)

        #expect(recorder.oneHourData.count == 1)
        #expect(recorder.oneHourData.first?.maxDownloadMbps == 10)
        #expect(recorder.oneHourData.first?.maxUploadMbps == 2)
    }

    @Test func encoded_hasNoId() throws {
        let point = NetworkDataPoint(
            timestamp: Date(timeIntervalSinceReferenceDate: 783_820_800),
            downloadSpeed: 100, uploadSpeed: 50, maxDownloadSpeed: 900, maxUploadSpeed: 70
        )

        let data = try JSONEncoder().encode(point)

        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["id"] == nil)
        #expect(Set(object.keys) == ["timestamp", "downloadSpeed", "uploadSpeed", "maxDownloadSpeed", "maxUploadSpeed"])
        let decoded = try JSONDecoder().decode(NetworkDataPoint.self, from: data)
        #expect(decoded.downloadSpeed == 100)
        #expect(decoded.uploadSpeed == 50)
        #expect(decoded.maxDownloadSpeed == 900)
        #expect(decoded.maxUploadSpeed == 70)
    }

    // MARK: - Per-second ring

    @Test func ring_capacity900() {
        let clock = TestClock(2026, 11, 3, 9)
        let recorder = makeRecorder(clock)

        record(recorder, clock, (0..<1000).map(Double.init))

        #expect(recorder.recentSamples.count == 900)
        #expect(recorder.recentSamples.first?.downloadMbps == 100) // the oldest 100 were dropped
        #expect(recorder.recentSamples.last?.downloadMbps == 999)
        #expect(recorder.recentSamples.allSatisfy { $0.maxDownloadSpeed == $0.downloadSpeed }) // raw samples
        #expect(recorder.points(since: clock.now.addingTimeInterval(-60)).count == 60)
    }

    @Test func points_mergesRingAndTenSecond() {
        let clock = TestClock(2026, 11, 3, 7)
        let recorder = makeRecorder(clock)
        // 1 h 45 min of one sample every 10 s, then 15 min of one per second: 2 hours in all.
        for _ in 0..<630 {
            recorder.recordSpeed(speed(20))
            clock.advance(by: 10)
        }
        record(recorder, clock, Array(repeating: 30, count: 900))
        let now = clock.now

        let points = recorder.points(since: now.addingTimeInterval(-3600))

        let times = points.map(\.timestamp)
        #expect(isStrictlyIncreasing(times)) // in order, no duplicates
        #expect(times.allSatisfy { $0 >= now.addingTimeInterval(-3600) })
        let recentTimes = times.filter { $0 >= now.addingTimeInterval(-900) }
        #expect(recentTimes.count == 900) // the last 15 minutes at 1-second resolution
        #expect(zip(recentTimes, recentTimes.dropFirst()).allSatisfy { $1.timeIntervalSince($0) == 1 })
        #expect(times.filter { $0 < now.addingTimeInterval(-900) }.count == 270) // 45 minutes of 10-second points
        #expect(ChartSnapshot.make(source: points, range: .oneHour, now: now).availability == .complete)
    }

    @Test func seam_losesNoSample() {
        // The ring starts in the middle of a 10-second window. A burst in that window's first
        // seconds, already gone from the ring, must still reach the merged points.
        let clock = TestClock(2026, 11, 3, 9)
        let recorder = makeRecorder(clock)
        var downloads = Array(repeating: 5.0, count: 1805)
        downloads[901] = 700

        record(recorder, clock, downloads)

        let points = recorder.points(since: clock.now.addingTimeInterval(-3600))
        #expect(recorder.recentSamples.allSatisfy { $0.downloadMbps == 5 })
        #expect(points.map(\.maxDownloadMbps).max() == 700)
    }
}
