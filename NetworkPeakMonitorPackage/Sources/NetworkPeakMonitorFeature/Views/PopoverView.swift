import SwiftUI

public struct PopoverView: View {
    @ObservedObject var viewModel: NetworkMonitorViewModel
    @State private var showingSettings = false

    public init(viewModel: NetworkMonitorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Network Peak Monitor")
                    .font(.headline)
                Spacer()
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
            }

            Divider()

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
            }

            Divider()

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
            }

            Divider()

            // Reset Button
            Button("重置峰值記錄") {
                viewModel.resetPeaks()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 350, height: 320)
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