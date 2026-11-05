# Competitive Features Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add 3 competitive features inspired by market analysis: (1) Latency/Jitter + Connection Quality, (2) Disconnect Event Tracking, (3) Monthly Summary Report. Per-App bandwidth monitoring is excluded due to App Sandbox restrictions.

**Architecture:** Each feature is a new service class following existing patterns (concrete `ObservableObject` class, `UserDefaults` persistence, wired into `NetworkMonitorViewModel.setupBindings()`). New views are added as sections in `PopoverView`. All strings go through `L10n` for i18n.

**Tech Stack:** Swift 6.1, SwiftUI, Combine, Network framework (`NWPathMonitor`), Swift Testing

**Important Constraints (from API research):**
- App is sandboxed (`com.apple.security.app-sandbox`). Cannot launch external processes (`networkquality`, `nettop`).
- Per-App bandwidth monitoring is **impossible** in a sandboxed App Store app (no public API). This feature is **deferred** to a future non-sandboxed distribution.
- Latency measurement uses `URLSession` ping to known endpoints (not `networkquality` CLI).
- Disconnect detection uses `NWPathMonitor` (Network framework) — fully sandbox-compatible.

---

## Feature 1: Latency / Jitter + Connection Quality Score

### Approach
- Use `URLSession` HEAD requests to reliable endpoints (Apple CDN, Google DNS) to measure round-trip time.
- Calculate jitter as the standard deviation of recent RTT samples.
- Derive a simple connection quality score: Good / Fair / Poor based on latency + jitter thresholds.
- Sample every 30 seconds to minimize resource usage.

---

### Task 1: Create LatencyMonitor service

**Files:**
- Create: `BandwidthECGPackage/Sources/BandwidthECGFeature/Services/LatencyMonitor.swift`
- Test: `BandwidthECGPackage/Tests/BandwidthECGFeatureTests/LatencyMonitorTests.swift`

**Step 1: Write the failing test**

```swift
// LatencyMonitorTests.swift
import Testing
@testable import BandwidthECGFeature

@Test func qualityScore_lowLatencyLowJitter_returnsGood() async throws {
    let monitor = await LatencyMonitor()
    let score = await monitor.calculateQualityScore(latency: 15.0, jitter: 3.0)
    #expect(score == .good)
}

@Test func qualityScore_highLatencyHighJitter_returnsPoor() async throws {
    let monitor = await LatencyMonitor()
    let score = await monitor.calculateQualityScore(latency: 200.0, jitter: 50.0)
    #expect(score == .poor)
}

@Test func qualityScore_mediumLatency_returnsFair() async throws {
    let monitor = await LatencyMonitor()
    let score = await monitor.calculateQualityScore(latency: 80.0, jitter: 15.0)
    #expect(score == .fair)
}

@Test func jitterCalculation_stableSamples_returnsLowJitter() async throws {
    let monitor = await LatencyMonitor()
    let jitter = await monitor.calculateJitter(from: [20.0, 21.0, 19.0, 20.5, 20.0])
    #expect(jitter < 2.0)
}

@Test func jitterCalculation_unstableSamples_returnsHighJitter() async throws {
    let monitor = await LatencyMonitor()
    let jitter = await monitor.calculateJitter(from: [10.0, 100.0, 15.0, 90.0, 20.0])
    #expect(jitter > 30.0)
}
```

**Step 2: Run test to verify it fails**

Run: `cd /path/to/bandwidth-monitor/BandwidthECGPackage && swift test --filter LatencyMonitor 2>&1`
Expected: FAIL — `LatencyMonitor` type does not exist

**Step 3: Write minimal implementation**

```swift
// LatencyMonitor.swift
import Foundation
import Combine

@MainActor
public class LatencyMonitor: ObservableObject {
    @Published public var currentLatency: Double = 0.0  // ms
    @Published public var currentJitter: Double = 0.0    // ms
    @Published public var qualityScore: ConnectionQuality = .unknown
    @Published public var isMonitoring: Bool = false

    private var timer: Timer?
    private var recentLatencies: [Double] = []
    private let maxSamples = 20  // Keep last 20 samples (~10 min at 30s interval)
    private let measurementInterval: TimeInterval = 30.0

    // Endpoints to measure latency against (Apple CDN is reliable and fast)
    private let endpoints: [URL] = [
        URL(string: "https://www.apple.com")!,
        URL(string: "https://dns.google")!,
    ]

    public enum ConnectionQuality: String, Sendable {
        case good    // latency < 50ms AND jitter < 10ms
        case fair    // latency < 100ms AND jitter < 30ms
        case poor    // everything else
        case unknown

        public var displayName: String {
            switch self {
            case .good: return L10n.connectionQualityGood
            case .fair: return L10n.connectionQualityFair
            case .poor: return L10n.connectionQualityPoor
            case .unknown: return L10n.connectionQualityUnknown
            }
        }

        public var icon: String {
            switch self {
            case .good: return "checkmark.circle.fill"
            case .fair: return "exclamationmark.circle.fill"
            case .poor: return "xmark.circle.fill"
            case .unknown: return "questionmark.circle"
            }
        }

        public var color: String {
            switch self {
            case .good: return "green"
            case .fair: return "orange"
            case .poor: return "red"
            case .unknown: return "gray"
            }
        }
    }

    public init() {}

    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        // Take first measurement immediately
        Task { await measureLatency() }
        timer = Timer.scheduledTimer(withTimeInterval: measurementInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.measureLatency()
            }
        }
    }

    public func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
    }

    public func calculateQualityScore(latency: Double, jitter: Double) -> ConnectionQuality {
        if latency < 50 && jitter < 10 {
            return .good
        } else if latency < 100 && jitter < 30 {
            return .fair
        } else {
            return .poor
        }
    }

    public func calculateJitter(from samples: [Double]) -> Double {
        guard samples.count >= 2 else { return 0 }
        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.map { pow($0 - mean, 2) }.reduce(0, +) / Double(samples.count)
        return sqrt(variance)
    }

    private func measureLatency() async {
        guard let endpoint = endpoints.first else { return }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "HEAD"

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            let (_, response) = try await session.data(for: request)
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0 // ms

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 400 {
                recentLatencies.append(elapsed)
                if recentLatencies.count > maxSamples {
                    recentLatencies.removeFirst()
                }

                currentLatency = elapsed
                currentJitter = calculateJitter(from: recentLatencies)
                qualityScore = calculateQualityScore(latency: currentLatency, jitter: currentJitter)
            }
        } catch {
            // Network error — mark as poor quality
            qualityScore = .poor
        }

        session.invalidateAndCancel()
    }

    deinit {
        timer?.invalidate()
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /path/to/bandwidth-monitor/BandwidthECGPackage && swift test --filter LatencyMonitor 2>&1`
Expected: PASS

**Step 5: Commit**

```bash
git add BandwidthECGPackage/Sources/BandwidthECGFeature/Services/LatencyMonitor.swift BandwidthECGPackage/Tests/BandwidthECGFeatureTests/LatencyMonitorTests.swift
git commit -m "feat: add LatencyMonitor service with jitter calculation and quality scoring"
```

---

### Task 2: Add L10n strings for latency/quality feature

**Files:**
- Modify: `BandwidthECGPackage/Sources/BandwidthECGFeature/Utilities/L10n.swift` (append after line 280)
- Modify: `BandwidthECG/Localizable.xcstrings` (add translations)

**Step 1: Add L10n keys**

Add these to `L10n.swift` before the closing `}`:

```swift
// MARK: - Connection Quality
public static let connectionQualityTitle = String(localized: "connection.quality.title", defaultValue: "連線品質")
public static let connectionQualityGood = String(localized: "connection.quality.good", defaultValue: "良好")
public static let connectionQualityFair = String(localized: "connection.quality.fair", defaultValue: "普通")
public static let connectionQualityPoor = String(localized: "connection.quality.poor", defaultValue: "差")
public static let connectionQualityUnknown = String(localized: "connection.quality.unknown", defaultValue: "未知")
public static let latencyLabel = String(localized: "latency.label", defaultValue: "延遲")
public static let jitterLabel = String(localized: "jitter.label", defaultValue: "抖動")
public static let latencyUnit = String(localized: "latency.unit", defaultValue: "ms")
```

**Step 2: Build to verify compilation**

Run: `cd /path/to/bandwidth-monitor/BandwidthECGPackage && swift build 2>&1`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add BandwidthECGPackage/Sources/BandwidthECGFeature/Utilities/L10n.swift
git commit -m "feat: add L10n strings for connection quality feature"
```

**Note:** Translations in `Localizable.xcstrings` will be auto-generated when the project is built in Xcode. Manual editing of the xcstrings file is optional but recommended for quality translations.

---

### Task 3: Wire LatencyMonitor into ViewModel

**Files:**
- Modify: `BandwidthECGPackage/Sources/BandwidthECGFeature/ViewModels/NetworkMonitorViewModel.swift`

**Step 1: Add latencyMonitor property**

Add after line 12 (`@Published public var errorHandler = ErrorHandler()`):

```swift
@Published public var latencyMonitor = LatencyMonitor()
```

**Step 2: Start latency monitoring in initialize()**

Add to `initialize()` method, after the existing `startMonitoring()` Task block (after line 27):

```swift
latencyMonitor.startMonitoring()
```

**Step 3: Build to verify compilation**

Run: `cd /path/to/bandwidth-monitor/BandwidthECGPackage && swift build 2>&1`
Expected: Build succeeded

**Step 4: Commit**

```bash
git add BandwidthECGPackage/Sources/BandwidthECGFeature/ViewModels/NetworkMonitorViewModel.swift
git commit -m "feat: wire LatencyMonitor into NetworkMonitorViewModel"
```

---

### Task 4: Add Connection Quality section to PopoverView

**Files:**
- Modify: `BandwidthECGPackage/Sources/BandwidthECGFeature/Views/PopoverView.swift`

**Step 1: Add Connection Quality section after the Network Anomaly Section**

Insert before the closing `}` of the scrollable content VStack (before line 390, after the anomaly section's `Divider()`):

```swift
// Connection Quality Section
VStack(alignment: .leading, spacing: 8) {
    HStack {
        Image(systemName: viewModel.latencyMonitor.qualityScore.icon)
            .foregroundColor(qualityColor(viewModel.latencyMonitor.qualityScore))
        Text(L10n.connectionQualityTitle)
            .font(.headline)
            .fontWeight(.medium)
        Spacer()
        Text(viewModel.latencyMonitor.qualityScore.displayName)
            .font(.subheadline)
            .foregroundColor(qualityColor(viewModel.latencyMonitor.qualityScore))
            .fontWeight(.bold)
    }

    HStack(spacing: 24) {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.latencyLabel)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(String(format: "%.0f %@", viewModel.latencyMonitor.currentLatency, L10n.latencyUnit))
                .font(.title3)
                .monospacedDigit()
        }

        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.jitterLabel)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(String(format: "%.1f %@", viewModel.latencyMonitor.currentJitter, L10n.latencyUnit))
                .font(.title3)
                .monospacedDigit()
        }
    }
}
.padding(12)
.background(
    RoundedRectangle(cornerRadius: 8)
        .fill(Color.secondary.opacity(0.05))
)

Divider()
```

**Step 2: Add helper function to PopoverView**

Add inside the `PopoverView` struct (before the `// MARK: - Helper Functions` comment):

```swift
private func qualityColor(_ quality: LatencyMonitor.ConnectionQuality) -> Color {
    switch quality {
    case .good: return .green
    case .fair: return .orange
    case .poor: return Color.Adaptive.error
    case .unknown: return .secondary
    }
}
```

**Step 3: Build to verify compilation**

Run: `cd /path/to/bandwidth-monitor/BandwidthECGPackage && swift build 2>&1`
Expected: Build succeeded

**Step 4: Commit**

```bash
git add BandwidthECGPackage/Sources/BandwidthECGFeature/Views/PopoverView.swift
git commit -m "feat: add Connection Quality section to PopoverView"
```

---

## Feature 2: Disconnect Event Tracking

### Approach
- Use `NWPathMonitor` from the Network framework to detect real connectivity changes.
- Track disconnect events with start time, end time, duration, and interface type.
- Persist events to UserDefaults (JSON-encoded).
- Show disconnect history in PopoverView with summary stats.

---

### Task 5: Create DisconnectTracker service

**Files:**
- Create: `BandwidthECGPackage/Sources/BandwidthECGFeature/Services/DisconnectTracker.swift`
- Test: `BandwidthECGPackage/Tests/BandwidthECGFeatureTests/DisconnectTrackerTests.swift`

**Step 1: Write the failing test**

```swift
// DisconnectTrackerTests.swift
import Testing
import Foundation
@testable import BandwidthECGFeature

@Test func disconnectEvent_hasDuration() async throws {
    let start = Date().addingTimeInterval(-60)
    let end = Date()
    let event = DisconnectEvent(startTime: start, endTime: end, interfaceType: "wifi")
    #expect(abs(event.duration - 60.0) < 1.0)
}

@Test func disconnectEvent_formattedDuration_seconds() async throws {
    let start = Date()
    let end = start.addingTimeInterval(45)
    let event = DisconnectEvent(startTime: start, endTime: end, interfaceType: "wifi")
    #expect(event.formattedDuration.contains("45"))
}

@Test func disconnectEvent_formattedDuration_minutes() async throws {
    let start = Date()
    let end = start.addingTimeInterval(130)
    let event = DisconnectEvent(startTime: start, endTime: end, interfaceType: "wifi")
    #expect(event.formattedDuration.contains("2"))
}

@Test func tracker_todayEvents_filtersCorrectly() async throws {
    let tracker = await DisconnectTracker()
    let today = Date()
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

    let todayEvent = DisconnectEvent(startTime: today.addingTimeInterval(-60), endTime: today, interfaceType: "wifi")
    let yesterdayEvent = DisconnectEvent(startTime: yesterday.addingTimeInterval(-60), endTime: yesterday, interfaceType: "wifi")

    await tracker.addEventForTesting(todayEvent)
    await tracker.addEventForTesting(yesterdayEvent)

    let todayEvents = await tracker.todayEvents
    #expect(todayEvents.count == 1)
}

@Test func tracker_totalDowntimeToday_calculatesCorrectly() async throws {
    let tracker = await DisconnectTracker()
    let now = Date()

    let event1 = DisconnectEvent(startTime: now.addingTimeInterval(-120), endTime: now.addingTimeInterval(-60), interfaceType: "wifi")
    let event2 = DisconnectEvent(startTime: now.addingTimeInterval(-30), endTime: now, interfaceType: "wifi")

    await tracker.addEventForTesting(event1)
    await tracker.addEventForTesting(event2)

    let downtime = await tracker.totalDowntimeToday
    #expect(abs(downtime - 90.0) < 1.0)
}
```

**Step 2: Run test to verify it fails**

Run: `cd /path/to/bandwidth-monitor/BandwidthECGPackage && swift test --filter DisconnectTracker 2>&1`
Expected: FAIL — types do not exist

**Step 3: Write minimal implementation**

```swift
// DisconnectTracker.swift
import Foundation
import Combine
import Network

public struct DisconnectEvent: Codable, Identifiable, Sendable {
    public let id: UUID
    public let startTime: Date
    public let endTime: Date
    public let interfaceType: String

    public init(startTime: Date, endTime: Date, interfaceType: String) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.interfaceType = interfaceType
    }

    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    public var formattedDuration: String {
        let totalSeconds = Int(duration)
        if totalSeconds < 60 {
            return "\(totalSeconds) \(L10n.disconnectSeconds)"
        } else if totalSeconds < 3600 {
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return "\(minutes) \(L10n.disconnectMinutes) \(seconds) \(L10n.disconnectSeconds)"
        } else {
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            return "\(hours) \(L10n.disconnectHours) \(minutes) \(L10n.disconnectMinutes)"
        }
    }
}

@MainActor
public class DisconnectTracker: ObservableObject {
    @Published public var events: [DisconnectEvent] = []
    @Published public var isConnected: Bool = true
    @Published public var currentInterfaceType: String = "unknown"

    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.networkpeakmonitor.disconnect")
    private var disconnectStartTime: Date?
    private var disconnectedInterfaceType: String?

    private let userDefaults = UserDefaults.standard
    private let storageKey = "disconnectEvents"
    private let maxEvents = 200  // Keep last 200 events

    public init() {
        loadEvents()
    }

    public func startMonitoring() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handlePathUpdate(path)
            }
        }
        monitor.start(queue: monitorQueue)
        self.pathMonitor = monitor
    }

    public func stopMonitoring() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    private func handlePathUpdate(_ path: NWPath) {
        let wasConnected = isConnected
        isConnected = path.status == .satisfied

        // Determine interface type
        if path.usesInterfaceType(.wifi) {
            currentInterfaceType = "wifi"
        } else if path.usesInterfaceType(.wiredEthernet) {
            currentInterfaceType = "ethernet"
        } else if path.usesInterfaceType(.cellular) {
            currentInterfaceType = "cellular"
        } else {
            currentInterfaceType = "other"
        }

        if wasConnected && !isConnected {
            // Just disconnected
            disconnectStartTime = Date()
            disconnectedInterfaceType = currentInterfaceType
        } else if !wasConnected && isConnected {
            // Just reconnected — record event
            if let startTime = disconnectStartTime {
                let event = DisconnectEvent(
                    startTime: startTime,
                    endTime: Date(),
                    interfaceType: disconnectedInterfaceType ?? "unknown"
                )
                events.insert(event, at: 0)
                pruneEvents()
                saveEvents()
                disconnectStartTime = nil
                disconnectedInterfaceType = nil
            }
        }
    }

    // MARK: - Computed Properties

    public var todayEvents: [DisconnectEvent] {
        let calendar = Calendar.current
        return events.filter { calendar.isDateInToday($0.startTime) }
    }

    public var totalDowntimeToday: TimeInterval {
        todayEvents.reduce(0) { $0 + $1.duration }
    }

    public var formattedDowntimeToday: String {
        let totalSeconds = Int(totalDowntimeToday)
        if totalSeconds == 0 {
            return L10n.disconnectNoDowntime
        } else if totalSeconds < 60 {
            return "\(totalSeconds) \(L10n.disconnectSeconds)"
        } else {
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return "\(minutes) \(L10n.disconnectMinutes) \(seconds) \(L10n.disconnectSeconds)"
        }
    }

    // MARK: - Testing Support

    public func addEventForTesting(_ event: DisconnectEvent) {
        events.append(event)
    }

    public func clearEvents() {
        events.removeAll()
        userDefaults.removeObject(forKey: storageKey)
    }

    // MARK: - Persistence

    private func pruneEvents() {
        // Keep only last 30 days
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
        events = events.filter { $0.startTime > thirtyDaysAgo }
        if events.count > maxEvents {
            events = Array(events.prefix(maxEvents))
        }
    }

    private func saveEvents() {
        if let encoded = try? JSONEncoder().encode(events) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }

    private func loadEvents() {
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([DisconnectEvent].self, from: data) {
            let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
            events = decoded.filter { $0.startTime > thirtyDaysAgo }
        }
    }

    deinit {
        pathMonitor?.cancel()
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /path/to/bandwidth-monitor/BandwidthECGPackage && swift test --filter DisconnectTracker 2>&1`
Expected: PASS (may need L10n strings from Task 6 first — if so, add stub strings first)

**Step 5: Commit**

```bash
git add BandwidthECGPackage/Sources/BandwidthECGFeature/Services/DisconnectTracker.swift BandwidthECGPackage/Tests/BandwidthECGFeatureTests/DisconnectTrackerTests.swift
git commit -m "feat: add DisconnectTracker service with NWPathMonitor integration"
```

---

### Task 6: Add L10n strings for disconnect tracking

**Files:**
- Modify: `BandwidthECGPackage/Sources/BandwidthECGFeature/Utilities/L10n.swift`

**Step 1: Add L10n keys**

Append to `L10n.swift` before the closing `}`:

```swift
// MARK: - Disconnect Tracking
public static let disconnectTitle = String(localized: "disconnect.title", defaultValue: "斷線記錄")
public static let disconnectTodayCount = String(localized: "disconnect.today.count", defaultValue: "今日斷線")
public static let disconnectTotalDowntime = String(localized: "disconnect.total.downtime", defaultValue: "總中斷時間")
public static let disconnectNoDowntime = String(localized: "disconnect.no.downtime", defaultValue: "無中斷")
public static let disconnectNoEventsToday = String(localized: "disconnect.no.events.today", defaultValue: "今日無斷線記錄")
public static let disconnectSeconds = String(localized: "disconnect.seconds", defaultValue: "秒")
public static let disconnectMinutes = String(localized: "disconnect.minutes", defaultValue: "分鐘")
public static let disconnectHours = String(localized: "disconnect.hours", defaultValue: "小時")
public static let disconnectInterfaceWifi = String(localized: "disconnect.interface.wifi", defaultValue: "Wi-Fi")
public static let disconnectInterfaceEthernet = String(localized: "disconnect.interface.ethernet", defaultValue: "乙太網路")
public static let disconnectInterfaceCellular = String(localized: "disconnect.interface.cellular", defaultValue: "行動數據")
public static let disconnectInterfaceOther = String(localized: "disconnect.interface.other", defaultValue: "其他")
public static func disconnectTimesUnit(_ count: Int) -> String {
    String(format: String(localized: "disconnect.times.unit", defaultValue: "%d 次"), count)
}
```

**Step 2: Build to verify**

Run: `cd /path/to/bandwidth-monitor/BandwidthECGPackage && swift build 2>&1`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add BandwidthECGPackage/Sources/BandwidthECGFeature/Utilities/L10n.swift
git commit -m "feat: add L10n strings for disconnect tracking feature"
```

---

### Task 7: Wire DisconnectTracker into ViewModel

**Files:**
- Modify: `BandwidthECGPackage/Sources/BandwidthECGFeature/ViewModels/NetworkMonitorViewModel.swift`

**Step 1: Add disconnectTracker property**

Add after the `latencyMonitor` property:

```swift
@Published public var disconnectTracker = DisconnectTracker()
```

**Step 2: Start disconnect monitoring in initialize()**

Add to `initialize()` method:

```swift
disconnectTracker.startMonitoring()
```

**Step 3: Build to verify**

Run: `cd /path/to/bandwidth-monitor/BandwidthECGPackage && swift build 2>&1`
Expected: Build succeeded

**Step 4: Commit**

```bash
git add BandwidthECGPackage/Sources/BandwidthECGFeature/ViewModels/NetworkMonitorViewModel.swift
git commit -m "feat: wire DisconnectTracker into NetworkMonitorViewModel"
```

---

### Task 8: Add Disconnect History section to PopoverView

**Files:**
- Modify: `BandwidthECGPackage/Sources/BandwidthECGFeature/Views/PopoverView.swift`

**Step 1: Add Disconnect section after Connection Quality section**

Insert as a new section in the scrollable content:

```swift
// Disconnect History Section
VStack(alignment: .leading, spacing: 8) {
    HStack {
        Image(systemName: viewModel.disconnectTracker.isConnected ? "wifi" : "wifi.slash")
            .foregroundColor(viewModel.disconnectTracker.isConnected ? .green : Color.Adaptive.error)
        Text(L10n.disconnectTitle)
            .font(.headline)
            .fontWeight(.medium)
        Spacer()
    }

    HStack(spacing: 24) {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.disconnectTodayCount)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(L10n.disconnectTimesUnit(viewModel.disconnectTracker.todayEvents.count))
                .font(.title3)
                .monospacedDigit()
                .foregroundColor(viewModel.disconnectTracker.todayEvents.isEmpty ? .secondary : Color.Adaptive.error)
        }

        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.disconnectTotalDowntime)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(viewModel.disconnectTracker.formattedDowntimeToday)
                .font(.title3)
                .monospacedDigit()
        }
    }

    // Recent disconnect events
    if !viewModel.disconnectTracker.todayEvents.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.disconnectTracker.todayEvents.prefix(5)) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "wifi.slash")
                                .font(.caption)
                            Text(event.formattedDuration)
                                .font(.caption)
                        }
                        Text(formatDisconnectTime(event.startTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 1)
        }
    } else {
        Text(L10n.disconnectNoEventsToday)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .italic()
    }
}
.padding(12)
.background(
    RoundedRectangle(cornerRadius: 8)
        .fill(viewModel.disconnectTracker.todayEvents.isEmpty ?
              Color.secondary.opacity(0.05) :
              Color.red.opacity(0.08))
)
.overlay(
    RoundedRectangle(cornerRadius: 8)
        .stroke(viewModel.disconnectTracker.todayEvents.isEmpty ?
               Color.clear :
               Color.red.opacity(0.3), lineWidth: 1)
)

Divider()
```

**Step 2: Add formatDisconnectTime helper to PopoverView**

```swift
private func formatDisconnectTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return formatter.string(from: date)
}
```

**Step 3: Build to verify**

Run: `cd /path/to/bandwidth-monitor/BandwidthECGPackage && swift build 2>&1`
Expected: Build succeeded

**Step 4: Commit**

```bash
git add BandwidthECGPackage/Sources/BandwidthECGFeature/Views/PopoverView.swift
git commit -m "feat: add Disconnect History section to PopoverView"
```

---

## Feature 3: Monthly Summary Report

### Approach
- Aggregate data from existing services (PeakRecorder, NetworkHistoryRecorder, PeakApproachTracker, DisconnectTracker, LatencyMonitor).
- Store monthly summaries in UserDefaults (JSON-encoded).
- Auto-generate summary at the end of each day (accumulating daily data).
- Provide a "View Monthly Report" button that opens a summary panel.
- Include CSV export of the monthly report.

---

### Task 9: Create MonthlySummary model

**Files:**
- Create: `BandwidthECGPackage/Sources/BandwidthECGFeature/Models/MonthlySummary.swift`
- Test: `BandwidthECGPackage/Tests/BandwidthECGFeatureTests/MonthlySummaryTests.swift`

**Step 1: Write the failing test**

```swift
// MonthlySummaryTests.swift
import Testing
import Foundation
@testable import BandwidthECGFeature

@Test func monthlySummary_planUtilization_calculatesCorrectly() async throws {
    var summary = MonthlySummary(
        month: Date(),
        peakDownloadMbps: 250.0,
        peakUploadMbps: 200.0,
        avgDownloadMbps: 50.0,
        avgUploadMbps: 30.0,
        planDownloadMbps: 300.0,
        planUploadMbps: 300.0,
        peakApproachCount: 5,
        disconnectCount: 3,
        totalDowntimeSeconds: 180.0,
        avgLatencyMs: 25.0,
        avgJitterMs: 5.0,
        daysMonitored: 15
    )

    // 250/300 = 83.3%
    #expect(abs(summary.downloadPlanUtilization - 83.33) < 1.0)
    // 200/300 = 66.7%
    #expect(abs(summary.uploadPlanUtilization - 66.67) < 1.0)
}

@Test func monthlySummary_upgradeRecommendation_frequentApproaches() async throws {
    let summary = MonthlySummary(
        month: Date(),
        peakDownloadMbps: 290.0,
        peakUploadMbps: 280.0,
        avgDownloadMbps: 150.0,
        avgUploadMbps: 100.0,
        planDownloadMbps: 300.0,
        planUploadMbps: 300.0,
        peakApproachCount: 20,
        disconnectCount: 0,
        totalDowntimeSeconds: 0,
        avgLatencyMs: 15.0,
        avgJitterMs: 3.0,
        daysMonitored: 30
    )
    #expect(summary.recommendation == .considerUpgrade)
}

@Test func monthlySummary_downgradeRecommendation_lowUtilization() async throws {
    let summary = MonthlySummary(
        month: Date(),
        peakDownloadMbps: 80.0,
        peakUploadMbps: 40.0,
        avgDownloadMbps: 20.0,
        avgUploadMbps: 10.0,
        planDownloadMbps: 1000.0,
        planUploadMbps: 1000.0,
        peakApproachCount: 0,
        disconnectCount: 0,
        totalDowntimeSeconds: 0,
        avgLatencyMs: 10.0,
        avgJitterMs: 2.0,
        daysMonitored: 30
    )
    #expect(summary.recommendation == .considerDowngrade)
}

@Test func monthlySummary_planFits_moderateUsage() async throws {
    let summary = MonthlySummary(
        month: Date(),
        peakDownloadMbps: 200.0,
        peakUploadMbps: 150.0,
        avgDownloadMbps: 80.0,
        avgUploadMbps: 40.0,
        planDownloadMbps: 300.0,
        planUploadMbps: 300.0,
        peakApproachCount: 3,
        disconnectCount: 1,
        totalDowntimeSeconds: 30.0,
        avgLatencyMs: 20.0,
        avgJitterMs: 5.0,
        daysMonitored: 30
    )
    #expect(summary.recommendation == .planFits)
}
```

**Step 2: Run test to verify it fails**

Run: `cd /path/to/bandwidth-monitor/BandwidthECGPackage && swift test --filter MonthlySummary 2>&1`
Expected: FAIL

**Step 3: Write minimal implementation**

```swift
// MonthlySummary.swift
import Foundation

public struct MonthlySummary: Codable, Identifiable, Sendable {
    public let id: UUID
    public let month: Date
    public let peakDownloadMbps: Double
    public let peakUploadMbps: Double
    public let avgDownloadMbps: Double
    public let avgUploadMbps: Double
    public let planDownloadMbps: Double
    public let planUploadMbps: Double
    public let peakApproachCount: Int
    public let disconnectCount: Int
    public let totalDowntimeSeconds: Double
    public let avgLatencyMs: Double
    public let avgJitterMs: Double
    public let daysMonitored: Int

    public init(
        month: Date,
        peakDownloadMbps: Double,
        peakUploadMbps: Double,
        avgDownloadMbps: Double,
        avgUploadMbps: Double,
        planDownloadMbps: Double,
        planUploadMbps: Double,
        peakApproachCount: Int,
        disconnectCount: Int,
        totalDowntimeSeconds: Double,
        avgLatencyMs: Double,
        avgJitterMs: Double,
        daysMonitored: Int
    ) {
        self.id = UUID()
        self.month = month
        self.peakDownloadMbps = peakDownloadMbps
        self.peakUploadMbps = peakUploadMbps
        self.avgDownloadMbps = avgDownloadMbps
        self.avgUploadMbps = avgUploadMbps
        self.planDownloadMbps = planDownloadMbps
        self.planUploadMbps = planUploadMbps
        self.peakApproachCount = peakApproachCount
        self.disconnectCount = disconnectCount
        self.totalDowntimeSeconds = totalDowntimeSeconds
        self.avgLatencyMs = avgLatencyMs
        self.avgJitterMs = avgJitterMs
        self.daysMonitored = daysMonitored
    }

    // MARK: - Computed Properties

    /// Download plan utilization as percentage (0-100)
    public var downloadPlanUtilization: Double {
        guard planDownloadMbps > 0 else { return 0 }
        return (peakDownloadMbps / planDownloadMbps) * 100
    }

    /// Upload plan utilization as percentage (0-100)
    public var uploadPlanUtilization: Double {
        guard planUploadMbps > 0 else { return 0 }
        return (peakUploadMbps / planUploadMbps) * 100
    }

    public enum PlanRecommendation: String, Codable, Sendable {
        case considerUpgrade
        case planFits
        case considerDowngrade
        case insufficientData

        public var displayName: String {
            switch self {
            case .considerUpgrade: return L10n.reportRecommendUpgrade
            case .planFits: return L10n.reportRecommendFits
            case .considerDowngrade: return L10n.reportRecommendDowngrade
            case .insufficientData: return L10n.reportRecommendInsufficientData
            }
        }

        public var icon: String {
            switch self {
            case .considerUpgrade: return "arrow.up.circle.fill"
            case .planFits: return "checkmark.circle.fill"
            case .considerDowngrade: return "arrow.down.circle.fill"
            case .insufficientData: return "questionmark.circle"
            }
        }
    }

    /// Recommendation based on usage patterns
    public var recommendation: PlanRecommendation {
        guard daysMonitored >= 7 else { return .insufficientData }

        // Consider upgrade if:
        // - Peak approach count > 10 per month (averaging more than once every 3 days)
        // - OR peak download utilization > 90%
        if peakApproachCount > 10 || downloadPlanUtilization > 90 {
            return .considerUpgrade
        }

        // Consider downgrade if:
        // - Peak download utilization < 30% (never using more than 30% of plan)
        // - AND peak approach count == 0
        if downloadPlanUtilization < 30 && uploadPlanUtilization < 30 && peakApproachCount == 0 {
            return .considerDowngrade
        }

        return .planFits
    }

    /// Month formatted as "YYYY年MM月" or "January 2026"
    public var formattedMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM"
        return formatter.string(from: month)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /path/to/bandwidth-monitor/BandwidthECGPackage && swift test --filter MonthlySummary 2>&1`
Expected: PASS (may need L10n strings from Task 10 — add stubs if needed)

**Step 5: Commit**

```bash
git add BandwidthECGPackage/Sources/BandwidthECGFeature/Models/MonthlySummary.swift BandwidthECGPackage/Tests/BandwidthECGFeatureTests/MonthlySummaryTests.swift
git commit -m "feat: add MonthlySummary model with plan recommendation logic"
```

---

### Task 10: Add L10n strings for monthly report

**Files:**
- Modify: `BandwidthECGPackage/Sources/BandwidthECGFeature/Utilities/L10n.swift`

**Step 1: Add L10n keys**

```swift
// MARK: - Monthly Report
public static let reportTitle = String(localized: "report.title", defaultValue: "月度報告")
public static let reportViewReport = String(localized: "report.view", defaultValue: "查看月度報告")
public static let reportPeakDownload = String(localized: "report.peak.download", defaultValue: "下載峰值")
public static let reportPeakUpload = String(localized: "report.peak.upload", defaultValue: "上傳峰值")
public static let reportAvgDownload = String(localized: "report.avg.download", defaultValue: "平均下載")
public static let reportAvgUpload = String(localized: "report.avg.upload", defaultValue: "平均上傳")
public static let reportPlanUtilization = String(localized: "report.plan.utilization", defaultValue: "方案使用率")
public static let reportPeakApproaches = String(localized: "report.peak.approaches", defaultValue: "接近上限次數")
public static let reportDisconnects = String(localized: "report.disconnects", defaultValue: "斷線次數")
public static let reportTotalDowntime = String(localized: "report.total.downtime", defaultValue: "總中斷時間")
public static let reportAvgLatency = String(localized: "report.avg.latency", defaultValue: "平均延遲")
public static let reportAvgJitter = String(localized: "report.avg.jitter", defaultValue: "平均抖動")
public static let reportDaysMonitored = String(localized: "report.days.monitored", defaultValue: "監控天數")
public static let reportRecommendation = String(localized: "report.recommendation", defaultValue: "建議")
public static let reportRecommendUpgrade = String(localized: "report.recommend.upgrade", defaultValue: "建議升級方案")
public static let reportRecommendFits = String(localized: "report.recommend.fits", defaultValue: "目前方案合適")
public static let reportRecommendDowngrade = String(localized: "report.recommend.downgrade", defaultValue: "可考慮降級方案")
public static let reportRecommendInsufficientData = String(localized: "report.recommend.insufficient", defaultValue: "資料不足")
public static let reportNoData = String(localized: "report.no.data", defaultValue: "尚無月度報告資料")
public static let reportExport = String(localized: "report.export", defaultValue: "匯出報告")
public static func reportMonthLabel(_ month: String) -> String {
    String(format: String(localized: "report.month.label", defaultValue: "%@ 月度報告"), month)
}
```

**Step 2: Build to verify**

Run: `cd /path/to/bandwidth-monitor/BandwidthECGPackage && swift build 2>&1`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add BandwidthECGPackage/Sources/BandwidthECGFeature/Utilities/L10n.swift
git commit -m "feat: add L10n strings for monthly report feature"
```

---

### Task 11: Create MonthlyReportService

**Files:**
- Create: `BandwidthECGPackage/Sources/BandwidthECGFeature/Services/MonthlyReportService.swift`

**Step 1: Implement the service**

```swift
// MonthlyReportService.swift
import Foundation
import Combine

@MainActor
public class MonthlyReportService: ObservableObject {
    @Published public var currentMonthSummary: MonthlySummary?
    @Published public var pastSummaries: [MonthlySummary] = []

    private let userDefaults = UserDefaults.standard
    private let storageKey = "monthlySummaries"
    private let maxMonths = 12

    // Accumulators for current month
    private var dailyPeakDownloads: [Double] = []
    private var dailyPeakUploads: [Double] = []
    private var dailyAvgDownloads: [Double] = []
    private var dailyAvgUploads: [Double] = []
    private var monthlyPeakApproachCount: Int = 0
    private var monthlyDisconnectCount: Int = 0
    private var monthlyTotalDowntime: Double = 0
    private var dailyLatencies: [Double] = []
    private var dailyJitters: [Double] = []
    private var currentMonthStart: Date?
    private var daysRecorded: Int = 0

    public init() {
        loadSummaries()
    }

    /// Record daily snapshot data (call once per day or on app launch)
    public func recordDailySnapshot(
        peakDownload: Double,
        peakUpload: Double,
        avgDownload: Double,
        avgUpload: Double,
        peakApproachCount: Int,
        disconnectCount: Int,
        totalDowntime: Double,
        avgLatency: Double,
        avgJitter: Double,
        planDownload: Double,
        planUpload: Double
    ) {
        let calendar = Calendar.current
        let now = Date()

        // Check if we crossed into a new month
        if let monthStart = currentMonthStart {
            if !calendar.isDate(monthStart, equalTo: now, toGranularity: .month) {
                // New month — finalize previous month's summary
                finalizeMonthlySummary(planDownload: planDownload, planUpload: planUpload)
            }
        }

        // Set current month start if not set
        if currentMonthStart == nil || !calendar.isDate(currentMonthStart!, equalTo: now, toGranularity: .month) {
            currentMonthStart = calendar.dateInterval(of: .month, for: now)?.start
            resetAccumulators()
        }

        // Accumulate daily data
        dailyPeakDownloads.append(peakDownload)
        dailyPeakUploads.append(peakUpload)
        dailyAvgDownloads.append(avgDownload)
        dailyAvgUploads.append(avgUpload)
        monthlyPeakApproachCount += peakApproachCount
        monthlyDisconnectCount += disconnectCount
        monthlyTotalDowntime += totalDowntime
        if avgLatency > 0 { dailyLatencies.append(avgLatency) }
        if avgJitter > 0 { dailyJitters.append(avgJitter) }
        daysRecorded += 1

        // Update current month summary
        updateCurrentMonthSummary(planDownload: planDownload, planUpload: planUpload)

        // Save accumulators
        saveAccumulators()
    }

    private func updateCurrentMonthSummary(planDownload: Double, planUpload: Double) {
        guard let monthStart = currentMonthStart else { return }

        currentMonthSummary = MonthlySummary(
            month: monthStart,
            peakDownloadMbps: dailyPeakDownloads.max() ?? 0,
            peakUploadMbps: dailyPeakUploads.max() ?? 0,
            avgDownloadMbps: dailyAvgDownloads.isEmpty ? 0 : dailyAvgDownloads.reduce(0, +) / Double(dailyAvgDownloads.count),
            avgUploadMbps: dailyAvgUploads.isEmpty ? 0 : dailyAvgUploads.reduce(0, +) / Double(dailyAvgUploads.count),
            planDownloadMbps: planDownload,
            planUploadMbps: planUpload,
            peakApproachCount: monthlyPeakApproachCount,
            disconnectCount: monthlyDisconnectCount,
            totalDowntimeSeconds: monthlyTotalDowntime,
            avgLatencyMs: dailyLatencies.isEmpty ? 0 : dailyLatencies.reduce(0, +) / Double(dailyLatencies.count),
            avgJitterMs: dailyJitters.isEmpty ? 0 : dailyJitters.reduce(0, +) / Double(dailyJitters.count),
            daysMonitored: daysRecorded
        )
    }

    private func finalizeMonthlySummary(planDownload: Double, planUpload: Double) {
        guard let monthStart = currentMonthStart, daysRecorded > 0 else { return }

        let summary = MonthlySummary(
            month: monthStart,
            peakDownloadMbps: dailyPeakDownloads.max() ?? 0,
            peakUploadMbps: dailyPeakUploads.max() ?? 0,
            avgDownloadMbps: dailyAvgDownloads.reduce(0, +) / Double(dailyAvgDownloads.count),
            avgUploadMbps: dailyAvgUploads.reduce(0, +) / Double(dailyAvgUploads.count),
            planDownloadMbps: planDownload,
            planUploadMbps: planUpload,
            peakApproachCount: monthlyPeakApproachCount,
            disconnectCount: monthlyDisconnectCount,
            totalDowntimeSeconds: monthlyTotalDowntime,
            avgLatencyMs: dailyLatencies.isEmpty ? 0 : dailyLatencies.reduce(0, +) / Double(dailyLatencies.count),
            avgJitterMs: dailyJitters.isEmpty ? 0 : dailyJitters.reduce(0, +) / Double(dailyJitters.count),
            daysMonitored: daysRecorded
        )

        pastSummaries.insert(summary, at: 0)
        if pastSummaries.count > maxMonths {
            pastSummaries = Array(pastSummaries.prefix(maxMonths))
        }

        saveSummaries()
    }

    private func resetAccumulators() {
        dailyPeakDownloads = []
        dailyPeakUploads = []
        dailyAvgDownloads = []
        dailyAvgUploads = []
        monthlyPeakApproachCount = 0
        monthlyDisconnectCount = 0
        monthlyTotalDowntime = 0
        dailyLatencies = []
        dailyJitters = []
        daysRecorded = 0
    }

    /// Generate CSV export of monthly report
    public func exportToCSV(_ summary: MonthlySummary) -> String {
        var csv = "Metric,Value\n"
        csv += "Month,\(summary.formattedMonth)\n"
        csv += "Days Monitored,\(summary.daysMonitored)\n"
        csv += "Peak Download (Mbps),\(String(format: "%.1f", summary.peakDownloadMbps))\n"
        csv += "Peak Upload (Mbps),\(String(format: "%.1f", summary.peakUploadMbps))\n"
        csv += "Avg Download (Mbps),\(String(format: "%.1f", summary.avgDownloadMbps))\n"
        csv += "Avg Upload (Mbps),\(String(format: "%.1f", summary.avgUploadMbps))\n"
        csv += "Plan Download (Mbps),\(String(format: "%.0f", summary.planDownloadMbps))\n"
        csv += "Plan Upload (Mbps),\(String(format: "%.0f", summary.planUploadMbps))\n"
        csv += "Download Utilization (%),\(String(format: "%.1f", summary.downloadPlanUtilization))\n"
        csv += "Upload Utilization (%),\(String(format: "%.1f", summary.uploadPlanUtilization))\n"
        csv += "Peak Approach Count,\(summary.peakApproachCount)\n"
        csv += "Disconnect Count,\(summary.disconnectCount)\n"
        csv += "Total Downtime (seconds),\(String(format: "%.0f", summary.totalDowntimeSeconds))\n"
        csv += "Avg Latency (ms),\(String(format: "%.1f", summary.avgLatencyMs))\n"
        csv += "Avg Jitter (ms),\(String(format: "%.1f", summary.avgJitterMs))\n"
        csv += "Recommendation,\(summary.recommendation.rawValue)\n"
        return csv
    }

    // MARK: - Persistence

    private func saveSummaries() {
        if let encoded = try? JSONEncoder().encode(pastSummaries) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }

    private func loadSummaries() {
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([MonthlySummary].self, from: data) {
            pastSummaries = decoded
        }
    }

    private func saveAccumulators() {
        // Save current month accumulators for crash recovery
        let accumulatorData: [String: Any] = [
            "dailyPeakDownloads": dailyPeakDownloads,
            "dailyPeakUploads": dailyPeakUploads,
            "dailyAvgDownloads": dailyAvgDownloads,
            "dailyAvgUploads": dailyAvgUploads,
            "monthlyPeakApproachCount": monthlyPeakApproachCount,
            "monthlyDisconnectCount": monthlyDisconnectCount,
            "monthlyTotalDowntime": monthlyTotalDowntime,
            "dailyLatencies": dailyLatencies,
            "dailyJitters": dailyJitters,
            "daysRecorded": daysRecorded,
            "currentMonthStart": currentMonthStart as Any
        ]
        userDefaults.set(accumulatorData, forKey: "monthlyReportAccumulators")
    }
}
```

**Step 2: Build to verify**

Run: `cd /path/to/bandwidth-monitor/BandwidthECGPackage && swift build 2>&1`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add BandwidthECGPackage/Sources/BandwidthECGFeature/Services/MonthlyReportService.swift
git commit -m "feat: add MonthlyReportService with daily snapshot accumulation"
```

---

### Task 12: Wire MonthlyReportService into ViewModel

**Files:**
- Modify: `BandwidthECGPackage/Sources/BandwidthECGFeature/ViewModels/NetworkMonitorViewModel.swift`

**Step 1: Add property**

```swift
@Published public var monthlyReportService = MonthlyReportService()
```

**Step 2: Add daily snapshot method**

Add to the ViewModel:

```swift
/// Call once per day to snapshot daily data for monthly report
public func recordDailySnapshot() {
    let avgDownload = historyRecorder.twentyFourHourData.isEmpty ? 0 :
        historyRecorder.twentyFourHourData.map { $0.avgDownloadSpeed / 125_000 }.reduce(0, +) / Double(historyRecorder.twentyFourHourData.count)
    let avgUpload = historyRecorder.twentyFourHourData.isEmpty ? 0 :
        historyRecorder.twentyFourHourData.map { $0.avgUploadSpeed / 125_000 }.reduce(0, +) / Double(historyRecorder.twentyFourHourData.count)

    monthlyReportService.recordDailySnapshot(
        peakDownload: peakRecorder.todayPeakDownload,
        peakUpload: peakRecorder.todayPeakUpload,
        avgDownload: avgDownload,
        avgUpload: avgUpload,
        peakApproachCount: peakApproachTracker.todayApproachCount,
        disconnectCount: disconnectTracker.todayEvents.count,
        totalDowntime: disconnectTracker.totalDowntimeToday,
        avgLatency: latencyMonitor.currentLatency,
        avgJitter: latencyMonitor.currentJitter,
        planDownload: preferences.downloadPlanSpeed,
        planUpload: preferences.uploadPlanSpeed
    )
}
```

**Step 3: Set up daily snapshot timer in setupBindings()**

Add at the end of `setupBindings()`:

```swift
// Daily snapshot for monthly report (check every hour, record once per day)
Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
    Task { @MainActor in
        self?.checkAndRecordDailySnapshot()
    }
}
```

And add the helper method:

```swift
private var lastDailySnapshotDate: Date? {
    get { UserDefaults.standard.object(forKey: "lastDailySnapshotDate") as? Date }
    set { UserDefaults.standard.set(newValue, forKey: "lastDailySnapshotDate") }
}

private func checkAndRecordDailySnapshot() {
    let calendar = Calendar.current
    if let lastDate = lastDailySnapshotDate, calendar.isDateInToday(lastDate) {
        return // Already recorded today
    }
    recordDailySnapshot()
    lastDailySnapshotDate = Date()
}
```

**Step 4: Build to verify**

Run: `cd /path/to/bandwidth-monitor/BandwidthECGPackage && swift build 2>&1`
Expected: Build succeeded

**Step 5: Commit**

```bash
git add BandwidthECGPackage/Sources/BandwidthECGFeature/ViewModels/NetworkMonitorViewModel.swift
git commit -m "feat: wire MonthlyReportService into ViewModel with daily snapshots"
```

---

### Task 13: Create MonthlyReportView

**Files:**
- Create: `BandwidthECGPackage/Sources/BandwidthECGFeature/Views/MonthlyReportView.swift`

**Step 1: Implement the view**

```swift
// MonthlyReportView.swift
import SwiftUI

public struct MonthlyReportView: View {
    @ObservedObject var viewModel: NetworkMonitorViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: NetworkMonitorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L10n.reportTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(L10n.buttonClose) { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            if let summary = viewModel.monthlyReportService.currentMonthSummary {
                ScrollView {
                    VStack(spacing: 16) {
                        // Month label
                        Text(L10n.reportMonthLabel(summary.formattedMonth))
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Recommendation card
                        recommendationCard(summary)

                        // Speed stats
                        speedStatsCard(summary)

                        // Connection quality
                        connectionCard(summary)

                        // Plan utilization
                        utilizationCard(summary)

                        // Export button
                        Button(action: { exportReport(summary) }) {
                            Label(L10n.reportExport, systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(L10n.reportNoData)
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 500, height: 600)
    }

    // MARK: - Card Views

    private func recommendationCard(_ summary: MonthlySummary) -> some View {
        HStack {
            Image(systemName: summary.recommendation.icon)
                .font(.title)
                .foregroundColor(recommendationColor(summary.recommendation))
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.reportRecommendation)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Text(summary.recommendation.displayName)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(recommendationColor(summary.recommendation))
            }
            Spacer()
            Text("\(summary.daysMonitored) " + L10n.reportDaysMonitored)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(recommendationColor(summary.recommendation).opacity(0.1)))
    }

    private func speedStatsCard(_ summary: MonthlySummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                statItem(L10n.reportPeakDownload, value: String(format: "%.1f Mbps", summary.peakDownloadMbps))
                statItem(L10n.reportPeakUpload, value: String(format: "%.1f Mbps", summary.peakUploadMbps))
            }
            HStack(spacing: 24) {
                statItem(L10n.reportAvgDownload, value: String(format: "%.1f Mbps", summary.avgDownloadMbps))
                statItem(L10n.reportAvgUpload, value: String(format: "%.1f Mbps", summary.avgUploadMbps))
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
    }

    private func connectionCard(_ summary: MonthlySummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                statItem(L10n.reportAvgLatency, value: String(format: "%.0f ms", summary.avgLatencyMs))
                statItem(L10n.reportAvgJitter, value: String(format: "%.1f ms", summary.avgJitterMs))
            }
            HStack(spacing: 24) {
                statItem(L10n.reportDisconnects, value: "\(summary.disconnectCount)")
                statItem(L10n.reportPeakApproaches, value: "\(summary.peakApproachCount)")
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
    }

    private func utilizationCard(_ summary: MonthlySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.reportPlanUtilization)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            HStack(spacing: 16) {
                utilizationBar(label: "↓", percentage: summary.downloadPlanUtilization)
                utilizationBar(label: "↑", percentage: summary.uploadPlanUtilization)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
    }

    // MARK: - Helpers

    private func statItem(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func utilizationBar(label: String, percentage: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text(String(format: "%.0f%%", percentage))
                    .font(.caption)
                    .fontWeight(.bold)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(utilizationColor(percentage))
                        .frame(width: geometry.size.width * min(percentage / 100, 1.0))
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func utilizationColor(_ percentage: Double) -> Color {
        if percentage > 90 { return .red }
        if percentage > 70 { return .orange }
        return .green
    }

    private func recommendationColor(_ recommendation: MonthlySummary.PlanRecommendation) -> Color {
        switch recommendation {
        case .considerUpgrade: return .orange
        case .planFits: return .green
        case .considerDowngrade: return .blue
        case .insufficientData: return .secondary
        }
    }

    private func exportReport(_ summary: MonthlySummary) {
        let csv = viewModel.monthlyReportService.exportToCSV(summary)
        let filename = "monthly_report_\(summary.formattedMonth.replacingOccurrences(of: "/", with: "-")).csv"

        DataExportService.showSavePanel(suggestedFilename: filename) { url in
            guard let url = url else { return }
            try? csv.write(to: url, atomically: true, encoding: .utf8)
            DataExportService.revealInFinder(url: url)
        }
    }
}
```

**Step 2: Build to verify**

Run: `cd /path/to/bandwidth-monitor/BandwidthECGPackage && swift build 2>&1`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add BandwidthECGPackage/Sources/BandwidthECGFeature/Views/MonthlyReportView.swift
git commit -m "feat: add MonthlyReportView with recommendation display and CSV export"
```

---

### Task 14: Add Monthly Report button to PopoverView

**Files:**
- Modify: `BandwidthECGPackage/Sources/BandwidthECGFeature/Views/PopoverView.swift`

**Step 1: Add @State for showing report sheet**

Add to the existing `@State` properties at the top of PopoverView:

```swift
@State private var showingMonthlyReport = false
```

**Step 2: Add Monthly Report button in the bottom bar**

In the bottom buttons HStack (around line 399), add after the Export Menu button:

```swift
// Monthly Report Button
Button(action: { showingMonthlyReport = true }) {
    Label(L10n.reportViewReport, systemImage: "chart.bar.doc.horizontal")
        .font(.subheadline)
}
.buttonStyle(.bordered)
.help(L10n.reportViewReport)
```

**Step 3: Add sheet modifier**

Add after the existing `.sheet(isPresented: $showingSettings)` modifier:

```swift
.sheet(isPresented: $showingMonthlyReport) {
    MonthlyReportView(viewModel: viewModel)
}
```

**Step 4: Build to verify**

Run: `cd /path/to/bandwidth-monitor/BandwidthECGPackage && swift build 2>&1`
Expected: Build succeeded

**Step 5: Commit**

```bash
git add BandwidthECGPackage/Sources/BandwidthECGFeature/Views/PopoverView.swift
git commit -m "feat: add Monthly Report button to PopoverView bottom bar"
```

---

### Task 15: Run full test suite and verify build

**Step 1: Run all tests**

Run: `cd /path/to/bandwidth-monitor/BandwidthECGPackage && swift test 2>&1`
Expected: All tests PASS

**Step 2: Build full workspace**

Run: `cd /path/to/bandwidth-monitor && xcodebuild build -workspace BandwidthECG.xcworkspace -scheme BandwidthECG -destination 'platform=macOS' 2>&1 | tail -20`
Expected: Build succeeded

**Step 3: Commit any fixes if needed**

---

## Summary

| Feature | Tasks | New Files | Modified Files |
|---------|-------|-----------|----------------|
| Latency/Jitter + Quality | 1-4 | `LatencyMonitor.swift`, `LatencyMonitorTests.swift` | `L10n.swift`, `NetworkMonitorViewModel.swift`, `PopoverView.swift` |
| Disconnect Tracking | 5-8 | `DisconnectTracker.swift`, `DisconnectTrackerTests.swift` | `L10n.swift`, `NetworkMonitorViewModel.swift`, `PopoverView.swift` |
| Monthly Report | 9-14 | `MonthlySummary.swift`, `MonthlySummaryTests.swift`, `MonthlyReportService.swift`, `MonthlyReportView.swift` | `L10n.swift`, `NetworkMonitorViewModel.swift`, `PopoverView.swift` |
| Final Verification | 15 | — | — |

**Deferred (requires non-sandboxed distribution):**
- Per-App Bandwidth Analysis (needs `nettop` or `libproc`, blocked by sandbox)
- `networkquality` CLI integration (blocked by sandbox)
