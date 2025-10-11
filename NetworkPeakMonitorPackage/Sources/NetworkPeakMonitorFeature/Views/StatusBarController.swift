import SwiftUI
import AppKit
import Combine
import UserNotifications

@MainActor
public class StatusBarController: NSObject, ObservableObject, NSPopoverDelegate {
    private var statusBarItem: NSStatusItem?
    private var popover: NSPopover?
    private let viewModel = NetworkMonitorViewModel()
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?
    private var onboardingWindow: NSWindow?

    public override init() {
        super.init()
        setupStatusBar()
        setupPopover()
        setupKeyboardShortcuts()
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

    private func setupKeyboardShortcuts() {
        // Bind keyboard shortcut callbacks
        viewModel.keyboardShortcuts.onTogglePopover = { [weak self] in
            self?.togglePopover()
        }

        viewModel.keyboardShortcuts.onOpenSettings = { [weak self] in
            self?.openSettings()
        }

        viewModel.keyboardShortcuts.onResetPeaks = { [weak self] in
            self?.handleResetPeaks()
        }

        viewModel.keyboardShortcuts.onExportData = { [weak self] in
            self?.handleExportData()
        }

        viewModel.keyboardShortcuts.onOptimizeMemory = { [weak self] in
            self?.handleOptimizeMemory()
        }
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
        guard let popover = popover else { return }

        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
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
}