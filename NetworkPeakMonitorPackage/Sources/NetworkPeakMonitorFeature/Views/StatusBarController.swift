import SwiftUI
import AppKit
import Combine

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