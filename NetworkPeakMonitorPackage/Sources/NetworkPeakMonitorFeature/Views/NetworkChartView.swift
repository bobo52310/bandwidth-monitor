import SwiftUI
import Charts
#if os(macOS)
import AppKit
#endif

@available(macOS 13.0, *)
public struct NetworkChartView: View {
    @ObservedObject var historyRecorder: NetworkHistoryRecorder
    @ObservedObject var preferences: UserPreferences
    let currentSpeed: NetworkSpeed  // Real-time current speed
    @State private var selectedTimeRange: TimeRange = .oneHour
    @Binding var showUpload: Bool
    @Binding var showDownload: Bool

    // Hover tracking state
    @State private var selectedDate: Date?
    @State private var hoverLocation: CGPoint?

    public enum TimeRange: String, CaseIterable {
        case oneMinute = "1 分鐘"
        case fiveMinutes = "5 分鐘"
        case fifteenMinutes = "15 分鐘"
        case thirtyMinutes = "30 分鐘"
        case oneHour = "1 小時"
        case threeHours = "3 小時"
        case sixHours = "6 小時"
        case twelveHours = "12 小時"
        case twentyFourHours = "24 小時"

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
    }

    public init(historyRecorder: NetworkHistoryRecorder, preferences: UserPreferences, currentSpeed: NetworkSpeed, showUpload: Binding<Bool>, showDownload: Binding<Bool>) {
        self.historyRecorder = historyRecorder
        self.preferences = preferences
        self.currentSpeed = currentSpeed
        self._showUpload = showUpload
        self._showDownload = showDownload
    }

    // Computed binding for segmented control to handle extended ranges
    private var segmentedControlBinding: Binding<TimeRange> {
        Binding(
            get: {
                // If extended range is selected, default to oneHour for segmented control display
                selectedTimeRange.isStandard ? selectedTimeRange : .oneHour
            },
            set: { newValue in
                // Only update if a standard range is selected
                if newValue.isStandard {
                    selectedTimeRange = newValue
                }
            }
        )
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Time Range Picker - Dual Layer Design
            HStack(spacing: 8) {
                // Standard ranges (quick access segmented control)
                Picker("Time Range", selection: segmentedControlBinding) {
                    ForEach(TimeRange.standardRanges, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)

                // Extended ranges (dropdown menu)
                Menu {
                    ForEach(TimeRange.extendedRanges, id: \.self) { range in
                        Button(action: {
                            selectedTimeRange = range
                        }) {
                            HStack {
                                Text(range.rawValue)
                                if selectedTimeRange == range {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if selectedTimeRange.isExtended {
                            Text(selectedTimeRange.rawValue)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        } else {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.subheadline)
                        }
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(selectedTimeRange.isExtended ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.1))
                    .foregroundColor(selectedTimeRange.isExtended ? .blue : .secondary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("更長時間範圍")
                .fixedSize()
            }

            // Statistics Card
            StatisticsCardView(
                data: filteredData,
                showDownload: showDownload,
                showUpload: showUpload,
                unit: preferences.displayUnit,
                timeRange: selectedTimeRange,
                currentDownloadSpeed: currentSpeed.downloadMbps,
                currentUploadSpeed: currentSpeed.uploadMbps,
                onToggleDownload: { showDownload.toggle() },
                onToggleUpload: { showUpload.toggle() }
            )

            // Chart
            chartView
                .frame(height: 200)

            // Legend
            legendView
        }
        .padding()
    }

    @ViewBuilder
    private var chartView: some View {
        // All time ranges now use short-term chart with filtered data
        shortTermChart
    }

    // Filter data based on selected time range
    private var filteredData: [NetworkDataPoint] {
        let now = Date()
        let cutoffTime = now.addingTimeInterval(-selectedTimeRange.seconds)
        return historyRecorder.oneHourData.filter { $0.timestamp > cutoffTime }
    }

    @ViewBuilder
    private var shortTermChart: some View {
        if #available(macOS 14.0, *) {
            shortTermChartWithSelection
        } else {
            shortTermChartBasic
        }
    }

    @available(macOS 14.0, *)
    private var shortTermChartWithSelection: some View {
        Chart {
            // Download speed area (gradient fill)
            if showDownload {
                ForEach(filteredData) { dataPoint in
                    AreaMark(
                        x: .value("Time", dataPoint.timestamp),
                        yStart: .value("Min", 0),
                        yEnd: .value("Speed", convertSpeed(dataPoint.downloadMbps))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue.opacity(0.3), .blue.opacity(0.05)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }

            // Download speed line (on top of area)
            if showDownload {
                ForEach(filteredData) { dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("Speed", convertSpeed(dataPoint.downloadMbps))
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }
            }

            // Upload speed area (gradient fill)
            if showUpload {
                ForEach(filteredData) { dataPoint in
                    AreaMark(
                        x: .value("Time", dataPoint.timestamp),
                        yStart: .value("Min", 0),
                        yEnd: .value("Speed", convertSpeed(dataPoint.uploadMbps))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [.green.opacity(0.3), .green.opacity(0.05)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }

            // Upload speed line (on top of area)
            if showUpload {
                ForEach(filteredData) { dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("Speed", convertSpeed(dataPoint.uploadMbps))
                    )
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }
            }

            // Visual crosshair at hover position
            if let selectedDate = selectedDate {
                RuleMark(x: .value("Selected", selectedDate))
                    .foregroundStyle(.gray.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            // Plan speed reference lines
            if showDownload && preferences.downloadPlanSpeed > 0 {
                RuleMark(y: .value("Plan", convertSpeed(preferences.downloadPlanSpeed)))
                    .foregroundStyle(.blue.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            }

            if showUpload && preferences.uploadPlanSpeed > 0 {
                RuleMark(y: .value("Plan", convertSpeed(preferences.uploadPlanSpeed)))
                    .foregroundStyle(.green.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYScale(domain: 0...getMaxYValueShortTerm())
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
               let dataPoint = findNearestDataPoint(for: selectedDate, in: filteredData) {
                ChartTooltipView(
                    timestamp: dataPoint.timestamp,
                    downloadSpeed: showDownload ? dataPoint.downloadMbps : nil,
                    uploadSpeed: showUpload ? dataPoint.uploadMbps : nil,
                    unit: preferences.displayUnit,
                    preferences: preferences
                )
                .offset(x: 10, y: 10)
            }
        }
    }

    private var shortTermChartBasic: some View {
        Chart {
            // Download speed area (gradient fill)
            if showDownload {
                ForEach(filteredData) { dataPoint in
                    AreaMark(
                        x: .value("Time", dataPoint.timestamp),
                        yStart: .value("Min", 0),
                        yEnd: .value("Speed", convertSpeed(dataPoint.downloadMbps))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue.opacity(0.3), .blue.opacity(0.05)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }

            // Download speed line (on top of area)
            if showDownload {
                ForEach(filteredData) { dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("Speed", convertSpeed(dataPoint.downloadMbps))
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }
            }

            // Upload speed area (gradient fill)
            if showUpload {
                ForEach(filteredData) { dataPoint in
                    AreaMark(
                        x: .value("Time", dataPoint.timestamp),
                        yStart: .value("Min", 0),
                        yEnd: .value("Speed", convertSpeed(dataPoint.uploadMbps))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [.green.opacity(0.3), .green.opacity(0.05)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }

            // Upload speed line (on top of area)
            if showUpload {
                ForEach(filteredData) { dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("Speed", convertSpeed(dataPoint.uploadMbps))
                    )
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }
            }

            // Plan speed reference lines
            if showDownload && preferences.downloadPlanSpeed > 0 {
                RuleMark(y: .value("Plan", convertSpeed(preferences.downloadPlanSpeed)))
                    .foregroundStyle(.blue.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            }

            if showUpload && preferences.uploadPlanSpeed > 0 {
                RuleMark(y: .value("Plan", convertSpeed(preferences.uploadPlanSpeed)))
                    .foregroundStyle(.green.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            }
        }
        .chartYScale(domain: 0...getMaxYValueShortTerm())
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
    }

    @ViewBuilder
    private var twentyFourHourChart: some View {
        if #available(macOS 14.0, *) {
            twentyFourHourChartWithSelection
        } else {
            twentyFourHourChartBasic
        }
    }

    @available(macOS 14.0, *)
    private var twentyFourHourChartWithSelection: some View {
        Chart {
            // Average download speed area (gradient fill)
            if showDownload {
                ForEach(historyRecorder.twentyFourHourData) { dataPoint in
                    AreaMark(
                        x: .value("Time", dataPoint.timestamp),
                        yStart: .value("Min", 0),
                        yEnd: .value("Speed", convertSpeed(dataPoint.avgDownloadMbps))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue.opacity(0.3), .blue.opacity(0.05)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }

            // Average download speed line (on top of area)
            if showDownload {
                ForEach(historyRecorder.twentyFourHourData) { dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("Speed", convertSpeed(dataPoint.avgDownloadMbps))
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }
            }

            // Average upload speed area (gradient fill)
            if showUpload {
                ForEach(historyRecorder.twentyFourHourData) { dataPoint in
                    AreaMark(
                        x: .value("Time", dataPoint.timestamp),
                        yStart: .value("Min", 0),
                        yEnd: .value("Speed", convertSpeed(dataPoint.avgUploadMbps))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [.green.opacity(0.3), .green.opacity(0.05)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }

            // Average upload speed line (on top of area)
            if showUpload {
                ForEach(historyRecorder.twentyFourHourData) { dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("Speed", convertSpeed(dataPoint.avgUploadMbps))
                    )
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }
            }

            // Visual crosshair at hover position
            if let selectedDate = selectedDate {
                RuleMark(x: .value("Selected", selectedDate))
                    .foregroundStyle(.gray.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            // Plan speed reference lines
            if showDownload && preferences.downloadPlanSpeed > 0 {
                RuleMark(y: .value("Plan", convertSpeed(preferences.downloadPlanSpeed)))
                    .foregroundStyle(.blue.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            }

            if showUpload && preferences.uploadPlanSpeed > 0 {
                RuleMark(y: .value("Plan", convertSpeed(preferences.uploadPlanSpeed)))
                    .foregroundStyle(.green.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYScale(domain: 0...getMaxYValue24Hour())
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour(), centered: false)
            }
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
               let dataPoint = findNearestHourlyDataPoint(for: selectedDate, in: historyRecorder.twentyFourHourData) {
                ChartTooltipView24Hour(
                    timestamp: dataPoint.timestamp,
                    avgDownloadSpeed: showDownload ? dataPoint.avgDownloadMbps : nil,
                    avgUploadSpeed: showUpload ? dataPoint.avgUploadMbps : nil,
                    maxDownloadSpeed: showDownload ? dataPoint.maxDownloadMbps : nil,
                    maxUploadSpeed: showUpload ? dataPoint.maxUploadMbps : nil,
                    unit: preferences.displayUnit,
                    preferences: preferences
                )
                .offset(x: 10, y: 10)
            }
        }
    }

    private var twentyFourHourChartBasic: some View {
        Chart {
            // Average download speed area (gradient fill)
            if showDownload {
                ForEach(historyRecorder.twentyFourHourData) { dataPoint in
                    AreaMark(
                        x: .value("Time", dataPoint.timestamp),
                        yStart: .value("Min", 0),
                        yEnd: .value("Speed", convertSpeed(dataPoint.avgDownloadMbps))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue.opacity(0.3), .blue.opacity(0.05)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }

            // Average download speed line (on top of area)
            if showDownload {
                ForEach(historyRecorder.twentyFourHourData) { dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("Speed", convertSpeed(dataPoint.avgDownloadMbps))
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }
            }

            // Average upload speed area (gradient fill)
            if showUpload {
                ForEach(historyRecorder.twentyFourHourData) { dataPoint in
                    AreaMark(
                        x: .value("Time", dataPoint.timestamp),
                        yStart: .value("Min", 0),
                        yEnd: .value("Speed", convertSpeed(dataPoint.avgUploadMbps))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [.green.opacity(0.3), .green.opacity(0.05)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }

            // Average upload speed line (on top of area)
            if showUpload {
                ForEach(historyRecorder.twentyFourHourData) { dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("Speed", convertSpeed(dataPoint.avgUploadMbps))
                    )
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }
            }

            // Plan speed reference lines
            if showDownload && preferences.downloadPlanSpeed > 0 {
                RuleMark(y: .value("Plan", convertSpeed(preferences.downloadPlanSpeed)))
                    .foregroundStyle(.blue.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            }

            if showUpload && preferences.uploadPlanSpeed > 0 {
                RuleMark(y: .value("Plan", convertSpeed(preferences.uploadPlanSpeed)))
                    .foregroundStyle(.green.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            }
        }
        .chartYScale(domain: 0...getMaxYValue24Hour())
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour(), centered: false)
            }
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
    }

    // Adaptive X-axis marks based on selected time range
    @available(macOS 13.0, *)
    @AxisContentBuilder
    private var xAxisMarks: some AxisContent {
        switch selectedTimeRange {
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
        HStack(spacing: 20) {
            // Interactive Download legend button
            Button(action: { showDownload.toggle() }) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(showDownload ? .blue : .gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text("下載")
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
            .help("Toggle Download Data")

            // Interactive Upload legend button
            Button(action: { showUpload.toggle() }) {
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(showUpload ? .green : .gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text("上傳")
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
            .help("Toggle Upload Data")

            // Plan speed legend (non-interactive)
            if (showDownload && preferences.downloadPlanSpeed > 0) || (showUpload && preferences.uploadPlanSpeed > 0) {
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
                    Text("方案速度")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }

    // Helper functions
    private func convertSpeed(_ speedMbps: Double) -> Double {
        switch preferences.displayUnit {
        case .mbps:
            return speedMbps
        case .mbps_lower:
            return speedMbps / 8.0 // Convert Mbps to MB/s
        }
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

    // Find nearest data point to the selected date
    private func findNearestDataPoint(for date: Date, in data: [NetworkDataPoint]) -> NetworkDataPoint? {
        guard !data.isEmpty else { return nil }

        return data.min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) })
    }

    // Find nearest hourly data point to the selected date
    private func findNearestHourlyDataPoint(for date: Date, in data: [HourlyDataPoint]) -> HourlyDataPoint? {
        guard !data.isEmpty else { return nil }

        return data.min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) })
    }

    // Calculate maximum Y value for short-term charts (5min, 15min, 30min, 1hr)
    private func getMaxYValueShortTerm() -> Double {
        var maxValue: Double = 100.0 // Default minimum scale

        if showDownload {
            let maxDownload = filteredData.map { convertSpeed($0.downloadMbps) }.max() ?? 0
            maxValue = max(maxValue, maxDownload)
        }

        if showUpload {
            let maxUpload = filteredData.map { convertSpeed($0.uploadMbps) }.max() ?? 0
            maxValue = max(maxValue, maxUpload)
        }

        // Consider plan speed for better scale
        if preferences.downloadPlanSpeed > 0 {
            maxValue = max(maxValue, convertSpeed(preferences.downloadPlanSpeed))
        }
        if preferences.uploadPlanSpeed > 0 {
            maxValue = max(maxValue, convertSpeed(preferences.uploadPlanSpeed))
        }

        // Add 10% padding for better visualization
        return maxValue * 1.1
    }

    // Calculate maximum Y value for 24-hour chart
    private func getMaxYValue24Hour() -> Double {
        var maxValue: Double = 100.0 // Default minimum scale

        if showDownload {
            let maxDownload = historyRecorder.twentyFourHourData.map { convertSpeed($0.avgDownloadMbps) }.max() ?? 0
            maxValue = max(maxValue, maxDownload)
        }

        if showUpload {
            let maxUpload = historyRecorder.twentyFourHourData.map { convertSpeed($0.avgUploadMbps) }.max() ?? 0
            maxValue = max(maxValue, maxUpload)
        }

        // Consider plan speed for better scale
        if preferences.downloadPlanSpeed > 0 {
            maxValue = max(maxValue, convertSpeed(preferences.downloadPlanSpeed))
        }
        if preferences.uploadPlanSpeed > 0 {
            maxValue = max(maxValue, convertSpeed(preferences.uploadPlanSpeed))
        }

        // Add 10% padding for better visualization
        return maxValue * 1.1
    }
}

// MARK: - Tooltip Views

@available(macOS 13.0, *)
struct ChartTooltipView: View {
    let timestamp: Date
    let downloadSpeed: Double?
    let uploadSpeed: Double?
    let unit: UserPreferences.SpeedUnit
    let preferences: UserPreferences

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Timestamp
            Text(dateFormatter.string(from: timestamp))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            // Speed information
            VStack(alignment: .leading, spacing: 2) {
                if let downloadSpeed = downloadSpeed {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 4, height: 4)
                        Text(formatSpeed(downloadSpeed))
                            .font(.system(size: 12))
                            .foregroundColor(isPeakConcerning(speed: downloadSpeed, planSpeed: preferences.downloadPlanSpeed) ? .orange : .primary)
                    }
                }

                if let uploadSpeed = uploadSpeed {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(.green)
                            .frame(width: 4, height: 4)
                        Text(formatSpeed(uploadSpeed))
                            .font(.system(size: 12))
                            .foregroundColor(isPeakConcerning(speed: uploadSpeed, planSpeed: preferences.uploadPlanSpeed) ? .orange : .primary)
                    }
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
        guard planSpeed > 0 else { return false }
        return speed >= planSpeed * 0.9
    }
}

@available(macOS 13.0, *)
struct ChartTooltipView24Hour: View {
    let timestamp: Date
    let avgDownloadSpeed: Double?
    let avgUploadSpeed: Double?
    let maxDownloadSpeed: Double?
    let maxUploadSpeed: Double?
    let unit: UserPreferences.SpeedUnit
    let preferences: UserPreferences

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Timestamp
            Text(dateFormatter.string(from: timestamp))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            // Speed information
            VStack(alignment: .leading, spacing: 2) {
                if let avgDownloadSpeed = avgDownloadSpeed {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 4, height: 4)
                        Text("平均 \(formatSpeed(avgDownloadSpeed))")
                            .font(.system(size: 12))
                            .foregroundColor(isPeakConcerning(speed: avgDownloadSpeed, planSpeed: preferences.downloadPlanSpeed) ? .orange : .primary)
                    }

                    if let maxDownloadSpeed = maxDownloadSpeed, maxDownloadSpeed != avgDownloadSpeed {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.blue.opacity(0.5))
                                .frame(width: 4, height: 4)
                            Text("峰值 \(formatSpeed(maxDownloadSpeed))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if let avgUploadSpeed = avgUploadSpeed {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(.green)
                            .frame(width: 4, height: 4)
                        Text("平均 \(formatSpeed(avgUploadSpeed))")
                            .font(.system(size: 12))
                            .foregroundColor(isPeakConcerning(speed: avgUploadSpeed, planSpeed: preferences.uploadPlanSpeed) ? .orange : .primary)
                    }

                    if let maxUploadSpeed = maxUploadSpeed, maxUploadSpeed != avgUploadSpeed {
                        HStack(spacing: 4) {
                            Rectangle()
                                .fill(.green.opacity(0.5))
                                .frame(width: 4, height: 4)
                            Text("峰值 \(formatSpeed(maxUploadSpeed))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
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
        guard planSpeed > 0 else { return false }
        return speed >= planSpeed * 0.9
    }
}

// MARK: - Statistics Card View

@available(macOS 13.0, *)
struct StatisticsCardView: View {
    let data: [NetworkDataPoint]
    let showDownload: Bool
    let showUpload: Bool
    let unit: UserPreferences.SpeedUnit
    let timeRange: NetworkChartView.TimeRange
    let currentDownloadSpeed: Double  // Real-time current speed
    let currentUploadSpeed: Double    // Real-time current speed

    // Add bindings for toggling
    var onToggleDownload: (() -> Void)?
    var onToggleUpload: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Download statistics - always show but toggleable
            StatColumnView(
                title: "下載",
                color: .blue,
                current: currentDownloadSpeed,
                peak: peakDownloadSpeed,
                average: averageDownloadSpeed,
                unit: unit,
                isActive: showDownload,
                onToggle: onToggleDownload
            )
            .frame(maxWidth: .infinity)
            .opacity(showDownload ? 1.0 : 0.5)

            Divider()

            // Upload statistics - always show but toggleable
            StatColumnView(
                title: "上傳",
                color: .green,
                current: currentUploadSpeed,
                peak: peakUploadSpeed,
                average: averageUploadSpeed,
                unit: unit,
                isActive: showUpload,
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

    // Calculate peak speed
    private var peakDownloadSpeed: Double {
        data.map { $0.downloadMbps }.max() ?? 0
    }

    private var peakUploadSpeed: Double {
        data.map { $0.uploadMbps }.max() ?? 0
    }

    // Calculate average speed
    private var averageDownloadSpeed: Double {
        guard !data.isEmpty else { return 0 }
        let sum = data.map { $0.downloadMbps }.reduce(0, +)
        return sum / Double(data.count)
    }

    private var averageUploadSpeed: Double {
        guard !data.isEmpty else { return 0 }
        let sum = data.map { $0.uploadMbps }.reduce(0, +)
        return sum / Double(data.count)
    }
}

@available(macOS 13.0, *)
struct StatColumnView: View {
    let title: String
    let color: Color
    let current: Double
    let peak: Double
    let average: Double
    let unit: UserPreferences.SpeedUnit
    let isActive: Bool
    var onToggle: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title - with visual feedback
            HStack(spacing: 4) {
                Circle()
                    .fill(isActive ? color : color.opacity(0.3))
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isActive ? .primary : .secondary)
            }

            // Current speed (prominent)
            VStack(alignment: .leading, spacing: 2) {
                Text("即時")
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
                    Text("峰值")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatSpeed(peak))
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(isActive ? .primary : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("平均")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatSpeed(average))
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
        .help("點擊切換 \(title) 資料顯示")
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

// Provide a pointing-hand cursor on macOS while remaining a no-op elsewhere.
private extension View {
    func pointerCursor() -> some View {
#if os(macOS)
        return self.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
#else
        return self
#endif
    }
}
