import Testing
import AppKit
import SwiftUI
import Foundation
@testable import BandwidthECGFeature

/// The approach counter's label and help text (UI-P2-13, Stage 10.3).
@Suite("Approach text")
struct ApproachTextTests {

    @Test func label_namesBothDirections() {
        let text = L10n.approachingSpeedLimit(300, 100)

        #expect(text.contains("↓300"))
        #expect(text.contains("↑100"))
        #expect(text.contains("Mbps"))
    }

    @Test func help_isBuiltFromItsInputs() {
        let text = L10n.approachingHelp(seconds: 45, percent: 70)

        #expect(text.contains("45"))
        #expect(text.contains("70"))
    }

    @Test func help_followsReportRules() {
        // The counter's rule is `ReportRules`; the help must say the same thing.
        let percent = Int((ReportRules.approachRatio * 100).rounded())
        let seconds = Int(ReportRules.approachSustainSeconds)

        #expect(L10n.approachingHelpCurrent == L10n.approachingHelp(seconds: seconds, percent: percent))
        #expect(L10n.approachingHelpCurrent.contains("80"))
        #expect(L10n.approachingHelpCurrent.contains("30"))
    }
}

/// UI-P3-8: warning text on its pale orange tint must reach WCAG AA (4.5:1) in light mode.
@Suite("Warning colour contrast")
@MainActor
struct WarningContrastTests {

    private func resolve(_ color: NSColor, in name: NSAppearance.Name) -> (r: Double, g: Double, b: Double) {
        var result: (Double, Double, Double) = (0, 0, 0)
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let rgb = color.usingColorSpace(.sRGB)!
            result = (Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
        }
        return result
    }

    private func luminance(_ c: (r: Double, g: Double, b: Double)) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    private func contrast(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double)) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// `color` at `alpha` over `base`, as a view with `.opacity(alpha)` is composited.
    private func blend(
        _ color: (r: Double, g: Double, b: Double),
        alpha: Double,
        over base: (r: Double, g: Double, b: Double)
    ) -> (r: Double, g: Double, b: Double) {
        (
            color.r * alpha + base.r * (1 - alpha),
            color.g * alpha + base.g * (1 - alpha),
            color.b * alpha + base.b * (1 - alpha)
        )
    }

    @Test func light_isReadableOnThePaleOrangeTint() {
        let text = resolve(Color.Adaptive.warningNSColor, in: .aqua)
        let window = resolve(.windowBackgroundColor, in: .aqua)
        let orange = resolve(.systemOrange, in: .aqua)
        let tint = blend(orange, alpha: 0.15, over: window)

        #expect(contrast(text, tint) >= 4.5)
        #expect(contrast(text, window) >= 4.5)
    }

    @Test func light_isTheDeepOrange() {
        let text = resolve(Color.Adaptive.warningNSColor, in: .aqua)

        // #9A3412
        #expect(abs(text.r - 154.0 / 255) < 0.01)
        #expect(abs(text.g - 52.0 / 255) < 0.01)
        #expect(abs(text.b - 18.0 / 255) < 0.01)
    }

    @Test func dark_staysOrange() {
        let text = resolve(Color.Adaptive.warningNSColor, in: .darkAqua)
        let orange = resolve(.systemOrange, in: .darkAqua)

        #expect(abs(text.r - orange.r) < 0.01)
        #expect(abs(text.g - orange.g) < 0.01)
        #expect(abs(text.b - orange.b) < 0.01)
    }

    @Test func dark_isReadableOnTheDarkWindow() {
        let text = resolve(Color.Adaptive.warningNSColor, in: .darkAqua)
        let window = resolve(.windowBackgroundColor, in: .darkAqua)

        #expect(contrast(text, window) >= 4.5)
    }
}
