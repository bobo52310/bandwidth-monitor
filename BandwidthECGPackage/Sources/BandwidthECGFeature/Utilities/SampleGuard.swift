import Foundation

/// Limits that stop a bad counter reading from turning into a fake speed.
public enum SampleGuard {
    /// The fastest speed treated as real. Anything above it is a measurement error.
    public static let maxPlausibleMbps: Double = 10_000
    public static var maxPlausibleBytesPerSecond: Double { maxPlausibleMbps * 125_000 }
    /// Windows shorter than this are skipped and their bytes counted in the next sample,
    /// because a shortened window inflates the peak.
    public static let minSampleInterval: TimeInterval = 0.5

    /// Bytes a 32-bit interface counter moved between two reads, `elapsed` seconds apart.
    ///
    /// A counter that went backwards has either wrapped at 2^32 or been reset, and the two look
    /// the same. A wrap that would imply more than `maxPlausibleBytesPerSecond` is taken as a
    /// reset and counts as 0. Smaller resets still pass as wraps; that residual risk is known.
    static func delta(previous: UInt32, current: UInt32, elapsed: TimeInterval) -> UInt64 {
        let moved = UInt64(current &- previous)
        guard current < previous else { return moved }
        return Double(moved) / elapsed <= maxPlausibleBytesPerSecond ? moved : 0
    }
}
