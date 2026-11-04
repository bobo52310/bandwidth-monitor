import SwiftUI
import AppKit

public struct PopoverView: View {
    @Bindable var viewModel: NetworkMonitorViewModel
    @State private var showingSettings = false
    @State private var showingMonthlyReport = false
    @State private var showingResetConfirm = false
    /// The direction whose all-time peak the user asked to clear, until they confirm or cancel.
    @State private var pendingClear: PeakDirection?

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
                                    .accessibilityHidden(true)
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
                        // Pinned or not is shown by colour only; say it too.
                        .accessibilityValue(viewModel.preferences.isPinned ? L10n.accessibilityStateOn : L10n.accessibilityStateOff)

                        // Settings button
                        Button(action: { showingSettings = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "gear")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                                    .accessibilityHidden(true)
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
                    // The chart choices live in the view model: the popover's views are
                    // released when it closes (D10).
                    NetworkChartView(
                        historyRecorder: viewModel.historyRecorder,
                        preferences: viewModel.preferences,
                        currentSpeed: viewModel.currentSpeed,
                        timeRange: $viewModel.chartRange,
                        showUpload: $viewModel.showUpload,
                        showDownload: $viewModel.showDownload,
                        bannerDismissed: $viewModel.chartBannerDismissed,
                        warningRatio: viewModel.notificationService.threshold
                    )

                    Divider()

                    // Peak Approach Counter Section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "gauge.high")
                                .foregroundColor(Color.Adaptive.warning)
                                .accessibilityHidden(true)
                            // Each direction against its own plan, and what counts as one time.
                            Text(L10n.approachingSpeedLimit(
                                Int(viewModel.preferences.downloadPlanSpeed),
                                Int(viewModel.preferences.uploadPlanSpeed)
                            ))
                                .font(.headline)
                                .fontWeight(.semibold)
                                .help(L10n.approachingHelpCurrent)
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
                                                    .accessibilityHidden(true)
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
                    if viewModel.showDownload && viewModel.showUpload {
                        // Side-by-side layout when both are visible
                        HStack(alignment: .top, spacing: 16) {
                            // Download Section - Statistics
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .foregroundColor(Color.Adaptive.downloadPrimary)
                                        .accessibilityHidden(true)
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
                                    timestamp: viewModel.peakRecorder.allTimePeakDownloadTime,
                                    onClear: { pendingClear = .download },
                                    clearLabel: L10n.peakClearAccessibility(L10n.peakDirectionDownload)
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
                                        .accessibilityHidden(true)
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
                                    timestamp: viewModel.peakRecorder.allTimePeakUploadTime,
                                    onClear: { pendingClear = .upload },
                                    clearLabel: L10n.peakClearAccessibility(L10n.peakDirectionUpload)
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
                    } else if viewModel.showUpload {
                        // Upload Section only - Statistics
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundColor(.green)
                                    .accessibilityHidden(true)
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
                                timestamp: viewModel.peakRecorder.allTimePeakUploadTime,
                                onClear: { pendingClear = .upload },
                                clearLabel: L10n.peakClearAccessibility(L10n.peakDirectionUpload)
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
                    } else if viewModel.showDownload {
                        // Download Section only - Statistics
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundColor(.blue)
                                    .accessibilityHidden(true)
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
                                timestamp: viewModel.peakRecorder.allTimePeakDownloadTime,
                                onClear: { pendingClear = .download },
                                clearLabel: L10n.peakClearAccessibility(L10n.peakDirectionDownload)
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
                                    .accessibilityHidden(true)
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
                                                .accessibilityHidden(true)
                                            Text(L10n.networkInterruptions(summary.connectionDrops))
                                                .font(.caption)
                                        }
                                        .foregroundColor(Color.Adaptive.error)
                                    }
                                    if summary.speedDrops > 0 {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.down.circle.fill")
                                                .font(.caption)
                                                .accessibilityHidden(true)
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
                    let latency = viewModel.latencyMonitor
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: latency.isEnabled ? latency.qualityScore.icon : "pause.circle")
                                .foregroundColor(latency.isEnabled ? latency.qualityScore.color : .secondary)
                                .accessibilityHidden(true)
                            Text(L10n.connectionQualityTitle)
                                .font(.headline)
                                .fontWeight(.medium)
                            Spacer()
                            if latency.isEnabled {
                                Text(latency.qualityScore.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(latency.qualityScore.color)
                                    .fontWeight(.bold)
                            }
                        }

                        if latency.isEnabled {
                            // Nothing measured yet, or the last probe failed: no number to show.
                            HStack(spacing: 24) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.latencyLabel)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .textCase(.uppercase)
                                    Text(latency.hasMeasurement
                                         ? String(format: "%.0f %@", latency.currentLatency, L10n.latencyUnit)
                                         : "—")
                                        .font(.title3)
                                        .monospacedDigit()
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.jitterLabel)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .textCase(.uppercase)
                                    // Also "—" while there is a single sample: it has no spread yet.
                                    Text(latency.currentJitter.map { String(format: "%.1f %@", $0, L10n.latencyUnit) } ?? "—")
                                        .font(.title3)
                                        .monospacedDigit()
                                }
                            }
                        } else {
                            Text(L10n.latencyDisabled)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
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
                                .accessibilityHidden(true)
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
                                                    .accessibilityHidden(true)
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
                        // The save panel closes the popover, and the result is shown by the
                        // view model once the file is written, so nothing here waits for it.
                        Button(L10n.exportRecent24Hours) {
                            viewModel.exportData(format: .recent24Hours)
                        }
                        Button(L10n.exportPeakHistory) {
                            viewModel.exportData(format: .peakHistory)
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
                        showingResetConfirm = true
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
        .resetPeaksConfirmation(isPresented: $showingResetConfirm) {
            viewModel.resetPeaks()
        }
        .confirmationDialog(
            pendingClear.map { L10n.peakClearConfirmTitle(Self.directionName($0)) } ?? "",
            isPresented: Binding(
                get: { pendingClear != nil },
                set: { if !$0 { pendingClear = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingClear
        ) { direction in
            Button(L10n.peakClearButton, role: .destructive) {
                viewModel.clearAllTimePeak(direction)
            }
            Button(L10n.buttonCancel, role: .cancel) { }
        } message: { _ in
            Text(L10n.peakClearConfirmMessage)
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.showDownload)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showUpload)
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingMonthlyReport) {
            MonthlyReportView(viewModel: viewModel)
        }
    }

    // MARK: - Helper Functions

    private static func directionName(_ direction: PeakDirection) -> String {
        switch direction {
        case .download: return L10n.peakDirectionDownload
        case .upload: return L10n.peakDirectionUpload
        }
    }

    /// One formatter for all the chips: the view is rebuilt every second.
    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()

    private func formatDisconnectTime(_ date: Date) -> String {
        Self.shortTimeFormatter.string(from: date)
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
    /// Shown as a small clear button when set and there is a peak to clear.
    var onClear: (() -> Void)?
    /// What the clear button is called for VoiceOver.
    var clearLabel = ""

    var body: some View {
        HStack {
            // The label keeps its full width: in English "All-Time Peak:" is longer than 80 pt.
            Text(label + ":")
                .font(.body)
                .lineLimit(1)
                .fixedSize()
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
            if let onClear, speed > 0 {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .help(L10n.peakClearHelp)
                .accessibilityLabel(clearLabel)
            }
        }
    }
}

/// Reset is destructive and can't be undone, so it always asks first.
extension View {
    func resetPeaksConfirmation(isPresented: Binding<Bool>, onConfirm: @escaping () -> Void) -> some View {
        confirmationDialog(
            L10n.resetConfirmTitle,
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button(L10n.actionResetPeaks, role: .destructive, action: onConfirm)
            Button(L10n.buttonCancel, role: .cancel) { }
        } message: {
            Text(L10n.resetConfirmMessage)
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
                .lineLimit(1)
                .fixedSize()
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
                    .accessibilityHidden(true)
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