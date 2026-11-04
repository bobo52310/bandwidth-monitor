import Foundation
@testable import BandwidthECGFeature

// Shared fakes for every service test. Nothing here touches cfprefsd, the network, the
// notification center or the real Application Support directory.
//
// The fakes are `@unchecked Sendable` and lock-protected: this is the one place where the
// project allows that escape hatch, because the production protocols require `Sendable`.

// MARK: - Defaults

/// A `UserDefaults` that lives entirely in memory. Every write goes through a property-list
/// round trip so values bridge exactly as they would on disk (a `Date` stays a `Date`,
/// a `[Double]` stays an array of numbers), but nothing is ever persisted.
final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]

    /// Each instance gets a unique suite name so two instances can never share state.
    static func make() -> MemoryDefaults {
        MemoryDefaults(suiteName: "tests.memory.\(UUID().uuidString)")!
    }

    override func object(forKey defaultName: String) -> Any? {
        lock.withLock { storage[defaultName] }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        guard let value else {
            removeObject(forKey: defaultName)
            return
        }
        // Property-list round trip, as the real store would do. A value a plist cannot hold
        // is a bug in the code under test, so fail loudly here.
        let data = try! PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        let bridged = try! PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        lock.withLock { storage[defaultName] = bridged }
    }

    override func set(_ value: Double, forKey defaultName: String) { set(NSNumber(value: value) as Any?, forKey: defaultName) }
    override func set(_ value: Float, forKey defaultName: String) { set(NSNumber(value: value) as Any?, forKey: defaultName) }
    override func set(_ value: Int, forKey defaultName: String) { set(NSNumber(value: value) as Any?, forKey: defaultName) }
    override func set(_ value: Bool, forKey defaultName: String) { set(NSNumber(value: value) as Any?, forKey: defaultName) }

    override func removeObject(forKey defaultName: String) {
        lock.withLock { _ = storage.removeValue(forKey: defaultName) }
    }

    override func double(forKey defaultName: String) -> Double { (object(forKey: defaultName) as? NSNumber)?.doubleValue ?? 0 }
    override func integer(forKey defaultName: String) -> Int { (object(forKey: defaultName) as? NSNumber)?.intValue ?? 0 }
    override func bool(forKey defaultName: String) -> Bool { (object(forKey: defaultName) as? NSNumber)?.boolValue ?? false }
    override func string(forKey defaultName: String) -> String? { object(forKey: defaultName) as? String }
    override func array(forKey defaultName: String) -> [Any]? { object(forKey: defaultName) as? [Any] }
    override func dictionary(forKey defaultName: String) -> [String: Any]? { object(forKey: defaultName) as? [String: Any] }
    override func data(forKey defaultName: String) -> Data? { object(forKey: defaultName) as? Data }
    override func synchronize() -> Bool { true }
}

// MARK: - Clock

/// A controllable clock. `advance(by:)` moves wall time and monotonic time together, as real
/// time does. `setWall(_:)` moves only the wall clock, which is what a user changing the date
/// or time zone does. Neither one moves on its own.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var wall: Date
    private var monotonicSeconds: TimeInterval = 0
    let calendar: Calendar

    init(start: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
        self.wall = start
    }

    /// Convenience: a local wall-clock time such as `2026-10-31 23:59` in `timeZone`.
    convenience init(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
        timeZone: TimeZone = TimeZone(identifier: "Asia/Taipei")!
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
        self.init(start: start, timeZone: timeZone)
    }

    var now: Date { lock.withLock { wall } }
    var monotonic: TimeInterval { lock.withLock { monotonicSeconds } }

    func advance(by seconds: TimeInterval) {
        lock.withLock {
            wall = wall.addingTimeInterval(seconds)
            monotonicSeconds += seconds
        }
    }

    /// Moves only the wall clock (manual clock or time zone change).
    func setWall(_ date: Date) {
        lock.withLock { wall = date }
    }

    var appClock: AppClock {
        appClock(in: calendar.timeZone)
    }

    /// The same clock seen from another time zone, as the live calendar does when the user travels.
    func appClock(in timeZone: TimeZone) -> AppClock {
        var calendar = calendar
        calendar.timeZone = timeZone
        return AppClock(
            now: { [self] in self.now },
            monotonic: { [self] in self.monotonic },
            calendar: calendar
        )
    }
}

// MARK: - Counters

/// Replays a scripted list of counter reads; `nil` entries simulate a failed `getifaddrs`.
/// When the script runs out the last entry is repeated.
final class FakeCounterSource: CounterSource, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [[String: InterfaceCounters]?]
    private var _readCount = 0

    init(_ script: [[String: InterfaceCounters]?] = []) {
        self.script = script
    }

    var readCount: Int { lock.withLock { _readCount } }

    func enqueue(_ reading: [String: InterfaceCounters]?) {
        lock.withLock { script.append(reading) }
    }

    func read() -> [String: InterfaceCounters]? {
        lock.withLock {
            _readCount += 1
            guard !script.isEmpty else { return [:] }
            return script.count > 1 ? script.removeFirst() : script[0]
        }
    }
}

// MARK: - Notifications

final class FakeNotificationDelivery: NotificationDelivering, @unchecked Sendable {
    struct Delivered: Equatable {
        var title: String
        var body: String
        var identifier: String
    }

    struct DeliveryFailure: Error {}

    private let lock = NSLock()
    private var _authorizationRequested = false
    private var _grantAuthorization = true
    private var _failNextDelivery = false
    private var _delivered: [Delivered] = []

    var authorizationRequested: Bool { lock.withLock { _authorizationRequested } }
    var delivered: [Delivered] { lock.withLock { _delivered } }

    var grantAuthorization: Bool {
        get { lock.withLock { _grantAuthorization } }
        set { lock.withLock { _grantAuthorization = newValue } }
    }

    var failNextDelivery: Bool {
        get { lock.withLock { _failNextDelivery } }
        set { lock.withLock { _failNextDelivery = newValue } }
    }

    func requestAuthorization() async -> Bool {
        lock.withLock {
            _authorizationRequested = true
            return _grantAuthorization
        }
    }

    func deliver(title: String, body: String, identifier: String) async throws {
        let shouldFail = lock.withLock {
            let fail = _failNextDelivery
            _failNextDelivery = false
            if !fail {
                _delivered.append(Delivered(title: title, body: body, identifier: identifier))
            }
            return fail
        }
        if shouldFail { throw DeliveryFailure() }
    }
}

// MARK: - Latency

/// Replays queued results. An empty queue throws, like a probe that cannot reach the network.
final class FakeLatencyProbe: LatencyProbe, @unchecked Sendable {
    struct Exhausted: Error {}
    struct ProbeFailure: Error {}

    private let lock = NSLock()
    private var queue: [Result<TimeInterval, Error>] = []
    private var _callCount = 0

    init(seconds: [TimeInterval] = []) {
        queue = seconds.map { .success($0) }
    }

    var callCount: Int { lock.withLock { _callCount } }

    func enqueue(seconds: TimeInterval) {
        lock.withLock { queue.append(.success(seconds)) }
    }

    func enqueueFailure() {
        lock.withLock { queue.append(.failure(ProbeFailure())) }
    }

    func measureSeconds() async throws -> TimeInterval {
        let next: Result<TimeInterval, Error>? = lock.withLock {
            _callCount += 1
            return queue.isEmpty ? nil : queue.removeFirst()
        }
        guard let next else { throw Exhausted() }
        return try next.get()
    }
}

// MARK: - Network path

final class FakePathSource: PathStatusSource, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (PathSnapshot) -> Void)?
    private var _startCount = 0
    private var _stopCount = 0

    var startCount: Int { lock.withLock { _startCount } }
    var stopCount: Int { lock.withLock { _stopCount } }
    var isStarted: Bool { lock.withLock { handler != nil } }

    func start(_ handler: @escaping @Sendable (PathSnapshot) -> Void) {
        lock.withLock {
            _startCount += 1
            self.handler = handler
        }
    }

    func stop() {
        lock.withLock {
            _stopCount += 1
            handler = nil
        }
    }

    /// Delivers a snapshot to the registered handler, if any.
    func emit(_ snapshot: PathSnapshot) {
        let current = lock.withLock { handler }
        current?(snapshot)
    }
}

// MARK: - Login items

/// Stands in for `SMAppService`: registering a login item changes the user's real system
/// configuration, so no test may reach the system controller's `setEnabled`.
final class FakeLoginItems: LoginItemControlling, @unchecked Sendable {
    struct RegistrationFailure: Error, LocalizedError {
        var errorDescription: String? { "registration refused" }
    }

    private let lock = NSLock()
    private var _status: LoginItemStatus
    private var _statusAfterEnable: LoginItemStatus = .enabled
    private var _failNextChange = false
    private var _setEnabledCalls: [Bool] = []
    private var _openSystemSettingsCount = 0

    init(status: LoginItemStatus = .disabled) {
        _status = status
    }

    var status: LoginItemStatus { lock.withLock { _status } }
    /// Every value `setEnabled` was called with, in order.
    var setEnabledCalls: [Bool] { lock.withLock { _setEnabledCalls } }
    var openSystemSettingsCount: Int { lock.withLock { _openSystemSettingsCount } }

    /// What the status becomes after a successful `setEnabled(true)`.
    var statusAfterEnable: LoginItemStatus {
        get { lock.withLock { _statusAfterEnable } }
        set { lock.withLock { _statusAfterEnable = newValue } }
    }

    /// Makes the next `setEnabled` throw and leave the status alone.
    var failNextChange: Bool {
        get { lock.withLock { _failNextChange } }
        set { lock.withLock { _failNextChange = newValue } }
    }

    /// The user flipping the switch in System Settings.
    func setStatusBehindTheAppsBack(_ status: LoginItemStatus) {
        lock.withLock { _status = status }
    }

    func setEnabled(_ enabled: Bool) throws {
        let fail = lock.withLock {
            _setEnabledCalls.append(enabled)
            let fail = _failNextChange
            _failNextChange = false
            if !fail {
                _status = enabled ? _statusAfterEnable : .disabled
            }
            return fail
        }
        if fail { throw RegistrationFailure() }
    }

    func openSystemSettings() {
        lock.withLock { _openSystemSettingsCount += 1 }
    }
}

// MARK: - Blob store

final class InMemoryBlobStore: BlobStore, @unchecked Sendable {
    struct WriteFailure: Error {}
    struct ReadFailure: Error {}
    struct QuarantineFailure: Error {}

    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var _writeCount = 0
    private var _failNextWrite = false
    private var _failNextRead = false
    private var _failQuarantine = false
    private var _quarantined: [String] = []

    var writeCount: Int { lock.withLock { _writeCount } }
    /// Names that were quarantined, in order. The renamed content is kept under `<name>.corrupt-<n>`.
    var quarantined: [String] { lock.withLock { _quarantined } }
    var fileNames: [String] { lock.withLock { files.keys.sorted() } }

    var failNextWrite: Bool {
        get { lock.withLock { _failNextWrite } }
        set { lock.withLock { _failNextWrite = newValue } }
    }

    var failNextRead: Bool {
        get { lock.withLock { _failNextRead } }
        set { lock.withLock { _failNextRead = newValue } }
    }

    var failQuarantine: Bool {
        get { lock.withLock { _failQuarantine } }
        set { lock.withLock { _failQuarantine = newValue } }
    }

    /// The stored bytes, for assertions. Unlike `read`, it never fails and counts as nothing.
    func contents(of name: String) -> Data? {
        lock.withLock { files[name] }
    }

    /// Seeds a file without counting it as a write by the code under test.
    func seed(_ data: Data, named name: String) {
        lock.withLock { files[name] = data }
    }

    func read(_ name: String) throws -> Data? {
        let shouldFail = lock.withLock {
            let fail = _failNextRead
            _failNextRead = false
            return fail
        }
        if shouldFail { throw ReadFailure() }
        return lock.withLock { files[name] }
    }

    func write(_ data: Data, named name: String) throws {
        let shouldFail = lock.withLock {
            if _failNextWrite {
                _failNextWrite = false
                return true
            }
            _writeCount += 1
            files[name] = data
            return false
        }
        if shouldFail { throw WriteFailure() }
    }

    func quarantine(_ name: String) throws {
        if failQuarantine { throw QuarantineFailure() }
        lock.withLock {
            guard let data = files.removeValue(forKey: name) else { return }
            _quarantined.append(name)
            files["\(name).corrupt-\(_quarantined.count)"] = data
        }
    }
}

// MARK: - Dependencies

extension AppDependencies {
    /// Fully faked dependencies: memory defaults, a controllable clock, no network, no file log.
    /// Pass your own fake when the test needs to inspect or script it.
    static func test(
        clock: TestClock,
        defaults: UserDefaults = MemoryDefaults.make(),
        counterSource: any CounterSource = FakeCounterSource(),
        notifications: any NotificationDelivering = FakeNotificationDelivery(),
        latencyProbe: any LatencyProbe = FakeLatencyProbe(),
        pathSource: any PathStatusSource = FakePathSource(),
        loginItems: any LoginItemControlling = FakeLoginItems(),
        blobStore: any BlobStore = InMemoryBlobStore()
    ) -> AppDependencies {
        AppDependencies(
            defaults: defaults,
            clock: clock.appClock,
            counterSource: counterSource,
            notifications: notifications,
            latencyProbe: latencyProbe,
            pathSource: pathSource,
            loginItems: loginItems,
            blobStore: blobStore,
            logToFile: false
        )
    }
}

// MARK: - Waiting

/// Polls `condition` on the main actor until it holds or `timeout` seconds of polling pass.
/// For asserting on work that hops through a `Task`, where there is nothing to await directly.
///
/// The budget counts polls, not wall-clock time. `RepeatingTimerTests` holds the main actor for
/// over 2 seconds, and a wall-clock deadline ran out during that wait with no further poll.
@MainActor
func eventually(timeout: TimeInterval = 2, _ condition: @MainActor () -> Bool) async -> Bool {
    let pollMilliseconds = 5
    for _ in 0..<Int(timeout * 1000) / pollMilliseconds {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(pollMilliseconds))
    }
    return condition()
}
