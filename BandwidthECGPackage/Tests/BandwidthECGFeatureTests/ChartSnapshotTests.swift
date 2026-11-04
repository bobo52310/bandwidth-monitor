import Testing
import Foundation
@testable import BandwidthECGFeature

/// Down-sampling and statistics for the popover chart (PERF-01).
@Suite("ChartSnapshot")
struct ChartSnapshotTests {

    private static let bytesPerMbps = 125_000.0

    /// Bucket edges are anchored to absolute time, so `now` sits half an hour past a whole hour:
    /// with `maxPoints: 2` the one-hour buckets are then whole hours since the reference date.
    private let now = Date(timeIntervalSinceReferenceDate: 3600 * 220_000 + 1800)

    private func point(
        _ secondsAgo: TimeInterval, _ downloadMbps: Double, _ uploadMbps: Double = 0,
        maxDownload: Double? = nil, maxUpload: Double? = nil
    ) -> NetworkDataPoint {
        NetworkDataPoint(
            timestamp: now.addingTimeInterval(-secondsAgo),
            downloadSpeed: downloadMbps * Self.bytesPerMbps,
            uploadSpeed: uploadMbps * Self.bytesPerMbps,
            maxDownloadSpeed: maxDownload.map { $0 * Self.bytesPerMbps },
            maxUploadSpeed: maxUpload.map { $0 * Self.bytesPerMbps }
        )
    }

    /// `count` points `spacing` seconds apart, oldest first, the newest `newest` seconds ago.
    private func series(_ count: Int, spacing: TimeInterval, newest: TimeInterval = 0, mbps: Double = 10) -> [NetworkDataPoint] {
        (0..<count).reversed().map { point(newest + Double($0) * spacing, mbps, mbps) }
    }

    private func isStrictlyIncreasing(_ points: [ChartPoint]) -> Bool {
        zip(points, points.dropFirst()).allSatisfy { $0.timestamp < $1.timestamp }
    }

    // MARK: - Down-sampling

    @Test func fewPoints_passThrough() {
        let source = (0..<100).map { point(Double(99 - $0), Double($0), 1, maxDownload: Double($0) + 5) }

        let snapshot = ChartSnapshot.make(source: source, range: .fiveMinutes, now: now)

        #expect(snapshot.points.count == 100)
        #expect(snapshot.points.map(\.timestamp) == source.map(\.timestamp))
        #expect(snapshot.points.map(\.avgDownloadMbps) == source.map(\.downloadMbps))
        #expect(snapshot.points.map(\.maxDownloadMbps) == source.map(\.maxDownloadMbps))
    }

    @Test func n8640_atMost300() {
        let snapshot = ChartSnapshot.make(source: series(8640, spacing: 10), range: .twentyFourHours, now: now)

        #expect(snapshot.points.count <= 300)
        #expect(snapshot.points.count >= 290) // merged only as far as needed
    }

    @Test func atMost300_forEveryRangeAndPhase() {
        // Ten-second points for 24 hours plus one sample per second for the last 15 minutes.
        let source = series(8550, spacing: 10, newest: 900) + series(900, spacing: 1)
        for range in NetworkChartView.TimeRange.allCases {
            for phase in stride(from: 0.0, to: 10.0, by: 0.37) {
                let snapshot = ChartSnapshot.make(source: source, range: range, now: now.addingTimeInterval(phase))
                #expect(snapshot.points.count <= 300, "\(range) at +\(phase) s")
            }
        }
    }

    @Test func newestBucket_isCurrent() {
        // Every bucket is one width wide, the newest too, so the line reaches the present.
        let snapshot = ChartSnapshot.make(source: series(8640, spacing: 10), range: .twentyFourHours, now: now)

        let width = 86_400.0 / 299
        #expect((snapshot.points.last?.timestamp ?? .distantPast) >= now.addingTimeInterval(-width - 10))
    }

    @Test func bucket_keepsMaxAndWeightedAvg() {
        let source = [point(3, 10), point(2, 500), point(1, 10)]

        let snapshot = ChartSnapshot.make(source: source, range: .oneHour, now: now, maxPoints: 2)

        #expect(snapshot.points.count == 1)
        #expect(snapshot.points.first?.maxDownloadMbps == 500)
        #expect(abs((snapshot.points.first?.avgDownloadMbps ?? 0) - 173.33) < 0.01)
    }

    @Test func bucket_weighsByDuration() {
        // A 10-second point at 100 Mbps, then ten 1-second samples at 0: 20 seconds, half at 100.
        let source = [point(30, 100)] + series(10, spacing: 1, newest: 11, mbps: 0)

        let snapshot = ChartSnapshot.make(source: source, range: .oneHour, now: now, maxPoints: 2)

        #expect(snapshot.points.count == 1)
        #expect(abs((snapshot.points.first?.avgDownloadMbps ?? 0) - 50) < 0.01)
    }

    @Test func bucket_newestPointCountsLikeTheOneBefore() {
        // Three 10-second points: the newest stands for 10 s like the others, not for 1 s.
        let source = [point(30, 10), point(20, 500), point(10, 10)]

        let snapshot = ChartSnapshot.make(source: source, range: .oneHour, now: now, maxPoints: 2)

        #expect(abs((snapshot.points.first?.avgDownloadMbps ?? 0) - 173.33) < 0.01)
    }

    @Test func oneHour_spikeIsTheLinePeak() throws {
        // 45 min of 10-second points at 5 Mbps, then 15 min of per-second samples at 5 Mbps
        // with one second at 69 Mbps down and 33 Mbps up. One hour of that is bucketed (~12 s).
        var samples = series(900, spacing: 1, mbps: 5)
        samples[450] = point(now.timeIntervalSince(samples[450].timestamp), 69, 33)
        let source = series(270, spacing: 10, newest: 910, mbps: 5) + samples

        let snapshot = ChartSnapshot.make(source: source, range: .oneHour, now: now)

        let spike = try #require(snapshot.points.first { $0.maxDownloadMbps == 69 })
        #expect(spike.avgDownloadMbps < 69) // the bucket averages the spike with its neighbours...
        #expect(spike.lineDownloadMbps == 69) // ...but the line plots the spike
        #expect(spike.lineUploadMbps == 33)
        #expect(snapshot.points.map(\.lineDownloadMbps).max() == 69)
        #expect(spike.tooltipPeakDownloadMbps == 69)
        #expect(spike.tooltipPeakUploadMbps == 33)
    }

    @Test func tooltipPeak_onlyWhenThePointAggregates() {
        // Per-second samples pass through unmerged: max equals average, nothing extra to show.
        let snapshot = ChartSnapshot.make(source: series(100, spacing: 1), range: .fiveMinutes, now: now)

        #expect(snapshot.points.allSatisfy { $0.tooltipPeakDownloadMbps == nil && $0.tooltipPeakUploadMbps == nil })
        #expect(snapshot.points.allSatisfy { $0.lineDownloadMbps == $0.avgDownloadMbps })
    }

    @Test func peak_fromFullResolution() {
        var source = series(8640, spacing: 10)
        source[4321] = point(now.timeIntervalSince(source[4321].timestamp), 10, 10, maxDownload: 937)
        source[6000] = point(now.timeIntervalSince(source[6000].timestamp), 10, 10, maxUpload: 88)

        let snapshot = ChartSnapshot.make(source: source, range: .twentyFourHours, now: now)

        #expect(snapshot.peakDownloadMbps == 937)
        #expect(snapshot.peakUploadMbps == 88)
        #expect(snapshot.points.map(\.maxDownloadMbps).max() == 937) // the bucket keeps it too
        #expect(snapshot.points.map(\.maxUploadMbps).max() == 88)
    }

    @Test func sortedAscending() {
        let shuffled = Array(series(1000, spacing: 1).reversed()) + [point(500, 3)]
        let small = Array(series(50, spacing: 1).reversed()) + [point(10, 3)]

        let bucketed = ChartSnapshot.make(source: shuffled, range: .thirtyMinutes, now: now)
        let passedThrough = ChartSnapshot.make(source: small, range: .fiveMinutes, now: now)

        #expect(isStrictlyIncreasing(bucketed.points))
        #expect(isStrictlyIncreasing(passedThrough.points))
        #expect(passedThrough.points.count == 50) // the duplicate timestamp became one point
    }

    @Test func bucketsStayPutAsTimeMoves() {
        // Bucket edges follow absolute time, so redrawing 10 s later does not reshuffle the line.
        let source = series(8640, spacing: 10)
        let earlier = ChartSnapshot.make(source: source, range: .twentyFourHours, now: now)
        let later = ChartSnapshot.make(source: source, range: .twentyFourHours, now: now.addingTimeInterval(10))

        let settled = now.addingTimeInterval(-86_400 + 1000)
        #expect(earlier.points.filter { $0.timestamp > settled } == later.points.filter { $0.timestamp > settled })
    }

    // MARK: - Statistics

    @Test func average_isTimeWeighted() {
        // 45 minutes of 10-second points at 100 Mbps, then 15 minutes of per-second samples at 0.
        // By count the samples are 77% of the points; by time they are 25%.
        let source = series(270, spacing: 10, newest: 910, mbps: 100) + series(900, spacing: 1, mbps: 0)

        let snapshot = ChartSnapshot.make(source: source, range: .oneHour, now: now)

        #expect(abs(snapshot.averageDownloadMbps - 75) < 0.5)
        #expect(abs(snapshot.averageUploadMbps - 75) < 0.5)
    }

    @Test func average_sleepGapCountsAsOneWindow() {
        // 100 Mbps, then the Mac sleeps for almost an hour, then eleven samples at 0.
        let source = [point(3000, 100)] + series(11, spacing: 1, mbps: 0)

        let snapshot = ChartSnapshot.make(source: source, range: .oneHour, now: now)

        #expect(abs(snapshot.averageDownloadMbps - 1000.0 / 21) < 0.01)
    }

    @Test func futurePoints_areIgnored() {
        // After the wall clock is set back, the newest history lies ahead of "now".
        let snapshot = ChartSnapshot.make(source: [point(10, 10), point(-30, 900)], range: .oneHour, now: now)

        #expect(snapshot.points.count == 1)
        #expect(snapshot.peakDownloadMbps == 10)
    }

    @Test func empty_isEmptyAvailability() {
        let empty = ChartSnapshot.make(source: [], range: .oneHour, now: now)
        let onlyOlder = ChartSnapshot.make(source: [point(7200, 50)], range: .oneHour, now: now)
        let justBefore = ChartSnapshot.make(source: [point(3605, 50)], range: .oneHour, now: now)

        for snapshot in [empty, onlyOlder, justBefore] {
            #expect(snapshot.availability == .empty)
            #expect(snapshot.points.isEmpty)
            #expect(snapshot.peakDownloadMbps == 0)
            #expect(snapshot.averageDownloadMbps == 0)
            #expect(snapshot.coveragePercentage == 0)
            #expect(snapshot.coverageRequired == 3600)
        }
    }

    @Test func availability_thresholds() {
        func availability(oldest: TimeInterval, _ range: NetworkChartView.TimeRange = .oneHour) -> NetworkChartView.DataAvailability {
            ChartSnapshot.make(source: [point(oldest, 10), point(0, 10)], range: range, now: now).availability
        }

        #expect(availability(oldest: 0.49 * 3600) == .insufficient)
        #expect(availability(oldest: 0.50 * 3600) == .partial)
        #expect(availability(oldest: 3600) == .complete)
        // The range is (now - 1 h, now]: the point exactly an hour old counts for coverage only.
        #expect(ChartSnapshot.make(source: [point(3600, 10), point(0, 10)], range: .oneHour, now: now).points.count == 1)
        #expect(ChartSnapshot.make(source: [point(5, 10)], range: .oneMinute, now: now).availability == .complete)
        let half = ChartSnapshot.make(source: [point(1800, 10), point(0, 10)], range: .oneHour, now: now)
        #expect(half.coverageActual == 1800)
        #expect(half.coveragePercentage == 50)
    }

    @Test func olderStretch_doesNotCountAsCoverage() {
        // Data two hours ago, then nothing until 1000 s ago: the hour is not covered.
        let source = [point(7200, 10), point(1000, 10), point(0, 10)]

        let snapshot = ChartSnapshot.make(source: source, range: .oneHour, now: now)

        #expect(snapshot.availability == .insufficient)
        #expect(snapshot.coverageActual == 1000)
    }

    @Test func fullTenSecondHistory_isComplete() {
        // The oldest 10-second point in a range starts up to one window after the range does.
        let full = ChartSnapshot.make(source: series(360, spacing: 10), range: .oneHour, now: now)
        let minuteShort = ChartSnapshot.make(source: series(354, spacing: 10), range: .oneHour, now: now)

        #expect(full.availability == .complete)
        #expect(minuteShort.availability == .partial)
    }

    @Test func averageArea_belowThreeHours() {
        #expect(NetworkChartView.TimeRange.allCases.filter(\.drawsAverageArea) == [.oneMinute, .fiveMinutes, .fifteenMinutes, .thirtyMinutes, .oneHour])
    }
}
