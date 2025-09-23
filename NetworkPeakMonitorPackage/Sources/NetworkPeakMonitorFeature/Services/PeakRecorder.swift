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
            userDefaults.set(today, forKey: "lastRecordDate")
        }

        // Update today's peaks
        if speed.downloadMbps > todayPeakDownload {
            todayPeakDownload = speed.downloadMbps
            userDefaults.set(todayPeakDownload, forKey: "todayPeakDownload")
        }

        if speed.uploadMbps > todayPeakUpload {
            todayPeakUpload = speed.uploadMbps
            userDefaults.set(todayPeakUpload, forKey: "todayPeakUpload")
        }

        // Update all-time peaks
        if speed.downloadMbps > allTimePeakDownload {
            allTimePeakDownload = speed.downloadMbps
            userDefaults.set(allTimePeakDownload, forKey: "allTimePeakDownload")
        }

        if speed.uploadMbps > allTimePeakUpload {
            allTimePeakUpload = speed.uploadMbps
            userDefaults.set(allTimePeakUpload, forKey: "allTimePeakUpload")
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
        speedHistory.removeAll()

        userDefaults.removeObject(forKey: "todayPeakDownload")
        userDefaults.removeObject(forKey: "todayPeakUpload")
        userDefaults.removeObject(forKey: "allTimePeakDownload")
        userDefaults.removeObject(forKey: "allTimePeakUpload")
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

        // Load today's peaks if it's the same day
        if Calendar.current.isDate(lastRecordDate, inSameDayAs: today) {
            todayPeakDownload = userDefaults.double(forKey: "todayPeakDownload")
            todayPeakUpload = userDefaults.double(forKey: "todayPeakUpload")
        } else {
            // Reset today's peaks for new day
            todayPeakDownload = 0
            todayPeakUpload = 0
            userDefaults.set(today, forKey: "lastRecordDate")
        }
    }
}