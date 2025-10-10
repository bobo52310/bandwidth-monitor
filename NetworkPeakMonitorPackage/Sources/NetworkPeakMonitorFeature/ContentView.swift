import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject var viewModel: NetworkMonitorViewModel
    @Environment(\.dismiss) private var dismiss

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

                Section("系統設定") {
                    Toggle("登入時開啟", isOn: $viewModel.preferences.launchAtLogin)
                }
            }

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
        .padding()
        .frame(width: 400, height: 600)
    }
}
