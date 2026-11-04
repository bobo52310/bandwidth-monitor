import SwiftUI
import AppKit
import UserNotifications

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    /// The notification center holds its delegate weakly, so it is kept here.
    private let notificationPresenter = ForegroundNotificationPresenter()

    public func applicationWillFinishLaunching(_ notification: Notification) {
        // Set before launch finishes, so alerts show as banners while the app is in front.
        UNUserNotificationCenter.current().delegate = notificationPresenter
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusBarController()
        statusBarController = controller
        // The Info.plist starts the app without a Dock icon; bring it up only if the user asked.
        controller.applyActivationPolicy()
    }

    /// The app was opened a second time. The status item can be pushed out of a full menu bar,
    /// and then this is the way to the panel.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBarController?.showPanelFromReopen()
        return false
    }

    public func applicationWillTerminate(_ notification: Notification) {
        statusBarController?.cleanUp()
    }
}