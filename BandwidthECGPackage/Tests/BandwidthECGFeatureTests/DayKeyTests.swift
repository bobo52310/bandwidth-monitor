import Testing
import Foundation
@testable import BandwidthECGFeature

@Suite("DayKey Tests")
struct DayKeyTests {

    /// Builds an instant from wall-clock components in the given time zone.
    private func instant(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int, _ minute: Int,
        in timeZone: TimeZone
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )
        return calendar.date(from: components)!
    }

    private func calendar(
        _ identifier: Calendar.Identifier = .gregorian,
        timeZone: TimeZone
    ) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = timeZone
        return calendar
    }

    private let taipei = TimeZone(identifier: "Asia/Taipei")!
    private let newYork = TimeZone(identifier: "America/New_York")!

    @Test func dayAndMonth_inTaipei() {
        let date = instant(2026, 10, 31, 23, 59, in: taipei)
        let cal = calendar(timeZone: taipei)
        #expect(DayKey.day(for: date, calendar: cal) == "2026-10-31")
        #expect(DayKey.month(for: date, calendar: cal) == "2026-10")
    }

    @Test func monthBoundary() {
        let date = instant(2026, 11, 1, 0, 1, in: taipei)
        let cal = calendar(timeZone: taipei)
        #expect(DayKey.day(for: date, calendar: cal) == "2026-11-01")
        #expect(DayKey.month(for: date, calendar: cal) == "2026-11")
    }

    @Test func monthOfDay_takesTheYearMonthPrefix() {
        #expect(DayKey.month(ofDay: "2026-10-31") == "2026-10")
        #expect(DayKey.month(ofDay: "2026-01-01") == "2026-01")
    }

    /// A user whose system calendar is Minguo, Buddhist or Japanese must still get
    /// Gregorian keys, otherwise monthly reports would be filed under "0115-11".
    @Test(arguments: [
        Calendar.Identifier.republicOfChina,
        Calendar.Identifier.buddhist,
        Calendar.Identifier.japanese,
    ])
    func nonGregorianCalendar_stillGregorian(identifier: Calendar.Identifier) {
        let date = instant(2026, 10, 31, 23, 59, in: taipei)
        let cal = calendar(identifier, timeZone: taipei)
        #expect(DayKey.day(for: date, calendar: cal) == "2026-10-31")
        #expect(DayKey.month(for: date, calendar: cal) == "2026-10")
    }

    @Test func usesCalendarTimeZone() {
        // 2026-10-31 23:59 in Taipei is 2026-10-31 11:59 in New York.
        // 2026-11-01 02:30 in Taipei is still 2026-10-31 14:30 in New York.
        let date = instant(2026, 11, 1, 2, 30, in: taipei)
        let inTaipei = DayKey.day(for: date, calendar: calendar(timeZone: taipei))
        let inNewYork = DayKey.day(for: date, calendar: calendar(timeZone: newYork))
        #expect(inTaipei == "2026-11-01")
        #expect(inNewYork == "2026-10-31")
        #expect(inTaipei != inNewYork)
    }

    /// The two DST transition days in New York (2026-03-08 spring forward,
    /// 2026-11-01 fall back) still map early and late local times to one key.
    @Test(arguments: [(2026, 3, 8), (2026, 11, 1)])
    func dst_newYork(year: Int, month: Int, day: Int) {
        let cal = calendar(timeZone: newYork)
        let early = instant(year, month, day, 0, 30, in: newYork)
        let late = instant(year, month, day, 23, 30, in: newYork)
        let expected = String(format: "%04ld-%02ld-%02ld", year, month, day)
        #expect(DayKey.day(for: early, calendar: cal) == expected)
        #expect(DayKey.day(for: late, calendar: cal) == expected)
    }
}
