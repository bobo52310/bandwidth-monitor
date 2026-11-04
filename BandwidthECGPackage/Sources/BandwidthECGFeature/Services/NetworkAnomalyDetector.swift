import Foundation
import Observation

/// Detects network anomalies: finished connection drops, speed drops while the connection is
/// failing, and a dead link that reads zero.
///
/// The connection state comes from `updateConnectivity` (the network path and the latency
/// probe), never from the timing of the samples (CORE-10). A sleep or a stalled timer is not
/// an outage, and ordinary traffic (a download ending, chunked streaming, an idle link) is not
/// an anomaly (CORE-22).
@MainActor
@Observable
public class NetworkAnomalyDetector {
    /// A speed drop lasts this many samples in a row before it can count.
    static let dropSamples = 5
    /// Zero speed with the path down lasts this many samples in a row before it counts.
    static let zeroSpeedSamples = 30
    /// Samples further apart than this are not "in a row", as for the sustained peak (R14).
    static let maxSampleGapSeconds: TimeInterval = 2.5

    public var recentAnomalies: [NetworkAnomaly] = []
    /// The path is up and the latency probe has not failed twice in a row.
    public private(set) var isConnectionStable: Bool = true
    public var isDetectionEnabled: Bool {
        didSet {
            defaults.set(isDetectionEnabled, forKey: "anomalyDetectionEnabled")
        }
    }

    private let defaults: UserDefaults
    private let clock: AppClock

    // Configuration
    private let maxAnomalyHistory = 50
    private let speedFluctuationThreshold: Double = 0.7 // below 70% of the recent average
    private let minSamplesForAnalysis = 5
    private let speedHistoryLimit = 10

    // Analysis state
    @ObservationIgnored private var isPathSatisfied = true
    @ObservationIgnored private var recentSpeeds: [(download: Double, upload: Double)] = []
    @ObservationIgnored private var lastSampleTime: TimeInterval?
    @ObservationIgnored private var downloadDrop = DropStreak()
    @ObservationIgnored private var uploadDrop = DropStreak()
    @ObservationIgnored private var zeroSpeedStreak = 0

    /// Samples in a row below the threshold in one direction.
    private struct DropStreak {
        var samples = 0
        /// The average the drop is measured from: the one before its first sample.
        var fromMbps: Double = 0
        var isRecorded = false
    }

    public init(defaults: UserDefaults = .standard, clock: AppClock = .live) {
        self.defaults = defaults
        self.clock = clock
        self.isDetectionEnabled = defaults.object(forKey: "anomalyDetectionEnabled") as? Bool ?? true
    }

    /// The connection state behind "stable" and behind the zero-speed and drop checks.
    public func updateConnectivity(pathSatisfied: Bool, probeFailures: Int) {
        isPathSatisfied = pathSatisfied
        let stable = pathSatisfied && probeFailures < DisconnectTracker.probeFailuresForOutage
        if stable != isConnectionStable {
            isConnectionStable = stable
        }
    }

    /// A finished outage reported by `DisconnectTracker`. Each one is recorded, even two
    /// within a minute, so the count matches the disconnect record.
    public func recordConnectionDrop(duration: TimeInterval) {
        guard isDetectionEnabled else { return }
        recordAnomaly(.connectionDrop(duration: duration))
    }

    /// Analyze network speed for anomalies
    public func analyzeSpeed(_ speed: NetworkSpeed) {
        guard isDetectionEnabled else { return }

        // After a gap (sleep, a stalled timer) the samples before it say nothing about now.
        let now = clock.monotonic()
        if let lastSampleTime, now - lastSampleTime > Self.maxSampleGapSeconds {
            recentSpeeds.removeAll()
            downloadDrop = DropStreak()
            uploadDrop = DropStreak()
            zeroSpeedStreak = 0
        }
        lastSampleTime = now

        checkZeroSpeed(speed)

        if recentSpeeds.count >= minSamplesForAnalysis {
            let count = Double(recentSpeeds.count)
            let downloadAverage = recentSpeeds.map { $0.download }.reduce(0, +) / count
            let uploadAverage = recentSpeeds.map { $0.upload }.reduce(0, +) / count
            if let drop = advance(&downloadDrop, speed: speed.downloadMbps, average: downloadAverage) {
                recordSpeedDrop(.download, from: drop.from, to: drop.to)
            }
            if let drop = advance(&uploadDrop, speed: speed.uploadMbps, average: uploadAverage) {
                recordSpeedDrop(.upload, from: drop.from, to: drop.to)
            }
        }

        recentSpeeds.append((download: speed.downloadMbps, upload: speed.uploadMbps))
        if recentSpeeds.count > speedHistoryLimit {
            recentSpeeds.removeFirst()
        }
    }

    /// Zero both ways is only a dead link when the path is down too: an idle Mac reads exactly
    /// zero in many seconds.
    private func checkZeroSpeed(_ speed: NetworkSpeed) {
        guard !isPathSatisfied, speed.downloadMbps == 0, speed.uploadMbps == 0 else {
            zeroSpeedStreak = 0
            return
        }
        zeroSpeedStreak += 1
        if zeroSpeedStreak == Self.zeroSpeedSamples {
            recordAnomaly(.zeroSpeed)
        }
    }

    /// Moves one direction's streak on by a sample and returns the drop to record, if any.
    /// A drop needs `dropSamples` in a row below the threshold while the connection is failing;
    /// with the connection fine it is just traffic ending.
    private func advance(_ streak: inout DropStreak, speed: Double, average: Double) -> (from: Double, to: Double)? {
        // Skip if the average is too low (not enough activity to detect a drop)
        guard average > 1.0, speed < average * speedFluctuationThreshold else {
            streak = DropStreak()
            return nil
        }
        if streak.samples == 0 {
            streak.fromMbps = average
        }
        streak.samples += 1
        guard streak.samples >= Self.dropSamples, !isConnectionStable, !streak.isRecorded else {
            return nil
        }
        streak.isRecorded = true
        return (streak.fromMbps, speed)
    }

    private func recordSpeedDrop(_ direction: NetworkAnomaly.AnomalyType.Direction, from: Double, to: Double) {
        recordAnomaly(.speedDrop(
            direction: direction,
            fromSpeed: from,
            toSpeed: to,
            dropPercentage: (from - to) / from * 100
        ))
    }

    /// Record an anomaly
    private func recordAnomaly(_ type: NetworkAnomaly.AnomalyType) {
        let now = clock.now()
        // A speed or zero-speed anomaly like one in the last minute is the same episode.
        // Connection drops are finished outages and always count.
        if case .connectionDrop = type {} else {
            let recentSimilarAnomaly = recentAnomalies.first { anomaly in
                anomaly.type.isSimilar(to: type) &&
                now.timeIntervalSince(anomaly.timestamp) < 60 // Within last minute
            }
            guard recentSimilarAnomaly == nil else { return }
        }

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

    /// Get formatted anomaly summary
    public func getAnomalySummary(for period: TimeInterval = 3600) -> AnomalySummary {
        let cutoffTime = clock.now().addingTimeInterval(-period)
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
                case .download: return L10n.anomalyDownload
                case .upload: return L10n.anomalyUpload
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
                return L10n.anomalyConnectionDrop(String(format: "%.1f", duration))
            case .speedDrop(let direction, let from, let to, let percentage):
                return L10n.anomalySpeedDrop(
                    direction.displayName,
                    String(format: "%.0f", percentage),
                    String(format: "%.1f", from),
                    String(format: "%.1f", to)
                )
            case .zeroSpeed:
                return L10n.anomalyZeroSpeed
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
