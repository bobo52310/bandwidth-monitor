import Foundation

/// How close the current speed is to the plan, for the menu bar (D18).
public enum MenuBarAlertLevel: Int, Sendable, Comparable {
    case normal
    /// At or above the notification threshold the user chose.
    case warning
    /// At or above the plan itself.
    case critical

    public static func < (lhs: MenuBarAlertLevel, rhs: MenuBarAlertLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The higher of the two directions, each measured against its own plan. A direction whose
    /// plan is zero, negative or not finite is skipped, and a speed that is not finite counts as
    /// no traffic: neither can raise an alert.
    public static func evaluate(
        downloadMbps: Double,
        uploadMbps: Double,
        planDownloadMbps: Double,
        planUploadMbps: Double,
        warningRatio: Double
    ) -> MenuBarAlertLevel {
        max(
            level(speed: downloadMbps, plan: planDownloadMbps, warningRatio: warningRatio),
            level(speed: uploadMbps, plan: planUploadMbps, warningRatio: warningRatio)
        )
    }

    private static func level(speed: Double, plan: Double, warningRatio: Double) -> MenuBarAlertLevel {
        guard plan.isFinite, plan > 0, speed.isFinite else { return .normal }
        // Division, not `plan * warningRatio`: 285 / 300 is exactly 0.95 where 300 * 0.95 is not.
        let ratio = speed / plan
        if ratio >= 1.0 { return .critical }
        if ratio >= warningRatio { return .warning }
        return .normal
    }
}

/// Holds the highest level seen in the last 3 seconds, so a speed that hovers around the
/// threshold does not make the title flicker once a second. A rise shows at once; only the
/// way back down waits.
struct MenuBarAlertTracker {
    /// How long a level stays after the sample that raised it.
    static let holdSeconds: TimeInterval = 3

    private var recent: [(time: TimeInterval, level: MenuBarAlertLevel)] = []

    /// Feeds one sample and returns the level to show. `monotonic` is a clock that keeps
    /// counting through sleep, so a long gap simply lets the hold run out.
    mutating func update(_ level: MenuBarAlertLevel, at monotonic: TimeInterval) -> MenuBarAlertLevel {
        // A clock that moved backwards cannot say how old the old samples are.
        if let last = recent.last, monotonic < last.time {
            recent.removeAll()
        }
        recent.removeAll { monotonic - $0.time >= Self.holdSeconds }
        recent.append((time: monotonic, level: level))
        return recent.map(\.level).max() ?? level
    }
}

/// What the menu bar item shows: the speed text, with a text cue when it is close to the plan.
struct MenuBarTitle: Equatable {
    /// The speed text, with a prefix when `level` is not normal. The prefix is the cue that
    /// does not depend on seeing the colour.
    let text: String
    let level: MenuBarAlertLevel
    /// What VoiceOver adds to the button, or `nil` when there is nothing to add.
    let accessibilityValue: String?

    static func make(base: String, level: MenuBarAlertLevel) -> MenuBarTitle {
        switch level {
        case .normal:
            return MenuBarTitle(text: base, level: level, accessibilityValue: nil)
        case .warning:
            return MenuBarTitle(text: "▲ " + base, level: level, accessibilityValue: L10n.menuBarAlertWarning)
        case .critical:
            return MenuBarTitle(text: "▲▲ " + base, level: level, accessibilityValue: L10n.menuBarAlertCritical)
        }
    }
}

/// Decides whether the menu bar button needs to be written again. Writing a title that is
/// already there is not free (PERF-16.1), and a change of the colour setting alone, such as
/// "Increase contrast" being switched in System Settings, must still get through.
struct MenuBarTitleGate {
    private var shownTitle: MenuBarTitle?
    private var shownWithColor = false

    /// `true` when `title` or `useColor` differs from what was applied last; remembers them then.
    mutating func shouldApply(title: MenuBarTitle, useColor: Bool) -> Bool {
        guard title != shownTitle || useColor != shownWithColor else { return false }
        shownTitle = title
        shownWithColor = useColor
        return true
    }
}
