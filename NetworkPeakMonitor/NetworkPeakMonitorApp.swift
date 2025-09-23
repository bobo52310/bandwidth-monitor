import SwiftUI
import NetworkPeakMonitorFeature

@main
struct NetworkPeakMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
