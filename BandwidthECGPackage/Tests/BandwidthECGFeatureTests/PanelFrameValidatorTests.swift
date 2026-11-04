import Testing
import CoreGraphics
@testable import BandwidthECGFeature

/// UI-P3-10: a saved floating panel position on a display that is gone must not be restored.
@Suite("PanelFrameValidator")
struct PanelFrameValidatorTests {
    private let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let external = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    @Test func onScreen_true() {
        let frame = CGRect(x: 200, y: 100, width: 580, height: 700)
        #expect(PanelFrameValidator.isVisible(frame, screens: [main]))
    }

    @Test func onSecondScreen_true() {
        let frame = CGRect(x: 1700, y: 100, width: 580, height: 700)
        #expect(PanelFrameValidator.isVisible(frame, screens: [main, external]))
    }

    /// The external display the panel was on is unplugged.
    @Test func disconnectedDisplay_false() {
        let frame = CGRect(x: 1700, y: 100, width: 580, height: 700)
        #expect(!PanelFrameValidator.isVisible(frame, screens: [main]))
    }

    @Test func partialOverlap_100pt_true() {
        // Exactly 100 x 100 points are still on the screen.
        let frame = CGRect(x: 1340, y: 800, width: 580, height: 700)
        #expect(PanelFrameValidator.isVisible(frame, screens: [main]))
    }

    @Test func partialOverlap_10pt_false() {
        let frame = CGRect(x: 1430, y: 100, width: 580, height: 700)
        #expect(!PanelFrameValidator.isVisible(frame, screens: [main]))
    }

    @Test func noScreens_false() {
        let frame = CGRect(x: 200, y: 100, width: 580, height: 700)
        #expect(!PanelFrameValidator.isVisible(frame, screens: []))
    }

    /// Wide enough but too thin, or tall enough but too narrow: both dimensions count.
    @Test func overlapNeedsBothDimensions() {
        let thin = CGRect(x: 200, y: 890, width: 580, height: 700)
        #expect(!PanelFrameValidator.isVisible(thin, screens: [main]))
        let narrow = CGRect(x: 1430, y: 0, width: 580, height: 700)
        #expect(!PanelFrameValidator.isVisible(narrow, screens: [main]))
    }

    /// A panel that straddles two displays counts as visible when either shows enough of it.
    @Test func straddlingTwoScreens_true() {
        let frame = CGRect(x: 1200, y: 100, width: 580, height: 700)
        #expect(PanelFrameValidator.isVisible(frame, screens: [main, external]))
    }

    @Test func nonFiniteFrame_false() {
        let frame = CGRect(x: CGFloat.nan, y: 0, width: 580, height: 700)
        #expect(!PanelFrameValidator.isVisible(frame, screens: [main]))
    }
}
