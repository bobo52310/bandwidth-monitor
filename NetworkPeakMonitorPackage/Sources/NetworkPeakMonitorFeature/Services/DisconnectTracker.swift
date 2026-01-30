import Foundation
import Network

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

/// Tracks network disconnection events using NWPathMonitor and persists them to UserDefaults.
///
/// Monitors connectivity changes in real time and records disconnection events
/// with their duration and interface type. Events are persisted across app launches
/// and automatically pruned when they exceed age or count limits.
@MainActor
public class DisconnectTracker: ObservableObject {
    @Published public var events: [DisconnectEvent] = []
    @Published public var isConnected: Bool = true
    @Published public var currentInterfaceType: String = "unknown"

    private var pathMonitor: NWPathMonitor?
    private var monitorQueue: DispatchQueue?
    private var disconnectStartTime: Date?
    private var disconnectInterfaceType: String = "unknown"

    private let userDefaultsKey = "disconnectEvents"
    private let maxEvents = 200
    private let maxAgeDays = 30

    public init() {
        loadEvents()
    }

    // MARK: - Public API

    /// Starts monitoring network connectivity using NWPathMonitor.
    public func startMonitoring() {
        guard pathMonitor == nil else { return }

        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.networkpeakmonitor.disconnecttracker")
        monitorQueue = queue

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handlePathUpdate(path)
            }
        }

        monitor.start(queue: queue)
        pathMonitor = monitor
    }

    /// Stops monitoring network connectivity.
    public func stopMonitoring() {
        pathMonitor?.cancel()
        pathMonitor = nil
        monitorQueue = nil
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
        let startOfToday = Calendar.current.startOfDay(for: Date())
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

    /// Handles NWPath updates to detect connectivity changes.
    private func handlePathUpdate(_ path: NWPath) {
        let wasConnected = isConnected
        let nowConnected = path.status == .satisfied

        // Update interface type
        currentInterfaceType = interfaceTypeString(from: path)

        if wasConnected && !nowConnected {
            // Connection lost — record the start time
            disconnectStartTime = Date()
            disconnectInterfaceType = currentInterfaceType
            isConnected = false
        } else if !wasConnected && nowConnected {
            // Connection restored — record the event
            if let startTime = disconnectStartTime {
                let event = DisconnectEvent(
                    startTime: startTime,
                    endTime: Date(),
                    interfaceType: disconnectInterfaceType
                )
                events.append(event)
                pruneEvents()
                saveEvents()
            }
            disconnectStartTime = nil
            isConnected = true
        } else {
            isConnected = nowConnected
        }
    }

    /// Converts NWPath interface types to a human-readable string.
    private func interfaceTypeString(from path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) {
            return "wifi"
        } else if path.usesInterfaceType(.wiredEthernet) {
            return "ethernet"
        } else if path.usesInterfaceType(.cellular) {
            return "cellular"
        } else {
            return "other"
        }
    }

    /// Removes events exceeding the maximum count or older than the maximum age.
    private func pruneEvents() {
        // Remove events older than maxAgeDays
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: Date()) ?? Date()
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
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            // Silently fail — logging can be added later if needed
        }
    }

    /// Loads events from UserDefaults.
    private func loadEvents() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        do {
            events = try JSONDecoder().decode([DisconnectEvent].self, from: data)
            pruneEvents()
        } catch {
            events = []
        }
    }
}
