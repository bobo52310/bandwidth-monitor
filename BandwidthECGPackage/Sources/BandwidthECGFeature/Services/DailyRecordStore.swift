import Foundation
import Observation
import OSLog

/// Keeps one `DailyRecord` per calendar day, updated by every sample and event.
///
/// Records are upserted by day key, so there is nothing to finalize when a day ends and a day
/// the app missed the end of is already complete. Monthly reports are derived from `records`.
@MainActor
@Observable
public final class DailyRecordStore {
    public private(set) var records: [String: DailyRecord] = [:]

    static let fileName = "daily-records.json"
    private static let schemaVersion = 1

    private struct File: Codable {
        let schemaVersion: Int
        let records: [DailyRecord]
    }

    private enum LoadError: Error {
        case unsupportedSchema(Int)
    }

    private let store: any BlobStore
    /// A `var` so a test can move the time zone, which the live calendar does by itself.
    @ObservationIgnored var clock: AppClock
    private let logger = Logger(subsystem: "com.bandwidthecg", category: "DailyRecords")

    @ObservationIgnored private var downloadWindow = SustainedPeakWindow()
    @ObservationIgnored private var uploadWindow = SustainedPeakWindow()
    /// Changes in memory that have not reached the file. Stays set when a write fails.
    @ObservationIgnored private var isDirty = false
    @ObservationIgnored private var lastFlushAttempt: TimeInterval
    /// The live file could not be read or moved aside. Nothing may be written over it.
    @ObservationIgnored private var hasBadFile = false

    public init(store: any BlobStore, clock: AppClock) {
        self.store = store
        self.clock = clock
        self.lastFlushAttempt = clock.monotonic()
        load()
    }

    // MARK: - Recording

    /// Adds one sample to today's record. Called once per sample, so the monotonic time between
    /// calls is the sample interval. Samples above the plausible limit are ignored.
    public func ingest(_ speed: NetworkSpeed, planDownloadMbps: Double, planUploadMbps: Double) {
        let download = speed.downloadMbps
        let upload = speed.uploadMbps
        guard download <= SampleGuard.maxPlausibleMbps, upload <= SampleGuard.maxPlausibleMbps else { return }

        let monotonic = clock.monotonic()
        let sustainedDownload = downloadWindow.add(download, at: monotonic)
        let sustainedUpload = uploadWindow.add(upload, at: monotonic)
        let now = clock.now()

        updateRecord(on: now) { record in
            record.sampleCount += 1
            record.downloadSum += download
            record.uploadSum += upload
            record.planDownloadMbps = planDownloadMbps
            record.planUploadMbps = planUploadMbps
            if let sustainedDownload, sustainedDownload > record.sustainedPeakDownloadMbps {
                record.sustainedPeakDownloadMbps = sustainedDownload
                record.sustainedPeakDownloadTime = now
            }
            if let sustainedUpload, sustainedUpload > record.sustainedPeakUploadMbps {
                record.sustainedPeakUploadMbps = sustainedUpload
                record.sustainedPeakUploadTime = now
            }
        }
        flushIfDue()
    }

    public func recordApproachEvent() {
        updateRecord(on: clock.now()) { $0.approachCount += 1 }
        flushIfDue()
    }

    /// `jitterMs` is `nil` when the reading was made from a single sample, which has no jitter.
    /// Recording 0 for it would pull the month's average jitter down, so only the latency counts.
    public func recordLatency(latencyMs: Double, jitterMs: Double?) {
        updateRecord(on: clock.now()) { record in
            record.latencySum += latencyMs
            record.latencyCount += 1
            if let jitterMs {
                record.jitterSum += jitterMs
                record.jitterCount += 1
            }
        }
        flushIfDue()
    }

    /// A failed probe has no latency, so it is counted apart and never enters the average.
    public func recordLatencyFailure() {
        updateRecord(on: clock.now()) { $0.latencyFailures += 1 }
        flushIfDue()
    }

    /// Splits the outage at each midnight. Every day it touches gets its share of the downtime
    /// and counts one disconnect.
    public func recordDisconnect(start: Date, end: Date) {
        defer { flushIfDue() }

        // The wall clock moved back during the outage: it happened, but its length is unknown.
        guard end > start else {
            updateRecord(on: start) { $0.disconnectCount += 1 }
            return
        }

        let calendar = clock.calendar
        var segmentStart = start
        while segmentStart < end {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: segmentStart)) ?? end
            let segmentEnd = min(nextDay, end)
            let downtime = segmentEnd.timeIntervalSince(segmentStart)
            updateRecord(on: segmentStart) { record in
                record.disconnectCount += 1
                record.downtimeSeconds += downtime
            }
            segmentStart = segmentEnd
        }
    }

    private func updateRecord(on date: Date, _ change: (inout DailyRecord) -> Void) {
        let key = DayKey.day(for: date, calendar: clock.calendar)
        if records[key] == nil {
            pruneExpired()
        }
        var record = records[key] ?? DailyRecord(dayKey: key)
        change(&record)
        records[key] = record
        isDirty = true
    }

    // MARK: - Queries

    /// The month's records, oldest first.
    public func records(inMonth monthKey: String) -> [DailyRecord] {
        records.values
            .filter { DayKey.month(ofDay: $0.dayKey) == monthKey }
            .sorted { $0.dayKey < $1.dayKey }
    }

    /// Every month with at least one record, newest first.
    public var monthKeys: [String] {
        Set(records.keys.map(DayKey.month(ofDay:))).sorted(by: >)
    }

    // MARK: - Persistence

    /// Writes pending changes now. Called on sleep and on quit.
    public func flush() {
        guard isDirty else { return }

        lastFlushAttempt = clock.monotonic()
        if hasBadFile {
            quarantineFile()
        }
        guard !hasBadFile else { return }

        do {
            let sorted = records.values.sorted { $0.dayKey < $1.dayKey }
            let data = try JSONEncoder().encode(File(schemaVersion: Self.schemaVersion, records: sorted))
            try store.write(data, named: Self.fileName)
            isDirty = false
        } catch {
            logger.error("Could not write \(Self.fileName, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Uses the time of the last attempt, so a failing disk is retried at the normal pace.
    private func flushIfDue() {
        guard clock.monotonic() - lastFlushAttempt >= ReportRules.flushIntervalSeconds else { return }
        flush()
    }

    private func load() {
        do {
            guard let data = try store.read(Self.fileName) else { return }
            let file = try JSONDecoder().decode(File.self, from: data)
            guard file.schemaVersion == Self.schemaVersion else {
                throw LoadError.unsupportedSchema(file.schemaVersion)
            }
            records = Dictionary(file.records.map { ($0.dayKey, $0) }) { _, later in later }
            pruneExpired()
        } catch {
            logger.error("Could not load \(Self.fileName, privacy: .public): \(String(describing: error), privacy: .public)")
            quarantineFile()
        }
    }

    /// Moves the unusable file aside. While that fails it is still the live file, so `flush`
    /// keeps the new data in memory and tries again rather than replacing it.
    private func quarantineFile() {
        do {
            try store.quarantine(Self.fileName)
            hasBadFile = false
        } catch {
            hasBadFile = true
            logger.error("Could not quarantine \(Self.fileName, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func pruneExpired() {
        let calendar = clock.calendar
        guard let cutoff = calendar.date(byAdding: .day, value: -ReportRules.retentionDays, to: clock.now()) else { return }
        // Day keys are zero-padded, so they sort as dates.
        let oldestKept = DayKey.day(for: cutoff, calendar: calendar)
        guard records.keys.contains(where: { $0 < oldestKept }) else { return }
        records = records.filter { $0.key >= oldestKept }
        isDirty = true
    }
}
