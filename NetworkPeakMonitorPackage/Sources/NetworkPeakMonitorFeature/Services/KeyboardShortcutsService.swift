import Foundation
import AppKit
import Carbon

/// Service to manage global keyboard shortcuts
@MainActor
public class KeyboardShortcutsService: ObservableObject {
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "keyboardShortcutsEnabled")
            if isEnabled {
                registerShortcuts()
            } else {
                unregisterShortcuts()
            }
        }
    }

    // Registered event handlers (use array instead of dict to avoid Hashable requirement)
    private var eventHandlers: [EventHotKeyRef] = []

    // Callbacks for different shortcuts
    public var onTogglePopover: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onResetPeaks: (() -> Void)?
    public var onExportData: (() -> Void)?
    public var onOptimizeMemory: (() -> Void)?

    // Shortcut definitions
    public enum Shortcut: UInt32 {
        case togglePopover = 1  // Cmd+Shift+N
        case openSettings = 2   // Cmd+Shift+,
        case resetPeaks = 3     // Cmd+Shift+R
        case exportData = 4     // Cmd+Shift+E
        case optimizeMemory = 5 // Cmd+Shift+M

        var keyCode: UInt32 {
            switch self {
            case .togglePopover: return UInt32(kVK_ANSI_N)
            case .openSettings: return UInt32(kVK_ANSI_Comma)
            case .resetPeaks: return UInt32(kVK_ANSI_R)
            case .exportData: return UInt32(kVK_ANSI_E)
            case .optimizeMemory: return UInt32(kVK_ANSI_M)
            }
        }

        var modifiers: UInt32 {
            return UInt32(cmdKey | shiftKey)
        }

        var displayName: String {
            switch self {
            case .togglePopover: return "切換視窗"
            case .openSettings: return "開啟設定"
            case .resetPeaks: return "重置峰值"
            case .exportData: return "導出數據"
            case .optimizeMemory: return "優化記憶體"
            }
        }

        var displayShortcut: String {
            switch self {
            case .togglePopover: return "⌘⇧N"
            case .openSettings: return "⌘⇧,"
            case .resetPeaks: return "⌘⇧R"
            case .exportData: return "⌘⇧E"
            case .optimizeMemory: return "⌘⇧M"
            }
        }
    }

    public init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "keyboardShortcutsEnabled") as? Bool ?? true

        if isEnabled {
            Task {
                await MainActor.run {
                    registerShortcuts()
                }
            }
        }
    }

    /// Register all keyboard shortcuts
    private func registerShortcuts() {
        // Register each shortcut
        registerShortcut(.togglePopover)
        registerShortcut(.openSettings)
        registerShortcut(.resetPeaks)
        registerShortcut(.exportData)
        registerShortcut(.optimizeMemory)
    }

    /// Register a single keyboard shortcut
    private func registerShortcut(_ shortcut: Shortcut) {
        var eventHotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(UTGetOSTypeFromString("NWPK" as CFString)), id: shortcut.rawValue)

        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &eventHotKey
        )

        if status == noErr, let eventHotKey = eventHotKey {
            eventHandlers.append(eventHotKey)

            // Install event handler for this shortcut
            installEventHandler(for: shortcut)
        } else {
            print("Failed to register shortcut: \(shortcut.displayName)")
        }
    }

    /// Install event handler for a specific shortcut
    private func installEventHandler(for shortcut: Shortcut) {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isEnabled else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCommandShift = flags == [.command, .shift]

            guard isCommandShift else { return event }

            // Check if this matches our shortcut
            if event.keyCode == UInt16(shortcut.keyCode) {
                self.handleShortcut(shortcut)
                return nil // Consume the event
            }

            return event
        }
    }

    /// Handle shortcut activation
    private func handleShortcut(_ shortcut: Shortcut) {
        switch shortcut {
        case .togglePopover:
            onTogglePopover?()
        case .openSettings:
            onOpenSettings?()
        case .resetPeaks:
            onResetPeaks?()
        case .exportData:
            onExportData?()
        case .optimizeMemory:
            onOptimizeMemory?()
        }
    }

    /// Unregister all keyboard shortcuts
    private func unregisterShortcuts() {
        for eventHotKey in eventHandlers {
            UnregisterEventHotKey(eventHotKey)
        }
        eventHandlers.removeAll()
    }

    deinit {
        // Note: Cannot call async methods in deinit
        // Event handlers will be cleaned up when the object is deallocated
    }

    /// Get all available shortcuts for display
    public static func getAllShortcuts() -> [(name: String, shortcut: String)] {
        return [
            (Shortcut.togglePopover.displayName, Shortcut.togglePopover.displayShortcut),
            (Shortcut.openSettings.displayName, Shortcut.openSettings.displayShortcut),
            (Shortcut.resetPeaks.displayName, Shortcut.resetPeaks.displayShortcut),
            (Shortcut.exportData.displayName, Shortcut.exportData.displayShortcut),
            (Shortcut.optimizeMemory.displayName, Shortcut.optimizeMemory.displayShortcut)
        ]
    }
}
