import Foundation
import SwiftUI
import Observation

/// Represents the quality of a network connection based on latency and jitter metrics.
public enum ConnectionQuality: Equatable, Sendable {
    case good
    case fair
    case poor
    case unknown

    /// Localized display name for the connection quality level.
    public var displayName: String {
        switch self {
        case .good: L10n.connectionQualityGood
        case .fair: L10n.connectionQualityFair
        case .poor: L10n.connectionQualityPoor
        case .unknown: L10n.connectionQualityUnknown
        }
    }

    /// SF Symbol icon representing the connection quality level.
    public var icon: String {
        switch self {
        case .good: "wifi"
        case .fair: "wifi.exclamationmark"
        case .poor: "wifi.slash"
        case .unknown: "questionmark.circle"
        }
    }

    /// Color representing the connection quality level.
    public var color: Color {
        switch self {
        case .good: .green
        case .fair: .orange
        case .poor: .red
        case .unknown: .gray
        }
    }
}

/// Monitors network latency by periodically sending HEAD requests and calculating
/// round-trip time, jitter, and connection quality score.
@MainActor
@Observable
public class LatencyMonitor {
    public var currentLatency: Double = 0
    public var currentJitter: Double = 0
    public var qualityScore: ConnectionQuality = .unknown
    public var isMonitoring: Bool = false

    private var timer: Timer?
    private var latencySamples: [Double] = []
    private let maxSamples = 20

    public init() {}

    // MARK: - Public API

    /// Starts periodic latency monitoring at 30-second intervals.
    public func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true

        // Perform an initial measurement immediately
        Task {
            await measureLatency()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.measureLatency()
            }
        }
    }

    /// Stops latency monitoring and invalidates the timer.
    public func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Public Calculation Methods (for testing)

    /// Calculates the connection quality score based on latency and jitter values.
    /// - Parameters:
    ///   - latency: The measured latency in milliseconds.
    ///   - jitter: The calculated jitter in milliseconds.
    /// - Returns: A `ConnectionQuality` value representing the overall connection quality.
    nonisolated public static func calculateQualityScore(latency: Double, jitter: Double) -> ConnectionQuality {
        if latency < 50 && jitter < 10 {
            return .good
        } else if latency < 100 && jitter < 30 {
            return .fair
        } else {
            return .poor
        }
    }

    /// Calculates jitter as the standard deviation of the provided latency samples.
    /// - Parameter samples: An array of latency measurements in milliseconds.
    /// - Returns: The standard deviation of the samples, or 0 if fewer than 2 samples are provided.
    nonisolated public static func calculateJitter(from samples: [Double]) -> Double {
        guard samples.count >= 2 else { return 0 }

        let mean = samples.reduce(0, +) / Double(samples.count)
        let squaredDifferences = samples.map { ($0 - mean) * ($0 - mean) }
        let variance = squaredDifferences.reduce(0, +) / Double(samples.count)
        return sqrt(variance)
    }

    // MARK: - Private

    /// Measures latency by sending an HTTP HEAD request to apple.com and recording the round-trip time.
    private func measureLatency() async {
        guard let url = URL(string: "https://www.apple.com") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10

        let startTime = Date()

        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            let latency = Date().timeIntervalSince(startTime) * 1000 // Convert to ms

            addSample(latency)
            currentLatency = latency
            currentJitter = LatencyMonitor.calculateJitter(from: latencySamples)
            qualityScore = LatencyMonitor.calculateQualityScore(latency: currentLatency, jitter: currentJitter)
        } catch {
            // On failure, don't update latency — keep last known values
        }
    }

    /// Adds a latency sample to the rolling window, removing the oldest if at capacity.
    private func addSample(_ latency: Double) {
        latencySamples.append(latency)
        if latencySamples.count > maxSamples {
            latencySamples.removeFirst()
        }
    }

}
