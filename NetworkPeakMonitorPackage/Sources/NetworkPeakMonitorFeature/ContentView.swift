import SwiftUI

public struct SettingsView: View {
    @ObservedObject var viewModel: NetworkMonitorViewModel

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
                    NSApplication.shared.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 400)
    }
}
