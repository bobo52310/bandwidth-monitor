import Testing
import Foundation
@testable import BandwidthECGFeature

@Test func disconnectEvent_hasDuration() async throws {
    let start = Date().addingTimeInterval(-60)
    let end = Date()
    let event = DisconnectEvent(startTime: start, endTime: end, interfaceType: "wifi")
    #expect(abs(event.duration - 60.0) < 1.0)
}

@Test func disconnectEvent_formattedDuration_seconds() async throws {
    let start = Date()
    let end = start.addingTimeInterval(45)
    let event = DisconnectEvent(startTime: start, endTime: end, interfaceType: "wifi")
    #expect(event.formattedDuration.contains("45"))
}

@Test func disconnectEvent_formattedDuration_minutes() async throws {
    let start = Date()
    let end = start.addingTimeInterval(130)
    let event = DisconnectEvent(startTime: start, endTime: end, interfaceType: "wifi")
    #expect(event.formattedDuration.contains("2"))
}

@Test func tracker_todayEvents_filtersCorrectly() async throws {
    let tracker = await DisconnectTracker()
    let today = Date()
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

    let todayEvent = DisconnectEvent(startTime: today.addingTimeInterval(-60), endTime: today, interfaceType: "wifi")
    let yesterdayEvent = DisconnectEvent(startTime: yesterday.addingTimeInterval(-60), endTime: yesterday, interfaceType: "wifi")

    await tracker.addEventForTesting(todayEvent)
    await tracker.addEventForTesting(yesterdayEvent)

    let todayEvents = await tracker.todayEvents
    #expect(todayEvents.count == 1)
}

@Test func tracker_totalDowntimeToday_calculatesCorrectly() async throws {
    let tracker = await DisconnectTracker()
    let now = Date()

    let event1 = DisconnectEvent(startTime: now.addingTimeInterval(-120), endTime: now.addingTimeInterval(-60), interfaceType: "wifi")
    let event2 = DisconnectEvent(startTime: now.addingTimeInterval(-30), endTime: now, interfaceType: "wifi")

    await tracker.addEventForTesting(event1)
    await tracker.addEventForTesting(event2)

    let downtime = await tracker.totalDowntimeToday
    #expect(abs(downtime - 90.0) < 1.0)
}
