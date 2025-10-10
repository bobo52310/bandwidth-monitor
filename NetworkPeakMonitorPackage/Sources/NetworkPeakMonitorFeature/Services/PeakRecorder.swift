import Foundation
import Combine

public class PeakRecorder: ObservableObject {
    @Published public var todayPeakDownload: Double = 0
    @Published public var todayPeakUpload: Double = 0
    @Published public var allTimePeakDownload: Double = 0
    @Published public var allTimePeakUpload: Double = 0
    @Published public var hourlyPeakDownload: Double = 0
    @Published public var hourlyPeakUpload: Double = 0
    @Published public var hourlyPeakDownloadTime: Date?
    @Published public var hourlyPeakUploadTime: Date?
    @Published public var todayPeakDownloadTime: Date?
    @Published public var todayPeakUploadTime: Date?
    @Published public var allTimePeakDownloadTime: Date?
    @Published public var allTimePeakUploadTime: Date?

    private let userDefaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    private var speedHistory: [(speed: NetworkSpeed, timestamp: Date)] = []

    public init() {
        loadPeakData()
    }

    public func recordSpeed(_ speed: NetworkSpeed) {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let lastRecordDate = userDefaults.object(forKey: "lastRecordDate") as? Date ?? Date.distantPast

        // Add to speed history
        speedHistory.append((speed: speed, timestamp: now))

        // Clean old entries (keep only last hour)
        let oneHourAgo = now.addingTimeInterval(-3600)
        speedHistory = speedHistory.filter { $0.timestamp > oneHourAgo }

        // Update hourly peaks
        updateHourlyPeaks()

        // Reset today's peaks if it's a new day
        if !Calendar.current.isDate(lastRecordDate, inSameDayAs: today) {
            todayPeakDownload = 0
            todayPeakUpload = 0
            todayPeakDownloadTime = nil
            todayPeakUploadTime = nil
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
        let today = Calendar.current.startOfDay(for: Date())
        let lastRecordDate = userDefaults.object(forKey: "lastRecordDate") as? Date ?? Date.distantPast

        // Load all-time peaks
        allTimePeakDownload = userDefaults.double(forKey: "allTimePeakDownload")
        allTimePeakUpload = userDefaults.double(forKey: "allTimePeakUpload")
        allTimePeakDownloadTime = userDefaults.object(forKey: "allTimePeakDownloadTime") as? Date
        allTimePeakUploadTime = userDefaults.object(forKey: "allTimePeakUploadTime") as? Date

        // Load today's peaks if it's the same day
        if Calendar.current.isDate(lastRecordDate, inSameDayAs: today) {
            todayPeakDownload = userDefaults.double(forKey: "todayPeakDownload")
            todayPeakUpload = userDefaults.double(forKey: "todayPeakUpload")
            todayPeakDownloadTime = userDefaults.object(forKey: "todayPeakDownloadTime") as? Date
            todayPeakUploadTime = userDefaults.object(forKey: "todayPeakUploadTime") as? Date
        } else {
            // Reset today's peaks for new day
            todayPeakDownload = 0
            todayPeakUpload = 0
            todayPeakDownloadTime = nil
            todayPeakUploadTime = nil
            userDefaults.set(today, forKey: "lastRecordDate")
        }
    }
}