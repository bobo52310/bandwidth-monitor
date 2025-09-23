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

    public enum SpeedUnit: String, CaseIterable {
        case mbps = "Mbps"
        case mbps_lower = "MB/s"

        public var displayName: String {
            return self.rawValue
        }
    }

    public init() {
        self.downloadPlanSpeed = userDefaults.double(forKey: "downloadPlanSpeed")
        self.uploadPlanSpeed = userDefaults.double(forKey: "uploadPlanSpeed")
        self.displayUnit = SpeedUnit(rawValue: userDefaults.string(forKey: "displayUnit") ?? "Mbps") ?? .mbps
        self.launchAtLogin = userDefaults.bool(forKey: "launchAtLogin")

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