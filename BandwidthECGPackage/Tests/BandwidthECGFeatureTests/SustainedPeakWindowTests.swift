import Testing
import Foundation
@testable import BandwidthECGFeature

@Suite("SustainedPeakWindow")
struct SustainedPeakWindowTests {

    /// Adds one sample per second and returns what the window reported for each.
    private func feed(_ samples: [Double]) -> [Double?] {
        var window = SustainedPeakWindow()
        return samples.enumerated().map { window.add($1, at: TimeInterval($0)) }
    }

    @Test func singleSecondSpike_ignored() {
        let results = feed([1, 276, 1]).compactMap { $0 }
        #expect(results.max() == 1)
    }

    @Test func threeSeconds_sustained() {
        #expect(feed([280, 280, 280]).last == 280)
    }

    @Test func usesMinimum() {
        #expect(feed([280, 300, 290]).last == 280)
    }

    @Test func firstTwoSamples_reportNothing() {
        let results = feed([280, 280])
        #expect(results.allSatisfy { $0 == nil })
    }

    @Test func slidesOverTheLastThreeSamples() {
        #expect(feed([10, 280, 280, 280]).last == 280)
    }

    @Test func gapResetsWindow() {
        var window = SustainedPeakWindow()
        _ = window.add(280, at: 0)
        _ = window.add(280, at: 1)
        #expect(window.add(280, at: 4) == nil) // 3 seconds after the previous sample
    }

    @Test func gapOfExactlyTheLimit_keepsTheWindow() {
        var window = SustainedPeakWindow()
        _ = window.add(280, at: 0)
        _ = window.add(280, at: 1)
        #expect(window.add(280, at: 1 + ReportRules.sustainedMaxGapSeconds) == 280)
    }

    /// After a sleep one sample covers the whole gap. It starts a new window and cannot
    /// complete, or stretch, the one that was open before the gap.
    @Test func sampleAfterALongGap_cannotBridgeThePreviousWindow() {
        var window = SustainedPeakWindow()
        #expect(window.add(280, at: 0) == nil)
        #expect(window.add(280, at: 1) == nil)
        #expect(window.add(280, at: 3_601) == nil)
        #expect(window.add(280, at: 3_602) == nil)
        #expect(window.add(280, at: 3_603) == 280)
    }
}
