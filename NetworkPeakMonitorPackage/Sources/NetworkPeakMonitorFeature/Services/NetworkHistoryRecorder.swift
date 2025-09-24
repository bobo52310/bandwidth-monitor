import Foundation
import Combine

public class NetworkHistoryRecorder: ObservableObject {
    @Published public private(set) var oneHourData: [NetworkDataPoint] = []
    @Published public private(set) var twentyFourHourData: [HourlyDataPoint] = []

    private let userDefaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    // Store data points every 10 seconds for 1-hour view (360 points max)
    private let oneHourInterval: TimeInterval = 10.0
    private let maxOneHourPoints = 360 // 1 hour = 3600 seconds / 10 seconds

    // Store hourly aggregates for 24-hour view (24 points max)
    private let maxTwentyFourHourPoints = 24

    private var lastRecordTime: Date?
    private var currentHourData: [NetworkDataPoint] = []

    public init() {
        loadStoredData()
        startHourlyAggregation()
    }

    public func recordSpeed(_ speed: NetworkSpeed) {
        let now = Date()
        let dataPoint = NetworkDataPoint(
            timestamp: now,
            downloadSpeed: speed.downloadSpeed,
            uploadSpeed: speed.uploadSpeed
        )

        // Check if we should record a new 10-second data point
        if shouldRecordNewDataPoint(at: now) {
            // Add to one hour data
            oneHourData.append(dataPoint)

            // Keep only last hour of data
            let oneHourAgo = now.addingTimeInterval(-3600)
            oneHourData = oneHourData.filter { $0.timestamp > oneHourAgo }

            // Limit to max points
            if oneHourData.count > maxOneHourPoints {
                oneHourData.removeFirst(oneHourData.count - maxOneHourPoints)
            }

            // Add to current hour accumulator
            currentHourData.append(dataPoint)

            lastRecordTime = now
            saveOneHourData()
        }

        // Always add to current hour data for accurate hourly aggregation
        if !currentHourData.contains(where: { abs($0.timestamp.timeIntervalSince(now)) < 1.0 }) {
            currentHourData.append(dataPoint)
        }
    }

    private func shouldRecordNewDataPoint(at date: Date) -> Bool {
        guard let lastTime = lastRecordTime else { return true }
        return date.timeIntervalSince(lastTime) >= oneHourInterval
    }

    private func startHourlyAggregation() {
        // Check every minute if we need to create a new hourly aggregate
        Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.checkForHourlyAggregation()
        }
    }

    private func checkForHourlyAggregation() {
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now

        // Check if we have data for the previous hour that hasn't been aggregated
        if !currentHourData.isEmpty {
            let oldestData = currentHourData.min(by: { $0.timestamp < $1.timestamp })?.timestamp ?? now
            let dataHour = calendar.dateInterval(of: .hour, for: oldestData)?.start ?? oldestData

            // If the data is from a previous hour, aggregate it
            if dataHour < currentHour {
                aggregateHourlyData(for: dataHour)
            }
        }
    }

    private func aggregateHourlyData(for hour: Date) {
        let calendar = Calendar.current
        let hourInterval = calendar.dateInterval(of: .hour, for: hour)!

        let hourData = currentHourData.filter { hourInterval.contains($0.timestamp) }
        guard !hourData.isEmpty else { return }

        let avgDownload = hourData.map { $0.downloadSpeed }.reduce(0, +) / Double(hourData.count)
        let avgUpload = hourData.map { $0.uploadSpeed }.reduce(0, +) / Double(hourData.count)
        let maxDownload = hourData.map { $0.downloadSpeed }.max() ?? 0
        let maxUpload = hourData.map { $0.uploadSpeed }.max() ?? 0

        let hourlyPoint = HourlyDataPoint(
            timestamp: hour,
            avgDownloadSpeed: avgDownload,
            avgUploadSpeed: avgUpload,
            maxDownloadSpeed: maxDownload,
            maxUploadSpeed: maxUpload
        )

        // Add to 24-hour data
        twentyFourHourData.append(hourlyPoint)

        // Keep only last 24 hours
        let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 3600)
        twentyFourHourData = twentyFourHourData.filter { $0.timestamp > twentyFourHoursAgo }

        // Limit to max points
        if twentyFourHourData.count > maxTwentyFourHourPoints {
            twentyFourHourData.removeFirst(twentyFourHourData.count - maxTwentyFourHourPoints)
        }

        // Remove aggregated data from current hour accumulator
        currentHourData = currentHourData.filter { !hourInterval.contains($0.timestamp) }

        saveTwentyFourHourData()
    }

    public func clearHistory() {
        oneHourData.removeAll()
        twentyFourHourData.removeAll()
        currentHourData.removeAll()
        lastRecordTime = nil

        userDefaults.removeObject(forKey: "networkHistory_oneHour")
        userDefaults.removeObject(forKey: "networkHistory_twentyFourHour")
        userDefaults.removeObject(forKey: "networkHistory_lastRecordTime")
    }

    // MARK: - Persistence

    private func saveOneHourData() {
        if let encoded = try? JSONEncoder().encode(oneHourData) {
            userDefaults.set(encoded, forKey: "networkHistory_oneHour")
        }
        userDefaults.set(lastRecordTime, forKey: "networkHistory_lastRecordTime")
    }

    private func saveTwentyFourHourData() {
        if let encoded = try? JSONEncoder().encode(twentyFourHourData) {
            userDefaults.set(encoded, forKey: "networkHistory_twentyFourHour")
        }
    }

    private func loadStoredData() {
        // Load one hour data
        if let data = userDefaults.data(forKey: "networkHistory_oneHour"),
           let decoded = try? JSONDecoder().decode([NetworkDataPoint].self, from: data) {
            // Filter out old data (older than 1 hour)
            let oneHourAgo = Date().addingTimeInterval(-3600)
            oneHourData = decoded.filter { $0.timestamp > oneHourAgo }
        }

        // Load twenty-four hour data
        if let data = userDefaults.data(forKey: "networkHistory_twentyFourHour"),
           let decoded = try? JSONDecoder().decode([HourlyDataPoint].self, from: data) {
            // Filter out old data (older than 24 hours)
            let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 3600)
            twentyFourHourData = decoded.filter { $0.timestamp > twentyFourHoursAgo }
        }

        // Load last record time
        lastRecordTime = userDefaults.object(forKey: "networkHistory_lastRecordTime") as? Date
    }
}