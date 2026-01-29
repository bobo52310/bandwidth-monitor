import SwiftUI
import AppKit

// MARK: - Collapsible Section Component
struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    init(title: String, icon: String, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self._isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section Header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.accentColor)
                        .frame(width: 20)
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // Section Content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .clipped() // Prevent content overflow during animation
    }
}

public struct SettingsView: View {
    @ObservedObject var viewModel: NetworkMonitorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingOnboarding = false

    // Section expansion states
    @State private var networkSettingsExpanded = false
    @State private var displayNotificationExpanded = true
    @State private var systemMaintenanceExpanded = true

    public init(viewModel: NetworkMonitorViewModel) {
        self.viewModel = viewModel
    }

    public init() {
        self.viewModel = NetworkMonitorViewModel()
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button(action: { dismiss() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text(L10n.buttonBack)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help(L10n.tooltipBackToMain)

                Spacer()

                Text(L10n.settingsTitle)
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                // Invisible spacer to balance the layout
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text(L10n.buttonBack)
                        .font(.system(size: 14, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .opacity(0)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    // MARK: - Network Settings Section
                    CollapsibleSection(
                        title: L10n.settingsNetworkSection,
                        icon: "network",
                        isExpanded: $networkSettingsExpanded
                    ) {
                        // Network Plan Settings
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.settingsNetworkPlan)
                                .font(.headline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            HStack {
                                Text(L10n.settingsDownloadLimit)
                                    .font(.body)
                                    .frame(width: 100, alignment: .leading)
                                TextField("300", value: $viewModel.preferences.downloadPlanSpeed, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                Text("Mbps")
                                    .font(.body)
                            }

                            HStack {
                                Text(L10n.settingsUploadLimit)
                                    .font(.body)
                                    .frame(width: 100, alignment: .leading)
                                TextField("300", value: $viewModel.preferences.uploadPlanSpeed, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                Text("Mbps")
                                    .font(.body)
                            }
                        }

                        Divider()
                            .padding(.vertical, 4)

                        // Network Monitoring
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(L10n.settingsEnableAnomalyDetection, isOn: $viewModel.anomalyDetector.isDetectionEnabled)
                                .help(L10n.settingsAnomalyDetectionHelp)

                            if viewModel.anomalyDetector.isDetectionEnabled && !viewModel.anomalyDetector.recentAnomalies.isEmpty {
                                HStack {
                                    Text(L10n.settingsAnomalyHistory)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button(L10n.settingsClearHistory) {
                                        viewModel.anomalyDetector.clearHistory()
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                                }
                            }
                        }
                    }

                    // MARK: - Display & Notifications Section
                    CollapsibleSection(
                        title: L10n.settingsDisplayNotificationSection,
                        icon: "bell.badge",
                        isExpanded: $displayNotificationExpanded
                    ) {
                        // Display Settings
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.settingsDisplaySettings)
                                .font(.headline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            HStack {
                                Text(L10n.settingsDisplayUnit)
                                    .font(.body)
                                Spacer()
                                Picker(L10n.settingsUnitLabel, selection: $viewModel.preferences.displayUnit) {
                                    ForEach(UserPreferences.SpeedUnit.allCases, id: \.self) { unit in
                                        Text(unit.displayName).tag(unit)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.settingsMenuBarMode)
                                    .font(.body)
                                Picker(L10n.settingsDisplayMode, selection: $viewModel.preferences.menuBarDisplayMode) {
                                    ForEach(UserPreferences.MenuBarDisplayMode.allCases, id: \.self) { mode in
                                        Text(mode.displayName).tag(mode)
                                    }
                                }
                                .pickerStyle(.menu)

                                // Preview
                                HStack {
                                    Text(L10n.settingsPreview)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(viewModel.menuBarText)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(4)
                                }
                            }
                        }

                        Divider()
                            .padding(.vertical, 4)

                        // Notification Settings
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.settingsNotificationSettings)
                                .font(.headline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            Toggle(L10n.settingsEnablePeakNotification, isOn: $viewModel.notificationService.isEnabled)
                                .help(L10n.settingsPeakNotificationHelp)

                            if viewModel.notificationService.isEnabled {
                                HStack {
                                    Text(L10n.settingsNotificationThreshold)
                                        .font(.body)
                                    Spacer()
                                    Picker(L10n.settingsThreshold, selection: $viewModel.notificationService.threshold) {
                                        ForEach(NotificationService.thresholdOptions, id: \.value) { option in
                                            Text(option.label).tag(option.value)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 200)
                                    .help(L10n.settingsThresholdHelp)
                                }

                                Button(L10n.settingsSendTestNotification) {
                                    viewModel.notificationService.sendTestNotification()
                                }
                                .buttonStyle(.bordered)
                                .font(.subheadline)
                                .help(L10n.settingsTestNotificationHelp)
                            }
                        }
                    }

                    // MARK: - System & Maintenance Section
                    CollapsibleSection(
                        title: L10n.settingsSystemMaintenanceSection,
                        icon: "gearshape.2",
                        isExpanded: $systemMaintenanceExpanded
                    ) {
                        // System Settings
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.settingsSystemSettings)
                                .font(.headline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            Toggle(L10n.settingsLaunchAtLogin, isOn: $viewModel.preferences.launchAtLogin)

                            Toggle(L10n.settingsShowInDock, isOn: $viewModel.preferences.showInDock)
                                .help(L10n.settingsShowInDockHelp)

                            // Language Selection
                            HStack {
                                Text(L10n.settingsLanguage)
                                    .font(.body)
                                Spacer()
                                Picker(L10n.settingsLanguage, selection: $viewModel.preferences.appLanguage) {
                                    ForEach(UserPreferences.AppLanguage.allCases, id: \.self) { lang in
                                        Text(lang.displayName).tag(lang)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 150)
                            }

                            Button(L10n.settingsShowOnboarding) {
                                showingOnboarding = true
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                            .help(L10n.settingsShowOnboardingHelp)
                        }

                        Divider()
                            .padding(.vertical, 4)

                        // Error Logging (Simplified)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(L10n.settingsErrorLog)
                                    .font(.headline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)

                                Spacer()

                                // Error count badges
                                let errorSummary = viewModel.errorHandler.getErrorSummary()
                                if errorSummary.hasErrors {
                                    HStack(spacing: 6) {
                                        if errorSummary.warnings > 0 {
                                            Label("\(errorSummary.warnings)", systemImage: "exclamationmark.triangle.fill")
                                                .font(.caption2)
                                                .foregroundColor(.yellow)
                                        }
                                        if errorSummary.errors > 0 {
                                            Label("\(errorSummary.errors)", systemImage: "exclamationmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                        }
                                        if errorSummary.critical > 0 {
                                            Label("\(errorSummary.critical)", systemImage: "xmark.octagon.fill")
                                                .font(.caption2)
                                                .foregroundColor(.red)
                                        }
                                    }
                                }
                            }

                            Toggle(L10n.settingsEnableLogging, isOn: $viewModel.errorHandler.isLoggingEnabled)
                                .help(L10n.settingsLoggingHelp)

                            if viewModel.errorHandler.isLoggingEnabled {
                                HStack {
                                    if let logSize = viewModel.errorHandler.getLogFileSize() {
                                        Text("\(L10n.settingsLogSize) \(logSize)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()

                                    // Compact action menu
                                    Menu {
                                        let errorSummary = viewModel.errorHandler.getErrorSummary()
                                        Button(L10n.settingsClearErrors) {
                                            viewModel.errorHandler.clearErrors()
                                        }
                                        .disabled(!errorSummary.hasErrors)

                                        Button(L10n.settingsClearLogs) {
                                            viewModel.errorHandler.clearLogFile()
                                        }

                                        if viewModel.errorHandler.exportLogFile() != nil {
                                            Button(L10n.settingsExportLogs) {
                                                if let logURL = viewModel.errorHandler.exportLogFile() {
                                                    DataExportService.revealInFinder(url: logURL)
                                                }
                                            }
                                        }
                                    } label: {
                                        Label(L10n.settingsManage, systemImage: "ellipsis.circle")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                                }
                            }
                        }

                        Divider()
                            .padding(.vertical, 4)

                        // Memory Management
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.settingsMemoryManagement)
                                .font(.headline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            let memStats = viewModel.getMemoryStats()
                            HStack {
                                Text("\(L10n.settingsMemoryUsage) \(memStats.formattedTotal)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(L10n.settingsOptimizeMemory) {
                                    viewModel.optimizeMemory()
                                }
                                .buttonStyle(.bordered)
                                .font(.subheadline)
                                .help(L10n.settingsOptimizeMemoryHelp)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 70) // Space for fixed bottom bar
            }

            // MARK: - Fixed Bottom Action Bar
            VStack(spacing: 0) {
                Divider()

                HStack(spacing: 12) {
                    Button(L10n.settingsResetAllPeaks) {
                        viewModel.resetPeaks()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)

                    Spacer()

                    Button(L10n.buttonClose) {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.windowBackgroundColor))
            }
            .frame(height: 60)
        }
        .frame(width: 400, height: 600)
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView(viewModel: viewModel)
        }
    }
}
