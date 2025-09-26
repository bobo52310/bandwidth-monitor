import SwiftUI
import Charts

@available(macOS 13.0, *)
public struct NetworkChartView: View {
    @ObservedObject var historyRecorder: NetworkHistoryRecorder
    @ObservedObject var preferences: UserPreferences
    @State private var selectedTimeRange: TimeRange = .oneHour
    let showDownload: Bool
    let showUpload: Bool

    public enum TimeRange: String, CaseIterable {
        case oneHour = "1 小時"
        case twentyFourHours = "24 小時"
    }

    public init(historyRecorder: NetworkHistoryRecorder, preferences: UserPreferences, showDownload: Bool = true, showUpload: Bool = true) {
        self.historyRecorder = historyRecorder
        self.preferences = preferences
        self.showDownload = showDownload
        self.showUpload = showUpload
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

    private var oneHourChart: some View {
        Chart {
            // Download speed line
            if showDownload {
                ForEach(historyRecorder.oneHourData) { dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("Speed", convertSpeed(dataPoint.downloadMbps))
                    )
                    .foregroundStyle(.blue)
                    .symbol(.circle)
                }
            }

            // Upload speed line
            if showUpload {
                ForEach(historyRecorder.oneHourData) { dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("Speed", convertSpeed(dataPoint.uploadMbps))
                    )
                    .foregroundStyle(.green)
                    .symbol(.square)
                }
            }

            // Plan speed reference lines
            if showDownload && preferences.downloadPlanSpeed > 0 {
                RuleMark(y: .value("Plan", convertSpeed(preferences.downloadPlanSpeed)))
                    .foregroundStyle(.blue.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }

            if showUpload && preferences.uploadPlanSpeed > 0 {
                RuleMark(y: .value("Plan", convertSpeed(preferences.uploadPlanSpeed)))
                    .foregroundStyle(.green.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
        }
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

    private var twentyFourHourChart: some View {
        Chart {
            // Average download speed line
            if showDownload {
                ForEach(historyRecorder.twentyFourHourData) { dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("Speed", convertSpeed(dataPoint.avgDownloadMbps))
                    )
                    .foregroundStyle(.blue)
                    .symbol(.circle)
                }
            }

            // Average upload speed line
            if showUpload {
                ForEach(historyRecorder.twentyFourHourData) { dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("Speed", convertSpeed(dataPoint.avgUploadMbps))
                    )
                    .foregroundStyle(.green)
                    .symbol(.square)
                }
            }

            // Max speed area (optional, commented out to avoid clutter)
            /*
            ForEach(historyRecorder.twentyFourHourData) { dataPoint in
                AreaMark(
                    x: .value("Time", dataPoint.timestamp),
                    yStart: .value("Min", convertSpeed(dataPoint.avgDownloadMbps)),
                    yEnd: .value("Max", convertSpeed(dataPoint.maxDownloadMbps))
                )
                .foregroundStyle(.blue.opacity(0.2))
            }
            */

            // Plan speed reference lines
            if showDownload && preferences.downloadPlanSpeed > 0 {
                RuleMark(y: .value("Plan", convertSpeed(preferences.downloadPlanSpeed)))
                    .foregroundStyle(.blue.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }

            if showUpload && preferences.uploadPlanSpeed > 0 {
                RuleMark(y: .value("Plan", convertSpeed(preferences.uploadPlanSpeed)))
                    .foregroundStyle(.green.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
        }
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
            // Download legend
            if showDownload {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                    Text("下載")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Upload legend
            if showUpload {
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("上傳")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Plan speed legend
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
}