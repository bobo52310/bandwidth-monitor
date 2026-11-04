import Foundation
import Observation

/// Represents a single network disconnection event with start/end times and interface info.
public struct DisconnectEvent: Codable, Identifiable, Sendable {
    public let id: UUID
    public let startTime: Date
    public let endTime: Date
    public let interfaceType: String

    public init(id: UUID = UUID(), startTime: Date, endTime: Date, interfaceType: String) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.interfaceType = interfaceType
    }

    /// Duration of the disconnection in seconds.
    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    /// Human-readable formatted duration using L10n strings (e.g. "45 秒", "2 分鐘 10 秒", "1 小時 30 分鐘").
    public var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            if minutes > 0 {
                return "\(hours) \(L10n.disconnectHours) \(minutes) \(L10n.disconnectMinutes)"
            } else {
                return "\(hours) \(L10n.disconnectHours)"
            }
        } else if minutes > 0 {
            if seconds > 0 {
                return "\(minutes) \(L10n.disconnectMinutes) \(seconds) \(L10n.disconnectSeconds)"
            } else {
                return "\(minutes) \(L10n.disconnectMinutes)"
            }
        } else {
            return "\(seconds) \(L10n.disconnectSeconds)"
        }
    }
}

/// Records disconnections and persists them to UserDefaults.
///
/// The connection counts as down while the network path is unsatisfied, or while the latency
/// probe has failed twice in a row with the path up (an ISP outage behind a working router,
/// CORE-23). Turning Wi-Fi off by hand cannot be told apart from losing it, so it counts too.
///
/// Sleep is not downtime: `handleSleep()` ends an open outage, nothing is recorded while the
/// Mac sleeps, and an outage still going at wake starts at wake. An outage that began less than
/// 5 seconds before sleep is the sleep taking the network down and is dropped. A loss that
/// begins and ends within 10 seconds of waking is the network reconnecting and is not recorded.
@MainActor
@Observable
public class DisconnectTracker {
    public static let probeFailuresForOutage = 2
    public static let wakeGraceSeconds: TimeInterval = 10
    /// An outage that began less than this long before sleep is not recorded at all.
    public static let preSleepGraceSeconds: TimeInterval = 5

    public var events: [DisconnectEvent] = []
    /// False while an outage is open.
    public var isConnected: Bool = true
    /// The interface of the latest path update, satisfied or not.
    public var currentInterfaceType: String = "unknown"
    /// The interface of the last satisfied path. A path that reports a loss often has no
    /// interface left and reads "other", so outages are attributed to this one (CORE-31).
    public private(set) var lastKnownInterfaceType: String = "unknown"
    public private(set) var isPathSatisfied = true
    /// Probe failures in a row while the path was up. With the path down the probe is bound
    /// to fail, so those failures are not counted.
    public private(set) var consecutiveProbeFailures = 0
    /// Called when a connection comes back, with the finished disconnect.
    public var onEvent: ((DisconnectEvent) -> Void)?
    /// Called with the path's new state whenever it changes, asleep or not.
    public var onConnectivityChange: ((Bool) -> Void)?

    private let defaults: UserDefaults
    private let clock: AppClock
    private let pathSource: any PathStatusSource
    private var isStarted = false

    @ObservationIgnored private var isAsleep = false
    /// Monotonic time at which the grace after the last wake ends.
    @ObservationIgnored private var wakeGraceEnd: TimeInterval?
    @ObservationIgnored private var firstProbeFailureTime: Date?
    @ObservationIgnored private var firstProbeFailureMonotonic: TimeInterval?
    @ObservationIgnored private var outageStart: Date?
    /// Monotonic time the open outage began, so a wall-clock change cannot move it.
    @ObservationIgnored private var outageStartMonotonic: TimeInterval?
    @ObservationIgnored private var outageInterfaceType = "unknown"
    @ObservationIgnored private var outageOpenedInGrace = false

    private let userDefaultsKey = "disconnectEvents"
    private let maxEvents = 200
    private let maxAgeDays = 30

    public init(
        defaults: UserDefaults = .standard,
        clock: AppClock = .live,
        pathSource: any PathStatusSource = SystemPathStatusSource()
    ) {
        self.defaults = defaults
        self.clock = clock
        self.pathSource = pathSource
        loadEvents()
    }

    // MARK: - Public API

    /// Starts monitoring network connectivity through the path source.
    public func startMonitoring() {
        guard !isStarted else { return }
        isStarted = true

        pathSource.start { [weak self] snapshot in
            Task { @MainActor in
                self?.handle(snapshot)
            }
        }
    }

    /// Stops monitoring network connectivity.
    public func stopMonitoring() {
        guard isStarted else { return }
        isStarted = false
        pathSource.stop()
    }

    /// One latency probe's result. Two failures in a row with the path up open an outage that
    /// starts at the first of them; the next success closes it.
    public func noteProbe(success: Bool) {
        guard !isAsleep else { return }
        if success {
            resetProbeFailures()
            reconcileNow()
        } else {
            guard isPathSatisfied else { return }
            let now = clock.now()
            let monotonic = clock.monotonic()
            if consecutiveProbeFailures == 0 {
                firstProbeFailureTime = now
                firstProbeFailureMonotonic = monotonic
            }
            consecutiveProbeFailures += 1
            reconcile(
                openingAt: firstProbeFailureTime ?? now,
                monotonic: firstProbeFailureMonotonic ?? monotonic
            )
        }
    }

    /// The probe was switched off, so only the path counts from now on. An outage that only
    /// the probe was holding open ends here.
    public func clearProbeFailures() {
        resetProbeFailures()
        reconcileNow()
    }

    /// Before the Mac sleeps: an open outage ends now, and nothing is recorded until wake.
    /// One that began less than `preSleepGraceSeconds` ago is dropped: the network going down
    /// with the sleep can be reported just before `willSleep`.
    public func handleSleep() {
        guard !isAsleep else { return }
        if let outageStartMonotonic, clock.monotonic() - outageStartMonotonic < Self.preSleepGraceSeconds {
            discardOutage()
        } else {
            closeOutage(at: clock.now())
        }
        isAsleep = true
        resetProbeFailures()
        wakeGraceEnd = nil
    }

    /// After wake. A path that is still down starts an outage now, not when it went down.
    public func handleWake() {
        isAsleep = false
        wakeGraceEnd = clock.monotonic() + Self.wakeGraceSeconds
        reconcileNow()
    }

    /// Adds a disconnect event for testing purposes.
    /// - Parameter event: The event to add.
    public func addEventForTesting(_ event: DisconnectEvent) {
        events.append(event)
    }

    /// Clears all stored disconnect events.
    public func clearEvents() {
        events.removeAll()
        saveEvents()
    }

    // MARK: - Computed Properties

    /// Returns only today's disconnect events.
    public var todayEvents: [DisconnectEvent] {
        let startOfToday = clock.calendar.startOfDay(for: clock.now())
        return events.filter { $0.startTime >= startOfToday }
    }

    /// Total downtime in seconds for today's disconnect events.
    public var totalDowntimeToday: TimeInterval {
        todayEvents.reduce(0) { $0 + $1.duration }
    }

    /// Human-readable formatted total downtime for today.
    public var formattedDowntimeToday: String {
        let total = totalDowntimeToday
        guard total > 0 else { return L10n.disconnectNoDowntime }

        let totalSeconds = Int(total)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            if minutes > 0 {
                return "\(hours) \(L10n.disconnectHours) \(minutes) \(L10n.disconnectMinutes)"
            } else {
                return "\(hours) \(L10n.disconnectHours)"
            }
        } else if minutes > 0 {
            if seconds > 0 {
                return "\(minutes) \(L10n.disconnectMinutes) \(seconds) \(L10n.disconnectSeconds)"
            } else {
                return "\(minutes) \(L10n.disconnectMinutes)"
            }
        } else {
            return "\(seconds) \(L10n.disconnectSeconds)"
        }
    }

    // MARK: - Private

    /// Handles a path update. Internal so tests can feed snapshots directly.
    func handle(_ snapshot: PathSnapshot) {
        currentInterfaceType = snapshot.interfaceType
        if snapshot.isSatisfied {
            lastKnownInterfaceType = snapshot.interfaceType
        }

        let changed = snapshot.isSatisfied != isPathSatisfied
        isPathSatisfied = snapshot.isSatisfied
        // A single failed probe just before the path drops is explained by the drop. Two or
        // more already make an outage, and that one carries on.
        if changed, !snapshot.isSatisfied, consecutiveProbeFailures < Self.probeFailuresForOutage {
            resetProbeFailures()
        }

        reconcileNow()
        if changed {
            onConnectivityChange?(snapshot.isSatisfied)
        }
    }

    private var isDown: Bool {
        !isPathSatisfied || consecutiveProbeFailures >= Self.probeFailuresForOutage
    }

    /// `reconcile` with an outage that would start now.
    private func reconcileNow() {
        reconcile(openingAt: clock.now(), monotonic: clock.monotonic())
    }

    /// Opens or closes the outage to match `isDown`. Nothing changes while the Mac sleeps.
    private func reconcile(openingAt start: Date, monotonic: TimeInterval) {
        guard !isAsleep else { return }
        if isDown {
            if outageStart == nil {
                openOutage(at: start, monotonic: monotonic)
            }
        } else {
            closeOutage(at: clock.now())
        }
    }

    private func openOutage(at start: Date, monotonic: TimeInterval) {
        outageStart = start
        outageStartMonotonic = monotonic
        outageInterfaceType = lastKnownInterfaceType == "unknown" ? currentInterfaceType : lastKnownInterfaceType
        outageOpenedInGrace = wakeGraceEnd.map { clock.monotonic() < $0 } ?? false
        isConnected = false
    }

    /// Ends the open outage without recording it.
    private func discardOutage() {
        outageStart = nil
        outageStartMonotonic = nil
        isConnected = true
    }

    private func closeOutage(at end: Date) {
        guard let start = outageStart else { return }
        outageStart = nil
        outageStartMonotonic = nil
        isConnected = true

        // Lost and back within the grace after wake: the network was reconnecting.
        if outageOpenedInGrace, let wakeGraceEnd, clock.monotonic() < wakeGraceEnd {
            return
        }

        let event = DisconnectEvent(startTime: start, endTime: end, interfaceType: outageInterfaceType)
        events.append(event)
        pruneEvents()
        saveEvents()
        onEvent?(event)
    }

    private func resetProbeFailures() {
        consecutiveProbeFailures = 0
        firstProbeFailureTime = nil
        firstProbeFailureMonotonic = nil
    }

    /// Removes events exceeding the maximum count or older than the maximum age.
    private func pruneEvents() {
        // Remove events older than maxAgeDays
        let now = clock.now()
        let cutoffDate = clock.calendar.date(byAdding: .day, value: -maxAgeDays, to: now) ?? now
        events = events.filter { $0.startTime >= cutoffDate }

        // Keep only the most recent maxEvents
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
    }

    /// Persists events to UserDefaults as JSON-encoded data.
    private func saveEvents() {
        do {
            let data = try JSONEncoder().encode(events)
            defaults.set(data, forKey: userDefaultsKey)
        } catch {
            // Silently fail — logging can be added later if needed
        }
    }

    /// Loads events from UserDefaults.
    private func loadEvents() {
        guard let data = defaults.data(forKey: userDefaultsKey) else { return }
        do {
            events = try JSONDecoder().decode([DisconnectEvent].self, from: data)
            pruneEvents()
        } catch {
            events = []
        }
    }
}
