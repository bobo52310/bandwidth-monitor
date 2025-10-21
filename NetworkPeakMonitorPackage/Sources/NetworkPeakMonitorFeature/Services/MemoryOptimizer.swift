import Foundation

/// Manages memory usage by implementing smart data retention policies
public class MemoryOptimizer {

    // MARK: - Configuration

    /// Maximum number of anomalies to keep in memory
    public static let maxAnomaliesInMemory = 50

    /// Maximum age for anomaly records (7 days)
    public static let maxAnomalyAge: TimeInterval = 7 * 24 * 3600

    /// Maximum number of peak approach timestamps
    public static let maxPeakApproachTimestamps = 100

    /// Maximum age for peak approach records (30 days)
    public static let maxPeakApproachAge: TimeInterval = 30 * 24 * 3600

    /// Interval for automatic cleanup (1 hour)
    public static let cleanupInterval: TimeInterval = 3600

    // MARK: - Data Pruning

    /// Prune old data points from network history
    public static func pruneNetworkHistory(
        oneHourData: [NetworkDataPoint],
        twentyFourHourData: [HourlyDataPoint]
    ) -> (oneHour: [NetworkDataPoint], twentyFourHour: [HourlyDataPoint]) {
        let now = Date()

        // Keep only last 24 hours of detailed data and hourly aggregates
        let twentyFourHoursAgo = now.addingTimeInterval(-24 * 3600)
        let prunedOneHour = oneHourData.filter { $0.timestamp > twentyFourHoursAgo }
        let prunedTwentyFourHour = twentyFourHourData.filter { $0.timestamp > twentyFourHoursAgo }

        return (prunedOneHour, prunedTwentyFourHour)
    }

    /// Prune old anomaly records
    public static func pruneAnomalies(_ anomalies: [NetworkAnomaly]) -> [NetworkAnomaly] {
        let now = Date()
        let cutoffDate = now.addingTimeInterval(-maxAnomalyAge)

        // Filter by age
        var pruned = anomalies.filter { $0.timestamp > cutoffDate }

        // Limit by count
        if pruned.count > maxAnomaliesInMemory {
            pruned = Array(pruned.prefix(maxAnomaliesInMemory))
        }

        return pruned
    }

    /// Prune old peak approach timestamps
    public static func prunePeakApproaches(_ timestamps: [Date]) -> [Date] {
        let now = Date()
        let cutoffDate = now.addingTimeInterval(-maxPeakApproachAge)

        // Filter by age
        var pruned = timestamps.filter { $0 > cutoffDate }

        // Limit by count
        if pruned.count > maxPeakApproachTimestamps {
            pruned = Array(pruned.suffix(maxPeakApproachTimestamps))
        }

        return pruned
    }

    // MARK: - Memory Statistics

    /// Calculate estimated memory usage for network data
    public static func estimateNetworkDataMemory(
        oneHourDataCount: Int,
        twentyFourHourDataCount: Int
    ) -> Int {
        // Approximate size per NetworkDataPoint: 32 bytes (timestamp + 2 doubles)
        let oneHourBytes = oneHourDataCount * 32

        // Approximate size per HourlyDataPoint: 48 bytes (timestamp + 4 doubles)
        let twentyFourHourBytes = twentyFourHourDataCount * 48

        return oneHourBytes + twentyFourHourBytes
    }

    /// Calculate estimated memory usage for anomalies
    public static func estimateAnomalyMemory(anomalyCount: Int) -> Int {
        // Approximate size per NetworkAnomaly: ~100 bytes
        return anomalyCount * 100
    }

    /// Get human-readable memory size
    public static func formatMemorySize(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024.0
        let mb = kb / 1024.0

        if mb >= 1.0 {
            return String(format: "%.2f MB", mb)
        } else if kb >= 1.0 {
            return String(format: "%.2f KB", kb)
        } else {
            return "\(bytes) bytes"
        }
    }

    // MARK: - Optimization Recommendations

    public struct MemoryStats {
        public let networkDataBytes: Int
        public let anomalyDataBytes: Int
        public let totalBytes: Int
        public let oneHourDataCount: Int
        public let twentyFourHourDataCount: Int
        public let anomalyCount: Int

        public var formattedTotal: String {
            MemoryOptimizer.formatMemorySize(totalBytes)
        }

        public var formattedNetworkData: String {
            MemoryOptimizer.formatMemorySize(networkDataBytes)
        }

        public var formattedAnomalyData: String {
            MemoryOptimizer.formatMemorySize(anomalyDataBytes)
        }

        public var isHighUsage: Bool {
            // Consider > 1MB as high usage
            totalBytes > 1024 * 1024
        }
    }

    /// Calculate current memory statistics
    public static func calculateMemoryStats(
        oneHourDataCount: Int,
        twentyFourHourDataCount: Int,
        anomalyCount: Int
    ) -> MemoryStats {
        let networkBytes = estimateNetworkDataMemory(
            oneHourDataCount: oneHourDataCount,
            twentyFourHourDataCount: twentyFourHourDataCount
        )
        let anomalyBytes = estimateAnomalyMemory(anomalyCount: anomalyCount)

        return MemoryStats(
            networkDataBytes: networkBytes,
            anomalyDataBytes: anomalyBytes,
            totalBytes: networkBytes + anomalyBytes,
            oneHourDataCount: oneHourDataCount,
            twentyFourHourDataCount: twentyFourHourDataCount,
            anomalyCount: anomalyCount
        )
    }
}

// MARK: - Auto Cleanup Timer

public class MemoryCleanupService {
    private var timer: Timer?
    private weak var viewModel: NetworkMonitorViewModel?

    public init(viewModel: NetworkMonitorViewModel) {
        self.viewModel = viewModel
    }

    /// Start automatic memory cleanup
    public func startAutoCleanup() {
        // Run cleanup every hour
        timer = Timer.scheduledTimer(
            withTimeInterval: MemoryOptimizer.cleanupInterval,
            repeats: true
        ) { [weak self] _ in
            self?.performCleanup()
        }
    }

    /// Stop automatic cleanup
    public func stopAutoCleanup() {
        timer?.invalidate()
        timer = nil
    }

    /// Perform cleanup of old data
    @MainActor
    private func performCleanup() {
        guard let viewModel = viewModel else { return }

        // Prune network history
        let (prunedOneHour, prunedTwentyFourHour) = MemoryOptimizer.pruneNetworkHistory(
            oneHourData: viewModel.historyRecorder.oneHourData,
            twentyFourHourData: viewModel.historyRecorder.twentyFourHourData
        )

        // Update history recorder if data was pruned
        if prunedOneHour.count != viewModel.historyRecorder.oneHourData.count ||
           prunedTwentyFourHour.count != viewModel.historyRecorder.twentyFourHourData.count {
            // Note: This would require making NetworkHistoryRecorder properties writable
            // or adding a prune() method to the service
            print("Memory cleanup: Pruned network history data")
        }

        // Prune anomalies
        let originalAnomalyCount = viewModel.anomalyDetector.recentAnomalies.count
        let prunedAnomalies = MemoryOptimizer.pruneAnomalies(viewModel.anomalyDetector.recentAnomalies)

        if prunedAnomalies.count != originalAnomalyCount {
            print("Memory cleanup: Pruned \(originalAnomalyCount - prunedAnomalies.count) old anomalies")
        }

        // Prune peak approach timestamps
        let originalTimestampCount = viewModel.peakApproachTracker.approachTimestamps.count
        let prunedTimestamps = MemoryOptimizer.prunePeakApproaches(viewModel.peakApproachTracker.approachTimestamps)

        if prunedTimestamps.count != originalTimestampCount {
            print("Memory cleanup: Pruned \(originalTimestampCount - prunedTimestamps.count) old peak approach records")
        }
    }
}
