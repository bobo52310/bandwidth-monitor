import Foundation
import AppKit

public class UserPreferences: ObservableObject {
    private let userDefaults = UserDefaults.standard

    @Published public var downloadPlanSpeed: Double {
        didSet {
            userDefaults.set(downloadPlanSpeed, forKey: "downloadPlanSpeed")
        }
    }

    @Published public var uploadPlanSpeed: Double {
        didSet {
            userDefaults.set(uploadPlanSpeed, forKey: "uploadPlanSpeed")
        }
    }

    @Published public var displayUnit: SpeedUnit {
        didSet {
            userDefaults.set(displayUnit.rawValue, forKey: "displayUnit")
        }
    }

    @Published public var launchAtLogin: Bool {
        didSet {
            userDefaults.set(launchAtLogin, forKey: "launchAtLogin")
            updateLaunchAtLogin()
        }
    }

    @Published public var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            userDefaults.set(menuBarDisplayMode.rawValue, forKey: "menuBarDisplayMode")
        }
    }

    @Published public var isPinned: Bool {
        didSet {
            userDefaults.set(isPinned, forKey: "isPinned")
        }
    }

    @Published public var showInDock: Bool {
        didSet {
            userDefaults.set(showInDock, forKey: "showInDock")
            let shouldShowInDock = showInDock
            Task { @MainActor in
                if shouldShowInDock {
                    NSApp.setActivationPolicy(.regular)
                } else {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    @Published public var chartYAxisMode: ChartYAxisMode {
        didSet {
            userDefaults.set(chartYAxisMode.rawValue, forKey: "chartYAxisMode")
        }
    }

    @Published public var appLanguage: AppLanguage {
        didSet {
            userDefaults.set(appLanguage.rawValue, forKey: "appLanguage")
            applyLanguage()
        }
    }

    public enum AppLanguage: String, CaseIterable {
        case system = "system"
        case english = "en"
        case traditionalChinese = "zh-Hant"
        case japanese = "ja"
        case korean = "ko"

        public var displayName: String {
            switch self {
            case .system:
                return L10n.languageSystem
            case .english:
                return L10n.languageEnglish
            case .traditionalChinese:
                return L10n.languageTraditionalChinese
            case .japanese:
                return L10n.languageJapanese
            case .korean:
                return L10n.languageKorean
            }
        }

        /// The locale identifier for this language
        public var localeIdentifier: String? {
            switch self {
            case .system:
                return nil
            case .english:
                return "en"
            case .traditionalChinese:
                return "zh-Hant"
            case .japanese:
                return "ja"
            case .korean:
                return "ko"
            }
        }
    }

    private func applyLanguage() {
        if let localeId = appLanguage.localeIdentifier {
            UserDefaults.standard.set([localeId], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }

    public enum ChartYAxisMode: String, CaseIterable {
        case auto = "auto"
        case fixed = "fixed"

        public var displayName: String {
            switch self {
            case .auto:
                return L10n.chartYAxisModeAuto
            case .fixed:
                return L10n.chartYAxisModeFixed
            }
        }

        public var icon: String {
            switch self {
            case .auto:
                return "arrow.up.left.and.arrow.down.right"
            case .fixed:
                return "lock.fill"
            }
        }
    }

    public enum SpeedUnit: String, CaseIterable {
        case mbps = "Mbps"
        case mbps_lower = "MB/s"

        public var displayName: String {
            return self.rawValue
        }
    }

    public enum MenuBarDisplayMode: String, CaseIterable {
        case both = "both"
        case downloadOnly = "downloadOnly"
        case uploadOnly = "uploadOnly"
        case compact = "compact"

        public var displayName: String {
            switch self {
            case .both:
                return L10n.menuBarModeBoth
            case .downloadOnly:
                return L10n.menuBarModeDownloadOnly
            case .uploadOnly:
                return L10n.menuBarModeUploadOnly
            case .compact:
                return L10n.menuBarModeCompact
            }
        }

        public var description: String {
            switch self {
            case .both:
                return "↑ X.X ↓ X.X Mbps"
            case .downloadOnly:
                return "↓ X.X Mbps"
            case .uploadOnly:
                return "↑ X.X Mbps"
            case .compact:
                return "X.X/X.X Mbps"
            }
        }
    }

    public init() {
        self.downloadPlanSpeed = userDefaults.double(forKey: "downloadPlanSpeed")
        self.uploadPlanSpeed = userDefaults.double(forKey: "uploadPlanSpeed")
        self.displayUnit = SpeedUnit(rawValue: userDefaults.string(forKey: "displayUnit") ?? "Mbps") ?? .mbps
        self.launchAtLogin = userDefaults.bool(forKey: "launchAtLogin")
        self.menuBarDisplayMode = MenuBarDisplayMode(rawValue: userDefaults.string(forKey: "menuBarDisplayMode") ?? "both") ?? .both
        self.isPinned = userDefaults.bool(forKey: "isPinned")
        self.chartYAxisMode = ChartYAxisMode(rawValue: userDefaults.string(forKey: "chartYAxisMode") ?? "auto") ?? .auto
        self.appLanguage = AppLanguage(rawValue: userDefaults.string(forKey: "appLanguage") ?? "system") ?? .system

        // Default to false (menu bar only, no dock icon)
        // This will reset all users to the new default behavior
        self.showInDock = false
        userDefaults.set(false, forKey: "showInDock")

        // Set default values if not set
        if downloadPlanSpeed == 0 {
            downloadPlanSpeed = 300
        }
        if uploadPlanSpeed == 0 {
            uploadPlanSpeed = 300
        }
    }

    private func updateLaunchAtLogin() {
        // Implementation for macOS launch at login
        // Will be implemented later
    }
}