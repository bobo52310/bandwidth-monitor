import Foundation
import ServiceManagement

/// Whether the app is set to open when the user logs in, as the system sees it.
public enum LoginItemStatus: Sendable, Equatable {
    case enabled
    case disabled
    /// Registered, but the user has not allowed it yet in System Settings > Login Items.
    case requiresApproval
    /// The system can't register this app at all (for example it is not a bundle it knows).
    case unavailable
}

/// Registers the app as a login item. The system owns this state, so nothing here is stored in
/// `UserDefaults`; tests use a fake because registering changes the user's real configuration.
public protocol LoginItemControlling: Sendable {
    var status: LoginItemStatus { get }
    func setEnabled(_ enabled: Bool) throws
    func openSystemSettings()
}

/// `SMAppService.mainApp`-backed controller.
public struct SystemLoginItemController: LoginItemControlling {
    public init() {}

    public var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Where the running copy of the app lives. A login item registered for a copy that runs from
/// a mounted disk image or from the quarantine translocation path stops working after a restart
/// (PERF-04), so the setting is only offered for a copy in an Applications folder.
public enum InstallLocation {
    /// `true` for `/Applications` and the user's own `Applications` folder (any depth below them).
    public static func isInApplicationsFolder(_ bundleURL: URL, userHome: String) -> Bool {
        let path = bundleURL.standardizedFileURL.resolvingSymlinksInPath().path
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: userHome).appendingPathComponent("Applications"),
        ]
        return roots.contains { root in
            path.hasPrefix(root.standardizedFileURL.resolvingSymlinksInPath().path + "/")
        }
    }

    /// The real home directory. Inside the sandbox `NSHomeDirectory()` is the container, which
    /// is not where the user's `~/Applications` is.
    public static var userHome: String {
        if let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir {
            return String(cString: home)
        }
        return NSHomeDirectory()
    }

    /// Whether the running app can be registered as a login item that survives a restart.
    public static var currentCopyCanLaunchAtLogin: Bool {
        isInApplicationsFolder(Bundle.main.bundleURL, userHome: userHome)
    }
}
