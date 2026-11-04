import Foundation

/// A repeating main-thread timer that keeps firing while a menu is open or a window is being
/// dragged. `Timer.scheduledTimer` only runs in the default run loop mode, which AppKit leaves
/// for the whole of that time.
public enum RepeatingTimer {
    @MainActor @discardableResult
    public static func schedule(
        interval: TimeInterval,
        tolerance: TimeInterval,
        _ block: @escaping @MainActor () -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { block() }
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
