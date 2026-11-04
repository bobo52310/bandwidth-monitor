import Foundation
import Observation
import OSLog

public enum PeakDirection: Sendable {
    case download
    case upload
}

@Observable
public class PeakRecorder {
    public var todayPeakDownload: Double = 0
    public var todayPeakUpload: Double = 0
    public var allTimePeakDownload: Double = 0
    public var allTimePeakUpload: Double = 0
    public var hourlyPeakDownload: Double = 0
    public var hourlyPeakUpload: Double = 0
    public var hourlyPeakDownloadTime: Date?
    public var hourlyPeakUploadTime: Date?
    public var todayPeakDownloadTime: Date?
    public var todayPeakUploadTime: Date?
    public var allTimePeakDownloadTime: Date?
    public var allTimePeakUploadTime: Date?

    private let userDefaults: UserDefaults
    private let clock: AppClock
    private let logger = Logger(subsystem: "com.bandwidthecg", category: "Peaks")
    private var speedHistory: [(speed: NetworkSpeed, timestamp: Date)] = []

    public init(defaults: UserDefaults = .standard, clock: AppClock = .live) {
        self.userDefaults = defaults
        self.clock = clock
        loadPeakData()
    }

    public func recordSpeed(_ speed: NetworkSpeed) {
        guard speed.downloadMbps <= SampleGuard.maxPlausibleMbps,
              speed.uploadMbps <= SampleGuard.maxPlausibleMbps else {
            logger.warning("Ignored implausible sample: download \(speed.downloadMbps) Mbps, upload \(speed.uploadMbps) Mbps")
            return
        }

        let now = clock.now()
        let calendar = clock.calendar
        let today = calendar.startOfDay(for: now)
        let lastRecordDate = userDefaults.object(forKey: "lastRecordDate") as? Date ?? Date.distantPast

        // Add to speed history
        speedHistory.append((speed: speed, timestamp: now))

        // Clean old entries (keep only last hour)
        let oneHourAgo = now.addingTimeInterval(-3600)
        speedHistory = speedHistory.filter { $0.timestamp > oneHourAgo }

        // Update hourly peaks
        updateHourlyPeaks()

        // Reset today's peaks if it's a new day
        if !calendar.isDate(lastRecordDate, inSameDayAs: today) {
            clearTodayPeak(.download)
            clearTodayPeak(.upload)
            userDefaults.set(today, forKey: "lastRecordDate")
        }

        // Update today's peaks
        if speed.downloadMbps > todayPeakDownload {
            todayPeakDownload = speed.downloadMbps
            todayPeakDownloadTime = now
            userDefaults.set(todayPeakDownload, forKey: "todayPeakDownload")
            userDefaults.set(now, forKey: "todayPeakDownloadTime")
        }

        if speed.uploadMbps > todayPeakUpload {
            todayPeakUpload = speed.uploadMbps
            todayPeakUploadTime = now
            userDefaults.set(todayPeakUpload, forKey: "todayPeakUpload")
            userDefaults.set(now, forKey: "todayPeakUploadTime")
        }

        // Update all-time peaks
        if speed.downloadMbps > allTimePeakDownload {
            allTimePeakDownload = speed.downloadMbps
            allTimePeakDownloadTime = now
            userDefaults.set(allTimePeakDownload, forKey: "allTimePeakDownload")
            userDefaults.set(now, forKey: "allTimePeakDownloadTime")
        }

        if speed.uploadMbps > allTimePeakUpload {
            allTimePeakUpload = speed.uploadMbps
            allTimePeakUploadTime = now
            userDefaults.set(allTimePeakUpload, forKey: "allTimePeakUpload")
            userDefaults.set(now, forKey: "allTimePeakUploadTime")
        }
    }

    /// Removes one all-time peak, for example one left behind by a bad sample. A today peak with
    /// the same value came from the same sample, so it goes too.
    public func clearAllTimePeak(_ direction: PeakDirection) {
        switch direction {
        case .download:
            if todayPeakDownload == allTimePeakDownload { clearTodayPeak(.download) }
            allTimePeakDownload = 0
            allTimePeakDownloadTime = nil
            userDefaults.removeObject(forKey: "allTimePeakDownload")
            userDefaults.removeObject(forKey: "allTimePeakDownloadTime")
        case .upload:
            if todayPeakUpload == allTimePeakUpload { clearTodayPeak(.upload) }
            allTimePeakUpload = 0
            allTimePeakUploadTime = nil
            userDefaults.removeObject(forKey: "allTimePeakUpload")
            userDefaults.removeObject(forKey: "allTimePeakUploadTime")
        }
    }

    public func resetPeaks() {
        todayPeakDownload = 0
        todayPeakUpload = 0
        allTimePeakDownload = 0
        allTimePeakUpload = 0
        hourlyPeakDownload = 0
        hourlyPeakUpload = 0
        hourlyPeakDownloadTime = nil
        hourlyPeakUploadTime = nil
        todayPeakDownloadTime = nil
        todayPeakUploadTime = nil
        allTimePeakDownloadTime = nil
        allTimePeakUploadTime = nil
        speedHistory.removeAll()

        userDefaults.removeObject(forKey: "todayPeakDownload")
        userDefaults.removeObject(forKey: "todayPeakUpload")
        userDefaults.removeObject(forKey: "allTimePeakDownload")
        userDefaults.removeObject(forKey: "allTimePeakUpload")
        userDefaults.removeObject(forKey: "todayPeakDownloadTime")
        userDefaults.removeObject(forKey: "todayPeakUploadTime")
        userDefaults.removeObject(forKey: "allTimePeakDownloadTime")
        userDefaults.removeObject(forKey: "allTimePeakUploadTime")
        userDefaults.removeObject(forKey: "lastRecordDate")
    }

    private func clearTodayPeak(_ direction: PeakDirection) {
        switch direction {
        case .download:
            todayPeakDownload = 0
            todayPeakDownloadTime = nil
            userDefaults.removeObject(forKey: "todayPeakDownload")
            userDefaults.removeObject(forKey: "todayPeakDownloadTime")
        case .upload:
            todayPeakUpload = 0
            todayPeakUploadTime = nil
            userDefaults.removeObject(forKey: "todayPeakUpload")
            userDefaults.removeObject(forKey: "todayPeakUploadTime")
        }
    }

    private func updateHourlyPeaks() {
        guard !speedHistory.isEmpty else { return }

        let downloadPeak = speedHistory.max(by: { $0.speed.downloadMbps < $1.speed.downloadMbps })
        let uploadPeak = speedHistory.max(by: { $0.speed.uploadMbps < $1.speed.uploadMbps })

        if let downloadPeak = downloadPeak {
            hourlyPeakDownload = downloadPeak.speed.downloadMbps
            hourlyPeakDownloadTime = downloadPeak.timestamp
        }

        if let uploadPeak = uploadPeak {
            hourlyPeakUpload = uploadPeak.speed.uploadMbps
            hourlyPeakUploadTime = uploadPeak.timestamp
        }
    }

    private func loadPeakData() {
        let calendar = clock.calendar
        let now = clock.now()
        let today = calendar.startOfDay(for: now)
        let lastRecordDate = userDefaults.object(forKey: "lastRecordDate") as? Date ?? Date.distantPast

        (allTimePeakDownload, allTimePeakDownloadTime) = loadAllTimePeak(
            valueKey: "allTimePeakDownload", timeKey: "allTimePeakDownloadTime"
        )
        (allTimePeakUpload, allTimePeakUploadTime) = loadAllTimePeak(
            valueKey: "allTimePeakUpload", timeKey: "allTimePeakUploadTime"
        )
        (todayPeakDownload, todayPeakDownloadTime) = loadTodayPeak(
            valueKey: "todayPeakDownload", timeKey: "todayPeakDownloadTime", now: now
        )
        (todayPeakUpload, todayPeakUploadTime) = loadTodayPeak(
            valueKey: "todayPeakUpload", timeKey: "todayPeakUploadTime", now: now
        )

        // Moved forward here, or the first sample would see a new day and wipe the peaks just loaded.
        if !calendar.isDate(lastRecordDate, inSameDayAs: today) {
            userDefaults.set(today, forKey: "lastRecordDate")
        }
    }

    private func loadAllTimePeak(valueKey: String, timeKey: String) -> (peak: Double, time: Date?) {
        guard let peak = loadPlausiblePeak(valueKey: valueKey, timeKey: timeKey) else { return (0, nil) }
        return (peak, userDefaults.object(forKey: timeKey) as? Date)
    }

    /// A direction's today peak is only valid if its own time falls on today. `lastRecordDate`
    /// is shared by both directions and moves forward without either of them, so it can't tell.
    private func loadTodayPeak(valueKey: String, timeKey: String, now: Date) -> (peak: Double, time: Date?) {
        guard let peak = loadPlausiblePeak(valueKey: valueKey, timeKey: timeKey) else { return (0, nil) }
        guard let time = userDefaults.object(forKey: timeKey) as? Date,
              clock.calendar.isDate(time, inSameDayAs: now) else {
            removeStoredPeak(valueKey: valueKey, timeKey: timeKey)
            return (0, nil)
        }
        return (peak, time)
    }

    /// The stored peak, or `nil` if it can't be a real speed. Such a value is quarantined and
    /// then removed.
    private func loadPlausiblePeak(valueKey: String, timeKey: String) -> Double? {
        let peak = userDefaults.double(forKey: valueKey)
        guard peak <= SampleGuard.maxPlausibleMbps else {
            quarantinePeak(peak, valueKey: valueKey)
            logger.warning("Cleared implausible \(valueKey, privacy: .public): \(peak) Mbps")
            removeStoredPeak(valueKey: valueKey, timeKey: timeKey)
            return nil
        }
        return peak
    }

    /// Keeps a copy of a cleared value under `peakQuarantine`, as original key to value, so the
    /// original survives for diagnosis. Nothing reads it back. The first value for a key stays.
    private func quarantinePeak(_ peak: Double, valueKey: String) {
        var quarantine = userDefaults.dictionary(forKey: "peakQuarantine") ?? [:]
        guard quarantine[valueKey] == nil else { return }
        quarantine[valueKey] = peak
        userDefaults.set(quarantine, forKey: "peakQuarantine")
    }

    private func removeStoredPeak(valueKey: String, timeKey: String) {
        userDefaults.removeObject(forKey: valueKey)
        userDefaults.removeObject(forKey: timeKey)
    }
}
