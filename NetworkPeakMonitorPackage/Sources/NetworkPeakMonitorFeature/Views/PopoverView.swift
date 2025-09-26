import SwiftUI
import AppKit

public struct PopoverView: View {
    @ObservedObject var viewModel: NetworkMonitorViewModel
    @State private var showingSettings = false
    @State private var showingChart = true  // 預設開啟圖表顯示
    @State private var showDownload = true  // 預設顯示下載資料
    @State private var showUpload = true    // 預設顯示上傳資料

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
                        // Chart toggle button
                        Button(action: { showingChart.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: showingChart ? "chart.line.uptrend.xyaxis.circle.fill" : "chart.line.uptrend.xyaxis.circle")
                                    .foregroundColor(showingChart ? .white : .blue)
                                    .font(.caption)
                                Text("Chart")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(showingChart ? .blue : Color.blue.opacity(0.1))
                            .foregroundColor(showingChart ? .white : .blue)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("Toggle Chart View")

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
            .background(Color(NSColor.windowBackgroundColor))

            // Scrollable content area
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    // Chart Section (when enabled)
                    if showingChart {
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
                    }

                    // Upload and Download Sections
                    if showDownload && showUpload {
                        // Side-by-side layout when both are visible
                        HStack(alignment: .top, spacing: 16) {
                            // Upload Section
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .foregroundColor(.green)
                                    Text("上傳 (Upload)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }

                                SpeedRow(
                                    label: "即時",
                                    speed: viewModel.currentSpeed.uploadMbps,
                                    unit: viewModel.preferences.displayUnit,
                                    planSpeed: viewModel.preferences.uploadPlanSpeed,
                                    viewModel: viewModel
                                )

                                SpeedRow(
                                    label: "今日峰值",
                                    speed: viewModel.peakRecorder.todayPeakUpload,
                                    unit: viewModel.preferences.displayUnit,
                                    planSpeed: viewModel.preferences.uploadPlanSpeed,
                                    viewModel: viewModel
                                )

                                SpeedRow(
                                    label: "歷史總峰值",
                                    speed: viewModel.peakRecorder.allTimePeakUpload,
                                    unit: viewModel.preferences.displayUnit,
                                    planSpeed: viewModel.preferences.uploadPlanSpeed,
                                    viewModel: viewModel
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

                            // Download Section
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .foregroundColor(.blue)
                                    Text("下載 (Download)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }

                                SpeedRow(
                                    label: "即時",
                                    speed: viewModel.currentSpeed.downloadMbps,
                                    unit: viewModel.preferences.displayUnit,
                                    planSpeed: viewModel.preferences.downloadPlanSpeed,
                                    viewModel: viewModel
                                )

                                SpeedRow(
                                    label: "今日峰值",
                                    speed: viewModel.peakRecorder.todayPeakDownload,
                                    unit: viewModel.preferences.displayUnit,
                                    planSpeed: viewModel.preferences.downloadPlanSpeed,
                                    viewModel: viewModel
                                )

                                SpeedRow(
                                    label: "歷史總峰值",
                                    speed: viewModel.peakRecorder.allTimePeakDownload,
                                    unit: viewModel.preferences.displayUnit,
                                    planSpeed: viewModel.preferences.downloadPlanSpeed,
                                    viewModel: viewModel
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
                        }

                        Divider()
                    } else if showUpload {
                        // Upload Section only
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundColor(.green)
                                Text("上傳 (Upload)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }

                            SpeedRow(
                                label: "即時",
                                speed: viewModel.currentSpeed.uploadMbps,
                                unit: viewModel.preferences.displayUnit,
                                planSpeed: viewModel.preferences.uploadPlanSpeed,
                                viewModel: viewModel
                            )

                            SpeedRow(
                                label: "今日峰值",
                                speed: viewModel.peakRecorder.todayPeakUpload,
                                unit: viewModel.preferences.displayUnit,
                                planSpeed: viewModel.preferences.uploadPlanSpeed,
                                viewModel: viewModel
                            )

                            SpeedRow(
                                label: "歷史總峰值",
                                speed: viewModel.peakRecorder.allTimePeakUpload,
                                unit: viewModel.preferences.displayUnit,
                                planSpeed: viewModel.preferences.uploadPlanSpeed,
                                viewModel: viewModel
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
                        // Download Section only
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundColor(.blue)
                                Text("下載 (Download)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }

                            SpeedRow(
                                label: "即時",
                                speed: viewModel.currentSpeed.downloadMbps,
                                unit: viewModel.preferences.displayUnit,
                                planSpeed: viewModel.preferences.downloadPlanSpeed,
                                viewModel: viewModel
                            )

                            SpeedRow(
                                label: "今日峰值",
                                speed: viewModel.peakRecorder.todayPeakDownload,
                                unit: viewModel.preferences.displayUnit,
                                planSpeed: viewModel.preferences.downloadPlanSpeed,
                                viewModel: viewModel
                            )

                            SpeedRow(
                                label: "歷史總峰值",
                                speed: viewModel.peakRecorder.allTimePeakDownload,
                                unit: viewModel.preferences.displayUnit,
                                planSpeed: viewModel.preferences.downloadPlanSpeed,
                                viewModel: viewModel
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

                    // Peak Approach Counter Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
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

                HStack(spacing: 12) {
                    // Reset Button
                    Button("重置峰值記錄") {
                        viewModel.resetPeaks()
                    }
                    .buttonStyle(.bordered)

                    // Quit Button
                    Button("退出應用程式") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: showingChart ? 450 : 350, height: 600)
        .animation(.easeInOut(duration: 0.3), value: showingChart)
        .animation(.easeInOut(duration: 0.3), value: showDownload)
        .animation(.easeInOut(duration: 0.3), value: showUpload)
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
    }

}

struct SpeedRow: View {
    let label: String
    let speed: Double
    let unit: UserPreferences.SpeedUnit
    let planSpeed: Double
    let viewModel: NetworkMonitorViewModel

    var body: some View {
        HStack {
            Text(label + ":")
                .frame(maxWidth: 80, alignment: .leading)
            Text(viewModel.formatSpeed(speed, unit: unit) + " " + unit.displayName)
                .foregroundColor(
                    viewModel.isPeakConcerning(speed: speed, planSpeed: planSpeed) ? .orange : .primary
                )
                .fontWeight(
                    viewModel.isPeakConcerning(speed: speed, planSpeed: planSpeed) ? .bold : .regular
                )
            if viewModel.isPeakConcerning(speed: speed, planSpeed: planSpeed) {
                Text("(!! 高 !!)")
                    .foregroundColor(.red)
                    .font(.caption)
                    .fontWeight(.bold)
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