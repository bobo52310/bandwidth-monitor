import SwiftUI
import AppKit
import Observation

@MainActor
public class StatusBarController: NSObject, NSPopoverDelegate, NSWindowDelegate {
    private var statusBarItem: NSStatusItem?
    private var popover: NSPopover?
    private var floatingPanel: NSPanel?
    private var panelHostingController: NSHostingController<PopoverView>?
    private let viewModel = NetworkMonitorViewModel()
    private var eventMonitor: Any?
    private var onboardingWindow: NSWindow?
    /// What the menu bar button shows now. A new title equal to this is not set again, so an idle
    /// connection does no work in the status item (PERF-16.1).
    private var titleGate = MenuBarTitleGate()
    /// True while the right-click menu is open. The popover is closed first, and its close
    /// notification can arrive with the menu up.
    private var isShowingContextMenu = false

    public override init() {
        super.init()
        setupStatusBar()
        setupPopover()
        setupPinStateObserver()
        // The save panel and the export alert make the app active. Once they are gone, the
        // focus goes back as it does when the popover closes (final review F4).
        viewModel.onExportFinished = { [weak self] in
            self?.handBackFocusAfterWindowCloses()
        }
        viewModel.initialize()
        checkAndShowOnboarding()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        // "Increase contrast" turns the title colour off. Changing it in System Settings should
        // show at once, not at the next change of the title.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        restorePinnedPanel()
    }

    /// Applies the "show in Dock" setting. Called once at launch; changing the setting later
    /// applies it right away. The Info.plist starts the app without a Dock icon, so a user who
    /// never turned it on sees none at any point.
    public func applyActivationPolicy() {
        UserPreferences.applyActivationPolicy(showInDock: viewModel.preferences.showInDock)
    }

    /// A pinned panel comes back after a relaunch (UI-P3-9). Deferred a turn so the status item
    /// has a window to position the panel against when there is no saved position.
    private func restorePinnedPanel() {
        guard viewModel.preferences.isPinned else { return }
        Task { @MainActor [weak self] in
            guard let self, self.viewModel.preferences.isPinned else { return }
            self.showFloatingPanel()
        }
    }

    /// Ends an open outage (sleep is not downtime) and writes pending data.
    @objc private func systemWillSleep() {
        viewModel.handleSleep()
    }

    @objc private func systemDidWake() {
        viewModel.handleWake()
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        updateStatusBarTitle()
    }

    private func checkAndShowOnboarding() {
        let hasCompletedOnboarding = viewModel.defaults.bool(forKey: "hasCompletedOnboarding")
        if !hasCompletedOnboarding {
            showOnboarding()
        }
    }

    private func showOnboarding() {
        let onboardingView = OnboardingView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: onboardingView)

        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = L10n.onboardingWindowTitle
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        // Closing the window with its close button counts as done: it must not come back at
        // every launch (UI-P3-14).
        window.delegate = self
        // An accessory app starts in the background, so the window would open inactive (grey
        // title bar) and the first click would only activate the app (UI-P3-2). Plain
        // `activate()` is cooperative on macOS 14 and later and was not honoured while another
        // app was in front (QA, macOS 26); `ignoringOtherApps: true` is, and this window is the
        // direct result of the user starting the app for the first time.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        onboardingWindow = window
    }

    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusBarItem?.button {
            button.action = #selector(statusItemClicked)
            button.target = self
            // The right button opens a small menu (UI-P3-12): the way to quit when the item is
            // the only part of the app a user can reach.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusBarTitle()

        // Update status bar text when speed changes using observation tracking loop
        observeSpeedChanges()
    }

    private func observeSpeedChanges() {
        withObservationTracking {
            // The title reads the speed, the display mode, the unit and the alert level, so a
            // change to any of them comes through here.
            _ = viewModel.menuBarTitle
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateStatusBarTitle()
                self?.observeSpeedChanges()
            }
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        // The size `PopoverView` lays itself out at.
        popover?.contentSize = NSSize(width: 580, height: 700)
        popover?.behavior = .transient
        popover?.animates = true
        popover?.delegate = self
        // The content is built on show and dropped on close (PERF-03).
    }

    private func setupPinStateObserver() {
        observePinState()
    }

    private func observePinState() {
        withObservationTracking {
            _ = viewModel.preferences.isPinned
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                if self.viewModel.preferences.isPinned {
                    self.showFloatingPanel()
                } else {
                    self.closeFloatingPanel()
                }
                self.observePinState()
            }
        }
    }

    /// The status item's action: a left click toggles the panel, a right click (or a control
    /// click) opens the menu.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        guard let statusItem = statusBarItem, let button = statusItem.button else { return }
        if popover?.isShown == true {
            closePopover()
        }

        let menu = NSMenu()
        let open = NSMenuItem(title: L10n.menuBarMenuOpen, action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L10n.menuBarMenuQuit, action: #selector(quitFromMenu), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        // With a menu on the item the click shows the menu instead of calling the action; the
        // menu is taken off again so a left click goes back to the popover.
        isShowingContextMenu = true
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
        isShowingContextMenu = false
    }

    @objc private func openFromMenu() {
        if viewModel.preferences.isPinned {
            showFloatingPanel()
        } else {
            showPopover()
        }
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    /// The app was opened again while it was running (from Finder, Spotlight or the Dock). When
    /// the menu bar is full the status item can be hidden, and this is then the only way to bring
    /// the panel back. It opens as the pinned panel, which does not depend on the status item.
    public func showPanelFromReopen() {
        viewModel.preferences.isPinned = true
        showFloatingPanel()
        // The user just started the app; it must come to the front even if it was hidden after
        // the popover closed (QA: otherwise the panel opened behind the frontmost app).
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func togglePopover() {
        // If pinned, toggle the floating panel instead
        if viewModel.preferences.isPinned {
            if floatingPanel?.isVisible == true {
                closeFloatingPanel()
            } else {
                showFloatingPanel()
            }
            return
        }

        // Normal popover behavior
        guard let popover = popover else { return }

        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showFloatingPanel() {
        if NSApp.isHidden { NSApp.unhide(nil) }
        // Close popover if it's showing
        if popover?.isShown == true {
            closePopover()
        }

        // If panel already exists and is visible, just bring to front
        if let panel = floatingPanel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        // Create panel if it doesn't exist
        if floatingPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 700),
                styleMask: [.titled, .closable, .resizable, .utilityWindow],
                backing: .buffered,
                defer: false
            )

            panel.title = "Bandwidth ECG"
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false

            // Create hosting controller with same view model
            let hostingController = NSHostingController(rootView: PopoverView(viewModel: viewModel))
            panel.contentViewController = hostingController

            // Handle panel close button
            panel.delegate = self

            floatingPanel = panel
            panelHostingController = hostingController
        }

        // Restore saved position or position near status bar item
        if let savedFrame = getSavedPanelFrame() {
            floatingPanel?.setFrame(savedFrame, display: false)
        } else if let button = statusBarItem?.button, let screen = button.window?.screen {
            let buttonFrame = button.window?.convertToScreen(button.frame) ?? .zero
            let panelSize = floatingPanel!.frame.size
            let panelOrigin = NSPoint(
                x: buttonFrame.midX - panelSize.width / 2,
                y: buttonFrame.minY - panelSize.height - 8
            )

            // Keep panel on screen
            var adjustedOrigin = panelOrigin
            let screenFrame = screen.visibleFrame
            if adjustedOrigin.x < screenFrame.minX {
                adjustedOrigin.x = screenFrame.minX + 20
            }
            if adjustedOrigin.x + panelSize.width > screenFrame.maxX {
                adjustedOrigin.x = screenFrame.maxX - panelSize.width - 20
            }
            if adjustedOrigin.y < screenFrame.minY {
                adjustedOrigin.y = screenFrame.minY + 20
            }

            floatingPanel?.setFrame(NSRect(origin: adjustedOrigin, size: panelSize), display: false)
        }

        floatingPanel?.makeKeyAndOrderFront(nil)
    }

    /// The saved panel frame, if it can still be reached on the connected displays. A frame left
    /// on a display that was unplugged is ignored (UI-P3-10).
    private func getSavedPanelFrame() -> NSRect? {
        guard let dict = viewModel.defaults.dictionary(forKey: "floatingPanelFrame"),
              let x = dict["x"] as? CGFloat,
              let y = dict["y"] as? CGFloat,
              let width = dict["width"] as? CGFloat,
              let height = dict["height"] as? CGFloat else {
            return nil
        }
        let frame = NSRect(x: x, y: y, width: width, height: height)
        let screens = NSScreen.screens.map(\.visibleFrame)
        return PanelFrameValidator.isVisible(frame, screens: screens) ? frame : nil
    }

    private func savePanelFrame(_ frame: NSRect) {
        let dict: [String: CGFloat] = [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "width": frame.size.width,
            "height": frame.size.height
        ]
        viewModel.defaults.set(dict, forKey: "floatingPanelFrame")
    }

    private func closeFloatingPanel() {
        floatingPanel?.orderOut(nil)
        floatingPanel?.close()
        floatingPanel = nil
        panelHostingController = nil
    }

    private func showPopover() {
        guard let popover = popover, let button = statusBarItem?.button else { return }
        // Handing the focus back hides the app (`handBackFocusIfIdle`); a hidden app does not show
        // its windows.
        if NSApp.isHidden { NSApp.unhide(nil) }

        if popover.contentViewController == nil {
            popover.contentViewController = NSHostingController(rootView: PopoverView(viewModel: viewModel))
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // An accessory app is not active when its popover opens. Active, the popover window is
        // key, so Esc reaches it and closes it; no global key monitor is needed (PERF-16.8).
        // Plain `activate()` is cooperative on macOS 14 and later: with another app in front it
        // was not honoured (QA, macOS 26: the other app stayed in front, the popover was not key,
        // and Esc did nothing). Opening the popover is the user's own click on our item, so the
        // forceful form is right here, as it is for the onboarding window.
        NSApp.activate(ignoringOtherApps: true)
        setupEventMonitor()
    }

    private func closePopover() {
        popover?.performClose(nil)
        removeEventMonitor()
    }

    /// Closes the popover on a click anywhere else. Mouse events only: a key monitor would be
    /// handed every key press in every app, would need the Input Monitoring permission, and
    /// closed the popover when someone typed elsewhere while the pointer was outside it.
    private func setupEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let popover = self?.popover, popover.isShown,
                  let popoverWindow = popover.contentViewController?.view.window else { return }
            if !popoverWindow.frame.contains(NSEvent.mouseLocation) {
                self?.closePopover()
            }
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func updateStatusBarTitle() {
        let title = viewModel.menuBarTitle
        // "Increase contrast" turns the colour off; the prefix stays.
        let useColor = !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        guard titleGate.shouldApply(title: title, useColor: useColor) else { return }
        guard let button = statusBarItem?.button else { return }

        // Digits of equal width, so the item does not change width with every new number.
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        ]
        if useColor, let color = Self.color(for: title.level) {
            attributes[.foregroundColor] = color
        }
        button.attributedTitle = NSAttributedString(string: title.text, attributes: attributes)
        button.setAccessibilityValue(title.accessibilityValue)
    }

    /// Orange from the notification threshold, red from the plan. `nil` keeps the system's own
    /// menu bar text colour.
    private static func color(for level: MenuBarAlertLevel) -> NSColor? {
        switch level {
        case .normal: return nil
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    public func cleanUp() {
        removeEventMonitor()
        viewModel.prepareForQuit()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        statusBarItem = nil
    }

    // MARK: - NSPopoverDelegate

    public func popoverShouldClose(_ popover: NSPopover) -> Bool {
        return true
    }

    public func popoverDidClose(_ notification: Notification) {
        removeEventMonitor()
        // Skipped if the popover was shown again before this notification arrived.
        guard popover?.isShown != true else { return }
        let popoverWindow = popover?.contentViewController?.view.window
        // A hidden hosting controller keeps laying out and rendering the chart every second
        // (PERF-03). Dropping it releases the view graph; `showPopover()` builds a new one.
        popover?.contentViewController = nil
        handBackFocusIfIdle(ignoring: popoverWindow)
    }

    /// `showPopover()` made the app active so that Esc works. Left active, the app would stay in
    /// front after the popover is gone, and the next ⌘Q meant for the user's own app would quit
    /// this one. So when nothing of ours is left on screen, give the focus back.
    ///
    /// `closingWindow` is a window that is going away but may still report itself visible: the
    /// popover's, or onboarding's in `windowWillClose`.
    private func handBackFocusIfIdle(ignoring closingWindow: NSWindow?) {
        let windows = NSApp.windows.map {
            PopoverFocusPolicy.WindowState(
                isVisible: $0.isVisible,
                isTitled: $0.styleMask.contains(.titled),
                isClosing: $0 === closingWindow
            )
        }
        let hasOtherWindow = PopoverFocusPolicy.hasOtherWindow(windows, isShowingContextMenu: isShowingContextMenu)
        guard PopoverFocusPolicy.shouldHandBackFocus(
            activationPolicy: NSApp.activationPolicy(),
            isAppActive: NSApp.isActive,
            isPinnedPanelVisible: floatingPanel?.isVisible == true,
            hasOtherWindow: hasOtherWindow
        ) else { return }
        // `NSApp.deactivate()` was tried first and left this app in front (QA, macOS 26). Hiding
        // an app makes the system bring up the one the user was in; `showPopover()` and
        // `showFloatingPanel()` unhide it again.
        NSApp.hide(nil)
    }

    /// After the export save panel or the export alert has closed. Checked on the next turn of
    /// the run loop, so the panel or alert has left the screen by then.
    private func handBackFocusAfterWindowCloses() {
        DispatchQueue.main.async { [weak self] in
            self?.handBackFocusIfIdle(ignoring: nil)
        }
    }

    public func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        return false // Prevent detaching the popover
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === onboardingWindow {
            viewModel.defaults.set(true, forKey: "hasCompletedOnboarding")
            onboardingWindow = nil
            // Onboarding made the app active. With nothing else of ours on screen, the focus
            // goes back to the app the user was in (final review F4).
            handBackFocusIfIdle(ignoring: window)
            return
        }
        // When user closes the panel via close button, unpin it
        if let window = notification.object as? NSWindow, window === floatingPanel {
            // Save position before closing
            savePanelFrame(window.frame)
            viewModel.preferences.isPinned = false
        }
    }

    public func windowDidMove(_ notification: Notification) {
        // Save position when panel is moved
        if let window = notification.object as? NSWindow, window === floatingPanel {
            savePanelFrame(window.frame)
        }
    }

    public func windowDidResize(_ notification: Notification) {
        // Save size when panel is resized
        if let window = notification.object as? NSWindow, window === floatingPanel {
            savePanelFrame(window.frame)
        }
    }
}

/// Whether the app should give the focus back when its popover, the export save panel or alert,
/// or the onboarding window closes.
///
/// Only an app that has no Dock icon (`.accessory`) does: its popover is a transient thing, like
/// a menu, and the user was in another app a moment ago. An app that shows in the Dock is a
/// normal app that may stay in front. Nothing is handed back while the app is not the active one
/// (the user clicked into another app and that app already has the focus), while the pinned
/// panel is on screen, or while another window of ours is open (save panel, alert, onboarding).
enum PopoverFocusPolicy {
    static func shouldHandBackFocus(
        activationPolicy: NSApplication.ActivationPolicy,
        isAppActive: Bool,
        isPinnedPanelVisible: Bool,
        hasOtherWindow: Bool
    ) -> Bool {
        activationPolicy == .accessory && isAppActive && !isPinnedPanelVisible && !hasOtherWindow
    }

    /// What the decision needs to know about one of the app's windows.
    struct WindowState: Equatable {
        var isVisible: Bool
        /// An ordinary window is a titled one: a save panel, an alert, onboarding, the pinned
        /// panel. The popover, the status item and menus are not.
        var isTitled: Bool
        /// Going away now, though it may still report itself visible (the popover's window, or
        /// onboarding's in `windowWillClose`).
        var isClosing: Bool
    }

    /// Whether something of ours is still on screen: an ordinary window that is not the one
    /// closing, or the status item's menu.
    static func hasOtherWindow(_ windows: [WindowState], isShowingContextMenu: Bool) -> Bool {
        isShowingContextMenu || windows.contains { $0.isVisible && $0.isTitled && !$0.isClosing }
    }
}
