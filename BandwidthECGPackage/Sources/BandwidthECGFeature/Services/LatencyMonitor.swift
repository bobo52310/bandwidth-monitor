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

/// One probe's outcome. A failed probe has no latency to report.
public enum LatencyMeasurement: Sendable, Equatable {
    case success(latencyMs: Double, jitterMs: Double)
    case failure
}

/// Measures latency every 30 seconds with an HTTPS HEAD request to apple.com.
///
/// The value is the round trip of a whole HEAD request (the server's answer included), not the
/// ICMP round trip `ping` reports, so it reads higher than `ping`. On a new connection the
/// request also carries the TLS handshake (CORE-21: 563 ms against a steady 86 ms), so the first
/// successful probe after starting, after a failure and after wake is a warm-up and is dropped.
/// With `isEnabled` off no request is sent (D11).
@MainActor
@Observable
public class LatencyMonitor {
    public static let enabledKey = "latencyMonitoringEnabled"
    public static let probeInterval: TimeInterval = 30

    public var currentLatency: Double = 0
    /// The spread of the samples in the window. `nil` until there are two of them: one sample
    /// has no spread, and showing 0.0 ms would claim a perfectly steady line.
    public var currentJitter: Double?
    public var qualityScore: ConnectionQuality = .unknown
    /// Whether probes are being sent right now.
    public private(set) var isMonitoring: Bool = false
    /// The user's switch. Off stops the probes and clears what is shown; on resumes them if
    /// the app had started monitoring.
    public var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled {
                if isRequested { beginMonitoring() }
            } else {
                endMonitoring()
                clearMeasurement()
                latencySamples.removeAll()
                consecutiveFailures = 0
                needsWarmup = true
            }
            onEnabledChange?(isEnabled)
        }
    }
    /// False until a real (not warm-up) probe has succeeded, and again after a failure.
    public private(set) var hasMeasurement: Bool = false
    /// Failed probes in a row. A success resets it; a warm-up proves nothing either way.
    public private(set) var consecutiveFailures: Int = 0
    /// Called after every probe that counts, so a consumer can see all of them rather than
    /// the latest values. Warm-ups and probes that outlived a stop are not reported.
    public var onMeasurement: ((LatencyMeasurement) -> Void)?
    /// Called when `isEnabled` changes.
    public var onEnabledChange: ((Bool) -> Void)?

    private let defaults: UserDefaults
    private let clock: AppClock
    private let probe: any LatencyProbe

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    /// The rolling window behind the jitter. Internal so tests can read it.
    private(set) var latencySamples: [Double] = []
    private let maxSamples = 20
    /// The app asked for monitoring; `isEnabled` decides whether it actually runs.
    @ObservationIgnored private var isRequested = false
    /// The next successful probe opens a new connection and is not recorded.
    @ObservationIgnored private var needsWarmup = true
    /// Bumped whenever monitoring stops, so a probe already in flight cannot report afterwards.
    @ObservationIgnored private var generation = 0

    /// What one probe amounted to.
    enum ProbeOutcome: Equatable {
        case recorded
        case warmup
        case failed
        /// Monitoring was off, or stopped while the probe was out.
        case discarded
    }

    public init(
        defaults: UserDefaults = .standard,
        clock: AppClock = .live,
        probe: any LatencyProbe = HTTPHeadProbe()
    ) {
        self.defaults = defaults
        self.clock = clock
        self.probe = probe
        self.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    // MARK: - Public API

    /// Starts probing every 30 seconds, beginning with a warm-up and a real probe straight away.
    /// While `isEnabled` is off nothing is sent; switching it on later starts from here.
    public func startMonitoring() {
        isRequested = true
        guard isEnabled else { return }
        beginMonitoring()
    }

    /// Stops probing. A probe still in flight is ignored when it returns.
    public func stopMonitoring() {
        isRequested = false
        endMonitoring()
    }

    /// The Mac's connections do not survive sleep, so the next probe is a warm-up again.
    public func handleWake() {
        needsWarmup = true
    }

    // MARK: - Public Calculation Methods (for testing)

    /// Calculates the connection quality score based on latency and jitter values.
    ///
    /// The thresholds suit a HEAD request, not an ICMP round trip (R11): on the line they were
    /// calibrated on, TCP took 19.8 ms and a steady HEAD 86 ms.
    /// - Parameters:
    ///   - latency: The measured latency in milliseconds.
    ///   - jitter: The calculated jitter in milliseconds.
    /// - Returns: A `ConnectionQuality` value representing the overall connection quality.
    nonisolated public static func calculateQualityScore(latency: Double, jitter: Double) -> ConnectionQuality {
        if latency < 120 && jitter < 10 {
            return .good
        } else if latency < 200 && jitter < 30 {
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

    private func beginMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        needsWarmup = true
        scheduleProbe()
        timer = RepeatingTimer.schedule(interval: Self.probeInterval, tolerance: 2) { [weak self] in
            self?.scheduleProbe()
        }
    }

    private func endMonitoring() {
        generation += 1
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        probeTask?.cancel()
        probeTask = nil
    }

    /// Starts one scheduled probe, unless the previous one is still out.
    private func scheduleProbe() {
        guard probeTask == nil else { return }
        let generation = self.generation
        probeTask = Task { [weak self] in
            await self?.runProbe()
            if self?.generation == generation {
                self?.probeTask = nil
            }
        }
    }

    /// One scheduled probe. When it only warmed a new connection up, a second one follows
    /// straight away, so a value is shown without waiting another 30 seconds.
    private func runProbe() async {
        guard !Task.isCancelled else { return }
        guard await measureLatency() == .warmup, !Task.isCancelled else { return }
        await measureLatency()
    }

    /// Sends one probe through the injected `LatencyProbe` (by default an HTTPS HEAD request to
    /// apple.com) and records the result. Internal so tests can drive it directly.
    @discardableResult
    func measureLatency() async -> ProbeOutcome {
        guard isEnabled else { return .discarded }
        let generation = self.generation

        let seconds: TimeInterval?
        do {
            seconds = try await probe.measureSeconds()
        } catch {
            seconds = nil
        }
        // Stopped or switched off while the probe was out: its answer belongs to nobody.
        guard generation == self.generation, isEnabled else { return .discarded }

        guard let seconds else {
            // Nothing stale stays on screen, and the next connection starts cold.
            consecutiveFailures += 1
            needsWarmup = true
            clearMeasurement()
            onMeasurement?(.failure)
            return .failed
        }

        if needsWarmup {
            needsWarmup = false
            return .warmup
        }

        let latency = seconds * 1000 // Convert to ms
        consecutiveFailures = 0
        addSample(latency)
        currentLatency = latency
        let jitter = LatencyMonitor.calculateJitter(from: latencySamples)
        currentJitter = latencySamples.count >= 2 ? jitter : nil
        // A single sample grades on latency alone, and is recorded with a jitter of 0 as before.
        qualityScore = LatencyMonitor.calculateQualityScore(latency: currentLatency, jitter: jitter)
        hasMeasurement = true
        onMeasurement?(.success(latencyMs: latency, jitterMs: jitter))
        return .recorded
    }

    private func clearMeasurement() {
        currentLatency = 0
        currentJitter = nil
        qualityScore = .unknown
        hasMeasurement = false
    }

    /// Adds a latency sample to the rolling window, removing the oldest if at capacity.
    private func addSample(_ latency: Double) {
        latencySamples.append(latency)
        if latencySamples.count > maxSamples {
            latencySamples.removeFirst()
        }
    }
}
