import Testing
import AppKit
import Foundation
@testable import BandwidthECGFeature

/// Stage 10 fix round 1: `showPopover()` activates the app so Esc works, so closing the popover
/// has to give the focus back, or the user's next ⌘Q quits this app.
@Suite("Popover focus hand-back")
struct PopoverFocusTests {

    private func handBack(
        _ policy: NSApplication.ActivationPolicy = .accessory,
        active: Bool = true,
        pinnedPanel: Bool = false,
        otherWindow: Bool = false
    ) -> Bool {
        PopoverFocusPolicy.shouldHandBackFocus(
            activationPolicy: policy,
            isAppActive: active,
            isPinnedPanelVisible: pinnedPanel,
            hasOtherWindow: otherWindow
        )
    }

    @Test func menuBarOnlyAppWithNothingOpen_givesFocusBack() {
        #expect(handBack())
    }

    @Test func dockMode_keepsFocus() {
        #expect(!handBack(.regular))
    }

    @Test func prohibitedPolicy_keepsFocus() {
        #expect(!handBack(.prohibited))
    }

    @Test func pinnedPanelOnScreen_keepsFocus() {
        #expect(!handBack(pinnedPanel: true))
    }

    @Test func anotherWindowOfOurs_keepsFocus() {
        // Save panel, alert, onboarding, an open context menu.
        #expect(!handBack(otherWindow: true))
    }

    @Test func appNoLongerActive_hasNothingToGiveBack() {
        // The user clicked into another app; that app has the focus already.
        #expect(!handBack(active: false))
    }

    @Test func fullTruthTable_onlyOneRowIsTrue() {
        let policies: [NSApplication.ActivationPolicy] = [.regular, .accessory, .prohibited]
        var trueRows: [String] = []
        for policy in policies {
            for active in [false, true] {
                for pinned in [false, true] {
                    for other in [false, true] {
                        if handBack(policy, active: active, pinnedPanel: pinned, otherWindow: other) {
                            trueRows.append("\(policy.rawValue)/\(active)/\(pinned)/\(other)")
                        }
                    }
                }
            }
        }
        #expect(trueRows == ["\(NSApplication.ActivationPolicy.accessory.rawValue)/true/false/false"])
    }
}

/// Final review F4: the same hand-back after the export save panel, the export alert and the
/// onboarding window close. These decide whether a window of ours is still on screen.
@Suite("Focus hand-back after our windows close")
struct WindowFocusTests {
    private typealias Window = PopoverFocusPolicy.WindowState

    private func handBack(
        _ windows: [Window],
        policy: NSApplication.ActivationPolicy = .accessory,
        pinnedPanel: Bool = false,
        contextMenu: Bool = false
    ) -> Bool {
        PopoverFocusPolicy.shouldHandBackFocus(
            activationPolicy: policy,
            isAppActive: true,
            isPinnedPanelVisible: pinnedPanel,
            hasOtherWindow: PopoverFocusPolicy.hasOtherWindow(windows, isShowingContextMenu: contextMenu)
        )
    }

    private let closedAlert = Window(isVisible: false, isTitled: true, isClosing: false)
    private let openSavePanel = Window(isVisible: true, isTitled: true, isClosing: false)
    private let closingOnboarding = Window(isVisible: true, isTitled: true, isClosing: true)
    private let statusItemWindow = Window(isVisible: true, isTitled: false, isClosing: false)

    @Test func alertJustClosed_givesFocusBack() {
        #expect(handBack([closedAlert, statusItemWindow]))
    }

    @Test func savePanelCancelled_givesFocusBack() {
        let closedPanel = Window(isVisible: false, isTitled: true, isClosing: false)
        #expect(handBack([closedPanel, statusItemWindow]))
    }

    @Test func onboardingClosing_givesFocusBack() {
        // `windowWillClose` runs while the window is still on screen.
        #expect(handBack([closingOnboarding, statusItemWindow]))
    }

    @Test func anotherOfOurWindowsStillOpen_keepsFocus() {
        #expect(!handBack([closedAlert, openSavePanel]))
        #expect(!handBack([closingOnboarding, openSavePanel]))
    }

    @Test func dockMode_keepsFocus() {
        #expect(!handBack([closedAlert], policy: .regular))
    }

    @Test func pinnedPanelOnScreen_keepsFocus() {
        #expect(!handBack([closedAlert], pinnedPanel: true))
    }

    @Test func contextMenuOpen_keepsFocus() {
        #expect(!handBack([closedAlert], contextMenu: true))
    }
}

/// PERF-16.1 and the "Increase contrast" notification: what makes the title be written again.
@Suite("Menu bar title gate")
struct MenuBarTitleGateTests {

    private let idle = MenuBarTitle.make(base: "↓ 0.0 ↑ 0.0 Mbps", level: .normal)
    private let busy = MenuBarTitle.make(base: "↓ 9.0 ↑ 0.0 Mbps", level: .normal)
    private let warning = MenuBarTitle.make(base: "↓ 290.0 ↑ 0.0 Mbps", level: .warning)

    @Test func firstTitle_isApplied() {
        var gate = MenuBarTitleGate()

        let applied = gate.shouldApply(title: idle, useColor: true)

        #expect(applied)
    }

    @Test func sameTitle_isNotWrittenAgain() {
        var gate = MenuBarTitleGate()
        _ = gate.shouldApply(title: idle, useColor: true)

        let second = gate.shouldApply(title: idle, useColor: true)
        let third = gate.shouldApply(title: idle, useColor: true)

        #expect(!second)
        #expect(!third)
    }

    @Test func newText_isApplied() {
        var gate = MenuBarTitleGate()
        _ = gate.shouldApply(title: idle, useColor: true)

        let changed = gate.shouldApply(title: busy, useColor: true)
        let again = gate.shouldApply(title: busy, useColor: true)

        #expect(changed)
        #expect(!again)
    }

    @Test func sameTextNewLevel_isApplied() {
        var gate = MenuBarTitleGate()
        let plain = MenuBarTitle.make(base: "↓ 290.0 ↑ 0.0 Mbps", level: .normal)
        _ = gate.shouldApply(title: plain, useColor: true)

        let raised = gate.shouldApply(
            title: MenuBarTitle(text: plain.text, level: .warning, accessibilityValue: nil),
            useColor: true
        )

        #expect(raised)
    }

    @Test func increaseContrastSwitched_reappliesTheSameTitle() {
        var gate = MenuBarTitleGate()
        _ = gate.shouldApply(title: warning, useColor: true)

        // The setting changed, the title did not: it still has to be drawn again, without colour.
        let withoutColor = gate.shouldApply(title: warning, useColor: false)
        let unchanged = gate.shouldApply(title: warning, useColor: false)
        // And back.
        let withColor = gate.shouldApply(title: warning, useColor: true)

        #expect(withoutColor)
        #expect(!unchanged)
        #expect(withColor)
    }
}
