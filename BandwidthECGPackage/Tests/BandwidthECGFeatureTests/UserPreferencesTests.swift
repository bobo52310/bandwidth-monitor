import Testing
import Foundation
@testable import BandwidthECGFeature

/// Settings that must survive a restart and actually take effect (CORE-24, PERF-10).
@Suite("UserPreferences")
@MainActor
struct UserPreferencesTests {

    // MARK: - Dock

    /// CORE-24: `init` used to overwrite the stored value with `false` on every launch.
    @Test func showInDock_persistsAcrossInit() {
        let defaults = MemoryDefaults.make()
        let prefs = UserPreferences(defaults: defaults)

        prefs.showInDock = true

        let reloaded = UserPreferences(defaults: defaults)
        #expect(reloaded.showInDock)
        #expect(defaults.bool(forKey: "showInDock"))
    }

    @Test func showInDock_defaultFalse() {
        let defaults = MemoryDefaults.make()

        let prefs = UserPreferences(defaults: defaults)

        #expect(!prefs.showInDock)
    }

    @Test func showInDock_turnedOffAgain_persistsFalse() {
        let defaults = MemoryDefaults.make()
        let prefs = UserPreferences(defaults: defaults)
        prefs.showInDock = true
        prefs.showInDock = false

        #expect(!UserPreferences(defaults: defaults).showInDock)
    }

    /// Creating the preferences must not write a default for a key nobody has set.
    @Test func init_doesNotWriteShowInDock() {
        let defaults = MemoryDefaults.make()

        _ = UserPreferences(defaults: defaults)

        #expect(defaults.object(forKey: "showInDock") == nil)
    }

    // MARK: - Launch at login (CORE-15, UI-P1-1)

    private func makePreferences(
        _ loginItems: FakeLoginItems,
        defaults: MemoryDefaults = MemoryDefaults.make()
    ) -> UserPreferences {
        UserPreferences(defaults: defaults, loginItems: loginItems)
    }

    @Test func initialValue_fromSystemStatus() {
        let defaults = MemoryDefaults.make()
        // The saved copy says no; the system says yes. The system wins.
        defaults.set(false, forKey: "launchAtLogin")

        #expect(makePreferences(FakeLoginItems(status: .enabled), defaults: defaults).launchAtLogin)
        #expect(!makePreferences(FakeLoginItems(status: .disabled)).launchAtLogin)
        // Waiting for the user's approval is not "on": nothing opens at login yet.
        #expect(!makePreferences(FakeLoginItems(status: .requiresApproval)).launchAtLogin)
        #expect(!makePreferences(FakeLoginItems(status: .unavailable)).launchAtLogin)
    }

    @Test func enable_callsRegister() {
        let fake = FakeLoginItems(status: .disabled)
        let prefs = makePreferences(fake)

        prefs.setLaunchAtLogin(true)

        #expect(fake.setEnabledCalls == [true])
        #expect(prefs.launchAtLogin)
        #expect(prefs.launchAtLoginMessage == nil)
        #expect(fake.openSystemSettingsCount == 0)
    }

    @Test func disable_callsUnregister() {
        let fake = FakeLoginItems(status: .enabled)
        let prefs = makePreferences(fake)

        prefs.setLaunchAtLogin(false)

        #expect(fake.setEnabledCalls == [false])
        #expect(!prefs.launchAtLogin)
        #expect(prefs.launchAtLoginMessage == nil)
    }

    @Test func failure_rollsBackAndReports() {
        let fake = FakeLoginItems(status: .disabled)
        fake.failNextChange = true
        let prefs = makePreferences(fake)

        prefs.setLaunchAtLogin(true)

        #expect(!prefs.launchAtLogin)
        let message = prefs.launchAtLoginMessage
        #expect(message != nil)
        #expect(message?.contains("registration refused") == true)
    }

    /// Turning it off can fail too. The toggle then stays on, because that is what the system has.
    @Test func disableFailure_keepsTheToggleOn() {
        let fake = FakeLoginItems(status: .enabled)
        fake.failNextChange = true
        let prefs = makePreferences(fake)

        prefs.setLaunchAtLogin(false)

        #expect(prefs.launchAtLogin)
        #expect(prefs.launchAtLoginMessage != nil)
    }

    @Test func requiresApproval_opensSystemSettings() {
        let fake = FakeLoginItems(status: .disabled)
        fake.statusAfterEnable = .requiresApproval
        let prefs = makePreferences(fake)

        prefs.setLaunchAtLogin(true)

        #expect(fake.openSystemSettingsCount == 1)
        #expect(prefs.launchAtLoginMessage == L10n.settingsLaunchAtLoginNeedsApproval)
        #expect(!prefs.launchAtLogin)
    }

    /// Clicking again while the approval is still pending sends the user back to System
    /// Settings instead of registering a second time.
    @Test func requiresApproval_clickingAgain_opensSystemSettingsWithoutRegistering() {
        let fake = FakeLoginItems(status: .requiresApproval)
        let prefs = makePreferences(fake)

        prefs.setLaunchAtLogin(true)

        #expect(fake.setEnabledCalls.isEmpty)
        #expect(fake.openSystemSettingsCount == 1)
        #expect(prefs.launchAtLoginMessage != nil)
    }

    /// Registering twice or unregistering what isn't registered throws in the system API.
    @Test func alreadyInTheRequestedState_isANoOp() {
        let on = FakeLoginItems(status: .enabled)
        let prefsOn = makePreferences(on)
        prefsOn.setLaunchAtLogin(true)
        #expect(on.setEnabledCalls.isEmpty)
        #expect(prefsOn.launchAtLogin)

        let off = FakeLoginItems(status: .disabled)
        let prefsOff = makePreferences(off)
        prefsOff.setLaunchAtLogin(false)
        #expect(off.setEnabledCalls.isEmpty)
        #expect(!prefsOff.launchAtLogin)
    }

    @Test func oldDefaultsKey_ignoredAndRemoved() {
        let defaults = MemoryDefaults.make()
        defaults.set(true, forKey: "launchAtLogin")
        let fake = FakeLoginItems(status: .disabled)

        let prefs = UserPreferences(defaults: defaults, loginItems: fake)

        #expect(!prefs.launchAtLogin)
        #expect(defaults.object(forKey: "launchAtLogin") == nil)
        // Never registers on its own.
        #expect(fake.setEnabledCalls.isEmpty)
    }

    @Test func launchAtLogin_isNeverWrittenToDefaults() {
        let defaults = MemoryDefaults.make()
        let prefs = makePreferences(FakeLoginItems(status: .disabled), defaults: defaults)

        prefs.setLaunchAtLogin(true)

        #expect(prefs.launchAtLogin)
        #expect(defaults.object(forKey: "launchAtLogin") == nil)
    }

    @Test func refresh_followsSystemSettings() {
        let fake = FakeLoginItems(status: .requiresApproval)
        let prefs = makePreferences(fake)
        prefs.setLaunchAtLogin(true)
        #expect(prefs.launchAtLoginMessage != nil)

        // The user allows it in System Settings.
        fake.setStatusBehindTheAppsBack(.enabled)
        prefs.refreshLaunchAtLogin()

        #expect(prefs.launchAtLogin)
        #expect(prefs.launchAtLoginMessage == nil)

        // And later switches it off there.
        fake.setStatusBehindTheAppsBack(.disabled)
        prefs.refreshLaunchAtLogin()
        #expect(!prefs.launchAtLogin)
    }

    @Test func viewModel_usesTheInjectedLoginItems() {
        let fake = FakeLoginItems(status: .enabled)
        let viewModel = NetworkMonitorViewModel(
            dependencies: .test(clock: TestClock(2026, 11, 3, 10), loginItems: fake)
        )

        #expect(viewModel.preferences.launchAtLogin)
        viewModel.preferences.setLaunchAtLogin(false)
        #expect(fake.setEnabledCalls == [false])
    }

    // MARK: - Where the app runs from (PERF-04)

    @Test(arguments: [
        "/Applications/Bandwidth ECG.app",
        "/Applications/Utilities/Bandwidth ECG.app",
        "/Users/test/Applications/Bandwidth ECG.app",
    ])
    func installedCopy_canLaunchAtLogin(path: String) {
        let url = URL(fileURLWithPath: path)
        #expect(InstallLocation.isInApplicationsFolder(url, userHome: "/Users/test"))
    }

    @Test(arguments: [
        "/Users/test/Downloads/Bandwidth ECG.app",
        "/Users/test/Desktop/Bandwidth ECG.app",
        "/Volumes/Bandwidth ECG/Bandwidth ECG.app",
        "/private/var/folders/ab/cd/T/AppTranslocation/0A1B/d/Bandwidth ECG.app",
        "/ApplicationsOld/Bandwidth ECG.app",
        "/Users/other/Applications/Bandwidth ECG.app",
        "/Users/test/Applications.app",
    ])
    func copyOutsideApplications_cannotLaunchAtLogin(path: String) {
        let url = URL(fileURLWithPath: path)
        #expect(!InstallLocation.isInApplicationsFolder(url, userHome: "/Users/test"))
    }
}
