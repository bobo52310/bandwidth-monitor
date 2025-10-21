import Foundation
import Combine

/// Detects network anomalies such as connection drops and unusual speed fluctuations
@MainActor
public class NetworkAnomalyDetector: ObservableObject {
    @Published public var recentAnomalies: [NetworkAnomaly] = []
    @Published public var isConnectionStable: Bool = true
    @Published public var isDetectionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isDetectionEnabled, forKey: "anomalyDetectionEnabled")
        }
    }

    // Configuration
    private let maxAnomalyHistory = 50
    private let connectionDropThreshold: TimeInterval = 5.0 // 5 seconds without data
    private let speedFluctuationThreshold: Double = 0.7 // 70% drop from average
    private let minSamplesForAnalysis = 5

    // Analysis state
    private var lastDataTimestamp: Date?
    private var recentSpeeds: [(download: Double, upload: Double)] = []
    private let speedHistoryLimit = 10

    public init() {
        self.isDetectionEnabled = UserDefaults.standard.object(forKey: "anomalyDetectionEnabled") as? Bool ?? true
    }

    /// Analyze network speed for anomalies
    public func analyzeSpeed(_ speed: NetworkSpeed) {
        guard isDetectionEnabled else { return }

        let now = Date()

        // Check for connection drop
        if let lastTimestamp = lastDataTimestamp {
            let timeSinceLastData = now.timeIntervalSince(lastTimestamp)
            if timeSinceLastData > connectionDropThreshold {
                recordAnomaly(.connectionDrop(duration: timeSinceLastData))
                isConnectionStable = false
            } else {
                isConnectionStable = true
            }
        }

        lastDataTimestamp = now

        // Add to recent speeds
        recentSpeeds.append((download: speed.downloadMbps, upload: speed.uploadMbps))
        if recentSpeeds.count > speedHistoryLimit {
            recentSpeeds.removeFirst()
        }

        // Analyze speed fluctuations
        if recentSpeeds.count >= minSamplesForAnalysis {
            analyzeSpeedFluctuations(currentSpeed: speed)
        }

        // Check for zero speed (possible disconnection)
        if speed.downloadMbps == 0 && speed.uploadMbps == 0 {
            recordAnomaly(.zeroSpeed)
        }
    }

    /// Analyze speed fluctuations
    private func analyzeSpeedFluctuations(currentSpeed: NetworkSpeed) {
        let recentDownloadAvg = recentSpeeds.map { $0.download }.reduce(0, +) / Double(recentSpeeds.count)
        let recentUploadAvg = recentSpeeds.map { $0.upload }.reduce(0, +) / Double(recentSpeeds.count)

        // Skip if average is too low (not enough activity to detect anomaly)
        guard recentDownloadAvg > 1.0 || recentUploadAvg > 1.0 else { return }

        // Check for significant download drop
        if recentDownloadAvg > 1.0 && currentSpeed.downloadMbps < recentDownloadAvg * speedFluctuationThreshold {
            let dropPercentage = ((recentDownloadAvg - currentSpeed.downloadMbps) / recentDownloadAvg) * 100
            recordAnomaly(.speedDrop(
                direction: .download,
                fromSpeed: recentDownloadAvg,
                toSpeed: currentSpeed.downloadMbps,
                dropPercentage: dropPercentage
            ))
        }

        // Check for significant upload drop
        if recentUploadAvg > 1.0 && currentSpeed.uploadMbps < recentUploadAvg * speedFluctuationThreshold {
            let dropPercentage = ((recentUploadAvg - currentSpeed.uploadMbps) / recentUploadAvg) * 100
            recordAnomaly(.speedDrop(
                direction: .upload,
                fromSpeed: recentUploadAvg,
                toSpeed: currentSpeed.uploadMbps,
                dropPercentage: dropPercentage
            ))
        }
    }

    /// Record an anomaly
    private func recordAnomaly(_ type: NetworkAnomaly.AnomalyType) {
        // Check if we already have a recent similar anomaly (avoid duplicates)
        let now = Date()
        let recentSimilarAnomaly = recentAnomalies.first { anomaly in
            anomaly.type.isSimilar(to: type) &&
            now.timeIntervalSince(anomaly.timestamp) < 60 // Within last minute
        }

        guard recentSimilarAnomaly == nil else { return }

        let anomaly = NetworkAnomaly(type: type, timestamp: now)
        recentAnomalies.insert(anomaly, at: 0)

        // Limit history
        if recentAnomalies.count > maxAnomalyHistory {
            recentAnomalies.removeLast()
        }
    }

    /// Clear all anomaly history
    public func clearHistory() {
        recentAnomalies.removeAll()
    }

    /// Prune old anomalies to optimize memory
    public func pruneOldAnomalies() {
        let now = Date()
        let maxAge: TimeInterval = 7 * 24 * 3600 // 7 days

        let beforeCount = recentAnomalies.count

        // Remove anomalies older than max age
        recentAnomalies = recentAnomalies.filter { now.timeIntervalSince($0.timestamp) < maxAge }

        // Ensure we don't exceed max count
        if recentAnomalies.count > maxAnomalyHistory {
            recentAnomalies = Array(recentAnomalies.prefix(maxAnomalyHistory))
        }

        if beforeCount != recentAnomalies.count {
            print("Pruned \(beforeCount - recentAnomalies.count) old anomalies")
        }
    }

    /// Get formatted anomaly summary
    public func getAnomalySummary(for period: TimeInterval = 3600) -> AnomalySummary {
        let cutoffTime = Date().addingTimeInterval(-period)
        let periodAnomalies = recentAnomalies.filter { $0.timestamp > cutoffTime }

        return AnomalySummary(
            totalCount: periodAnomalies.count,
            connectionDrops: periodAnomalies.filter { if case .connectionDrop = $0.type { return true }; return false }.count,
            speedDrops: periodAnomalies.filter { if case .speedDrop = $0.type { return true }; return false }.count,
            zeroSpeedEvents: periodAnomalies.filter { if case .zeroSpeed = $0.type { return true }; return false }.count
        )
    }
}

// MARK: - Models

public struct NetworkAnomaly: Identifiable {
    public let id = UUID()
    public let type: AnomalyType
    public let timestamp: Date

    public enum AnomalyType {
        case connectionDrop(duration: TimeInterval)
        case speedDrop(direction: Direction, fromSpeed: Double, toSpeed: Double, dropPercentage: Double)
        case zeroSpeed

        public enum Direction {
            case download
            case upload

            var displayName: String {
                switch self {
                case .download: return "下載"
                case .upload: return "上傳"
                }
            }
        }

        func isSimilar(to other: AnomalyType) -> Bool {
            switch (self, other) {
            case (.connectionDrop, .connectionDrop):
                return true
            case (.zeroSpeed, .zeroSpeed):
                return true
            case (.speedDrop(let dir1, _, _, _), .speedDrop(let dir2, _, _, _)):
                return dir1 == dir2
            default:
                return false
            }
        }

        public var displayText: String {
            switch self {
            case .connectionDrop(let duration):
                return "連線中斷 \(String(format: "%.1f", duration)) 秒"
            case .speedDrop(let direction, let from, let to, let percentage):
                return "\(direction.displayName)速度驟降 \(String(format: "%.0f", percentage))% (從 \(String(format: "%.1f", from)) 降至 \(String(format: "%.1f", to)) Mbps)"
            case .zeroSpeed:
                return "網路速度為零"
            }
        }

        public var icon: String {
            switch self {
            case .connectionDrop:
                return "wifi.exclamationmark"
            case .speedDrop:
                return "arrow.down.circle.fill"
            case .zeroSpeed:
                return "network.slash"
            }
        }

        public var severity: Severity {
            switch self {
            case .connectionDrop(let duration):
                return duration > 30 ? .high : .medium
            case .speedDrop(_, _, _, let percentage):
                return percentage > 80 ? .high : .medium
            case .zeroSpeed:
                return .high
            }
        }

        /// Unique key for grouping similar anomaly types
        public var typeKey: String {
            switch self {
            case .connectionDrop:
                return "connectionDrop"
            case .speedDrop(let direction, _, _, _):
                return "speedDrop_\(direction.displayName)"
            case .zeroSpeed:
                return "zeroSpeed"
            }
        }
    }

    public enum Severity {
        case low
        case medium
        case high

        var color: String {
            switch self {
            case .low: return "yellow"
            case .medium: return "orange"
            case .high: return "red"
            }
        }
    }
}

public struct AnomalySummary {
    public let totalCount: Int
    public let connectionDrops: Int
    public let speedDrops: Int
    public let zeroSpeedEvents: Int

    public var hasAnomalies: Bool {
        totalCount > 0
    }
}
