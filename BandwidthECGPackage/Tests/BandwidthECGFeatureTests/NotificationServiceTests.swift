import Testing
import Foundation
import UserNotifications
@testable import BandwidthECGFeature

/// CORE-30, UI-P2-16: the title names the plan that was hit, the test button does not use up
/// the cooldown, and a refused permission or a failed delivery is visible.
@MainActor
@Suite("NotificationService")
struct NotificationServiceTests {
    private let clock = TestClock(2026, 11, 3, 12)

    private func makeService(_ delivery: FakeNotificationDelivery) async -> NotificationService {
        let service = NotificationService(
            defaults: MemoryDefaults.make(),
            clock: clock.appClock,
            delivery: delivery
        )
        await service.authorizationTask?.value
        return service
    }

    // MARK: - Title

    @Test func title_uploadTrigger_usesUploadPlan() async throws {
        let delivery = FakeNotificationDelivery()
        let service = await makeService(delivery)

        service.checkAndNotify(downloadSpeed: 10, uploadSpeed: 100, downloadPlanSpeed: 300, uploadPlanSpeed: 100)
        await service.lastDeliveryTask?.value

        let title = try #require(delivery.delivered.first?.title)
        #expect(title == L10n.notificationApproachingLimit(100))
        #expect(title.contains("100"))
        #expect(!title.contains("300"))
    }

    @Test func title_downloadTrigger_usesDownloadPlan() async throws {
        let delivery = FakeNotificationDelivery()
        let service = await makeService(delivery)

        service.checkAndNotify(downloadSpeed: 50, uploadSpeed: 1, downloadPlanSpeed: 50, uploadPlanSpeed: 200)
        await service.lastDeliveryTask?.value

        let title = try #require(delivery.delivered.first?.title)
        #expect(title == L10n.notificationApproachingLimit(50))
        #expect(!title.contains("200"))
    }

    @Test func title_bothTriggered_usesTheLargerPlan() async throws {
        let delivery = FakeNotificationDelivery()
        let service = await makeService(delivery)

        service.checkAndNotify(downloadSpeed: 300, uploadSpeed: 100, downloadPlanSpeed: 300, uploadPlanSpeed: 100)
        await service.lastDeliveryTask?.value

        let title = try #require(delivery.delivered.first?.title)
        #expect(title == L10n.notificationApproachingLimit(300))
    }

    /// Fix round 2: the larger plan is the upload one, so taking the first triggered plan
    /// (download) instead of the larger would name the wrong plan.
    @Test func title_bothTriggered_largerUploadPlan_usesTheUploadPlan() async throws {
        let delivery = FakeNotificationDelivery()
        let service = await makeService(delivery)

        service.checkAndNotify(downloadSpeed: 100, uploadSpeed: 500, downloadPlanSpeed: 100, uploadPlanSpeed: 500)
        await service.lastDeliveryTask?.value

        let title = try #require(delivery.delivered.first?.title)
        #expect(title == L10n.notificationApproachingLimit(500))
        #expect(delivery.delivered.first?.body.contains(L10n.notificationDownloadReached(100, "100.0")) == true)
        #expect(delivery.delivered.first?.body.contains(L10n.notificationUploadReached(100, "500.0")) == true)
    }

    // MARK: - Cooldown

    @Test func testNotification_doesNotStartCooldown() async {
        let delivery = FakeNotificationDelivery()
        let service = await makeService(delivery)

        service.sendTestNotification()
        await service.lastDeliveryTask?.value
        service.checkAndNotify(downloadSpeed: 300, uploadSpeed: 0, downloadPlanSpeed: 300, uploadPlanSpeed: 300)
        await service.lastDeliveryTask?.value

        #expect(delivery.delivered.count == 2)
        #expect(delivery.delivered.first?.title == L10n.notificationTestTitle)
    }

    @Test func cooldown_oneHour() async {
        let delivery = FakeNotificationDelivery()
        let service = await makeService(delivery)
        func alert() async {
            service.checkAndNotify(downloadSpeed: 300, uploadSpeed: 0, downloadPlanSpeed: 300, uploadPlanSpeed: 300)
            await service.lastDeliveryTask?.value
        }

        await alert()
        clock.advance(by: 59 * 60)
        await alert()
        #expect(delivery.delivered.count == 1)

        clock.advance(by: 60)
        await alert()
        #expect(delivery.delivered.count == 2)
    }

    // MARK: - Failures are visible

    /// The cooldown counts real elapsed time. Setting the clock back must not hold alerts back
    /// for the hours it went back, and setting it forward must not end the cooldown early.
    @Test func cooldown_followsElapsedTimeNotTheWallClock() async {
        let delivery = FakeNotificationDelivery()
        let service = await makeService(delivery)
        func trigger() async {
            service.checkAndNotify(downloadSpeed: 300, uploadSpeed: 0, downloadPlanSpeed: 300, uploadPlanSpeed: 300)
            await service.lastDeliveryTask?.value
        }

        await trigger()
        #expect(delivery.delivered.count == 1)

        // The wall clock goes back a day; an hour of real time passes.
        clock.setWall(clock.now.addingTimeInterval(-86_400))
        clock.advance(by: 3600)
        await trigger()
        #expect(delivery.delivered.count == 2, "a clock set back suppressed the alert")

        // The wall clock jumps a day forward with no real time passing: still cooling down.
        clock.setWall(clock.now.addingTimeInterval(86_400 * 2))
        await trigger()
        #expect(delivery.delivered.count == 2, "a clock set forward ended the cooldown")
    }

    @Test func deliverFailure_surfaced() async {
        let delivery = FakeNotificationDelivery()
        let service = await makeService(delivery)
        #expect(service.lastDeliveryError == nil)

        delivery.failNextDelivery = true
        service.sendTestNotification()
        await service.lastDeliveryTask?.value
        #expect(service.lastDeliveryError != nil)

        // The next delivery that works clears it.
        service.sendTestNotification()
        await service.lastDeliveryTask?.value
        #expect(service.lastDeliveryError == nil)
    }

    @Test func denied_flagged() async {
        let delivery = FakeNotificationDelivery()
        delivery.grantAuthorization = false

        let service = await makeService(delivery)

        #expect(delivery.authorizationRequested)
        #expect(service.isAuthorized == false)
    }

    @Test func granted_isAuthorized() async {
        let service = await makeService(FakeNotificationDelivery())

        #expect(service.isAuthorized)
    }

    /// The user can allow notifications in System Settings later; asking again picks that up.
    @Test func refreshAuthorization_picksUpAChange() async {
        let delivery = FakeNotificationDelivery()
        delivery.grantAuthorization = false
        let service = await makeService(delivery)
        #expect(service.isAuthorized == false)

        delivery.grantAuthorization = true
        await service.refreshAuthorization()

        #expect(service.isAuthorized)
    }

    // MARK: - Foreground presentation

    /// Without a delegate the system shows nothing while the app is in front, which is
    /// exactly when the test button is pressed.
    @Test func foregroundPresenter_showsBannerAndSound() {
        let presenter: any UNUserNotificationCenterDelegate = ForegroundNotificationPresenter()

        #expect(ForegroundNotificationPresenter.foregroundOptions == [.banner, .sound])
        #expect(presenter.responds(to: #selector(
            UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:)
        )))
    }
}
