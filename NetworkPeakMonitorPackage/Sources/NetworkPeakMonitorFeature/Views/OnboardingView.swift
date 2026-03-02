import SwiftUI

public struct OnboardingView: View {
    @Bindable var viewModel: NetworkMonitorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    public init(viewModel: NetworkMonitorViewModel) {
        self.viewModel = viewModel
    }

    private var pages: [OnboardingPage] {
        [
            OnboardingPage(
                icon: "chart.line.uptrend.xyaxis",
                iconColor: .blue,
                title: L10n.onboardingWelcomeTitle,
                description: L10n.onboardingWelcomeDescription,
                features: [
                    L10n.onboardingFeature1,
                    L10n.onboardingFeature2,
                    L10n.onboardingFeature3
                ]
            ),
            OnboardingPage(
                icon: "bell.badge.fill",
                iconColor: .orange,
                title: L10n.onboardingNotificationTitle,
                description: L10n.onboardingNotificationDescription,
                features: [
                    L10n.onboardingNotificationFeature1,
                    L10n.onboardingNotificationFeature2,
                    L10n.onboardingNotificationFeature3
                ]
            ),
            OnboardingPage(
                icon: "square.and.arrow.down",
                iconColor: .green,
                title: L10n.onboardingExportTitle,
                description: L10n.onboardingExportDescription,
                features: [
                    L10n.onboardingExportFeature1,
                    L10n.onboardingExportFeature2,
                    L10n.onboardingExportFeature3,
                    L10n.onboardingExportFeature4
                ]
            ),
            OnboardingPage(
                icon: "gear",
                iconColor: .secondary,
                title: L10n.onboardingSetupTitle,
                description: L10n.onboardingSetupDescription,
                features: []
            )
        ]
    }

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
                    Button(L10n.buttonPrevious) {
                        withAnimation {
                            currentPage -= 1
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if currentPage < pages.count - 1 {
                    Button(L10n.buttonNext) {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(L10n.buttonGetStarted) {
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
    @Bindable var viewModel: NetworkMonitorViewModel

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
                        Text(L10n.settingsDownloadLimit)
                            .frame(width: 120, alignment: .leading)
                        TextField("300", value: $viewModel.preferences.downloadPlanSpeed, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("Mbps")
                    }

                    HStack {
                        Text(L10n.settingsUploadLimit)
                            .frame(width: 120, alignment: .leading)
                        TextField("300", value: $viewModel.preferences.uploadPlanSpeed, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("Mbps")
                    }

                    Toggle(L10n.settingsEnablePeakNotification, isOn: $viewModel.notificationService.isEnabled)
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
