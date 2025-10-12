import SwiftUI
import AppKit

public struct PopoverView: View {
    @ObservedObject var viewModel: NetworkMonitorViewModel
    @State private var showingSettings = false
    @State private var showDownload = true  // 預設顯示下載資料
    @State private var showUpload = true    // 預設顯示上傳資料
    @State private var showingExportMenu = false
    @State private var exportSuccess = false
    @State private var exportError = false

    public init(viewModel: NetworkMonitorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header - Fixed at top
            VStack(spacing: 16) {
                // Title and Control Buttons
                HStack {
                    Text("Network Peak Monitor")
                        .font(.headline)
                    Spacer()

                    // Control buttons
                    HStack(spacing: 8) {
                        // Pin button
                        Button(action: { viewModel.preferences.isPinned.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: viewModel.preferences.isPinned ? "pin.fill" : "pin")
                                    .foregroundColor(viewModel.preferences.isPinned ? .white : .purple)
                                    .font(.caption)
                                Text("Pin")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(viewModel.preferences.isPinned ? .purple : Color.purple.opacity(0.1))
                            .foregroundColor(viewModel.preferences.isPinned ? .white : .purple)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("固定視窗")

                        // Settings button
                        Button(action: { showingSettings = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "gear")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                Text("Settings")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .foregroundColor(.secondary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("Settings")
                    }
                }

                Divider()
            }
            .padding()
            .padding(.top, 8)
            .background(Color.Adaptive.background)

            // Scrollable content area
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    // Chart Section (always visible)
                    if #available(macOS 13.0, *) {
                        NetworkChartView(
                            historyRecorder: viewModel.historyRecorder,
                            preferences: viewModel.preferences,
                            showUpload: $showUpload,
                            showDownload: $showDownload
                        )
                    } else {
                        VStack {
                            Text("圖表功能需要 macOS 13.0 或更新版本")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                        .frame(height: 100)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }

                    Divider()

                    // Upload and Download Sections
                    if showDownload && showUpload {
                        // Side-by-side layout when both are visible
                        HStack(alignment: .top, spacing: 16) {
                            // Download Section - Statistics
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .foregroundColor(Color.Adaptive.downloadPrimary)
                                    Text("下載統計 (Download Stats)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }

                                SpeedRow(
                                    label: "今日峰值",
                                    speed: viewModel.peakRecorder.todayPeakDownload,
                                    unit: viewModel.preferences.displayUnit,
                                    planSpeed: viewModel.preferences.downloadPlanSpeed,
                                    viewModel: viewModel,
                                    timestamp: viewModel.peakRecorder.todayPeakDownloadTime
                                )

                                SpeedRow(
                                    label: "歷史總峰值",
                                    speed: viewModel.peakRecorder.allTimePeakDownload,
                                    unit: viewModel.preferences.displayUnit,
                                    planSpeed: viewModel.preferences.downloadPlanSpeed,
                                    viewModel: viewModel,
                                    timestamp: viewModel.peakRecorder.allTimePeakDownloadTime
                                )

                                HourlyPeakRow(
                                    label: "1小時峰值",
                                    speed: viewModel.peakRecorder.hourlyPeakDownload,
                                    time: viewModel.peakRecorder.hourlyPeakDownloadTime,
                                    unit: viewModel.preferences.displayUnit,
                                    viewModel: viewModel
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            // Upload Section - Statistics
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .foregroundColor(Color.Adaptive.uploadPrimary)
                                    Text("上傳統計 (Upload Stats)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }

                                SpeedRow(
                                    label: "今日峰值",
                                    speed: viewModel.peakRecorder.todayPeakUpload,
                                    unit: viewModel.preferences.displayUnit,
                                    planSpeed: viewModel.preferences.uploadPlanSpeed,
                                    viewModel: viewModel,
                                    timestamp: viewModel.peakRecorder.todayPeakUploadTime
                                )

                                SpeedRow(
                                    label: "歷史總峰值",
                                    speed: viewModel.peakRecorder.allTimePeakUpload,
                                    unit: viewModel.preferences.displayUnit,
                                    planSpeed: viewModel.preferences.uploadPlanSpeed,
                                    viewModel: viewModel,
                                    timestamp: viewModel.peakRecorder.allTimePeakUploadTime
                                )

                                HourlyPeakRow(
                                    label: "1小時峰值",
                                    speed: viewModel.peakRecorder.hourlyPeakUpload,
                                    time: viewModel.peakRecorder.hourlyPeakUploadTime,
                                    unit: viewModel.preferences.displayUnit,
                                    viewModel: viewModel
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Divider()
                    } else if showUpload {
                        // Upload Section only - Statistics
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundColor(.green)
                                Text("上傳統計 (Upload Stats)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }

                            SpeedRow(
                                label: "今日峰值",
                                speed: viewModel.peakRecorder.todayPeakUpload,
                                unit: viewModel.preferences.displayUnit,
                                planSpeed: viewModel.preferences.uploadPlanSpeed,
                                viewModel: viewModel,
                                timestamp: viewModel.peakRecorder.todayPeakUploadTime
                            )

                            SpeedRow(
                                label: "歷史總峰值",
                                speed: viewModel.peakRecorder.allTimePeakUpload,
                                unit: viewModel.preferences.displayUnit,
                                planSpeed: viewModel.preferences.uploadPlanSpeed,
                                viewModel: viewModel,
                                timestamp: viewModel.peakRecorder.allTimePeakUploadTime
                            )

                            HourlyPeakRow(
                                label: "1小時峰值",
                                speed: viewModel.peakRecorder.hourlyPeakUpload,
                                time: viewModel.peakRecorder.hourlyPeakUploadTime,
                                unit: viewModel.preferences.displayUnit,
                                viewModel: viewModel
                            )
                        }

                        Divider()
                    } else if showDownload {
                        // Download Section only - Statistics
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundColor(.blue)
                                Text("下載統計 (Download Stats)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }

                            SpeedRow(
                                label: "今日峰值",
                                speed: viewModel.peakRecorder.todayPeakDownload,
                                unit: viewModel.preferences.displayUnit,
                                planSpeed: viewModel.preferences.downloadPlanSpeed,
                                viewModel: viewModel,
                                timestamp: viewModel.peakRecorder.todayPeakDownloadTime
                            )

                            SpeedRow(
                                label: "歷史總峰值",
                                speed: viewModel.peakRecorder.allTimePeakDownload,
                                unit: viewModel.preferences.displayUnit,
                                planSpeed: viewModel.preferences.downloadPlanSpeed,
                                viewModel: viewModel,
                                timestamp: viewModel.peakRecorder.allTimePeakDownloadTime
                            )

                            HourlyPeakRow(
                                label: "1小時峰值",
                                speed: viewModel.peakRecorder.hourlyPeakDownload,
                                time: viewModel.peakRecorder.hourlyPeakDownloadTime,
                                unit: viewModel.preferences.displayUnit,
                                viewModel: viewModel
                            )
                        }

                        Divider()
                    }

                    // Network Anomaly Section
                    if viewModel.anomalyDetector.isDetectionEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: viewModel.anomalyDetector.isConnectionStable ? "wifi" : "wifi.exclamationmark")
                                    .foregroundColor(viewModel.anomalyDetector.isConnectionStable ? .green : Color.Adaptive.error)
                                Text("網路狀態")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(viewModel.anomalyDetector.isConnectionStable ? "穩定" : "異常")
                                    .font(.caption)
                                    .foregroundColor(viewModel.anomalyDetector.isConnectionStable ? .green : Color.Adaptive.error)
                                    .fontWeight(.bold)
                            }

                            let summary = viewModel.anomalyDetector.getAnomalySummary()
                            if summary.hasAnomalies {
                                HStack(spacing: 12) {
                                    if summary.connectionDrops > 0 {
                                        HStack(spacing: 4) {
                                            Image(systemName: "wifi.exclamationmark")
                                                .font(.caption2)
                                            Text("\(summary.connectionDrops) 次中斷")
                                                .font(.caption2)
                                        }
                                        .foregroundColor(Color.Adaptive.error)
                                    }
                                    if summary.speedDrops > 0 {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.down.circle.fill")
                                                .font(.caption2)
                                            Text("\(summary.speedDrops) 次驟降")
                                                .font(.caption2)
                                        }
                                        .foregroundColor(Color.Adaptive.warning)
                                    }
                                }

                                // Show recent anomalies
                                if !viewModel.anomalyDetector.recentAnomalies.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 4) {
                                            ForEach(viewModel.anomalyDetector.recentAnomalies.prefix(5)) { anomaly in
                                                AnomalyBadge(anomaly: anomaly)
                                            }
                                        }
                                        .padding(.horizontal, 1)
                                    }
                                }
                            } else {
                                Text("近1小時無異常記錄")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()
                    }

                    // Peak Approach Counter Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Color.Adaptive.warning)
                            Text("今日接近峰值")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        HStack {
                            Text("次數: \(viewModel.peakApproachTracker.todayApproachCount)")
                                .font(.body)
                            Spacer()
                        }

                        if !viewModel.peakApproachTracker.approachTimestamps.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 4) {
                                    ForEach(viewModel.peakApproachTracker.getFormattedApproachTimes(), id: \.self) { time in
                                        Text(time)
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.2))
                                            .cornerRadius(4)
                                    }
                                }
                                .padding(.horizontal, 1)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }

            // Bottom buttons - Fixed at bottom
            VStack(spacing: 12) {
                Divider()

                HStack(spacing: 8) {
                    // Export Data Menu
                    Menu {
                        Button("導出今日數據") {
                            exportData(format: .todayData)
                        }
                        Button("導出峰值記錄") {
                            exportData(format: .peakHistory)
                        }
                        Button("導出完整歷史") {
                            exportData(format: .fullHistory)
                        }
                    } label: {
                        Label("導出數據", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("導出網路數據為 CSV 檔案")

                    // Reset Button
                    Button("重置峰值記錄") {
                        viewModel.resetPeaks()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)

                    Spacer()

                    // Quit Button
                    Button("退出應用程式") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .background(Color.Adaptive.background)
        }
        .frame(width: 450, height: 600)
        .animation(.easeInOut(duration: 0.3), value: showDownload)
        .animation(.easeInOut(duration: 0.3), value: showUpload)
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .alert("導出成功", isPresented: $exportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("數據已成功導出至下載資料夾")
        }
        .alert("導出失敗", isPresented: $exportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("無法導出數據，請稍後再試")
        }
    }

    // MARK: - Helper Functions

    private func exportData(format: DataExportService.ExportFormat) {
        viewModel.exportData(format: format) { result in
            switch result {
            case .success(let url):
                DataExportService.revealInFinder(url: url)
                exportSuccess = true
            case .failure:
                exportError = true
            }
        }
    }

}

struct SpeedRow: View {
    let label: String
    let speed: Double
    let unit: UserPreferences.SpeedUnit
    let planSpeed: Double
    let viewModel: NetworkMonitorViewModel
    let timestamp: Date?

    var body: some View {
        HStack {
            Text(label + ":")
                .frame(maxWidth: 80, alignment: .leading)
            Text(viewModel.formatSpeed(speed, unit: unit) + " " + unit.displayName)
                .foregroundColor(
                    viewModel.isPeakConcerning(speed: speed, planSpeed: planSpeed) ? Color.Adaptive.warning : Color.Adaptive.text
                )
                .fontWeight(
                    viewModel.isPeakConcerning(speed: speed, planSpeed: planSpeed) ? .bold : .regular
                )
            if viewModel.isPeakConcerning(speed: speed, planSpeed: planSpeed) {
                let relativeTime = viewModel.formatRelativeTime(timestamp)
                if !relativeTime.isEmpty {
                    Text("(\(relativeTime))")
                        .foregroundColor(Color.Adaptive.error)
                        .font(.caption)
                        .fontWeight(.bold)
                }
            }
            Spacer()
        }
    }
}

struct HourlyPeakRow: View {
    let label: String
    let speed: Double
    let time: Date?
    let unit: UserPreferences.SpeedUnit
    let viewModel: NetworkMonitorViewModel

    var body: some View {
        HStack {
            Text(label + ":")
                .frame(maxWidth: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.formatSpeed(speed, unit: unit) + " " + unit.displayName)
                    .font(.body)
                if let time = time {
                    Text(viewModel.formatTime(time))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }
}

struct AnomalyBadge: View {
    let anomaly: NetworkAnomaly

    private var timeAgo: String {
        let now = Date()
        let interval = now.timeIntervalSince(anomaly.timestamp)

        if interval < 60 {
            return "剛剛"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)分鐘前"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)小時前"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: anomaly.type.icon)
                    .font(.caption2)
                Text(anomaly.type.displayText)
                    .font(.caption2)
                    .lineLimit(2)
            }
            Text(timeAgo)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .cornerRadius(4)
        .frame(maxWidth: 200)
    }

    private var backgroundColor: Color {
        switch anomaly.type.severity {
        case .low:
            return Color.yellow.opacity(0.2)
        case .medium:
            return Color.orange.opacity(0.2)
        case .high:
            return Color.red.opacity(0.2)
        }
    }
}