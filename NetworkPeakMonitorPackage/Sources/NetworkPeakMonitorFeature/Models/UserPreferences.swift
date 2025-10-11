import Foundation

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
                return "顯示兩者"
            case .downloadOnly:
                return "僅顯示下載"
            case .uploadOnly:
                return "僅顯示上傳"
            case .compact:
                return "簡潔模式"
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