import Foundation
import Combine

public class PeakApproachTracker: ObservableObject {
    @Published public var todayApproachCount: Int = 0
    @Published public var approachTimestamps: [Date] = []

    private let userDefaults = UserDefaults.standard
    private let approachThreshold: Double = 0.8 // 80% of plan speed

    public init() {
        loadApproachData()
    }

    public func checkForApproach(_ speed: NetworkSpeed, downloadPlanSpeed: Double, uploadPlanSpeed: Double) {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let lastRecordDate = userDefaults.object(forKey: "lastApproachRecordDate") as? Date ?? Date.distantPast

        // Reset approach count if it's a new day
        if !Calendar.current.isDate(lastRecordDate, inSameDayAs: today) {
            todayApproachCount = 0
            approachTimestamps.removeAll()
            userDefaults.set(today, forKey: "lastApproachRecordDate")
            saveApproachData()
        }

        // Check if either download or upload approaches peak
        let downloadApproach = speed.downloadMbps >= (downloadPlanSpeed * approachThreshold)
        let uploadApproach = speed.uploadMbps >= (uploadPlanSpeed * approachThreshold)

        if downloadApproach || uploadApproach {
            // Avoid counting multiple approaches within a short time (5 minutes)
            let fiveMinutesAgo = now.addingTimeInterval(-300)
            let recentApproach = approachTimestamps.contains { $0 > fiveMinutesAgo }

            if !recentApproach {
                todayApproachCount += 1
                approachTimestamps.append(now)
                saveApproachData()
            }
        }
    }

    public func resetApproachData() {
        todayApproachCount = 0
        approachTimestamps.removeAll()

        userDefaults.removeObject(forKey: "todayApproachCount")
        userDefaults.removeObject(forKey: "approachTimestamps")
        userDefaults.removeObject(forKey: "lastApproachRecordDate")
    }

    private func saveApproachData() {
        userDefaults.set(todayApproachCount, forKey: "todayApproachCount")

        // Save timestamps as array of TimeInterval
        let timestampIntervals = approachTimestamps.map { $0.timeIntervalSince1970 }
        userDefaults.set(timestampIntervals, forKey: "approachTimestamps")
    }

    private func loadApproachData() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastRecordDate = userDefaults.object(forKey: "lastApproachRecordDate") as? Date ?? Date.distantPast

        // Load approach data if it's the same day
        if Calendar.current.isDate(lastRecordDate, inSameDayAs: today) {
            todayApproachCount = userDefaults.integer(forKey: "todayApproachCount")

            // Load timestamps
            if let timestampIntervals = userDefaults.array(forKey: "approachTimestamps") as? [Double] {
                approachTimestamps = timestampIntervals.map { Date(timeIntervalSince1970: $0) }
            }
        } else {
            // Reset for new day
            todayApproachCount = 0
            approachTimestamps.removeAll()
            userDefaults.set(today, forKey: "lastApproachRecordDate")
        }
    }

    public func getFormattedApproachTimes() -> [String] {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return approachTimestamps.map { formatter.string(from: $0) }
    }
}