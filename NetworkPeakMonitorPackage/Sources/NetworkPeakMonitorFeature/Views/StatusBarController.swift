import SwiftUI
import AppKit
import Combine
import UserNotifications

@MainActor
public class StatusBarController: NSObject, ObservableObject, NSPopoverDelegate, NSWindowDelegate {
    private var statusBarItem: NSStatusItem?
    private var popover: NSPopover?
    private var floatingPanel: NSPanel?
    private var panelHostingController: NSHostingController<PopoverView>?
    private let viewModel = NetworkMonitorViewModel()
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?
    private var onboardingWindow: NSWindow?

    public override init() {
        super.init()
        setupStatusBar()
        setupPopover()
        setupPinStateObserver()
        viewModel.initialize()
        checkAndShowOnboarding()
    }

    private func checkAndShowOnboarding() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if !hasCompletedOnboarding {
            showOnboarding()
        }
    }

    private func showOnboarding() {
        let onboardingView = OnboardingView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: onboardingView)

        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = "歡迎使用 Network Peak Monitor"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)

        onboardingWindow = window
    }

    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusBarItem?.button {
            button.title = "↓ 0.0 ↑ 0.0 Mbps"
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Update status bar text when speed changes
        viewModel.$currentSpeed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBarTitle()
            }
            .store(in: &cancellables)
    }

    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 350, height: 600)
        popover?.behavior = .transient
        popover?.animates = true
        popover?.delegate = self
        popover?.contentViewController = NSHostingController(
            rootView: PopoverView(viewModel: viewModel)
        )
    }

    private func setupPinStateObserver() {
        // Observe pin state changes
        viewModel.preferences.$isPinned
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPinned in
                guard let self = self else { return }
                if isPinned {
                    // Convert popover to floating panel
                    self.showFloatingPanel()
                } else {
                    // Convert floating panel back to popover
                    self.closeFloatingPanel()
                }
            }
            .store(in: &cancellables)
    }

    private func openSettings() {
        // Show popover first if not shown
        if let popover = popover, !popover.isShown {
            showPopover()
        }

        // Open settings view
        let settingsView = SettingsView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .resizable]
        window.title = "設定"
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func handleResetPeaks() {
        viewModel.resetPeaks()
        sendNotification(title: "峰值已重置", body: "所有峰值記錄已清除")
    }

    private func handleExportData() {
        viewModel.exportDataWithSavePanel(format: .fullHistory) { success in
            if success {
                Task { @MainActor in
                    self.sendNotification(title: "導出成功", body: "數據已成功導出")
                }
            }
        }
    }

    private func handleOptimizeMemory() {
        viewModel.optimizeMemory()
        sendNotification(title: "記憶體已優化", body: "過期數據已清除")
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
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

            panel.title = "Network Peak Monitor"
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

    private func getSavedPanelFrame() -> NSRect? {
        guard let dict = UserDefaults.standard.dictionary(forKey: "floatingPanelFrame"),
              let x = dict["x"] as? CGFloat,
              let y = dict["y"] as? CGFloat,
              let width = dict["width"] as? CGFloat,
              let height = dict["height"] as? CGFloat else {
            return nil
        }
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func savePanelFrame(_ frame: NSRect) {
        let dict: [String: CGFloat] = [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "width": frame.size.width,
            "height": frame.size.height
        ]
        UserDefaults.standard.set(dict, forKey: "floatingPanelFrame")
    }

    private func closeFloatingPanel() {
        floatingPanel?.orderOut(nil)
        floatingPanel?.close()
        floatingPanel = nil
        panelHostingController = nil
    }

    private func showPopover() {
        guard let popover = popover, let button = statusBarItem?.button else { return }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        setupEventMonitor()
    }

    private func closePopover() {
        popover?.performClose(nil)
        removeEventMonitor()
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            if let popover = self?.popover, popover.isShown {
                // Check if the click is outside the popover
                if let popoverWindow = popover.contentViewController?.view.window {
                    let clickLocation = event.locationInWindow
                    let windowFrame = popoverWindow.frame
                    let screenClickLocation = NSEvent.mouseLocation

                    if !windowFrame.contains(screenClickLocation) {
                        self?.closePopover()
                    }
                }

                // Close on Escape key
                if event.type == .keyDown && event.keyCode == 53 { // Escape key
                    self?.closePopover()
                }
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
        DispatchQueue.main.async {
            self.statusBarItem?.button?.title = self.viewModel.menuBarText
        }
    }

    public func cleanUp() {
        removeEventMonitor()
        Task {
            await viewModel.stopMonitoring()
        }
        statusBarItem = nil
    }

    // MARK: - NSPopoverDelegate

    public func popoverShouldClose(_ popover: NSPopover) -> Bool {
        return true
    }

    public func popoverDidClose(_ notification: Notification) {
        removeEventMonitor()
    }

    public func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        return false // Prevent detaching the popover
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
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