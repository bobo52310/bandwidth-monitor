import SwiftUI
import Charts
#if os(macOS)
import AppKit
#endif

public struct NetworkChartView: View {
    var historyRecorder: NetworkHistoryRecorder
    var preferences: UserPreferences
    let currentSpeed: NetworkSpeed  // Real-time current speed
    @Binding var timeRange: TimeRange
    @Binding var showUpload: Bool
    @Binding var showDownload: Bool
    @Binding var bannerDismissed: Bool
    /// From this share of the plan a speed counts as concerning: the notification threshold the
    /// user chose, the same one the menu bar and the peak rows use.
    let warningRatio: Double

    /// What the chart draws. Rebuilt when the history or the choices change, never in `body`.
    @State private var snapshot = ChartSnapshot.empty(range: .oneHour)

    // Hover tracking state
    @State private var selectedDate: Date?
    @State private var hoverLocation: CGPoint?

    public enum TimeRange: String, CaseIterable {
        case oneMinute = "1m"
        case fiveMinutes = "5m"
        case fifteenMinutes = "15m"
        case thirtyMinutes = "30m"
        case oneHour = "1h"
        case threeHours = "3h"
        case sixHours = "6h"
        case twelveHours = "12h"
        case twentyFourHours = "24h"

        var displayName: String {
            switch self {
            case .oneMinute: return L10n.chartTimeRangeOneMinute
            case .fiveMinutes: return L10n.chartTimeRangeFiveMinutes
            case .fifteenMinutes: return L10n.chartTimeRangeFifteenMinutes
            case .thirtyMinutes: return L10n.chartTimeRangeThirtyMinutes
            case .oneHour: return L10n.chartTimeRangeOneHour
            case .threeHours: return L10n.chartTimeRangeThreeHours
            case .sixHours: return L10n.chartTimeRangeSixHours
            case .twelveHours: return L10n.chartTimeRangeTwelveHours
            case .twentyFourHours: return L10n.chartTimeRangeTwentyFourHours
            }
        }

        var seconds: TimeInterval {
            switch self {
            case .oneMinute: return 60
            case .fiveMinutes: return 5 * 60
            case .fifteenMinutes: return 15 * 60
            case .thirtyMinutes: return 30 * 60
            case .oneHour: return 60 * 60
            case .threeHours: return 3 * 60 * 60
            case .sixHours: return 6 * 60 * 60
            case .twelveHours: return 12 * 60 * 60
            case .twentyFourHours: return 24 * 60 * 60
            }
        }

        // Standard ranges for segmented control (quick access)
        static var standardRanges: [TimeRange] {
            [.oneMinute, .fiveMinutes, .fifteenMinutes, .thirtyMinutes, .oneHour]
        }

        // Extended ranges for dropdown menu
        static var extendedRanges: [TimeRange] {
            [.threeHours, .sixHours, .twelveHours, .twentyFourHours]
        }

        var isStandard: Bool {
            Self.standardRanges.contains(self)
        }

        var isExtended: Bool {
            Self.extendedRanges.contains(self)
        }

        /// The segment to highlight for this range. The control only has the standard ranges, so
        /// an extended range highlights none (UI-P2-2).
        var segmentedSelection: TimeRange? {
            isStandard ? self : nil
        }

        /// Below 3 hours an area shows each bucket's average under the peak line. From 3 hours
        /// up the line alone is drawn: there the average area would only be visual noise.
        var drawsAverageArea: Bool {
            seconds < 3 * 60 * 60
        }

        /// Up to 15 minutes the chart follows every sample; longer ranges move per 10-second point.
        var followsEverySample: Bool {
            seconds <= 15 * 60
        }
    }

    public init(
        historyRecorder: NetworkHistoryRecorder,
        preferences: UserPreferences,
        currentSpeed: NetworkSpeed,
        timeRange: Binding<TimeRange>,
        showUpload: Binding<Bool>,
        showDownload: Binding<Bool>,
        bannerDismissed: Binding<Bool>,
        warningRatio: Double
    ) {
        self.historyRecorder = historyRecorder
        self.preferences = preferences
        self.currentSpeed = currentSpeed
        self._timeRange = timeRange
        self._showUpload = showUpload
        self._showDownload = showDownload
        self._bannerDismissed = bannerDismissed
        self.warningRatio = warningRatio
    }

    /// Binding for the segmented control. With an extended range chosen nothing is highlighted
    /// (`nil`), so a click on any segment, 1 hour included, is a change and reaches `set`.
    private var segmentedControlBinding: Binding<TimeRange?> {
        Binding(
            get: { timeRange.segmentedSelection },
            set: { newValue in
                if let newValue {
                    timeRange = newValue
                }
            }
        )
    }

    // Y-Axis mode button label
    private var yAxisModeButtonLabel: String {
        if preferences.chartYAxisMode == .auto {
            let currentMax = getMaxYValue()
            return "0-\(formatAxisValue(currentMax))"
        } else {
            let planMax = max(preferences.downloadPlanSpeed, preferences.uploadPlanSpeed)
            return L10n.chartYAxisFixedLabel(ChartScale.planText(planMax, unit: preferences.displayUnit))
        }
    }

    // Y-Axis mode tooltip
    private var yAxisModeTooltip: String {
        if preferences.chartYAxisMode == .auto {
            return L10n.chartYAxisTooltipAuto
        } else {
            return L10n.chartYAxisTooltipFixed
        }
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Time Range Picker - Dual Layer Design with Y-Axis Mode Toggle
            HStack(spacing: 8) {
                // Standard ranges (quick access segmented control)
                Picker(L10n.chartTimeRangeAccessibility, selection: segmentedControlBinding) {
                    ForEach(TimeRange.standardRanges, id: \.self) { range in
                        Text(range.displayName).tag(Optional(range))
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)

                // Extended ranges (dropdown menu)
                Menu {
                    ForEach(TimeRange.extendedRanges, id: \.self) { range in
                        Button(action: {
                            timeRange = range
                        }) {
                            HStack {
                                Text(range.displayName)
                                if timeRange == range {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if timeRange.isExtended {
                            Text(timeRange.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        } else {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.subheadline)
                        }
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(timeRange.isExtended ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.1))
                    .foregroundColor(timeRange.isExtended ? .blue : .secondary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help(L10n.chartHelpExtendedRanges)
                .accessibilityLabel(L10n.chartHelpExtendedRanges)
                .accessibilityValue(timeRange.isExtended ? timeRange.displayName : "")
                .fixedSize()

                // Y-Axis Mode Toggle Button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        preferences.chartYAxisMode = preferences.chartYAxisMode == .auto ? .fixed : .auto
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: preferences.chartYAxisMode.icon)
                            .font(.subheadline)
                            .accessibilityHidden(true)
                        Text(yAxisModeButtonLabel)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(preferences.chartYAxisMode == .auto ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .foregroundColor(preferences.chartYAxisMode == .auto ? .green : .orange)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help(yAxisModeTooltip)
                // The visible label is a number such as "0-70"; say what the button is.
                .accessibilityLabel(L10n.chartYAxisAccessibility)
                .accessibilityValue("\(preferences.chartYAxisMode.displayName), \(yAxisModeButtonLabel)")
                .fixedSize()
            }

            // Data collection banner (show when insufficient data)
            DataCollectionBanner(
                availability: snapshot.availability,
                coverageInfo: coverageInfo,
                isDismissed: $bannerDismissed
            )

            // Statistics Card
            StatisticsCardView(
                peakDownloadSpeed: snapshot.peakDownloadMbps,
                peakUploadSpeed: snapshot.peakUploadMbps,
                averageDownloadSpeed: snapshot.averageDownloadMbps,
                averageUploadSpeed: snapshot.averageUploadMbps,
                showDownload: showDownload,
                showUpload: showUpload,
                unit: preferences.displayUnit,
                timeRange: timeRange,
                currentDownloadSpeed: currentSpeed.downloadMbps,
                currentUploadSpeed: currentSpeed.uploadMbps,
                dataAvailability: snapshot.availability,
                onToggleDownload: { showDownload.toggle() },
                onToggleUpload: { showUpload.toggle() }
            )

            // Partial data indicator (show when 50-99% coverage)
            if snapshot.availability == .partial {
                PartialDataIndicator(coverageInfo: coverageInfo)
            }

            // Chart - show different content based on data availability
            chartContentView
                .frame(height: 200)

            // Legend (only show when data is available)
            if snapshot.availability != .empty {
                legendView
            }
        }
        .padding()
        .animation(.easeInOut(duration: 0.3), value: preferences.chartYAxisMode)
        .onAppear { refreshSnapshot() }
        .onChange(of: historyRecorder.revision) { refreshSnapshot() }
        .onChange(of: latestSampleTime) { refreshSnapshot() }
        .onChange(of: timeRange) { refreshSnapshot() }
        .onChange(of: showDownload) { refreshSnapshot() }
        .onChange(of: showUpload) { refreshSnapshot() }
    }

    /// The newest sample, for ranges that follow every sample. `nil` for longer ranges, so
    /// they do not depend on the per-second samples at all.
    private var latestSampleTime: Date? {
        timeRange.followsEverySample ? historyRecorder.recentSamples.last?.timestamp : nil
    }

    private func refreshSnapshot() {
        let now = Date()
        snapshot = ChartSnapshot.make(
            source: historyRecorder.points(since: now.addingTimeInterval(-timeRange.seconds)),
            range: timeRange,
            now: now
        )
    }

    // Chart content view based on data availability
    @ViewBuilder
    private var chartContentView: some View {
        switch snapshot.availability {
        case .empty:
            EmptyStateView()
        case .insufficient, .partial, .complete:
            chartView
        }
    }

    @ViewBuilder
    private var chartView: some View {
        // All time ranges use the same chart, fed by the down-sampled snapshot
        shortTermChart
    }

    // Data availability status
    enum DataAvailability {
        case empty              // No data at all
        case insufficient       // < 50% coverage
        case partial            // 50-99% coverage
        case complete           // 100% coverage

        var needsWarning: Bool {
            switch self {
            case .empty, .insufficient:
                return true
            case .partial, .complete:
                return false
            }
        }
    }

    // Formatted data coverage info for the banner and the partial-data indicator
    private var coverageInfo: (actual: TimeInterval, required: TimeInterval, percentage: Double) {
        (actual: snapshot.coverageActual, required: snapshot.coverageRequired, percentage: snapshot.coveragePercentage)
    }

    private var shortTermChart: some View {
        shortTermChartWithSelection
    }

    private var shortTermChartWithSelection: some View {
        Chart {
            // Upload speed (average area below 3 hours, peak line always)
            if showUpload {
                ForEach(snapshot.points) { point in
                    if timeRange.drawsAverageArea {
                        // Upload area (gradient fill)
                        AreaMark(
                            x: .value(L10n.chartAxisTime, point.timestamp),
                            yStart: .value(L10n.chartAxisMinimum, 0),
                            yEnd: .value(L10n.chartAxisSpeed, convertSpeed(point.avgUploadMbps)),
                            series: .value(L10n.chartSeriesType, L10n.chartLegendUpload)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [.green.opacity(0.2), .green.opacity(0.03)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)
                    }

                    // Upload line
                    LineMark(
                        x: .value(L10n.chartAxisTime, point.timestamp),
                        y: .value(L10n.chartAxisSpeed, convertSpeed(point.lineUploadMbps)),
                        series: .value(L10n.chartSeriesType, L10n.chartLegendUpload)
                    )
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
                }
            }

            // Download speed (average area below 3 hours, peak line always)
            if showDownload {
                ForEach(snapshot.points) { point in
                    if timeRange.drawsAverageArea {
                        // Download area (gradient fill)
                        AreaMark(
                            x: .value(L10n.chartAxisTime, point.timestamp),
                            yStart: .value(L10n.chartAxisMinimum, 0),
                            yEnd: .value(L10n.chartAxisSpeed, convertSpeed(point.avgDownloadMbps)),
                            series: .value(L10n.chartSeriesType, L10n.chartLegendDownload)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [.blue.opacity(0.2), .blue.opacity(0.03)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)
                    }

                    // Download line
                    LineMark(
                        x: .value(L10n.chartAxisTime, point.timestamp),
                        y: .value(L10n.chartAxisSpeed, convertSpeed(point.lineDownloadMbps)),
                        series: .value(L10n.chartSeriesType, L10n.chartLegendDownload)
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
                }
            }

            // Visual crosshair at hover position
            if let selectedDate = selectedDate {
                RuleMark(x: .value(L10n.chartAxisSelectedTime, selectedDate))
                    .foregroundStyle(.gray.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            // Plan speed reference lines. A plan above the top of the axis is not drawn; the
            // legend says so instead (UI-P2-1).
            if let line = planLines.first(where: { $0.isDownload }), line.isDrawn {
                RuleMark(y: .value(L10n.chartLegendPlanSpeed, convertSpeed(line.planMbps)))
                    .foregroundStyle(.blue.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            }

            if let line = planLines.first(where: { !$0.isDownload }), line.isDrawn {
                RuleMark(y: .value(L10n.chartLegendPlanSpeed, convertSpeed(line.planMbps)))
                    .foregroundStyle(.green.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYScale(domain: 0...getMaxYValue())
        .chartXAxis {
            xAxisMarks
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    Text("\(formatAxisValue(value.as(Double.self) ?? 0)) \(preferences.displayUnit.displayName)")
                        .font(.caption)
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea.background(.clear)
        }
        .overlay(alignment: .topLeading) {
            if let selectedDate = selectedDate,
               let point = findNearestPoint(for: selectedDate) {
                ChartTooltipView(
                    timestamp: point.timestamp,
                    downloadSpeed: showDownload ? point.avgDownloadMbps : nil,
                    uploadSpeed: showUpload ? point.avgUploadMbps : nil,
                    peakDownloadSpeed: showDownload ? point.tooltipPeakDownloadMbps : nil,
                    peakUploadSpeed: showUpload ? point.tooltipPeakUploadMbps : nil,
                    unit: preferences.displayUnit,
                    preferences: preferences,
                    warningRatio: warningRatio
                )
                .offset(x: 10, y: 10)
            }
        }
    }

    // Adaptive X-axis marks based on selected time range

    @AxisContentBuilder
    private var xAxisMarks: some AxisContent {
        switch timeRange {
        case .oneMinute:
            // Every 10 seconds for 1-minute view (HH:MM:SS for precision)
            AxisMarks(values: .stride(by: .second, count: 10)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute().second(), centered: false)
            }
        case .fiveMinutes:
            // Every 1 minute for 5-minute view (HH:MM:SS for precision)
            AxisMarks(values: .stride(by: .minute, count: 1)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute().second(), centered: false)
            }
        case .fifteenMinutes:
            // Every 3 minutes for 15-minute view (HH:MM)
            AxisMarks(values: .stride(by: .minute, count: 3)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute(), centered: false)
            }
        case .thirtyMinutes:
            // Every 5 minutes for 30-minute view (HH:MM)
            AxisMarks(values: .stride(by: .minute, count: 5)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute(), centered: false)
            }
        case .oneHour:
            // Every 10 minutes for 1-hour view (HH:MM)
            AxisMarks(values: .stride(by: .minute, count: 10)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute(), centered: false)
            }
        case .threeHours:
            // Every 30 minutes for 3-hour view (HH:MM)
            AxisMarks(values: .stride(by: .minute, count: 30)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute(), centered: false)
            }
        case .sixHours:
            // Every 1 hour for 6-hour view (HH:MM)
            AxisMarks(values: .stride(by: .hour, count: 1)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute(), centered: false)
            }
        case .twelveHours:
            // Every 2 hours for 12-hour view (HH:MM)
            AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute(), centered: false)
            }
        case .twentyFourHours:
            // Every 4 hours for 24-hour view (HH:MM)
            AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute(), centered: false)
            }
        }
    }

    private var legendView: some View {
        let lines = planLines
        let hasDrawnLine = lines.contains { $0.isDrawn }
        let offscale = offscaleNotes(lines)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 20) {
                // Interactive Download legend button
                Button(action: { showDownload.toggle() }) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(showDownload ? .blue : .gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(L10n.chartLegendDownload)
                            .font(.subheadline)
                            .foregroundColor(showDownload ? .primary : .secondary)
                            .fontWeight(showDownload ? .medium : .regular)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(showDownload ? Color.blue.opacity(0.1) : Color.clear)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help(L10n.chartHelpToggleData(L10n.chartLegendDownload))
                // On or off is the whole point of this button, and the dot only says it in colour.
                .accessibilityValue(showDownload ? L10n.accessibilityStateOn : L10n.accessibilityStateOff)

                // Interactive Upload legend button
                Button(action: { showUpload.toggle() }) {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(showUpload ? .green : .gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(L10n.chartLegendUpload)
                            .font(.subheadline)
                            .foregroundColor(showUpload ? .primary : .secondary)
                            .fontWeight(showUpload ? .medium : .regular)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(showUpload ? Color.green.opacity(0.1) : Color.clear)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help(L10n.chartHelpToggleData(L10n.chartLegendUpload))
                .accessibilityValue(showUpload ? L10n.accessibilityStateOn : L10n.accessibilityStateOff)

                // Plan speed legend (non-interactive): only when a plan line is on the chart.
                if hasDrawnLine {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(.gray.opacity(0.5))
                            .frame(width: 12, height: 1)
                            .overlay(
                                Rectangle()
                                    .fill(.clear)
                                    .frame(width: 12, height: 1)
                                    .background(
                                        LinearGradient(
                                            colors: [.gray.opacity(0.5), .clear, .gray.opacity(0.5), .clear],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                            .accessibilityHidden(true)
                        Text(L10n.chartLegendPlanSpeed)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            // A plan that does not fit the axis has no line; say where it is instead.
            ForEach(offscale, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
            }
        }
    }

    /// One plan speed on the chart: the direction it belongs to and whether it fits the axis.
    private struct PlanLine {
        let isDownload: Bool
        let planMbps: Double
        let isDrawn: Bool
    }

    /// The plan lines of the series that are shown, each checked against the current axis.
    private var planLines: [PlanLine] {
        let axisMax = getMaxYValue()
        var lines: [PlanLine] = []
        if showDownload && preferences.downloadPlanSpeed > 0 {
            lines.append(PlanLine(
                isDownload: true,
                planMbps: preferences.downloadPlanSpeed,
                isDrawn: ChartScale.isPlanVisible(
                    planMbps: preferences.downloadPlanSpeed, unit: preferences.displayUnit, axisMax: axisMax
                )
            ))
        }
        if showUpload && preferences.uploadPlanSpeed > 0 {
            lines.append(PlanLine(
                isDownload: false,
                planMbps: preferences.uploadPlanSpeed,
                isDrawn: ChartScale.isPlanVisible(
                    planMbps: preferences.uploadPlanSpeed, unit: preferences.displayUnit, axisMax: axisMax
                )
            ))
        }
        return lines
    }

    /// "Plan 300 Mbps (off the chart)" for each plan that is not drawn. When both directions
    /// have the same plan one note covers them; otherwise an arrow says which is which.
    private func offscaleNotes(_ lines: [PlanLine]) -> [String] {
        let hidden = lines.filter { !$0.isDrawn }
        let unit = preferences.displayUnit
        if hidden.count == 2, hidden[0].planMbps == hidden[1].planMbps {
            return [L10n.chartPlanOffscale(ChartScale.planText(hidden[0].planMbps, unit: unit))]
        }
        return hidden.map { line in
            let arrow = line.isDownload ? "↓" : "↑"
            return "\(arrow) " + L10n.chartPlanOffscale(ChartScale.planText(line.planMbps, unit: unit))
        }
    }

    // Helper functions
    private func convertSpeed(_ speedMbps: Double) -> Double {
        ChartScale.convert(speedMbps, unit: preferences.displayUnit)
    }

    private func formatAxisValue(_ value: Double) -> String {
        if value < 1.0 {
            return String(format: "%.1f", value)
        } else if value < 10.0 {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.0f", value)
        }
    }

    // Find the plotted point nearest to the selected date
    private func findNearestPoint(for date: Date) -> ChartPoint? {
        snapshot.points.min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) })
    }

    /// Highest value the lines reach, in Mbps, over the series that are shown.
    private var plottedMaxMbps: Double {
        var maxSpeed: Double = 0
        for point in snapshot.points {
            if showDownload {
                maxSpeed = max(maxSpeed, point.lineDownloadMbps)
            }
            if showUpload {
                maxSpeed = max(maxSpeed, point.lineUploadMbps)
            }
        }
        return maxSpeed
    }

    /// Top of the Y axis in the unit on screen. The rules live in `ChartScale`.
    private func getMaxYValue() -> Double {
        ChartScale.maxValue(
            mode: preferences.chartYAxisMode,
            unit: preferences.displayUnit,
            plottedMaxMbps: plottedMaxMbps,
            downloadPlanMbps: preferences.downloadPlanSpeed,
            uploadPlanMbps: preferences.uploadPlanSpeed
        )
    }
}

// MARK: - Tooltip Views


struct ChartTooltipView: View {
    let timestamp: Date
    let downloadSpeed: Double?
    let uploadSpeed: Double?
    /// The bucket's peak, given when it differs from the average; the tooltip then shows both.
    var peakDownloadSpeed: Double? = nil
    var peakUploadSpeed: Double? = nil
    let unit: UserPreferences.SpeedUnit
    let preferences: UserPreferences
    /// From this share of the plan a speed is shown in orange (the notification threshold).
    let warningRatio: Double

    /// One formatter for every tooltip: the tooltip is rebuilt on every hover move.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Timestamp
            Text(Self.timeFormatter.string(from: timestamp))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            // Speed information
            VStack(alignment: .leading, spacing: 2) {
                if let downloadSpeed = downloadSpeed {
                    speedRows(Circle(), arrow: "↓", color: .blue, average: downloadSpeed, peak: peakDownloadSpeed, planSpeed: preferences.downloadPlanSpeed)
                }

                if let uploadSpeed = uploadSpeed {
                    speedRows(Rectangle(), arrow: "↑", color: .green, average: uploadSpeed, peak: peakUploadSpeed, planSpeed: preferences.uploadPlanSpeed)
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.background)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(.gray.opacity(0.3), lineWidth: 0.5)
        )
    }

    /// The direction in words rather than in colour or shape alone (UI-P3-8).
    private func directionArrow(_ arrow: String, color: Color) -> some View {
        Text(arrow)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .accessibilityHidden(true)
    }

    /// One row with the value, or a peak row and an average row when there is a peak. Every row
    /// starts with the direction arrow.
    @ViewBuilder
    private func speedRows<Marker: Shape>(_ marker: Marker, arrow: String, color: Color, average: Double, peak: Double?, planSpeed: Double) -> some View {
        if let peak {
            HStack(spacing: 4) {
                directionArrow(arrow, color: color)
                marker
                    .fill(color)
                    .frame(width: 4, height: 4)
                Text(L10n.chartTooltipPeak(formatSpeed(peak)))
                    .font(.system(size: 12))
                    .foregroundColor(isPeakConcerning(speed: peak, planSpeed: planSpeed) ? .orange : .primary)
            }
            HStack(spacing: 4) {
                directionArrow(arrow, color: color)
                marker
                    .fill(color.opacity(0.5))
                    .frame(width: 4, height: 4)
                Text(L10n.chartTooltipAverage(formatSpeed(average)))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        } else {
            HStack(spacing: 4) {
                directionArrow(arrow, color: color)
                marker
                    .fill(color)
                    .frame(width: 4, height: 4)
                Text(formatSpeed(average))
                    .font(.system(size: 12))
                    .foregroundColor(isPeakConcerning(speed: average, planSpeed: planSpeed) ? .orange : .primary)
            }
        }
    }

    private func formatSpeed(_ speedMbps: Double) -> String {
        let convertedSpeed = convertSpeed(speedMbps)
        return String(format: "%.1f %@", convertedSpeed, unit.displayName)
    }

    private func convertSpeed(_ speedMbps: Double) -> Double {
        switch unit {
        case .mbps:
            return speedMbps
        case .mbps_lower:
            return speedMbps / 8.0
        }
    }

    private func isPeakConcerning(speed: Double, planSpeed: Double) -> Bool {
        guard planSpeed.isFinite, planSpeed > 0 else { return false }
        return speed / planSpeed >= warningRatio
    }
}

// MARK: - Statistics Card View


struct StatisticsCardView: View {
    let peakDownloadSpeed: Double
    let peakUploadSpeed: Double
    let averageDownloadSpeed: Double
    let averageUploadSpeed: Double
    let showDownload: Bool
    let showUpload: Bool
    let unit: UserPreferences.SpeedUnit
    let timeRange: NetworkChartView.TimeRange
    let currentDownloadSpeed: Double  // Real-time current speed
    let currentUploadSpeed: Double    // Real-time current speed
    let dataAvailability: NetworkChartView.DataAvailability

    // Add bindings for toggling
    var onToggleDownload: (() -> Void)?
    var onToggleUpload: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Download statistics - always show but toggleable
            StatColumnView(
                title: L10n.chartLegendDownload,
                color: .blue,
                current: currentDownloadSpeed,
                peak: peakDownloadSpeed,
                average: averageDownloadSpeed,
                unit: unit,
                isActive: showDownload,
                dataAvailability: dataAvailability,
                onToggle: onToggleDownload
            )
            .frame(maxWidth: .infinity)
            .opacity(showDownload ? 1.0 : 0.5)

            Divider()

            // Upload statistics - always show but toggleable
            StatColumnView(
                title: L10n.chartLegendUpload,
                color: .green,
                current: currentUploadSpeed,
                peak: peakUploadSpeed,
                average: averageUploadSpeed,
                unit: unit,
                isActive: showUpload,
                dataAvailability: dataAvailability,
                onToggle: onToggleUpload
            )
            .frame(maxWidth: .infinity)
            .opacity(showUpload ? 1.0 : 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }
}


struct StatColumnView: View {
    let title: String
    let color: Color
    let current: Double
    let peak: Double
    let average: Double
    let unit: UserPreferences.SpeedUnit
    let isActive: Bool
    let dataAvailability: NetworkChartView.DataAvailability
    var onToggle: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title - with visual feedback
            HStack(spacing: 4) {
                Circle()
                    .fill(isActive ? color : color.opacity(0.3))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isActive ? .primary : .secondary)

                Spacer()

                // Data collection indicator
                if dataAvailability == .empty {
                    Text(L10n.chartStatsCollecting)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
            }

            // Current speed (prominent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.chartStatsRealtime)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formatSpeed(current))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(isActive ? color : color.opacity(0.5))
            }

            Divider()

            // Peak and Average (compact)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.chartStatsPeak)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(dataAvailability == .empty ? "--" : formatSpeed(peak))
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(isActive ? .primary : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.chartStatsAverage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(dataAvailability == .empty ? "--" : formatSpeed(average))
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(isActive ? .primary : .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? color.opacity(0.05) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? color.opacity(0.2) : Color.gray.opacity(0.1), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle?()
        }
        .pointerCursor()
        .help(L10n.chartHelpToggleData(title))
    }

    private func formatSpeed(_ speedMbps: Double) -> String {
        let convertedSpeed = convertSpeed(speedMbps)
        if convertedSpeed < 1.0 {
            return String(format: "%.2f %@", convertedSpeed, unit.displayName)
        } else if convertedSpeed < 10.0 {
            return String(format: "%.1f %@", convertedSpeed, unit.displayName)
        } else {
            return String(format: "%.0f %@", convertedSpeed, unit.displayName)
        }
    }

    private func convertSpeed(_ speedMbps: Double) -> Double {
        switch unit {
        case .mbps:
            return speedMbps
        case .mbps_lower:
            return speedMbps / 8.0
        }
    }
}

// MARK: - Empty State and Data Collection Views


struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            // Animated loading indicator
            ProgressView()
                .scaleEffect(1.2)
                .progressViewStyle(.circular)

            // Icon
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
                .accessibilityHidden(true)

            // Text content
            VStack(spacing: 8) {
                Text(L10n.chartEmptyCollecting)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(L10n.chartEmptyPleaseWait)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}


struct DataCollectionBanner: View {
    let availability: NetworkChartView.DataAvailability
    let coverageInfo: (actual: TimeInterval, required: TimeInterval, percentage: Double)
    @Binding var isDismissed: Bool

    var body: some View {
        if !isDismissed && availability.needsWarning {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: availability == .empty ? "clock" : "exclamationmark.triangle")
                    .foregroundColor(bannerColor)
                    .font(.subheadline)
                    .accessibilityHidden(true)

                // Message
                VStack(alignment: .leading, spacing: 4) {
                    Text(bannerTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    if availability == .insufficient {
                        Text(bannerMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Dismiss button
                Button(action: { isDismissed = true }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.chartHelpDismissBanner)
                .accessibilityLabel(L10n.chartHelpDismissBanner)
            }
            .padding(12)
            .background(bannerBackgroundColor)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(bannerColor.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private var bannerColor: Color {
        availability == .empty ? .blue : .orange
    }

    private var bannerBackgroundColor: Color {
        availability == .empty ? Color.blue.opacity(0.08) : Color.orange.opacity(0.08)
    }

    private var bannerTitle: String {
        if availability == .empty {
            return L10n.chartBannerCollecting
        } else {
            return L10n.chartBannerCollectingWithCoverage(formatCoverage())
        }
    }

    private var bannerMessage: String {
        let remaining = coverageInfo.required - coverageInfo.actual
        return L10n.chartBannerRemainingTime(formatTimeInterval(remaining))
    }

    private func formatCoverage() -> String {
        let percentage = Int(coverageInfo.percentage)
        return L10n.chartBannerCollected(percentage)
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 0 {
            if minutes > 0 {
                return L10n.chartTimeHoursMinutes(hours, minutes)
            } else {
                return L10n.chartTimeHours(hours)
            }
        } else {
            return L10n.chartTimeMinutes(minutes)
        }
    }
}


struct PartialDataIndicator: View {
    let coverageInfo: (actual: TimeInterval, required: TimeInterval, percentage: Double)

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.caption)
                .foregroundColor(.blue)
                .accessibilityHidden(true)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(4)
    }

    private var message: String {
        let actualFormatted = formatTimeInterval(coverageInfo.actual)
        let requiredFormatted = formatTimeInterval(coverageInfo.required)
        return L10n.chartPartialMessage(actualFormatted, requiredFormatted)
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 0 {
            if minutes > 0 {
                return L10n.chartTimeHoursMinutesShort(hours, minutes)
            } else {
                return L10n.chartTimeHours(hours)
            }
        } else if minutes > 0 {
            return L10n.chartTimeMinutes(minutes)
        } else {
            return L10n.chartTimeLessThanOneMinute
        }
    }
}

// Provide a pointing-hand cursor on macOS while remaining a no-op elsewhere.
private extension View {
    func pointerCursor() -> some View {
#if os(macOS)
        return modifier(PointerCursor())
#else
        return self
#endif
    }
}

#if os(macOS)
/// Pushes the pointing hand while the pointer is over the view, and pops it when the pointer
/// leaves. If the view goes away while the pointer is still over it (a range change rebuilds
/// the chart, a popover closes) there is no "leave" event, so the pop happens on disappear
/// (UI-P3-13). Otherwise the hand would stay on the stack and the cursor would stick.
private struct PointerCursor: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != isHovering else { return }
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isHovering {
                    isHovering = false
                    NSCursor.pop()
                }
            }
    }
}
#endif
