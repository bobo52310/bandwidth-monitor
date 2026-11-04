import Foundation

/// Calendar-day and month identifiers used as persistence keys.
///
/// Keys are always Gregorian ("2026-10-31", "2026-10") whatever calendar the user's
/// system uses, so a Minguo, Buddhist or Japanese calendar never produces "0115-11".
/// Only the calendar's time zone is honoured, because that decides where a day ends.
public enum DayKey {
    /// "2026-10-31"
    public static func day(for date: Date, calendar: Calendar) -> String {
        let parts = gregorianParts(of: date, in: calendar.timeZone)
        return String(format: "%04ld-%02ld-%02ld", parts.year, parts.month, parts.day)
    }

    /// "2026-10"
    public static func month(for date: Date, calendar: Calendar) -> String {
        let parts = gregorianParts(of: date, in: calendar.timeZone)
        return String(format: "%04ld-%02ld", parts.year, parts.month)
    }

    /// "2026-10" from "2026-10-31".
    public static func month(ofDay dayKey: String) -> String {
        String(dayKey.prefix(7))
    }

    private static func gregorianParts(
        of date: Date,
        in timeZone: TimeZone
    ) -> (year: Int, month: Int, day: Int) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        let components = gregorian.dateComponents([.year, .month, .day], from: date)
        return (components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
