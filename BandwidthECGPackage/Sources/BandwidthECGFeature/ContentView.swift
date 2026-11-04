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

// MARK: - Plan Speed Field

/// How a plan speed typed into `PlanSpeedField` becomes a model value. Kept apart from the view
/// so the rules can be tested.
enum PlanSpeedInput {
    /// The number in `text`, or `nil` for empty text and anything that isn't a plain finite number.
    /// Range checks belong to the model (`UserPreferences.planSpeedRange`).
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        // An input method can type full-width digits.
        let halfWidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let trimmed = halfWidth.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parsed = (try? Double(trimmed, format: .number.locale(locale))) ?? Double(trimmed)
        guard let value = parsed, value.isFinite else { return nil }
        // The locale-aware parser reads a leading number and ignores the rest ("300abc").
        let allowed = CharacterSet(charactersIn: "0123456789+-.,e").union(.whitespaces)
        guard trimmed.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value
    }

    /// The text for a model value: no grouping, no trailing ".0".
    static func display(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0...2)))
    }

    /// Writes `text` through `write` when it is a usable number that differs from `current()`,
    /// and returns the text the field should show afterwards. That is always the model's value,
    /// so an empty or invalid entry reverts, and a value the model rejected or clamped shows
    /// what the model kept.
    @discardableResult
    static func commit(
        _ text: String,
        current: () -> Double,
        write: (Double) -> Void,
        locale: Locale = .current
    ) -> String {
        if let value = parse(text, locale: locale), value != current() {
            write(value)
        }
        return display(current(), locale: locale)
    }
}

/// A plan speed (Mbps) entry shared by Settings and onboarding. It keeps its own text while the
/// user types and commits on return, when focus leaves, and when the field goes away: the
/// popover's content is released when it closes, so a value typed but not confirmed must not
/// be lost with it. An empty or invalid entry reverts to the model's value.
struct PlanSpeedField: View {
    let title: String
    @Binding var value: Double
    var labelMinWidth: CGFloat = 100
    var fieldWidth: CGFloat = 80

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(title: String, value: Binding<Double>, labelMinWidth: CGFloat = 100, fieldWidth: CGFloat = 80) {
        self.title = title
        self._value = value
        self.labelMinWidth = labelMinWidth
        self.fieldWidth = fieldWidth
        self._text = State(initialValue: PlanSpeedInput.display(value.wrappedValue))
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.body)
                .frame(minWidth: labelMinWidth, alignment: .leading)
                .fixedSize()
            TextField("300", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: fieldWidth)
                .focused($isFocused)
                .onSubmit(commit)
                .accessibilityLabel(title)
            Text("Mbps")
                .font(.body)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
        .onChange(of: value) { _, newValue in
            // The model changed behind the field's back; follow it unless the user is typing.
            if !isFocused { text = PlanSpeedInput.display(newValue) }
        }
        .onDisappear(perform: commit)
    }

    private func commit() {
        text = PlanSpeedInput.commit(text, current: { value }, write: { value = $0 })
    }
}

public struct SettingsView: View {
    @Bindable var viewModel: NetworkMonitorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingOnboarding = false
    @State private var showingResetConfirm = false
    @State private var showingLanguageRestart = false

    // Section expansion states
    @State private var networkSettingsExpanded = true
    @State private var displayNotificationExpanded = true
    @State private var systemMaintenanceExpanded = true

    public init(viewModel: NetworkMonitorViewModel) {
        self.viewModel = viewModel
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

                            PlanSpeedField(
                                title: L10n.settingsDownloadLimit,
                                value: $viewModel.preferences.downloadPlanSpeed
                            )

                            PlanSpeedField(
                                title: L10n.settingsUploadLimit,
                                value: $viewModel.preferences.uploadPlanSpeed
                            )
                        }

                        Divider()
                            .padding(.vertical, 4)

                        // Network Monitoring
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(L10n.settingsEnableAnomalyDetection, isOn: $viewModel.anomalyDetector.isDetectionEnabled)
                                .help(L10n.settingsAnomalyDetectionHelp)

                            Toggle(L10n.settingsEnableLatency, isOn: $viewModel.latencyMonitor.isEnabled)
                                .help(L10n.settingsLatencyHelp)

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
                                .labelsHidden()
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
                                .labelsHidden()
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

                            if !viewModel.notificationService.isAuthorized {
                                Label(L10n.settingsNotificationDenied, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(Color.Adaptive.warning)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if let deliveryError = viewModel.notificationService.lastDeliveryError {
                                Label(L10n.settingsNotificationDeliveryFailed(deliveryError), systemImage: "xmark.octagon.fill")
                                    .font(.caption)
                                    .foregroundColor(Color.Adaptive.error)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

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
                                    .labelsHidden()
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

                            Toggle(
                                L10n.settingsLaunchAtLogin,
                                isOn: Binding(
                                    get: { viewModel.preferences.launchAtLogin },
                                    set: { viewModel.preferences.setLaunchAtLogin($0) }
                                )
                            )
                            // Switching it off stays possible: it may have been turned on before the
                            // app was moved.
                            .disabled(!launchAtLoginAvailable && !viewModel.preferences.launchAtLogin)

                            // A copy that runs from a disk image or from Downloads can't keep a
                            // login item across restarts; say why the switch is off.
                            if !launchAtLoginAvailable {
                                Text(L10n.settingsLaunchAtLoginMoveHint)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if let message = viewModel.preferences.launchAtLoginMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(Color.Adaptive.warning)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

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
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 180)
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
                        showingResetConfirm = true
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
        .task {
            // Permission may have been changed in System Settings since launch.
            await viewModel.notificationService.refreshAuthorization()
        }
        .onAppear {
            // So may the login item.
            viewModel.preferences.refreshLaunchAtLogin()
        }
        .onChange(of: viewModel.preferences.appLanguage) {
            showingLanguageRestart = true
        }
        .resetPeaksConfirmation(isPresented: $showingResetConfirm) {
            viewModel.resetPeaks()
        }
        .alert(L10n.settingsLanguageRestartTitle, isPresented: $showingLanguageRestart) {
            Button(L10n.settingsLanguageRestartNow) {
                // The new instance reads its files while this one is still running.
                viewModel.flushPersistence()
                AppRelauncher.relaunch()
            }
            Button(L10n.settingsLanguageRestartLater, role: .cancel) { }
        } message: {
            Text(L10n.settingsLanguageRestartMessage)
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView(viewModel: viewModel)
        }
    }

    /// Login items only survive a restart for a copy that sits in an Applications folder.
    private var launchAtLoginAvailable: Bool {
        InstallLocation.currentCopyCanLaunchAtLogin
    }
}
