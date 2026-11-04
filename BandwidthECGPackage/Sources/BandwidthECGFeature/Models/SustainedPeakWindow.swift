import Foundation

/// The sustained speed: the lowest of the last three consecutive samples, so a one-second
/// spike cannot raise the result.
///
/// After a gap the next sample covers the whole gap, so it opens a new window instead of
/// joining the samples from before it.
struct SustainedPeakWindow {
    private var samples: [Double] = []
    private var lastSampleTime: TimeInterval?

    /// Returns the sustained speed once the window holds enough samples, otherwise `nil`.
    mutating func add(_ mbps: Double, at monotonic: TimeInterval) -> Double? {
        if let lastSampleTime, monotonic - lastSampleTime > ReportRules.sustainedMaxGapSeconds {
            samples.removeAll(keepingCapacity: true)
        }
        lastSampleTime = monotonic

        samples.append(mbps)
        if samples.count > ReportRules.sustainedPeakSamples {
            samples.removeFirst()
        }
        return samples.count == ReportRules.sustainedPeakSamples ? samples.min() : nil
    }
}
