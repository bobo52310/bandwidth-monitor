import Testing
import Foundation
@testable import BandwidthECGFeature

/// CORE-05: a plan speed of 0, a negative number, NaN or infinity used to reach `Int(...)`
/// (after dividing by zero) and crash the app.
@Suite("PlanSpeed Tests")
@MainActor
struct PlanSpeedTests {

    // MARK: - Helpers

    private typealias PlanKeyPath = ReferenceWritableKeyPath<UserPreferences, Double>

    /// Runs `body` once for the download plan and once for the upload plan, each on a fresh
    /// `UserPreferences` backed by its own in-memory defaults.
    private func forEachPlan(
        _ body: (_ prefs: UserPreferences, _ defaults: MemoryDefaults, _ plan: PlanKeyPath, _ key: String) -> Void
    ) {
        let plans: [(PlanKeyPath, String)] = [
            (\UserPreferences.downloadPlanSpeed, "downloadPlanSpeed"),
            (\UserPreferences.uploadPlanSpeed, "uploadPlanSpeed"),
        ]
        for (plan, key) in plans {
            let defaults = MemoryDefaults.make()
            body(UserPreferences(defaults: defaults), defaults, plan, key)
        }
    }

    private func makeService(
        _ delivery: FakeNotificationDelivery,
        clock: TestClock = TestClock(2026, 10, 31, 12)
    ) -> NotificationService {
        NotificationService(
            defaults: MemoryDefaults.make(),
            clock: clock.appClock,
            delivery: delivery
        )
    }

    // MARK: - UserPreferences: setting a plan

    @Test func planZero_keepsPrevious() {
        forEachPlan { prefs, defaults, plan, key in
            prefs[keyPath: plan] = 300
            prefs[keyPath: plan] = 0
            #expect(prefs[keyPath: plan] == 300)
            // A value that differs from the default, so falling back to 300 would be caught.
            prefs[keyPath: plan] = 450
            prefs[keyPath: plan] = 0
            #expect(prefs[keyPath: plan] == 450)
            #expect(defaults.double(forKey: key) == 450)
        }
    }

    @Test func planNegative_keepsPrevious() {
        forEachPlan { prefs, defaults, plan, key in
            prefs[keyPath: plan] = 300
            prefs[keyPath: plan] = -5
            #expect(prefs[keyPath: plan] == 300)
            prefs[keyPath: plan] = 450
            prefs[keyPath: plan] = -5
            #expect(prefs[keyPath: plan] == 450)
            #expect(defaults.double(forKey: key) == 450)
        }
    }

    @Test func planNaN_keepsPrevious() {
        forEachPlan { prefs, defaults, plan, key in
            prefs[keyPath: plan] = 300
            prefs[keyPath: plan] = .nan
            #expect(prefs[keyPath: plan] == 300)
            #expect(defaults.double(forKey: key) == 300)
        }
    }

    @Test func planInfinity_keepsPrevious() {
        forEachPlan { prefs, defaults, plan, key in
            prefs[keyPath: plan] = 300
            prefs[keyPath: plan] = .infinity
            #expect(prefs[keyPath: plan] == 300)
            prefs[keyPath: plan] = -.infinity
            #expect(prefs[keyPath: plan] == 300)
            #expect(defaults.double(forKey: key) == 300)
        }
    }

    /// `planSpeedRange` documents 1.0 as the lower bound. A value below it (a typo such as 0.3)
    /// is rejected like zero is, so it can't turn into a 1 Mbps plan nobody asked for.
    @Test(arguments: [0.5, 0.999, 1e-9])
    func planBelowLowerBound_keepsPrevious(proposed: Double) {
        forEachPlan { prefs, defaults, plan, key in
            prefs[keyPath: plan] = 450
            prefs[keyPath: plan] = proposed
            #expect(prefs[keyPath: plan] == 450)
            #expect(defaults.double(forKey: key) == 450)
        }
    }

    @Test func planAtLowerBound_isAccepted() {
        forEachPlan { prefs, defaults, plan, key in
            prefs[keyPath: plan] = 1.0
            #expect(prefs[keyPath: plan] == 1.0)
            #expect(defaults.double(forKey: key) == 1.0)
        }
    }

    @Test func planHuge_clamped() {
        forEachPlan { prefs, defaults, plan, key in
            prefs[keyPath: plan] = 1e300
            #expect(prefs[keyPath: plan] == 100_000)
            #expect(defaults.double(forKey: key) == 100_000)
        }
    }

    @Test func planValid_isStored() {
        forEachPlan { prefs, defaults, plan, key in
            prefs[keyPath: plan] = 1000
            #expect(prefs[keyPath: plan] == 1000)
            #expect(defaults.double(forKey: key) == 1000)
            prefs[keyPath: plan] = 100_000
            #expect(prefs[keyPath: plan] == 100_000)
        }
    }

    // MARK: - UserPreferences: loading a stored plan

    @Test(arguments: [0.0, -1.0, Double.infinity, 0.5, 0.999])
    func storedZero_loadsDefault(stored: Double) {
        let defaults = MemoryDefaults.make()
        defaults.set(stored, forKey: "downloadPlanSpeed")
        defaults.set(stored, forKey: "uploadPlanSpeed")

        let prefs = UserPreferences(defaults: defaults)

        #expect(prefs.downloadPlanSpeed == 300)
        #expect(prefs.uploadPlanSpeed == 300)
    }

    @Test func storedHuge_loadsClamped() {
        let defaults = MemoryDefaults.make()
        defaults.set(1e300, forKey: "downloadPlanSpeed")
        defaults.set(500.0, forKey: "uploadPlanSpeed")

        let prefs = UserPreferences(defaults: defaults)

        #expect(prefs.downloadPlanSpeed == 100_000)
        #expect(prefs.uploadPlanSpeed == 500)
    }

    @Test func preferences_useInjectedDefaults() {
        let defaults = MemoryDefaults.make()
        let prefs = UserPreferences(defaults: defaults)
        prefs.displayUnit = .mbps_lower
        prefs.isPinned = true

        let reloaded = UserPreferences(defaults: defaults)
        #expect(reloaded.displayUnit == .mbps_lower)
        #expect(reloaded.isPinned)
    }

    // MARK: - NotificationService.checkAndNotify

    @Test func checkAndNotify_planZero_noTrap() async {
        let delivery = FakeNotificationDelivery()
        let service = makeService(delivery)

        service.checkAndNotify(
            downloadSpeed: 100, uploadSpeed: 100,
            downloadPlanSpeed: 0, uploadPlanSpeed: 0
        )
        await service.lastDeliveryTask?.value

        #expect(delivery.delivered.isEmpty)
    }

    @Test func checkAndNotify_planNegative_noTrap() async {
        let delivery = FakeNotificationDelivery()
        let service = makeService(delivery)

        service.checkAndNotify(
            downloadSpeed: 100, uploadSpeed: 100,
            downloadPlanSpeed: -1, uploadPlanSpeed: -1
        )
        await service.lastDeliveryTask?.value

        #expect(delivery.delivered.isEmpty)
    }

    @Test func checkAndNotify_uint64Max_noTrap() async {
        let delivery = FakeNotificationDelivery()
        let service = makeService(delivery)

        service.checkAndNotify(
            downloadSpeed: Double(UInt64.max), uploadSpeed: 0,
            downloadPlanSpeed: 1, uploadPlanSpeed: 1
        )
        await service.lastDeliveryTask?.value

        #expect(delivery.delivered.count == 1)
        #expect(delivery.delivered.first?.body.contains("9999") == true)
    }

    @Test func checkAndNotify_planHuge_noTrap() async {
        let delivery = FakeNotificationDelivery()
        let service = makeService(delivery)

        service.checkAndNotify(
            downloadSpeed: 1, uploadSpeed: 1,
            downloadPlanSpeed: 1e300, uploadPlanSpeed: 1e300
        )
        await service.lastDeliveryTask?.value

        #expect(delivery.delivered.isEmpty)
    }

    /// An unusable plan on one side must not silence (or crash) the other side.
    @Test func checkAndNotify_invalidDownloadPlan_stillChecksUpload() async {
        let delivery = FakeNotificationDelivery()
        let service = makeService(delivery)

        service.checkAndNotify(
            downloadSpeed: 500, uploadSpeed: 100,
            downloadPlanSpeed: 0, uploadPlanSpeed: 100
        )
        await service.lastDeliveryTask?.value

        #expect(delivery.delivered.count == 1)
        #expect(delivery.delivered.first?.body.contains(L10n.notificationUploadReached(100, "100.0")) == true)
    }

    @Test func checkAndNotify_nonFiniteSpeeds_noTrap() async {
        let delivery = FakeNotificationDelivery()
        let service = makeService(delivery)

        service.checkAndNotify(
            downloadSpeed: .nan, uploadSpeed: -.infinity,
            downloadPlanSpeed: 300, uploadPlanSpeed: 300
        )
        await service.lastDeliveryTask?.value

        #expect(delivery.delivered.isEmpty)
    }

    // MARK: - NotificationService with an injected clock

    @Test func checkAndNotify_cooldownUsesInjectedClock() async {
        let clock = TestClock(2026, 10, 31, 12)
        let delivery = FakeNotificationDelivery()
        let service = makeService(delivery, clock: clock)

        service.checkAndNotify(downloadSpeed: 300, uploadSpeed: 0, downloadPlanSpeed: 300, uploadPlanSpeed: 300)
        await service.lastDeliveryTask?.value
        #expect(delivery.delivered.count == 1)

        // Still inside the one hour cooldown.
        clock.advance(by: 3599)
        service.checkAndNotify(downloadSpeed: 300, uploadSpeed: 0, downloadPlanSpeed: 300, uploadPlanSpeed: 300)
        await service.lastDeliveryTask?.value
        #expect(delivery.delivered.count == 1)

        // Cooldown over.
        clock.advance(by: 2)
        service.checkAndNotify(downloadSpeed: 300, uploadSpeed: 0, downloadPlanSpeed: 300, uploadPlanSpeed: 300)
        await service.lastDeliveryTask?.value
        #expect(delivery.delivered.count == 2)
    }
}
