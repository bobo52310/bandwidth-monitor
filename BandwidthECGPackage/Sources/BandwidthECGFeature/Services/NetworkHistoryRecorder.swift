import Foundation
import Observation
import OSLog

/// The chart history: one point per 10 seconds for the last 24 hours, and every sample of the
/// last 15 minutes.
///
/// The 10-second points are saved to `history-10s.json` at most every `writeIntervalSeconds`
/// and whenever `flush()` is called (before sleep and on quit), so a relaunch still shows the
/// last 24 hours (D7). The per-second samples are not saved.
@MainActor
@Observable
public class NetworkHistoryRecorder {
    /// One point per 10 seconds, each the average and maximum of its window, up to 24 hours.
    /// The name is older than the 24-hour history.
    public private(set) var oneHourData: [NetworkDataPoint] = []
    /// Moves on with every new 10-second point and when the history is cleared. A chart can
    /// redraw on it; unlike `oneHourData.count` it keeps moving once the history is full (R4).
    public private(set) var revision = 0
    /// Every sample of the last `recentSampleCapacity` seconds, oldest first.
    public private(set) var recentSamples: [NetworkDataPoint] = []

    static let fileName = "history-10s.json"
    /// Where a `UserDefaults` history that cannot be decoded is kept.
    static let legacyBackupFileName = "history-legacy.corrupt"
    /// A full file is about 0.7 MB, so it is not rewritten with every point (CORE-19).
    static let writeIntervalSeconds: TimeInterval = 600
    static let retentionSeconds: TimeInterval = 24 * 3600
    static let maxPoints = 8640 // 24 hours of 10-second points
    static let recentSampleCapacity = 900 // 15 minutes at one sample per second
    private static let pointInterval: TimeInterval = 10
    private static let schemaVersion = 1

    /// Where versions before the file kept the history. Moved to the file once, then removed.
    enum LegacyKey {
        static let points = "networkHistory_oneHour"
        static let hourlyAggregates = "networkHistory_twentyFourHour"
        static let lastRecordTime = "networkHistory_lastRecordTime"
        static let all = [points, hourlyAggregates, lastRecordTime]
    }

    private let defaults: UserDefaults
    private let clock: AppClock
    private let store: any BlobStore
    private let logger = Logger(subsystem: "com.bandwidthecg", category: "History")

    /// The 10-second point being collected.
    @ObservationIgnored private var window: PointWindow?
    /// Points in memory that have not reached the file. Stays set when a write fails.
    @ObservationIgnored private var isDirty = false
    @ObservationIgnored private var lastWriteAttempt: TimeInterval
    /// The live file could not be read or moved aside. Nothing may be written over it.
    @ObservationIgnored private var hasBadFile = false
    /// The old `UserDefaults` keys still hold the only saved copy; they go once the file is written.
    @ObservationIgnored private var legacyKeysAwaitFile = false

    public init(
        defaults: UserDefaults = .standard,
        clock: AppClock = .live,
        store: any BlobStore = AppSupportBlobStore()
    ) {
        self.defaults = defaults
        self.clock = clock
        self.store = store
        self.lastWriteAttempt = clock.monotonic()
        load()
    }

    // MARK: - Recording

    public func recordSpeed(_ speed: NetworkSpeed) {
        let now = clock.now()
        let monotonic = clock.monotonic()

        recentSamples.append(NetworkDataPoint(
            timestamp: now,
            downloadSpeed: speed.downloadSpeed,
            uploadSpeed: speed.uploadSpeed
        ))
        if recentSamples.count > Self.recentSampleCapacity {
            recentSamples.removeFirst(recentSamples.count - Self.recentSampleCapacity)
        }

        // A sample 10 s or more after the window opened starts the next one. Elapsed time is
        // monotonic, so setting the wall clock back does not stall the points and a sleep
        // closes the window before the gap.
        if let open = window, monotonic - open.startMonotonic >= Self.pointInterval {
            appendPoint(open.point, now: now)
            window = nil
        }
        if window == nil {
            window = PointWindow(start: now, startMonotonic: monotonic)
        }
        window?.add(speed)

        writeIfDue(at: monotonic)
    }

    private func appendPoint(_ point: NetworkDataPoint, now: Date) {
        oneHourData.append(point)
        let cutoff = now.addingTimeInterval(-Self.retentionSeconds)
        oneHourData.removeAll { $0.timestamp <= cutoff }
        if oneHourData.count > Self.maxPoints {
            oneHourData.removeFirst(oneHourData.count - Self.maxPoints)
        }
        revision += 1
        isDirty = true
    }

    /// Chart data from `cutoff` on: 10-second points up to where the per-second samples begin,
    /// then the samples. A point is stamped with its window's start, so the point whose window
    /// holds the oldest samples still counts and no sample at the seam is lost.
    /// Arrival order, which is time order unless the wall clock was set back.
    public func points(since cutoff: Date) -> [NetworkDataPoint] {
        let samplesStart = recentSamples.first?.timestamp ?? .distantFuture
        var points = oneHourData.filter { $0.timestamp >= cutoff && $0.timestamp < samplesStart }
        points.append(contentsOf: recentSamples.lazy.filter { $0.timestamp >= cutoff })
        return points
    }

    /// Empties the history in memory and on disk at once, so it does not return after a relaunch.
    public func clearHistory() {
        oneHourData.removeAll()
        recentSamples.removeAll()
        window = nil
        revision += 1
        removeLegacyKeys()
        isDirty = true
        flush()
    }

    // MARK: - Persistence

    /// Writes the points if they changed since the last write. Called before sleep and on quit;
    /// otherwise the recorder writes by itself at most every `writeIntervalSeconds`.
    public func flush() {
        guard isDirty else { return }

        lastWriteAttempt = clock.monotonic()
        if hasBadFile {
            quarantineFile()
        }
        guard !hasBadFile else { return }

        do {
            let file = File(schemaVersion: Self.schemaVersion, points: oneHourData.map(StoredPoint.init))
            try store.write(try JSONEncoder().encode(file), named: Self.fileName)
            isDirty = false
            if legacyKeysAwaitFile {
                removeLegacyKeys()
            }
        } catch {
            logger.error("Could not write \(Self.fileName, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Counts from the last attempt, so a failing disk is retried at the normal pace.
    private func writeIfDue(at monotonic: TimeInterval) {
        guard isDirty, monotonic - lastWriteAttempt >= Self.writeIntervalSeconds else { return }
        flush()
    }

    private func load() {
        guard let saved = loadFile() else {
            migrateLegacyHistory()
            return
        }
        oneHourData = retained(saved)
        // Only an older version, run after this one, writes the old keys again. The file wins.
        if hasLegacyKeys {
            logger.notice("Removed the UserDefaults history: \(Self.fileName, privacy: .public) replaces it")
            removeLegacyKeys()
        }
    }

    /// The saved points, or `nil` when there is no usable file. A file that cannot be read or
    /// decoded is moved aside, never written over.
    private func loadFile() -> [NetworkDataPoint]? {
        do {
            guard let data = try store.read(Self.fileName) else { return nil }
            let header = try JSONDecoder().decode(FileHeader.self, from: data)
            guard header.schemaVersion == Self.schemaVersion else {
                throw LoadError.unsupportedSchema(header.schemaVersion)
            }
            return try JSONDecoder().decode(File.self, from: data).points.map(\.dataPoint)
        } catch {
            logger.error("Could not load \(Self.fileName, privacy: .public): \(String(describing: error), privacy: .public)")
            quarantineFile()
            return nil
        }
    }

    /// Moves the unusable file aside. While that fails it is still the live file, so `flush`
    /// keeps the new points in memory and tries again rather than replacing it.
    private func quarantineFile() {
        do {
            try store.quarantine(Self.fileName)
            hasBadFile = false
        } catch {
            hasBadFile = true
            logger.error("Could not quarantine \(Self.fileName, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Earlier versions rewrote the whole history into the preferences plist every 10 seconds
    /// (PERF-08). Its points move to the file. The hourly aggregates were computed from the
    /// same points, so they are dropped with the keys.
    private func migrateLegacyHistory() {
        guard let data = defaults.data(forKey: LegacyKey.points) else {
            if hasLegacyKeys {
                removeLegacyKeys()
            }
            return
        }

        let points: [NetworkDataPoint]
        do {
            points = try JSONDecoder().decode([NetworkDataPoint].self, from: data)
        } catch {
            backUpUndecodableLegacyHistory(data, error: error)
            return
        }

        oneHourData = retained(points)
        legacyKeysAwaitFile = true
        isDirty = true
        flush()
        let moved = oneHourData.count
        logger.notice("Moved \(moved) history points from UserDefaults to \(Self.fileName, privacy: .public)")
    }

    /// Keeps the bytes in a file, then removes the keys, so this happens once. Without a backup
    /// the blob is the only copy and stays for the next launch.
    private func backUpUndecodableLegacyHistory(_ data: Data, error: Error) {
        do {
            try store.write(data, named: Self.legacyBackupFileName)
            removeLegacyKeys()
            logger.error("Could not decode the UserDefaults history, moved it to \(Self.legacyBackupFileName, privacy: .public): \(String(describing: error), privacy: .public)")
        } catch let backupError {
            logger.error("Could not decode the UserDefaults history or back it up, left it in place: \(String(describing: backupError), privacy: .public)")
        }
    }

    private var hasLegacyKeys: Bool {
        LegacyKey.all.contains { defaults.object(forKey: $0) != nil }
    }

    private func removeLegacyKeys() {
        for key in LegacyKey.all {
            defaults.removeObject(forKey: key)
        }
        legacyKeysAwaitFile = false
    }

    /// The last 24 hours of `points`, at most `maxPoints` of them, in their order.
    private func retained(_ points: [NetworkDataPoint]) -> [NetworkDataPoint] {
        let cutoff = clock.now().addingTimeInterval(-Self.retentionSeconds)
        return Array(points.filter { $0.timestamp > cutoff }.suffix(Self.maxPoints))
    }
}

// MARK: - File format

private struct FileHeader: Decodable {
    let schemaVersion: Int
}

private struct File: Codable {
    let schemaVersion: Int
    let points: [StoredPoint]
}

private enum LoadError: Error {
    case unsupportedSchema(Int)
}

/// One point as saved. Short keys and rounded values keep a full day under 1 MB even at the
/// 10 Gbps cap: speeds to whole bytes per second, the time (seconds since 2001, as `Date`
/// encodes it) to the millisecond.
private struct StoredPoint: Codable {
    let time: Double
    let download: Double
    let upload: Double
    let maxDownload: Double
    let maxUpload: Double

    private enum CodingKeys: String, CodingKey {
        case time = "t"
        case download = "d"
        case upload = "u"
        case maxDownload = "dm"
        case maxUpload = "um"
    }

    init(_ point: NetworkDataPoint) {
        time = (point.timestamp.timeIntervalSinceReferenceDate * 1000).rounded() / 1000
        download = point.downloadSpeed.rounded()
        upload = point.uploadSpeed.rounded()
        maxDownload = point.maxDownloadSpeed.rounded()
        maxUpload = point.maxUploadSpeed.rounded()
    }

    var dataPoint: NetworkDataPoint {
        NetworkDataPoint(
            timestamp: Date(timeIntervalSinceReferenceDate: time),
            downloadSpeed: download,
            uploadSpeed: upload,
            maxDownloadSpeed: maxDownload,
            maxUploadSpeed: maxUpload
        )
    }
}

/// Running average and maximum of the samples in one 10-second window.
private struct PointWindow {
    let start: Date
    let startMonotonic: TimeInterval
    private var count = 0
    private var downloadSum = 0.0
    private var uploadSum = 0.0
    private var downloadMax = 0.0
    private var uploadMax = 0.0

    init(start: Date, startMonotonic: TimeInterval) {
        self.start = start
        self.startMonotonic = startMonotonic
    }

    mutating func add(_ speed: NetworkSpeed) {
        count += 1
        downloadSum += speed.downloadSpeed
        uploadSum += speed.uploadSpeed
        downloadMax = max(downloadMax, speed.downloadSpeed)
        uploadMax = max(uploadMax, speed.uploadSpeed)
    }

    var point: NetworkDataPoint {
        NetworkDataPoint(
            timestamp: start,
            downloadSpeed: downloadSum / Double(count),
            uploadSpeed: uploadSum / Double(count),
            maxDownloadSpeed: downloadMax,
            maxUploadSpeed: uploadMax
        )
    }
}
