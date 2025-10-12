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
                        Text("返回")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("返回主頁面")

                Spacer()

                Text("設定")
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                // Invisible spacer to balance the layout
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("返回")
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
                        title: "網路設定",
                        icon: "network",
                        isExpanded: $networkSettingsExpanded
                    ) {
                        // Network Plan Settings
                        VStack(alignment: .leading, spacing: 10) {
                            Text("網路方案設定")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            HStack {
                                Text("下載速度上限:")
                                    .frame(width: 100, alignment: .leading)
                                TextField("300", value: $viewModel.preferences.downloadPlanSpeed, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                Text("Mbps")
                            }

                            HStack {
                                Text("上傳速度上限:")
                                    .frame(width: 100, alignment: .leading)
                                TextField("300", value: $viewModel.preferences.uploadPlanSpeed, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                Text("Mbps")
                            }
                        }

                        Divider()
                            .padding(.vertical, 4)

                        // Network Monitoring
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("啟用異常偵測", isOn: $viewModel.anomalyDetector.isDetectionEnabled)
                                .help("自動偵測網路中斷、速度驟降等異常狀況")

                            if viewModel.anomalyDetector.isDetectionEnabled && !viewModel.anomalyDetector.recentAnomalies.isEmpty {
                                HStack {
                                    Text("異常記錄:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button("清除歷史") {
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
                        title: "顯示與通知",
                        icon: "bell.badge",
                        isExpanded: $displayNotificationExpanded
                    ) {
                        // Display Settings
                        VStack(alignment: .leading, spacing: 10) {
                            Text("顯示設定")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            HStack {
                                Text("顯示單位:")
                                Spacer()
                                Picker("單位", selection: $viewModel.preferences.displayUnit) {
                                    ForEach(UserPreferences.SpeedUnit.allCases, id: \.self) { unit in
                                        Text(unit.displayName).tag(unit)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("選單列顯示模式:")
                                Picker("顯示模式", selection: $viewModel.preferences.menuBarDisplayMode) {
                                    ForEach(UserPreferences.MenuBarDisplayMode.allCases, id: \.self) { mode in
                                        Text(mode.displayName).tag(mode)
                                    }
                                }
                                .pickerStyle(.menu)

                                // Preview
                                HStack {
                                    Text("預覽:")
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
                            Text("通知設定")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            Toggle("啟用峰值通知", isOn: $viewModel.notificationService.isEnabled)
                                .help("當網路速度接近方案上限時發送通知")

                            if viewModel.notificationService.isEnabled {
                                HStack {
                                    Text("通知閾值:")
                                    Spacer()
                                    Picker("閾值", selection: $viewModel.notificationService.threshold) {
                                        ForEach(NotificationService.thresholdOptions, id: \.value) { option in
                                            Text(option.label).tag(option.value)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 200)
                                    .help("當速度超過此百分比時觸發通知")
                                }

                                Button("發送測試通知") {
                                    viewModel.notificationService.sendTestNotification()
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                                .help("測試通知功能是否正常")
                            }
                        }
                    }

                    // MARK: - System & Maintenance Section
                    CollapsibleSection(
                        title: "系統與維護",
                        icon: "gearshape.2",
                        isExpanded: $systemMaintenanceExpanded
                    ) {
                        // System Settings
                        VStack(alignment: .leading, spacing: 10) {
                            Text("系統設定")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            Toggle("登入時開啟", isOn: $viewModel.preferences.launchAtLogin)

                            Button("重新顯示新手引導") {
                                showingOnboarding = true
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                            .help("再次查看應用程式功能介紹")
                        }

                        Divider()
                            .padding(.vertical, 4)

                        // Error Logging (Simplified)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("錯誤日誌")
                                    .font(.subheadline)
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

                            Toggle("啟用錯誤記錄", isOn: $viewModel.errorHandler.isLoggingEnabled)
                                .help("記錄錯誤和應用程式活動以協助診斷問題")

                            if viewModel.errorHandler.isLoggingEnabled {
                                HStack {
                                    if let logSize = viewModel.errorHandler.getLogFileSize() {
                                        Text("日誌大小: \(logSize)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()

                                    // Compact action menu
                                    Menu {
                                        let errorSummary = viewModel.errorHandler.getErrorSummary()
                                        Button("清除錯誤") {
                                            viewModel.errorHandler.clearErrors()
                                        }
                                        .disabled(!errorSummary.hasErrors)

                                        Button("清除日誌") {
                                            viewModel.errorHandler.clearLogFile()
                                        }

                                        if viewModel.errorHandler.exportLogFile() != nil {
                                            Button("導出日誌") {
                                                if let logURL = viewModel.errorHandler.exportLogFile() {
                                                    DataExportService.revealInFinder(url: logURL)
                                                }
                                            }
                                        }
                                    } label: {
                                        Label("管理", systemImage: "ellipsis.circle")
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
                            Text("記憶體管理")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            let memStats = viewModel.getMemoryStats()
                            HStack {
                                Text("使用量: \(memStats.formattedTotal)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("優化記憶體") {
                                    viewModel.optimizeMemory()
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                                .help("清理過期數據以減少記憶體使用")
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
                    Button("重置所有峰值記錄") {
                        viewModel.resetPeaks()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)

                    Spacer()

                    Button("關閉") {
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
