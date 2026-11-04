import Foundation
import Network

/// What the app needs to know about a network path. `NWPath` cannot be constructed by hand,
/// so services consume this value type instead.
public struct PathSnapshot: Sendable, Equatable {
    public var isSatisfied: Bool
    public var interfaceType: String

    public init(isSatisfied: Bool, interfaceType: String) {
        self.isSatisfied = isSatisfied
        self.interfaceType = interfaceType
    }
}

/// Reports network path changes. The handler may be called on any thread.
public protocol PathStatusSource: AnyObject, Sendable {
    func start(_ handler: @escaping @Sendable (PathSnapshot) -> Void)
    func stop()
}

/// `NWPathMonitor`-backed source. An `NWPathMonitor` cannot be restarted after `cancel()`,
/// so each `start` builds a fresh one. Calling `start` twice without `stop` is ignored.
public final class SystemPathStatusSource: PathStatusSource, @unchecked Sendable {
    private let lock = NSLock()
    private var monitor: NWPathMonitor?

    public init() {}

    public func start(_ handler: @escaping @Sendable (PathSnapshot) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard monitor == nil else { return }

        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.bandwidthecg.disconnecttracker")
        monitor.pathUpdateHandler = { path in
            handler(PathSnapshot(
                isSatisfied: path.status == .satisfied,
                interfaceType: Self.interfaceType(of: path)
            ))
        }
        monitor.start(queue: queue)
        self.monitor = monitor
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        monitor?.cancel()
        monitor = nil
    }

    /// Converts NWPath interface types to a human-readable string.
    private static func interfaceType(of path: NWPath) -> String {
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
}
