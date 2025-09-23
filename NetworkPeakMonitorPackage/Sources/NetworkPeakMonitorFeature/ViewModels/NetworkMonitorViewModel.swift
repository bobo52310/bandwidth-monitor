import Foundation
import Combine

@MainActor
public class NetworkMonitorViewModel: ObservableObject {
    @Published public var currentSpeed = NetworkSpeed(uploadSpeed: 0, downloadSpeed: 0)
    @Published public var preferences = UserPreferences()
    @Published public var peakRecorder = PeakRecorder()

    private let networkMonitor = NetworkMonitor()
    private var cancellables = Set<AnyCancellable>()

    public init() {
        setupBindings()
    }

    public func initialize() {
        Task {
            await startMonitoring()
        }
    }

    private func setupBindings() {
        // Bind network monitor to current speed
        networkMonitor.$currentSpeed
            .sink { [weak self] speed in
                self?.currentSpeed = speed
                self?.peakRecorder.recordSpeed(speed)
            }
            .store(in: &cancellables)
    }

    public func startMonitoring() async {
        await networkMonitor.startMonitoring()
    }

    public func stopMonitoring() async {
        await networkMonitor.stopMonitoring()
    }

    public func resetPeaks() {
        peakRecorder.resetPeaks()
    }

    // Format speed for display
    public func formatSpeed(_ speed: Double, unit: UserPreferences.SpeedUnit) -> String {
        switch unit {
        case .mbps:
            return String(format: "%.1f", speed)
        case .mbps_lower:
            return String(format: "%.1f", speed / 8.0)
        }
    }

    // Get formatted current speeds for menu bar
    public var menuBarText: String {
        let uploadText = formatSpeed(currentSpeed.uploadMbps, unit: preferences.displayUnit)
        let downloadText = formatSpeed(currentSpeed.downloadMbps, unit: preferences.displayUnit)
        let unitText = preferences.displayUnit.displayName

        return "↑ \(uploadText) ↓ \(downloadText) \(unitText)"
    }

    // Check if peak is concerning (>90% of plan)
    public func isPeakConcerning(speed: Double, planSpeed: Double) -> Bool {
        return speed > (planSpeed * 0.9)
    }

}