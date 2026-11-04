import Foundation

/// The chart's Y axis, as pure functions of what is plotted and what the user chose.
/// Everything is in the unit on screen unless a name says `Mbps`.
enum ChartScale {

    /// Mbps to the displayed unit.
    static func convert(_ mbps: Double, unit: UserPreferences.SpeedUnit) -> Double {
        switch unit {
        case .mbps: return mbps
        case .mbps_lower: return mbps / 8.0 // MB/s
        }
    }

    /// The top of the axis. `plottedMaxMbps` is the highest value the lines reach.
    static func maxValue(
        mode: UserPreferences.ChartYAxisMode,
        unit: UserPreferences.SpeedUnit,
        plottedMaxMbps: Double,
        downloadPlanMbps: Double,
        uploadPlanMbps: Double
    ) -> Double {
        switch mode {
        case .auto:
            let smartMax = smartAxisMaxMbps(
                plottedMaxMbps: plottedMaxMbps,
                downloadPlanMbps: downloadPlanMbps,
                uploadPlanMbps: uploadPlanMbps
            )
            // Never below 10 Mbps, so a quiet line still has some room.
            return max(convert(10, unit: unit), convert(smartMax, unit: unit))

        case .fixed:
            // The floor is 100 Mbps in whatever unit is shown: 12.5 MB/s, not 100 MB/s.
            var value = convert(100, unit: unit)
            value = max(value, convert(plottedMaxMbps, unit: unit))
            if downloadPlanMbps > 0 {
                value = max(value, convert(downloadPlanMbps, unit: unit))
            }
            if uploadPlanMbps > 0 {
                value = max(value, convert(uploadPlanMbps, unit: unit))
            }
            // 10% room at the top.
            return value * 1.1
        }
    }

    /// Step-based top for the automatic axis, in Mbps: a few fixed steps for light use, and the
    /// plan (or the traffic, if higher) with room above it for heavy use.
    private static func smartAxisMaxMbps(
        plottedMaxMbps: Double,
        downloadPlanMbps: Double,
        uploadPlanMbps: Double
    ) -> Double {
        switch plottedMaxMbps {
        case 0..<5: return 10
        case 5..<20: return 30
        case 20..<50: return 70
        case 50..<100: return 150
        case 100..<200: return 300
        default:
            let planMax = max(downloadPlanMbps, uploadPlanMbps)
            return max(planMax * 1.1, plottedMaxMbps * 1.2)
        }
    }

    /// Whether a plan line fits inside the axis. A line past the top is not drawn: it would pull
    /// the axis up to a scale the traffic never reaches. A plan that cannot be drawn at all
    /// (zero, negative, not finite) is never visible.
    static func isPlanVisible(planMbps: Double, unit: UserPreferences.SpeedUnit, axisMax: Double) -> Bool {
        guard planMbps.isFinite, planMbps > 0 else { return false }
        return convert(planMbps, unit: unit) <= axisMax
    }

    /// A plan speed as the chart shows it, in the unit on screen: "300 Mbps", "37.5 MB/s".
    static func planText(_ planMbps: Double, unit: UserPreferences.SpeedUnit) -> String {
        let value = convert(planMbps, unit: unit)
        let number = value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(number) \(unit.displayName)"
    }
}
