import Foundation

/// One plotted point: a bucket of history with its time-weighted average and its maximum.
struct ChartPoint: Identifiable, Equatable {
    var id: Date { timestamp }
    let timestamp: Date
    let avgDownloadMbps, maxDownloadMbps, avgUploadMbps, maxUploadMbps: Double

    /// The line shows the true spike in every range; the area below 3 hours shows the average.
    /// A single sample has max equal to its average, so short ranges look the same either way.
    var lineDownloadMbps: Double { maxDownloadMbps }
    var lineUploadMbps: Double { maxUploadMbps }

    /// The peak for the tooltip, when the point merges samples that differ.
    var tooltipPeakDownloadMbps: Double? { maxDownloadMbps != avgDownloadMbps ? maxDownloadMbps : nil }
    var tooltipPeakUploadMbps: Double? { maxUploadMbps != avgUploadMbps ? maxUploadMbps : nil }
}

/// Everything the chart draws for one time range. Built when the data changes, not in `body`,
/// and never more than `maxPoints` points however long the history is (PERF-01).
struct ChartSnapshot {
    let points: [ChartPoint]
    let peakDownloadMbps, peakUploadMbps, averageDownloadMbps, averageUploadMbps: Double
    let availability: NetworkChartView.DataAvailability
    let coverageActual, coverageRequired, coveragePercentage: Double

    /// History has one point per 10 s, stamped with the start of its window, so a fully covered
    /// range can have its oldest point up to one window (and a late sample) after the range starts.
    static let coverageSlack: TimeInterval = 15

    /// A point stands for the time until the next one, but never for more than one 10-second
    /// window: a longer gap is the Mac asleep, not traffic.
    static let maxPointDuration: TimeInterval = 10

    /// Ranges this short count as complete as soon as there is any data.
    private static let alwaysCompleteBelow: TimeInterval = 300

    static func empty(range: NetworkChartView.TimeRange) -> ChartSnapshot {
        ChartSnapshot(
            points: [], peakDownloadMbps: 0, peakUploadMbps: 0, averageDownloadMbps: 0, averageUploadMbps: 0,
            availability: .empty, coverageActual: 0, coverageRequired: range.seconds, coveragePercentage: 0
        )
    }

    static func make(
        source: [NetworkDataPoint],
        range: NetworkChartView.TimeRange,
        now: Date,
        maxPoints: Int = 300
    ) -> ChartSnapshot {
        let required = range.seconds
        let cutoff = now.addingTimeInterval(-required)
        // History is already in order unless the wall clock was set back; sorting sorted input is linear.
        let sorted = source.sorted { $0.timestamp < $1.timestamp }
        let inRange = sorted.filter { $0.timestamp > cutoff && $0.timestamp <= now }
        // The oldest point that can stand for the start of the range: one inside it, or a window
        // that opened just before it. Anything older is a different stretch of history.
        guard !inRange.isEmpty,
              let oldest = sorted.first(where: { $0.timestamp >= cutoff.addingTimeInterval(-coverageSlack) })
        else { return empty(range: range) }

        let durations = durations(of: inRange)
        let buckets = bucket(inRange, durations: durations, cutoff: cutoff, required: required, maxPoints: max(maxPoints, 2))

        let totalDuration = durations.reduce(0, +)
        let actual = min(now.timeIntervalSince(oldest.timestamp), required)
        let availability: NetworkChartView.DataAvailability
        if required < alwaysCompleteBelow || required - actual <= coverageSlack {
            availability = .complete
        } else if actual / required >= 0.5 {
            availability = .partial
        } else {
            availability = .insufficient
        }

        return ChartSnapshot(
            points: buckets.map(\.point),
            peakDownloadMbps: inRange.map(\.maxDownloadMbps).max() ?? 0,
            peakUploadMbps: inRange.map(\.maxUploadMbps).max() ?? 0,
            averageDownloadMbps: zip(inRange, durations).reduce(0) { $0 + $1.0.downloadMbps * $1.1 } / totalDuration,
            averageUploadMbps: zip(inRange, durations).reduce(0) { $0 + $1.0.uploadMbps * $1.1 } / totalDuration,
            availability: availability,
            coverageActual: actual,
            coverageRequired: required,
            coveragePercentage: actual / required * 100
        )
    }

    /// How long each point stands for, so the per-second last 15 minutes do not outweigh the
    /// 10-second points before them. The newest point gets the same as the one before it.
    /// A duplicate timestamp gets almost nothing, which keeps every duration above zero.
    private static func durations(of points: [NetworkDataPoint]) -> [TimeInterval] {
        guard points.count > 1 else { return [1] }
        var durations = zip(points, points.dropFirst()).map { earlier, later in
            min(max(later.timestamp.timeIntervalSince(earlier.timestamp), 0.001), maxPointDuration)
        }
        durations.append(durations[durations.count - 1])
        return durations
    }

    /// Up to `maxPoints` points pass through as they are (equal timestamps merged). Beyond that,
    /// equal-width buckets whose edges sit on absolute time, so a redraw a few seconds later
    /// does not reshuffle which samples share a bucket.
    private static func bucket(
        _ points: [NetworkDataPoint],
        durations: [TimeInterval],
        cutoff: Date,
        required: TimeInterval,
        maxPoints: Int
    ) -> [Bucket] {
        // `maxPoints - 1` widths span the range, so it touches at most `maxPoints` cells.
        let width = points.count > maxPoints ? required / Double(maxPoints - 1) : nil
        let firstCell = width.map { (cutoff.timeIntervalSinceReferenceDate / $0).rounded(.down) } ?? 0

        var buckets: [Bucket] = []
        for (point, duration) in zip(points, durations) {
            let seconds = point.timestamp.timeIntervalSinceReferenceDate
            let key: Double
            if let width {
                // Clamped, so floating-point error at either edge cannot add a bucket.
                key = min(max((seconds / width).rounded(.down) - firstCell, 0), Double(maxPoints - 1))
            } else {
                key = seconds
            }
            if buckets.last?.key == key {
                buckets[buckets.count - 1].add(point, duration: duration)
            } else {
                buckets.append(Bucket(key: key, first: point, duration: duration))
            }
        }
        return buckets
    }

    private struct Bucket {
        let key: Double
        let timestamp: Date
        private var duration: TimeInterval
        private var download: Double
        private var upload: Double
        private var maxDownload: Double
        private var maxUpload: Double

        init(key: Double, first: NetworkDataPoint, duration: TimeInterval) {
            self.key = key
            self.timestamp = first.timestamp
            self.duration = duration
            self.download = first.downloadMbps * duration
            self.upload = first.uploadMbps * duration
            self.maxDownload = first.maxDownloadMbps
            self.maxUpload = first.maxUploadMbps
        }

        mutating func add(_ point: NetworkDataPoint, duration: TimeInterval) {
            self.duration += duration
            download += point.downloadMbps * duration
            upload += point.uploadMbps * duration
            maxDownload = max(maxDownload, point.maxDownloadMbps)
            maxUpload = max(maxUpload, point.maxUploadMbps)
        }

        var point: ChartPoint {
            ChartPoint(
                timestamp: timestamp,
                avgDownloadMbps: download / duration,
                maxDownloadMbps: maxDownload,
                avgUploadMbps: upload / duration,
                maxUploadMbps: maxUpload
            )
        }
    }
}
