import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject var viewModel: NetworkMonitorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingOnboarding = false

    public init(viewModel: NetworkMonitorViewModel) {
        self.viewModel = viewModel
    }

    public init() {
        self.viewModel = NetworkMonitorViewModel()
    }

    public var body: some View {
        VStack(spacing: 20) {
            Text("設定")
                .font(.title)
                .fontWeight(.bold)

            Form {
                Section("網路方案設定") {
                    HStack {
                        Text("下載速度上限:")
                        TextField("300", value: $viewModel.preferences.downloadPlanSpeed, format: .number)
                            .textFieldStyle(.roundedBorder)
                        Text("Mbps")
                    }

                    HStack {
                        Text("上傳速度上限:")
                        TextField("300", value: $viewModel.preferences.uploadPlanSpeed, format: .number)
                            .textFieldStyle(.roundedBorder)
                        Text("Mbps")
                    }
                }

                Section("顯示設定") {
                    HStack {
                        Text("顯示單位:")
                        Picker("單位", selection: $viewModel.preferences.displayUnit) {
                            ForEach(UserPreferences.SpeedUnit.allCases, id: \.self) { unit in
                                Text(unit.displayName).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("選單列顯示模式:")
                        Picker("顯示模式", selection: $viewModel.preferences.menuBarDisplayMode) {
                            ForEach(UserPreferences.MenuBarDisplayMode.allCases, id: \.self) { mode in
                                VStack(alignment: .leading) {
                                    Text(mode.displayName)
                                    Text(mode.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .tag(mode)
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

                Section("通知設定") {
                    Toggle("啟用峰值通知", isOn: $viewModel.notificationService.isEnabled)
                        .help("當網路速度接近方案上限時發送通知")

                    if viewModel.notificationService.isEnabled {
                        HStack {
                            Text("通知閾值:")
                            Picker("閾值", selection: $viewModel.notificationService.threshold) {
                                ForEach(NotificationService.thresholdOptions, id: \.value) { option in
                                    Text(option.label).tag(option.value)
                                }
                            }
                            .pickerStyle(.segmented)
                            .help("當速度超過此百分比時觸發通知")
                        }

                        Button("發送測試通知") {
                            viewModel.notificationService.sendTestNotification()
                        }
                        .buttonStyle(.bordered)
                        .help("測試通知功能是否正常")
                    }
                }

                Section("網路監控") {
                    Toggle("啟用異常偵測", isOn: $viewModel.anomalyDetector.isDetectionEnabled)
                        .help("自動偵測網路中斷、速度驟降等異常狀況")

                    if viewModel.anomalyDetector.isDetectionEnabled && !viewModel.anomalyDetector.recentAnomalies.isEmpty {
                        HStack {
                            Text("異常記錄:")
                            Spacer()
                            Button("清除歷史") {
                                viewModel.anomalyDetector.clearHistory()
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                }

                Section("快捷鍵") {
                    Toggle("啟用全域快捷鍵", isOn: $viewModel.keyboardShortcuts.isEnabled)
                        .help("啟用快捷鍵以快速存取常用功能")

                    if viewModel.keyboardShortcuts.isEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("可用快捷鍵:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(KeyboardShortcutsService.getAllShortcuts(), id: \.name) { shortcut in
                                HStack {
                                    Text(shortcut.name)
                                        .font(.caption)
                                    Spacer()
                                    Text(shortcut.shortcut)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("錯誤日誌") {
                    Toggle("啟用錯誤記錄", isOn: $viewModel.errorHandler.isLoggingEnabled)
                        .help("記錄錯誤和應用程式活動以協助診斷問題")

                    if viewModel.errorHandler.isLoggingEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            // Error summary
                            let errorSummary = viewModel.errorHandler.getErrorSummary()
                            if errorSummary.hasErrors {
                                HStack {
                                    Text("錯誤統計:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    HStack(spacing: 12) {
                                        if errorSummary.warnings > 0 {
                                            Label("\(errorSummary.warnings)", systemImage: "exclamationmark.triangle.fill")
                                                .font(.caption)
                                                .foregroundColor(.yellow)
                                        }
                                        if errorSummary.errors > 0 {
                                            Label("\(errorSummary.errors)", systemImage: "exclamationmark.circle.fill")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                        if errorSummary.critical > 0 {
                                            Label("\(errorSummary.critical)", systemImage: "xmark.octagon.fill")
                                                .font(.caption)
                                                .foregroundColor(.red)
                                        }
                                    }
                                }
                            }

                            // Log file info
                            if let logSize = viewModel.errorHandler.getLogFileSize() {
                                HStack {
                                    Text("日誌大小:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(logSize)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                            }

                            // Action buttons
                            HStack {
                                Button("清除錯誤") {
                                    viewModel.errorHandler.clearErrors()
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                                .disabled(!errorSummary.hasErrors)

                                Button("清除日誌") {
                                    viewModel.errorHandler.clearLogFile()
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)

                                if viewModel.errorHandler.exportLogFile() != nil {
                                    Button("導出日誌") {
                                        if let logURL = viewModel.errorHandler.exportLogFile() {
                                            DataExportService.revealInFinder(url: logURL)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("系統設定") {
                    Toggle("登入時開啟", isOn: $viewModel.preferences.launchAtLogin)

                    Button("重新顯示新手引導") {
                        showingOnboarding = true
                    }
                    .buttonStyle(.bordered)
                    .help("再次查看應用程式功能介紹")
                }
            }

            VStack(spacing: 12) {
                // Memory stats
                let memStats = viewModel.getMemoryStats()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("記憶體使用")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(memStats.formattedTotal)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                    Button("優化記憶體") {
                        viewModel.optimizeMemory()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                    .help("清理過期數據以減少記憶體使用")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)

                Divider()

                HStack {
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
            }
        }
        .padding()
        .frame(width: 400, height: 600)
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView(viewModel: viewModel)
        }
    }
}
