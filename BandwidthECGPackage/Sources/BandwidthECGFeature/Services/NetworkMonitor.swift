import Foundation
import Observation

@MainActor
@Observable
public class NetworkMonitor {
    public var currentSpeed = NetworkSpeed(uploadSpeed: 0, downloadSpeed: 0)
    public var isMonitoring = false

    /// Callback fired on each speed update, allowing the ViewModel to react without Combine.
    public var onSpeedUpdate: ((NetworkSpeed) -> Void)?

    private let source: any CounterSource
    private let clock: AppClock

    private var timer: Timer?
    /// Counters at the last sample. An interface missing from here contributes nothing until
    /// the following tick, so one that appears or returns never reads as a jump.
    private var baseline: [String: InterfaceCounters] = [:]
    /// Monotonic time of `baseline`, so changes to the wall clock cannot affect the speed.
    private var baselineTime: TimeInterval

    public init(source: any CounterSource = SystemCounterSource(), clock: AppClock = .live) {
        self.source = source
        self.clock = clock
        self.baselineTime = clock.monotonic()
    }

    public func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        takeBaseline()

        timer = RepeatingTimer.schedule(interval: 1.0, tolerance: 0.2) { [weak self] in
            self?.tick()
        }
    }

    public func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
    }

    private func takeBaseline() {
        baseline = source.read() ?? [:]
        baselineTime = clock.monotonic()
    }

    /// One sampling step, driven by the 1 second timer. Internal so tests can drive it directly.
    func tick() {
        // A failed read leaves the baseline untouched instead of treating it as zero bytes.
        guard let counters = source.read() else { return }

        let now = clock.monotonic()
        let elapsed = now - baselineTime
        guard elapsed >= SampleGuard.minSampleInterval else { return }

        var uploadBytes: UInt64 = 0
        var downloadBytes: UInt64 = 0
        for (name, current) in counters {
            guard let previous = baseline[name] else { continue }
            uploadBytes += SampleGuard.delta(previous: previous.tx, current: current.tx, elapsed: elapsed)
            downloadBytes += SampleGuard.delta(previous: previous.rx, current: current.rx, elapsed: elapsed)
        }
        baseline = counters
        baselineTime = now

        let newSpeed = NetworkSpeed(
            uploadSpeed: Double(uploadBytes) / elapsed,
            downloadSpeed: Double(downloadBytes) / elapsed,
            timestamp: clock.now()
        )
        self.currentSpeed = newSpeed
        self.onSpeedUpdate?(newSpeed)
    }

    deinit {
        // Timer is invalidated when stopMonitoring() is called before deallocation
    }
}
