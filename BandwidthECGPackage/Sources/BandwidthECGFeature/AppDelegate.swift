import SwiftUI
import AppKit

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Set initial activation policy based on user preference
        let preferences = UserPreferences()
        if preferences.showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }

        statusBarController = StatusBarController()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        statusBarController?.cleanUp()
    }
}