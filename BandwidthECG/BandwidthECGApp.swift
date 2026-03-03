import SwiftUI
import BandwidthECGFeature

@main
struct BandwidthECGApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        ErrorHandler.migrateDataFromLegacyPath()
    }

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
