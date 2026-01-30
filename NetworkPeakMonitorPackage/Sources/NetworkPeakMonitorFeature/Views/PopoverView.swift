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
    @State private var showingMonthlyReport = false

    public init(viewModel: NetworkMonitorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header - Fixed at top
            VStack(spacing: 16) {
                // Title and Control Buttons
                HStack {
                    Text(L10n.appTitle)
                        .font(.title3)
                    Spacer()

                    // Control buttons
                    HStack(spacing: 8) {
                        // Pin button
                        Button(action: { viewModel.preferences.isPinned.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: viewModel.preferences.isPinned ? "pin.fill" : "pin")
                                    .foregroundColor(viewModel.preferences.isPinned ? .white : .purple)
                                    .font(.subheadline)
                                Text(L10n.buttonPin)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(viewModel.preferences.isPinned ? .purple : Color.purple.opacity(0.1))
                            .foregroundColor(viewModel.preferences.isPinned ? .white : .purple)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.tooltipPinWindow)

                        // Settings button
                        Button(action: { showingSettings = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "gear")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                                Text(L10n.buttonSettings)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .foregroundColor(.secondary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.buttonSettings)
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
                            currentSpeed: viewModel.currentSpeed,
                            showUpload: $showUpload,
                            showDownload: $showDownload
                        )
                    } else {
                        VStack {
                            Text(L10n.chartRequiresMacOS13)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                        .frame(height: 100)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }

                    Divider()

                    // Peak Approach Counter Section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "gauge.high")
                                .foregroundColor(Color.Adaptive.warning)
                            Text(L10n.approachingSpeedLimit(Int(max(viewModel.preferences.downloadPlanSpeed, viewModel.preferences.uploadPlanSpeed))))
                                .font(.headline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(viewModel.peakApproachTracker.todayApproachCount)")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(viewModel.peakApproachTracker.todayApproachCount > 0 ? Color.Adaptive.warning : .secondary)
                                .monospacedDigit()
                            Text(L10n.peakTimesUnit)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if !viewModel.peakApproachTracker.approachTimestamps.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.peakTriggerTime)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(viewModel.peakApproachTracker.getFormattedApproachTimes(), id: \.self) { time in
                                            HStack(spacing: 4) {
                                                Image(systemName: "clock.fill")
                                                    .font(.caption)
                                                Text(time)
                                                    .font(.subheadline)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.orange.opacity(0.15))
                                            .foregroundColor(Color.Adaptive.warning)
                                            .cornerRadius(6)
                                        }
                                    }
                                    .padding(.horizontal, 1)
                                }
                            }
                        } else {
                            Text(L10n.peakNoApproachToday)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(viewModel.peakApproachTracker.todayApproachCount > 0 ?
                                  Color.orange.opacity(0.08) :
                                  Color.secondary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(viewModel.peakApproachTracker.todayApproachCount > 0 ?
                                   Color.orange.opacity(0.3) :
                                   Color.clear, lineWidth: 1)
                    )

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
                                    Text(L10n.statsDownload)
                                        .font(.headline)
                                        .fontWeight(.medium)
                                }

                                SpeedRow(
                                    label: L10n.statsTodayPeak,
                                    speed: viewModel.peakRecorder.todayPeakDownload,
                                    unit: viewModel.preferences.displayUnit,
                                    planSpeed: viewModel.preferences.downloadPlanSpeed,
                                    viewModel: viewModel,
                                    timestamp: viewModel.peakRecorder.todayPeakDownloadTime
                                )

                                SpeedRow(
                                    label: L10n.statsAllTimePeak,
                                    speed: viewModel.peakRecorder.allTimePeakDownload,
                                    unit: viewModel.preferences.displayUnit,
                                    planSpeed: viewModel.preferences.downloadPlanSpeed,
                                    viewModel: viewModel,
                                    timestamp: viewModel.peakRecorder.allTimePeakDownloadTime
                                )

                                HourlyPeakRow(
                                    label: L10n.statsHourlyPeak,
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
                                    Text(L10n.statsUpload)
                                        .font(.headline)
                                        .fontWeight(.medium)
                                }

                                SpeedRow(
                                    label: L10n.statsTodayPeak,
                                    speed: viewModel.peakRecorder.todayPeakUpload,
                                    unit: viewModel.preferences.displayUnit,
                                    planSpeed: viewModel.preferences.uploadPlanSpeed,
                                    viewModel: viewModel,
                                    timestamp: viewModel.peakRecorder.todayPeakUploadTime
                                )

                                SpeedRow(
                                    label: L10n.statsAllTimePeak,
                                    speed: viewModel.peakRecorder.allTimePeakUpload,
                                    unit: viewModel.preferences.displayUnit,
                                    planSpeed: viewModel.preferences.uploadPlanSpeed,
                                    viewModel: viewModel,
                                    timestamp: viewModel.peakRecorder.allTimePeakUploadTime
                                )

                                HourlyPeakRow(
                                    label: L10n.statsHourlyPeak,
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
                                Text(L10n.statsUpload)
                                    .font(.headline)
                                    .fontWeight(.medium)
                            }

                            SpeedRow(
                                label: L10n.statsTodayPeak,
                                speed: viewModel.peakRecorder.todayPeakUpload,
                                unit: viewModel.preferences.displayUnit,
                                planSpeed: viewModel.preferences.uploadPlanSpeed,
                                viewModel: viewModel,
                                timestamp: viewModel.peakRecorder.todayPeakUploadTime
                            )

                            SpeedRow(
                                label: L10n.statsAllTimePeak,
                                speed: viewModel.peakRecorder.allTimePeakUpload,
                                unit: viewModel.preferences.displayUnit,
                                planSpeed: viewModel.preferences.uploadPlanSpeed,
                                viewModel: viewModel,
                                timestamp: viewModel.peakRecorder.allTimePeakUploadTime
                            )

                            HourlyPeakRow(
                                label: L10n.statsHourlyPeak,
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
                                Text(L10n.statsDownload)
                                    .font(.headline)
                                    .fontWeight(.medium)
                            }

                            SpeedRow(
                                label: L10n.statsTodayPeak,
                                speed: viewModel.peakRecorder.todayPeakDownload,
                                unit: viewModel.preferences.displayUnit,
                                planSpeed: viewModel.preferences.downloadPlanSpeed,
                                viewModel: viewModel,
                                timestamp: viewModel.peakRecorder.todayPeakDownloadTime
                            )

                            SpeedRow(
                                label: L10n.statsAllTimePeak,
                                speed: viewModel.peakRecorder.allTimePeakDownload,
                                unit: viewModel.preferences.displayUnit,
                                planSpeed: viewModel.preferences.downloadPlanSpeed,
                                viewModel: viewModel,
                                timestamp: viewModel.peakRecorder.allTimePeakDownloadTime
                            )

                            HourlyPeakRow(
                                label: L10n.statsHourlyPeak,
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
                                Text(L10n.networkStatus)
                                    .font(.headline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(viewModel.anomalyDetector.isConnectionStable ? L10n.networkStable : L10n.networkAbnormal)
                                    .font(.subheadline)
                                    .foregroundColor(viewModel.anomalyDetector.isConnectionStable ? .green : Color.Adaptive.error)
                                    .fontWeight(.bold)
                            }

                            let summary = viewModel.anomalyDetector.getAnomalySummary()
                            if summary.hasAnomalies {
                                HStack(spacing: 12) {
                                    if summary.connectionDrops > 0 {
                                        HStack(spacing: 4) {
                                            Image(systemName: "wifi.exclamationmark")
                                                .font(.caption)
                                            Text(L10n.networkInterruptions(summary.connectionDrops))
                                                .font(.caption)
                                        }
                                        .foregroundColor(Color.Adaptive.error)
                                    }
                                    if summary.speedDrops > 0 {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.down.circle.fill")
                                                .font(.caption)
                                            Text(L10n.networkSpeedDrops(summary.speedDrops))
                                                .font(.caption)
                                        }
                                        .foregroundColor(Color.Adaptive.warning)
                                    }
                                }

                                // Show recent anomalies (deduplicated by type)
                                if !viewModel.anomalyDetector.recentAnomalies.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 4) {
                                            ForEach(getUniqueRecentAnomalies()) { anomaly in
                                                AnomalyBadge(anomaly: anomaly)
                                            }
                                        }
                                        .padding(.horizontal, 1)
                                    }
                                }
                            } else {
                                Text(L10n.networkNoAnomaliesRecently)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()
                    }

                    // Connection Quality Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: viewModel.latencyMonitor.qualityScore.icon)
                                .foregroundColor(viewModel.latencyMonitor.qualityScore.color)
                            Text(L10n.connectionQualityTitle)
                                .font(.headline)
                                .fontWeight(.medium)
                            Spacer()
                            Text(viewModel.latencyMonitor.qualityScore.displayName)
                                .font(.subheadline)
                                .foregroundColor(viewModel.latencyMonitor.qualityScore.color)
                                .fontWeight(.bold)
                        }

                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.latencyLabel)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Text(String(format: "%.0f %@", viewModel.latencyMonitor.currentLatency, L10n.latencyUnit))
                                    .font(.title3)
                                    .monospacedDigit()
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.jitterLabel)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Text(String(format: "%.1f %@", viewModel.latencyMonitor.currentJitter, L10n.latencyUnit))
                                    .font(.title3)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.05))
                    )

                    Divider()

                    // Disconnect History Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: viewModel.disconnectTracker.isConnected ? "wifi" : "wifi.slash")
                                .foregroundColor(viewModel.disconnectTracker.isConnected ? .green : .red)
                            Text(L10n.disconnectTitle)
                                .font(.headline)
                                .fontWeight(.medium)
                            Spacer()
                        }

                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.disconnectTodayCount)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Text(L10n.disconnectTimesUnit(viewModel.disconnectTracker.todayEvents.count))
                                    .font(.title3)
                                    .monospacedDigit()
                                    .foregroundColor(viewModel.disconnectTracker.todayEvents.isEmpty ? .secondary : .red)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.disconnectTotalDowntime)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Text(viewModel.disconnectTracker.formattedDowntimeToday)
                                    .font(.title3)
                                    .monospacedDigit()
                            }
                        }

                        if !viewModel.disconnectTracker.todayEvents.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(viewModel.disconnectTracker.todayEvents.prefix(5)) { event in
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "wifi.slash")
                                                    .font(.caption)
                                                Text(event.formattedDuration)
                                                    .font(.caption)
                                            }
                                            Text(formatDisconnectTime(event.startTime))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.red.opacity(0.1))
                                        .cornerRadius(6)
                                    }
                                }
                                .padding(.horizontal, 1)
                            }
                        } else {
                            Text(L10n.disconnectNoEventsToday)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(viewModel.disconnectTracker.todayEvents.isEmpty ?
                                  Color.secondary.opacity(0.05) :
                                  Color.red.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(viewModel.disconnectTracker.todayEvents.isEmpty ?
                                   Color.clear :
                                   Color.red.opacity(0.3), lineWidth: 1)
                    )

                    Divider()
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
                        Button(L10n.exportTodayData) {
                            exportData(format: .todayData)
                        }
                        Button(L10n.exportPeakHistory) {
                            exportData(format: .peakHistory)
                        }
                        Button(L10n.exportFullHistory) {
                            exportData(format: .fullHistory)
                        }
                    } label: {
                        Label(L10n.exportData, systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .help(L10n.exportDataHelp)

                    // Monthly Report Button
                    Button(action: { showingMonthlyReport = true }) {
                        Label(L10n.reportViewReport, systemImage: "chart.bar.doc.horizontal")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .help(L10n.reportViewReport)

                    // Reset Button
                    Button(L10n.actionResetPeaks) {
                        viewModel.resetPeaks()
                    }
                    .buttonStyle(.bordered)
                    .font(.subheadline)

                    Spacer()

                    // Quit Button
                    Button(L10n.actionQuitApp) {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.subheadline)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .background(Color.Adaptive.background)
        }
        .frame(width: 580, height: 700)
        .background(.regularMaterial)
        .animation(.easeInOut(duration: 0.3), value: showDownload)
        .animation(.easeInOut(duration: 0.3), value: showUpload)
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingMonthlyReport) {
            MonthlyReportView(viewModel: viewModel)
        }
        .alert(L10n.exportSuccess, isPresented: $exportSuccess) {
            Button(L10n.buttonOK, role: .cancel) { }
        } message: {
            Text(L10n.exportSuccessMessage)
        }
        .alert(L10n.exportFailure, isPresented: $exportError) {
            Button(L10n.buttonOK, role: .cancel) { }
        } message: {
            Text(L10n.exportFailureMessage)
        }
    }

    // MARK: - Helper Functions

    private func formatDisconnectTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

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

    /// Get unique recent anomalies, showing only the most recent of each type
    private func getUniqueRecentAnomalies() -> [NetworkAnomaly] {
        var seenTypes: Set<String> = []
        var uniqueAnomalies: [NetworkAnomaly] = []

        // Iterate through recent anomalies and keep only the first (most recent) of each type
        for anomaly in viewModel.anomalyDetector.recentAnomalies {
            let typeKey = anomaly.type.typeKey

            if !seenTypes.contains(typeKey) {
                seenTypes.insert(typeKey)
                uniqueAnomalies.append(anomaly)

                // Limit to 5 unique types
                if uniqueAnomalies.count >= 5 {
                    break
                }
            }
        }

        return uniqueAnomalies
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
                .font(.body)
                .frame(maxWidth: 80, alignment: .leading)
            Text(viewModel.formatSpeed(speed, unit: unit) + " " + unit.displayName)
                .font(.title3)
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
                        .font(.subheadline)
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
                .font(.body)
                .frame(maxWidth: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.formatSpeed(speed, unit: unit) + " " + unit.displayName)
                    .font(.title3)
                if let time = time {
                    Text(viewModel.formatTime(time))
                        .font(.subheadline)
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
            return L10n.timeJustNow
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return L10n.timeMinutesAgo(minutes)
        } else {
            let hours = Int(interval / 3600)
            return L10n.timeHoursAgo(hours)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: anomaly.type.icon)
                    .font(.caption)
                Text(anomaly.type.displayText)
                    .font(.caption)
                    .lineLimit(2)
            }
            Text(timeAgo)
                .font(.caption)
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