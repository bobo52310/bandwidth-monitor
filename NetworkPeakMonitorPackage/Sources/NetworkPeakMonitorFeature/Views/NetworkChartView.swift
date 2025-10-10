import SwiftUI
import Charts
#if os(macOS)
import AppKit
#endif

@available(macOS 13.0, *)
public struct NetworkChartView: View {
    @ObservedObject var historyRecorder: NetworkHistoryRecorder
    @ObservedObject var preferences: UserPreferences
    @State private var selectedTimeRange: TimeRange = .oneHour
    @Binding var showUpload: Bool
    @Binding var showDownload: Bool

    // Hover tracking state
    @State private var selectedDate: Date?
    @State private var hoverLocation: CGPoint?

    public enum TimeRange: String, CaseIterable {
        case oneHour = "1 小時"
        case twentyFourHours = "24 小時"
    }

    public init(historyRecorder: NetworkHistoryRecorder, preferences: UserPreferences, showUpload: Binding<Bool>, showDownload: Binding<Bool>) {
        self.historyRecorder = historyRecorder
        self.preferences = preferences
        self._showUpload = showUpload
        self._showDownload = showDownload
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Time Range Picker
            Picker("Time Range", selection: $selectedTimeRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

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
        switch selectedTimeRange {
        case .oneHour:
            oneHourChart
        case .twentyFourHours:
            twentyFourHourChart
        }
    }

    @ViewBuilder
    private var oneHourChart: some View {
        if #available(macOS 14.0, *) {
            oneHourChartWithSelection
        } else {
            oneHourChartBasic
        }
    }

    @available(macOS 14.0, *)
    private var oneHourChartWithSelection: some View {
        Chart {
            // Download speed area (gradient fill)
            if showDownload {
                ForEach(historyRecorder.oneHourData) { dataPoint in
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
                ForEach(historyRecorder.oneHourData) { dataPoint in
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
                ForEach(historyRecorder.oneHourData) { dataPoint in
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
                ForEach(historyRecorder.oneHourData) { dataPoint in
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
        .chartYScale(domain: 0...getMaxYValue())
        .chartXAxis {
            AxisMarks(values: .stride(by: .minute, count: 10)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute(), centered: false)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    Text("\(formatAxisValue(value.as(Double.self) ?? 0)) \(preferences.displayUnit.displayName)")
                        .font(.caption2)
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea.background(.clear)
        }
        .overlay(alignment: .topLeading) {
            if let selectedDate = selectedDate,
               let dataPoint = findNearestDataPoint(for: selectedDate, in: historyRecorder.oneHourData) {
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

    private var oneHourChartBasic: some View {
        Chart {
            // Download speed area (gradient fill)
            if showDownload {
                ForEach(historyRecorder.oneHourData) { dataPoint in
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
                ForEach(historyRecorder.oneHourData) { dataPoint in
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
                ForEach(historyRecorder.oneHourData) { dataPoint in
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
                ForEach(historyRecorder.oneHourData) { dataPoint in
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
        .chartYScale(domain: 0...getMaxYValue())
        .chartXAxis {
            AxisMarks(values: .stride(by: .minute, count: 10)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute(), centered: false)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    Text("\(formatAxisValue(value.as(Double.self) ?? 0)) \(preferences.displayUnit.displayName)")
                        .font(.caption2)
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
                        .font(.caption2)
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
                        .font(.caption2)
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea.background(.clear)
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
                        .font(.caption)
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
                        .font(.caption)
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
                        .font(.caption)
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

    // Calculate maximum Y value for 1-hour chart
    private func getMaxYValue() -> Double {
        var maxValue: Double = 100.0 // Default minimum scale

        if showDownload {
            let maxDownload = historyRecorder.oneHourData.map { convertSpeed($0.downloadMbps) }.max() ?? 0
            maxValue = max(maxValue, maxDownload)
        }

        if showUpload {
            let maxUpload = historyRecorder.oneHourData.map { convertSpeed($0.uploadMbps) }.max() ?? 0
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
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            // Speed information
            VStack(alignment: .leading, spacing: 2) {
                if let downloadSpeed = downloadSpeed {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 4, height: 4)
                        Text(formatSpeed(downloadSpeed))
                            .font(.system(size: 10))
                            .foregroundColor(isPeakConcerning(speed: downloadSpeed, planSpeed: preferences.downloadPlanSpeed) ? .orange : .primary)
                    }
                }

                if let uploadSpeed = uploadSpeed {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(.green)
                            .frame(width: 4, height: 4)
                        Text(formatSpeed(uploadSpeed))
                            .font(.system(size: 10))
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
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            // Speed information
            VStack(alignment: .leading, spacing: 2) {
                if let avgDownloadSpeed = avgDownloadSpeed {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 4, height: 4)
                        Text("平均 \(formatSpeed(avgDownloadSpeed))")
                            .font(.system(size: 10))
                            .foregroundColor(isPeakConcerning(speed: avgDownloadSpeed, planSpeed: preferences.downloadPlanSpeed) ? .orange : .primary)
                    }

                    if let maxDownloadSpeed = maxDownloadSpeed, maxDownloadSpeed != avgDownloadSpeed {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.blue.opacity(0.5))
                                .frame(width: 4, height: 4)
                            Text("峰值 \(formatSpeed(maxDownloadSpeed))")
                                .font(.system(size: 9))
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
                            .font(.system(size: 10))
                            .foregroundColor(isPeakConcerning(speed: avgUploadSpeed, planSpeed: preferences.uploadPlanSpeed) ? .orange : .primary)
                    }

                    if let maxUploadSpeed = maxUploadSpeed, maxUploadSpeed != avgUploadSpeed {
                        HStack(spacing: 4) {
                            Rectangle()
                                .fill(.green.opacity(0.5))
                                .frame(width: 4, height: 4)
                            Text("峰值 \(formatSpeed(maxUploadSpeed))")
                                .font(.system(size: 9))
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
