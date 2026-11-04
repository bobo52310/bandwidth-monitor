import AppKit
import OSLog

/// Starts a fresh copy of the running app and quits this one. Used when a setting only takes
/// effect at launch, such as the language.
enum AppRelauncher {
    private static let logger = Logger(subsystem: "com.bandwidthecg", category: "Lifecycle")

    /// Opens a second instance of this bundle, then terminates the current one once the new one
    /// is running. If the new instance can't be started, this one keeps running.
    ///
    /// The caller writes pending data first (`NetworkMonitorViewModel.flushPersistence()`): the
    /// new instance reads its files while this one is still alive.
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        // Without this the system just brings the running instance to the front.
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    logger.error("Relaunch failed: \(String(describing: error), privacy: .public)")
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }
}
