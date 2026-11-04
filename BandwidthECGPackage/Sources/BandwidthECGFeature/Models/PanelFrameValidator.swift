import CoreGraphics

/// Decides whether a saved window frame can still be reached on the displays that are connected
/// now. A display that was unplugged leaves a saved frame pointing at nothing (UI-P3-10).
enum PanelFrameValidator {
    /// The least width and height, in points, that must be on a screen for a frame to count as
    /// reachable: enough to see it and grab its title bar.
    static let minimumVisibleLength: CGFloat = 100

    /// `true` if at least `minimumVisibleLength` x `minimumVisibleLength` points of `frame` lie
    /// on one of `screens` (their usable areas, in the same coordinate space as `frame`).
    static func isVisible(_ frame: CGRect, screens: [CGRect]) -> Bool {
        guard frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite else { return false }
        return screens.contains { screen in
            let overlap = screen.intersection(frame)
            guard !overlap.isNull else { return false }
            return overlap.width >= minimumVisibleLength && overlap.height >= minimumVisibleLength
        }
    }
}
