import SwiftUI
import AppKit

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        statusBarController?.cleanUp()
    }
}