import Foundation

/// Raw 32-bit byte counters of one network interface, as the kernel reports them.
/// These wrap around at 2^32, which is why they are kept as `UInt32`.
public struct InterfaceCounters: Sendable, Equatable {
    public var rx: UInt32
    public var tx: UInt32

    public init(rx: UInt32, tx: UInt32) {
        self.rx = rx
        self.tx = tx
    }

    /// Keeps the low 32 bits, matching what the kernel counter would hold.
    public init(truncatingRx: UInt64, truncatingTx: UInt64) {
        self.rx = UInt32(truncatingIfNeeded: truncatingRx)
        self.tx = UInt32(truncatingIfNeeded: truncatingTx)
    }
}

/// Source of per-interface byte counters. `nil` means the read itself failed
/// (for example `getifaddrs` returned an error), which is different from "no interfaces".
public protocol CounterSource: Sendable {
    func read() -> [String: InterfaceCounters]?
}

/// Reads counters from `getifaddrs`.
///
/// Only Wi-Fi and Ethernet interfaces (`en*`, `wi*`) are returned, which excludes loopback,
/// VPN tunnels and bridges. `getifaddrs` returns one entry per address family for each
/// interface, but only the `AF_LINK` entry carries `if_data`, so the other entries are skipped.
public struct SystemCounterSource: CounterSource {
    public init() {}

    public func read() -> [String: InterfaceCounters]? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return nil }
        defer { freeifaddrs(head) }

        var result: [String: InterfaceCounters] = [:]
        var cursor = head
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }

            let name = String(cString: entry.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("wi") else { continue }
            guard let address = entry.pointee.ifa_addr,
                  Int32(address.pointee.sa_family) == AF_LINK,
                  let rawData = entry.pointee.ifa_data else { continue }

            let data = rawData.assumingMemoryBound(to: if_data.self).pointee
            result[name] = InterfaceCounters(rx: data.ifi_ibytes, tx: data.ifi_obytes)
        }
        return result
    }
}
