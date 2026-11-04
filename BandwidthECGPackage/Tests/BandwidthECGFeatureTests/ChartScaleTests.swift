import Testing
import Foundation
@testable import BandwidthECGFeature

/// UI-P2-2: the segmented control must be able to go back to 1 hour from an extended range.
@Suite("TimeRange")
struct TimeRangeTests {

    @Test func segmentedSelection() {
        #expect(NetworkChartView.TimeRange.oneHour.segmentedSelection == .oneHour)
        #expect(NetworkChartView.TimeRange.twentyFourHours.segmentedSelection == nil)
    }

    @Test func segmentedSelection_coversEveryRange() {
        for range in NetworkChartView.TimeRange.standardRanges {
            #expect(range.segmentedSelection == range)
        }
        for range in NetworkChartView.TimeRange.extendedRanges {
            #expect(range.segmentedSelection == nil)
        }
    }
}

/// UI-P2-1 and UI-P2-4: the Y axis, in the unit on screen.
@Suite("ChartScale")
struct ChartScaleTests {

    private func maxValue(
        mode: UserPreferences.ChartYAxisMode,
        unit: UserPreferences.SpeedUnit = .mbps,
        plotted: Double = 0,
        planDownload: Double = 300,
        planUpload: Double = 300
    ) -> Double {
        ChartScale.maxValue(
            mode: mode,
            unit: unit,
            plottedMaxMbps: plotted,
            downloadPlanMbps: planDownload,
            uploadPlanMbps: planUpload
        )
    }

    // MARK: - Fixed

    @Test func fixedMBs_planBelowFloor() {
        // 300 Mbps is 37.5 MB/s. The 100 floor is 100 Mbps (12.5 MB/s), not 100 MB/s.
        let value = maxValue(mode: .fixed, unit: .mbps_lower)

        #expect(abs(value - 41.25) < 1e-9)
    }

    @Test func fixedMbps_planBelowFloor_keepsTheFloor() {
        // A 50 Mbps plan is under the 100 Mbps floor: unchanged from before.
        let value = maxValue(mode: .fixed, planDownload: 50, planUpload: 20)

        #expect(abs(value - 110) < 1e-9)
    }

    @Test func fixed_followsTheLargerPlan() {
        #expect(abs(maxValue(mode: .fixed, planDownload: 300, planUpload: 1000) - 1100) < 1e-9)
        #expect(abs(maxValue(mode: .fixed, unit: .mbps_lower, planDownload: 300, planUpload: 1000) - 137.5) < 1e-9)
    }

    @Test func fixed_growsWithTraffic() {
        // Traffic past the plan raises the top, with the same 10% room.
        #expect(abs(maxValue(mode: .fixed, plotted: 400) - 440) < 1e-9)
        #expect(abs(maxValue(mode: .fixed, unit: .mbps_lower, plotted: 400) - 55) < 1e-9)
    }

    @Test func fixed_ignoresAnUnusablePlan() {
        let value = maxValue(mode: .fixed, planDownload: 0, planUpload: -5)

        #expect(abs(value - 110) < 1e-9)
    }

    // MARK: - Auto

    @Test func auto_stepsByUsage() {
        #expect(maxValue(mode: .auto, plotted: 0) == 10)
        #expect(maxValue(mode: .auto, plotted: 3) == 10)
        #expect(maxValue(mode: .auto, plotted: 12) == 30)
        #expect(maxValue(mode: .auto, plotted: 35) == 70)
        #expect(maxValue(mode: .auto, plotted: 80) == 150)
        #expect(maxValue(mode: .auto, plotted: 150) == 300)
    }

    @Test func auto_beyond200_usesThePlanWithRoom() {
        #expect(abs(maxValue(mode: .auto, plotted: 250) - 330) < 1e-9)
        // Traffic well over the plan wins: 600 * 1.2.
        #expect(abs(maxValue(mode: .auto, plotted: 600) - 720) < 1e-9)
    }

    @Test func auto_convertsToTheUnitOnScreen() {
        #expect(abs(maxValue(mode: .auto, unit: .mbps_lower, plotted: 3) - 1.25) < 1e-9)
        #expect(abs(maxValue(mode: .auto, unit: .mbps_lower, plotted: 150) - 37.5) < 1e-9)
    }

    // MARK: - Plan line

    @Test func planLine_isDrawnOnlyInsideTheAxis() {
        // Auto scale for a quiet line tops out at 10 Mbps: a 300 Mbps plan is off the chart.
        #expect(!ChartScale.isPlanVisible(planMbps: 300, unit: .mbps, axisMax: 10))
        #expect(ChartScale.isPlanVisible(planMbps: 300, unit: .mbps, axisMax: 330))
        // Exactly on the top edge still draws.
        #expect(ChartScale.isPlanVisible(planMbps: 300, unit: .mbps, axisMax: 300))
    }

    @Test func planLine_comparesInTheUnitOnScreen() {
        // 300 Mbps is 37.5 MB/s: inside a 41.25 MB/s axis, outside a 10 MB/s one.
        #expect(ChartScale.isPlanVisible(planMbps: 300, unit: .mbps_lower, axisMax: 41.25))
        #expect(!ChartScale.isPlanVisible(planMbps: 300, unit: .mbps_lower, axisMax: 10))
    }

    @Test func planLine_unusablePlanIsNeverVisible() {
        #expect(!ChartScale.isPlanVisible(planMbps: 0, unit: .mbps, axisMax: 100))
        #expect(!ChartScale.isPlanVisible(planMbps: -1, unit: .mbps, axisMax: 100))
        #expect(!ChartScale.isPlanVisible(planMbps: .nan, unit: .mbps, axisMax: 100))
    }

    @Test func planLine_followsTheScaleFunction() {
        // The two functions agree: a fixed axis always has room for the plan.
        let fixed = maxValue(mode: .fixed, unit: .mbps_lower)
        #expect(ChartScale.isPlanVisible(planMbps: 300, unit: .mbps_lower, axisMax: fixed))
        let auto = maxValue(mode: .auto, plotted: 2)
        #expect(!ChartScale.isPlanVisible(planMbps: 300, unit: .mbps, axisMax: auto))
    }

    // MARK: - Labels

    @Test func fixedLabel_usesTheConvertedValueAndTheUnit() {
        #expect(ChartScale.planText(300, unit: .mbps) == "300 Mbps")
        #expect(ChartScale.planText(300, unit: .mbps_lower) == "37.5 MB/s")
        #expect(ChartScale.planText(1000, unit: .mbps_lower) == "125 MB/s")
        #expect(ChartScale.planText(100, unit: .mbps_lower) == "12.5 MB/s")
    }

    @Test func fixedLabel_localizedFormat() {
        #expect(L10n.chartYAxisFixedLabel("37.5 MB/s").contains("37.5 MB/s"))
    }

    @Test func offscaleText_namesThePlan() {
        let text = L10n.chartPlanOffscale("300 Mbps")

        #expect(text.contains("300 Mbps"))
    }
}
