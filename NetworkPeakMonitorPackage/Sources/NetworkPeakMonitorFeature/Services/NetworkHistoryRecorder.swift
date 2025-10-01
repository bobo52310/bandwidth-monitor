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
        createInitialHourlyAggregates()

        // Immediately initialize current hour data for 24-hour chart display
        checkForHourlyAggregation()

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

        // Trigger immediate update of current hour aggregate for 24-hour chart responsiveness
        let calendar = Calendar.current
        let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let currentHourData = oneHourData.filter { point in
            guard let hourInterval = calendar.dateInterval(of: .hour, for: currentHour) else { return false }
            return hourInterval.contains(point.timestamp)
        }
        if !currentHourData.isEmpty {
            updateCurrentHourAggregate(for: currentHour, with: currentHourData)
        }
    }

    private func shouldRecordNewDataPoint(at date: Date) -> Bool {
        guard let lastTime = lastRecordTime else { return true }
        return date.timeIntervalSince(lastTime) >= oneHourInterval
    }

    private func createInitialHourlyAggregates() {
        guard !oneHourData.isEmpty else { return }

        let calendar = Calendar.current
        let now = Date()

        // Group existing one-hour data by hour
        let hourGroups = Dictionary(grouping: oneHourData) { dataPoint in
            calendar.dateInterval(of: .hour, for: dataPoint.timestamp)?.start ?? dataPoint.timestamp
        }

        // Create hourly aggregates for each hour that has data
        for (hourStart, hourData) in hourGroups {
            // Skip if we already have an aggregate for this hour
            if twentyFourHourData.contains(where: { calendar.isDate($0.timestamp, equalTo: hourStart, toGranularity: .hour) }) {
                continue
            }

            let avgDownload = hourData.map { $0.downloadSpeed }.reduce(0, +) / Double(hourData.count)
            let avgUpload = hourData.map { $0.uploadSpeed }.reduce(0, +) / Double(hourData.count)
            let maxDownload = hourData.map { $0.downloadSpeed }.max() ?? 0
            let maxUpload = hourData.map { $0.uploadSpeed }.max() ?? 0

            let hourlyPoint = HourlyDataPoint(
                timestamp: hourStart,
                avgDownloadSpeed: avgDownload,
                avgUploadSpeed: avgUpload,
                maxDownloadSpeed: maxDownload,
                maxUploadSpeed: maxUpload
            )

            twentyFourHourData.append(hourlyPoint)
        }

        // Sort by timestamp and keep only last 24 hours
        twentyFourHourData.sort { $0.timestamp < $1.timestamp }
        let twentyFourHoursAgo = now.addingTimeInterval(-24 * 3600)
        twentyFourHourData = twentyFourHourData.filter { $0.timestamp > twentyFourHoursAgo }

        if twentyFourHourData.count > maxTwentyFourHourPoints {
            twentyFourHourData.removeFirst(twentyFourHourData.count - maxTwentyFourHourPoints)
        }

        saveTwentyFourHourData()
    }

    private func startHourlyAggregation() {
        // Check every 10 seconds to update current hour aggregate for better 24-hour chart responsiveness
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkForHourlyAggregation()
        }
    }

    private func checkForHourlyAggregation() {
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now

        // Group all one-hour data by hour
        let hourGroups = Dictionary(grouping: oneHourData) { dataPoint in
            calendar.dateInterval(of: .hour, for: dataPoint.timestamp)?.start ?? dataPoint.timestamp
        }

        // Process each hour that has data
        for (hourStart, hourData) in hourGroups {
            // Check if this is a completed hour (not current hour) that hasn't been aggregated yet
            let isCompletedHour = hourStart < currentHour
            let alreadyExists = twentyFourHourData.contains { calendar.isDate($0.timestamp, equalTo: hourStart, toGranularity: .hour) }

            if isCompletedHour && !alreadyExists {
                // Aggregate completed hour
                aggregateHourlyData(for: hourStart, with: hourData)
            } else if hourStart == currentHour && !hourData.isEmpty {
                // Always update current hour aggregate (partial data) for immediate 24-hour chart display
                updateCurrentHourAggregate(for: hourStart, with: hourData)
            }
        }

        // If no data exists for current hour yet, create an initial aggregate to show in 24-hour chart
        if !hourGroups.keys.contains(currentHour) && !twentyFourHourData.contains(where: { calendar.isDate($0.timestamp, equalTo: currentHour, toGranularity: .hour) }) {
            // Create initial zero-value aggregate for current hour
            let initialHourlyPoint = HourlyDataPoint(
                timestamp: currentHour,
                avgDownloadSpeed: 0.0,
                avgUploadSpeed: 0.0,
                maxDownloadSpeed: 0.0,
                maxUploadSpeed: 0.0
            )
            twentyFourHourData.append(initialHourlyPoint)
            saveTwentyFourHourData()
        }

        // Also handle legacy currentHourData if it exists
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

    private func aggregateHourlyData(for hour: Date, with hourData: [NetworkDataPoint]) {
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

        // Sort by timestamp
        twentyFourHourData.sort { $0.timestamp < $1.timestamp }

        // Limit to max points
        if twentyFourHourData.count > maxTwentyFourHourPoints {
            twentyFourHourData.removeFirst(twentyFourHourData.count - maxTwentyFourHourPoints)
        }

        saveTwentyFourHourData()
    }

    private func updateCurrentHourAggregate(for hour: Date, with hourData: [NetworkDataPoint]) {
        guard !hourData.isEmpty else { return }

        let calendar = Calendar.current

        // Remove existing aggregate for this hour
        twentyFourHourData.removeAll { calendar.isDate($0.timestamp, equalTo: hour, toGranularity: .hour) }

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

        // Add updated aggregate to 24-hour data
        twentyFourHourData.append(hourlyPoint)

        // Keep only last 24 hours
        let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 3600)
        twentyFourHourData = twentyFourHourData.filter { $0.timestamp > twentyFourHoursAgo }

        // Sort by timestamp
        twentyFourHourData.sort { $0.timestamp < $1.timestamp }

        // Limit to max points
        if twentyFourHourData.count > maxTwentyFourHourPoints {
            twentyFourHourData.removeFirst(twentyFourHourData.count - maxTwentyFourHourPoints)
        }

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