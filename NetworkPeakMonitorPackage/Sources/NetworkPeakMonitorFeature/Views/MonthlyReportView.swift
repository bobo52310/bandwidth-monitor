import SwiftUI

public struct MonthlyReportView: View {
    @ObservedObject var viewModel: NetworkMonitorViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: NetworkMonitorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L10n.reportTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(L10n.buttonClose) { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            if let summary = viewModel.monthlyReportService.currentMonthSummary {
                ScrollView {
                    VStack(spacing: 16) {
                        // Month label
                        Text(L10n.reportMonthLabel(summary.formattedMonth))
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Recommendation card
                        recommendationCard(summary)

                        // Speed stats
                        speedStatsCard(summary)

                        // Connection quality
                        connectionCard(summary)

                        // Plan utilization
                        utilizationCard(summary)

                        // Export button
                        Button(action: { exportReport(summary) }) {
                            Label(L10n.reportExport, systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(L10n.reportNoData)
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 500, height: 600)
    }

    // MARK: - Card Views

    private func recommendationCard(_ summary: MonthlySummary) -> some View {
        HStack {
            Image(systemName: summary.recommendation.icon)
                .font(.title)
                .foregroundColor(recommendationColor(summary.recommendation))
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.reportRecommendation)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Text(summary.recommendation.displayName)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(recommendationColor(summary.recommendation))
            }
            Spacer()
            Text("\(summary.daysMonitored) " + L10n.reportDaysMonitored)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(recommendationColor(summary.recommendation).opacity(0.1)))
    }

    private func speedStatsCard(_ summary: MonthlySummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                statItem(L10n.reportPeakDownload, value: String(format: "%.1f Mbps", summary.peakDownloadMbps))
                statItem(L10n.reportPeakUpload, value: String(format: "%.1f Mbps", summary.peakUploadMbps))
            }
            HStack(spacing: 24) {
                statItem(L10n.reportAvgDownload, value: String(format: "%.1f Mbps", summary.avgDownloadMbps))
                statItem(L10n.reportAvgUpload, value: String(format: "%.1f Mbps", summary.avgUploadMbps))
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
    }

    private func connectionCard(_ summary: MonthlySummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                statItem(L10n.reportAvgLatency, value: String(format: "%.0f ms", summary.avgLatencyMs))
                statItem(L10n.reportAvgJitter, value: String(format: "%.1f ms", summary.avgJitterMs))
            }
            HStack(spacing: 24) {
                statItem(L10n.reportDisconnects, value: "\(summary.disconnectCount)")
                statItem(L10n.reportPeakApproaches, value: "\(summary.peakApproachCount)")
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
    }

    private func utilizationCard(_ summary: MonthlySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.reportPlanUtilization)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            HStack(spacing: 16) {
                utilizationBar(label: "\u{2193}", percentage: summary.downloadPlanUtilization)
                utilizationBar(label: "\u{2191}", percentage: summary.uploadPlanUtilization)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
    }

    // MARK: - Helpers

    private func statItem(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func utilizationBar(label: String, percentage: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text(String(format: "%.0f%%", percentage))
                    .font(.caption)
                    .fontWeight(.bold)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(utilizationColor(percentage))
                        .frame(width: geometry.size.width * min(percentage / 100, 1.0))
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func utilizationColor(_ percentage: Double) -> Color {
        if percentage > 90 { return .red }
        if percentage > 70 { return .orange }
        return .green
    }

    private func recommendationColor(_ recommendation: MonthlySummary.PlanRecommendation) -> Color {
        switch recommendation {
        case .considerUpgrade: return .orange
        case .planFits: return .green
        case .considerDowngrade: return .blue
        case .insufficientData: return .secondary
        }
    }

    private func exportReport(_ summary: MonthlySummary) {
        let csv = viewModel.monthlyReportService.exportToCSV(summary)
        let filename = "monthly_report_\(summary.formattedMonth.replacingOccurrences(of: "/", with: "-")).csv"

        DataExportService.showSavePanel(suggestedFilename: filename) { url in
            guard let url = url else { return }
            try? csv.write(to: url, atomically: true, encoding: .utf8)
            DataExportService.revealInFinder(url: url)
        }
    }
}
