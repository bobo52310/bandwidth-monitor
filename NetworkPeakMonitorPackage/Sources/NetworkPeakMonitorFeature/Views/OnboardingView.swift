import SwiftUI

public struct OnboardingView: View {
    @ObservedObject var viewModel: NetworkMonitorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    public init(viewModel: NetworkMonitorViewModel) {
        self.viewModel = viewModel
    }

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "chart.line.uptrend.xyaxis",
            iconColor: .blue,
            title: "歡迎使用 Network Peak Monitor",
            description: "即時監控您的網路速度，追蹤峰值記錄，確保您的網路效能符合預期。",
            features: [
                "即時顯示上傳/下載速度",
                "自動記錄今日、1小時和歷史峰值",
                "互動式圖表視覺化網路流量"
            ]
        ),
        OnboardingPage(
            icon: "bell.badge.fill",
            iconColor: .orange,
            title: "智慧通知提醒",
            description: "當網路速度接近您的方案上限時，我們會及時通知您。",
            features: [
                "可自訂通知閾值 (90%, 95%, 98%)",
                "避免過度使用頻寬",
                "1小時冷卻時間，避免通知干擾"
            ]
        ),
        OnboardingPage(
            icon: "square.and.arrow.down",
            iconColor: .green,
            title: "數據導出與分析",
            description: "輕鬆導出您的網路數據，進行深度分析。",
            features: [
                "導出今日數據 (過去24小時)",
                "導出峰值記錄",
                "導出完整歷史記錄",
                "CSV 格式，方便使用 Excel 分析"
            ]
        ),
        OnboardingPage(
            icon: "gear",
            iconColor: .secondary,
            title: "開始設定",
            description: "請設定您的網路方案速度上限，以便我們提供更準確的監控。",
            features: []
        )
    ]

    public var body: some View {
        VStack(spacing: 0) {
            // Page Indicator
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut, value: currentPage)
                }
            }
            .padding(.top, 20)

            // Content
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    OnboardingPageView(
                        page: pages[index],
                        isLastPage: index == pages.count - 1,
                        viewModel: viewModel
                    )
                    .tag(index)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation Buttons
            HStack {
                if currentPage > 0 {
                    Button("上一步") {
                        withAnimation {
                            currentPage -= 1
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if currentPage < pages.count - 1 {
                    Button("下一步") {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("開始使用") {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
        }
        .frame(width: 500, height: 550)
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        dismiss()
    }
}

struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let features: [String]
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    let isLastPage: Bool
    @ObservedObject var viewModel: NetworkMonitorViewModel

    var body: some View {
        VStack(spacing: 25) {
            // Icon
            Image(systemName: page.icon)
                .font(.system(size: 80))
                .foregroundColor(page.iconColor)
                .padding(.top, 40)

            // Title
            Text(page.title)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            // Description
            Text(page.description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            // Features or Settings
            if !page.features.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(page.features, id: \.self) { feature in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text(feature)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 40)
            } else if isLastPage {
                // Settings form for last page
                VStack(spacing: 16) {
                    HStack {
                        Text("下載速度上限:")
                            .frame(width: 120, alignment: .leading)
                        TextField("300", value: $viewModel.preferences.downloadPlanSpeed, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("Mbps")
                    }

                    HStack {
                        Text("上傳速度上限:")
                            .frame(width: 120, alignment: .leading)
                        TextField("300", value: $viewModel.preferences.uploadPlanSpeed, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("Mbps")
                    }

                    Toggle("啟用峰值通知", isOn: $viewModel.notificationService.isEnabled)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 40)
            }

            Spacer()
        }
    }
}

#Preview {
    OnboardingView(viewModel: NetworkMonitorViewModel())
}
