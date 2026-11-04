import Foundation
import AppKit
import Observation

@Observable
public class UserPreferences {
    private let userDefaults: UserDefaults
    private let loginItems: any LoginItemControlling

    /// Plan speeds the rest of the app can safely divide by and convert to `Int`.
    /// Values above the upper bound are clamped to it. Values below the lower bound (zero,
    /// negative and tiny ones such as a mistyped 0.3) and non-finite values are rejected.
    public static let planSpeedRange: ClosedRange<Double> = 1.0...100_000.0

    /// Plan speed (Mbps) used on first launch and whenever a stored value is unusable.
    public static let defaultPlanSpeed: Double = 300

    public var downloadPlanSpeed: Double {
        didSet {
            let valid = Self.validatedPlanSpeed(downloadPlanSpeed, previous: oldValue)
            if valid != downloadPlanSpeed {
                downloadPlanSpeed = valid
            }
            userDefaults.set(downloadPlanSpeed, forKey: "downloadPlanSpeed")
        }
    }

    public var uploadPlanSpeed: Double {
        didSet {
            let valid = Self.validatedPlanSpeed(uploadPlanSpeed, previous: oldValue)
            if valid != uploadPlanSpeed {
                uploadPlanSpeed = valid
            }
            userDefaults.set(uploadPlanSpeed, forKey: "uploadPlanSpeed")
        }
    }

    /// A newly assigned plan speed that is not finite or below `planSpeedRange.lowerBound` is
    /// rejected and the previous value is kept; anything above the upper bound is clamped to it.
    /// Rejecting rather than clamping a low value means a typo never becomes a 1 Mbps plan.
    private static func validatedPlanSpeed(_ proposed: Double, previous: Double) -> Double {
        guard proposed.isFinite, proposed >= planSpeedRange.lowerBound else { return previous }
        return min(proposed, planSpeedRange.upperBound)
    }

    /// A stored plan speed that is not finite or below the lower bound falls back to `defaultPlanSpeed`.
    private static func loadedPlanSpeed(_ stored: Double) -> Double {
        guard stored.isFinite, stored >= planSpeedRange.lowerBound else { return defaultPlanSpeed }
        return min(stored, planSpeedRange.upperBound)
    }

    public var displayUnit: SpeedUnit {
        didSet {
            userDefaults.set(displayUnit.rawValue, forKey: "displayUnit")
        }
    }

    /// Whether the system will open the app at login. The system owns this state, so it is read
    /// from the login item status and never stored in `UserDefaults`; change it with
    /// `setLaunchAtLogin(_:)`.
    public private(set) var launchAtLogin: Bool

    /// Why the last `setLaunchAtLogin(_:)` did not end the way the user asked, or `nil`.
    public private(set) var launchAtLoginMessage: String?

    public var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            userDefaults.set(menuBarDisplayMode.rawValue, forKey: "menuBarDisplayMode")
        }
    }

    public var isPinned: Bool {
        didSet {
            userDefaults.set(isPinned, forKey: "isPinned")
        }
    }

    public var showInDock: Bool {
        didSet {
            userDefaults.set(showInDock, forKey: "showInDock")
            let shouldShowInDock = showInDock
            Task { @MainActor in
                Self.applyActivationPolicy(showInDock: shouldShowInDock)
            }
        }
    }

    /// Shows or hides the Dock icon. Does nothing without a running application (tests).
    @MainActor
    public static func applyActivationPolicy(showInDock: Bool) {
        NSApp?.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    public var chartYAxisMode: ChartYAxisMode {
        didSet {
            userDefaults.set(chartYAxisMode.rawValue, forKey: "chartYAxisMode")
        }
    }

    public var appLanguage: AppLanguage {
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
            userDefaults.set([localeId], forKey: "AppleLanguages")
        } else {
            userDefaults.removeObject(forKey: "AppleLanguages")
        }
        userDefaults.synchronize()
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
    }

    public init(
        defaults: UserDefaults = .standard,
        loginItems: any LoginItemControlling = SystemLoginItemController()
    ) {
        self.userDefaults = defaults
        self.loginItems = loginItems
        self.downloadPlanSpeed = Self.loadedPlanSpeed(defaults.double(forKey: "downloadPlanSpeed"))
        self.uploadPlanSpeed = Self.loadedPlanSpeed(defaults.double(forKey: "uploadPlanSpeed"))
        self.displayUnit = SpeedUnit(rawValue: userDefaults.string(forKey: "displayUnit") ?? "Mbps") ?? .mbps
        self.launchAtLogin = loginItems.status == .enabled
        self.menuBarDisplayMode = MenuBarDisplayMode(rawValue: userDefaults.string(forKey: "menuBarDisplayMode") ?? "both") ?? .both
        self.isPinned = userDefaults.bool(forKey: "isPinned")
        self.chartYAxisMode = ChartYAxisMode(rawValue: userDefaults.string(forKey: "chartYAxisMode") ?? "auto") ?? .auto
        self.appLanguage = AppLanguage(rawValue: userDefaults.string(forKey: "appLanguage") ?? "system") ?? .system

        // Menu bar only (no Dock icon) until the user turns it on.
        self.showInDock = userDefaults.object(forKey: "showInDock") as? Bool ?? false

        // Older versions kept their own copy of the login item toggle. It says nothing about
        // what the system has registered, and it must never register the app by itself.
        defaults.removeObject(forKey: "launchAtLogin")

        // Write back a plan speed that was missing or had to be corrected, so the stored value is valid.
        if defaults.double(forKey: "downloadPlanSpeed") != downloadPlanSpeed {
            defaults.set(downloadPlanSpeed, forKey: "downloadPlanSpeed")
        }
        if defaults.double(forKey: "uploadPlanSpeed") != uploadPlanSpeed {
            defaults.set(uploadPlanSpeed, forKey: "uploadPlanSpeed")
        }
    }

    // MARK: - Launch at login

    /// Asks the system to open (or stop opening) the app at login, then shows what it ended up
    /// doing: a refused registration rolls the toggle back and says why, and a registration the
    /// user still has to approve opens System Settings.
    public func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginMessage = nil
        let current = loginItems.status

        if enabled {
            if current == .enabled {
                launchAtLogin = true
                return
            }
            // Registered already, waiting for the user: registering again changes nothing.
            if current == .requiresApproval {
                launchAtLogin = false
                askForApproval()
                return
            }
        } else if current == .disabled || current == .unavailable {
            // Nothing is registered, so there is nothing to undo (unregistering would throw).
            launchAtLogin = false
            return
        }

        do {
            try loginItems.setEnabled(enabled)
        } catch {
            launchAtLogin = loginItems.status == .enabled
            launchAtLoginMessage = L10n.settingsLaunchAtLoginFailed(error.localizedDescription)
            return
        }

        let after = loginItems.status
        launchAtLogin = after == .enabled
        if enabled, after == .requiresApproval {
            askForApproval()
        }
    }

    /// Re-reads the system state. The user can change it in System Settings at any time.
    public func refreshLaunchAtLogin() {
        launchAtLogin = loginItems.status == .enabled
        if launchAtLogin {
            launchAtLoginMessage = nil
        }
    }

    private func askForApproval() {
        launchAtLoginMessage = L10n.settingsLaunchAtLoginNeedsApproval
        loginItems.openSystemSettings()
    }
}