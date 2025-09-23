import SwiftUI
import AppKit
import Combine

@MainActor
public class StatusBarController: ObservableObject {
    private var statusBarItem: NSStatusItem?
    private var popover: NSPopover?
    private let viewModel = NetworkMonitorViewModel()
    private var cancellables = Set<AnyCancellable>()

    public init() {
        setupStatusBar()
        setupPopover()
        viewModel.initialize()
    }

    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusBarItem?.button {
            button.title = "↑ 0.0 ↓ 0.0 Mbps"
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
        popover?.contentSize = NSSize(width: 350, height: 500)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: PopoverView(viewModel: viewModel)
        )
    }

    @objc private func togglePopover() {
        guard let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            if let button = statusBarItem?.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    private func updateStatusBarTitle() {
        DispatchQueue.main.async {
            self.statusBarItem?.button?.title = self.viewModel.menuBarText
        }
    }

    public func cleanUp() {
        Task {
            await viewModel.stopMonitoring()
        }
        statusBarItem = nil
    }
}