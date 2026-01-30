import Foundation
import Combine

@MainActor
public class NetworkMonitorViewModel: ObservableObject {
    @Published public var currentSpeed = NetworkSpeed(uploadSpeed: 0, downloadSpeed: 0)
    @Published public var preferences = UserPreferences()
    @Published public var peakRecorder = PeakRecorder()
    @Published public var peakApproachTracker = PeakApproachTracker()
    @Published public var historyRecorder = NetworkHistoryRecorder()
    @Published public var notificationService = NotificationService()
    @Published public var anomalyDetector = NetworkAnomalyDetector()
    @Published public var errorHandler = ErrorHandler()
    @Published public var latencyMonitor = LatencyMonitor()

    private let networkMonitor = NetworkMonitor()
    private var cancellables = Set<AnyCancellable>()

    public init() {
        setupBindings()
    }

    public func initialize() {
        errorHandler.log("應用程式初始化", level: .info, context: "Lifecycle")
        Task {
            await startMonitoring()
        }
        latencyMonitor.startMonitoring()
    }

    private func setupBindings() {
        // Bind network monitor to current speed
        networkMonitor.$currentSpeed
            .sink { [weak self] speed in
                guard let self = self else { return }
                self.currentSpeed = speed
                self.peakRecorder.recordSpeed(speed)
                self.historyRecorder.recordSpeed(speed)
                self.peakApproachTracker.checkForApproach(
                    speed,
                    downloadPlanSpeed: self.preferences.downloadPlanSpeed,
                    uploadPlanSpeed: self.preferences.uploadPlanSpeed
                )
                // Check and send notification if speed approaches limit
                self.notificationService.checkAndNotify(
                    downloadSpeed: speed.downloadMbps,
                    uploadSpeed: speed.uploadMbps,
                    downloadPlanSpeed: self.preferences.downloadPlanSpeed,
                    uploadPlanSpeed: self.preferences.uploadPlanSpeed
                )
                // Analyze for network anomalies
                self.anomalyDetector.analyzeSpeed(speed)
            }
            .store(in: &cancellables)
    }

    public func startMonitoring() async {
        errorHandler.log("開始網路監控", level: .info, context: "Network")
        await networkMonitor.startMonitoring()
    }

    public func stopMonitoring() async {
        errorHandler.log("停止網路監控", level: .info, context: "Network")
        await networkMonitor.stopMonitoring()
        latencyMonitor.stopMonitoring()
    }

    public func resetPeaks() {
        errorHandler.log("重置所有峰值記錄", level: .info, context: "Data")
        peakRecorder.resetPeaks()
        peakApproachTracker.resetApproachData()
        historyRecorder.clearHistory()
    }

    /// Optimize memory by pruning old data
    public func optimizeMemory() {
        errorHandler.log("優化記憶體", level: .info, context: "Memory")
        historyRecorder.pruneOldData()
        anomalyDetector.pruneOldAnomalies()
        // Peak approach tracker pruning handled by optimizer
        let prunedTimestamps = MemoryOptimizer.prunePeakApproaches(peakApproachTracker.approachTimestamps)
        // Note: Would need to add a method to update timestamps in PeakApproachTracker
    }

    /// Get current memory statistics
    public func getMemoryStats() -> MemoryOptimizer.MemoryStats {
        return MemoryOptimizer.calculateMemoryStats(
            oneHourDataCount: historyRecorder.oneHourData.count,
            twentyFourHourDataCount: historyRecorder.twentyFourHourData.count,
            anomalyCount: anomalyDetector.recentAnomalies.count
        )
    }

    // MARK: - Data Export

    /// Export data to CSV format
    public func exportData(format: DataExportService.ExportFormat, completion: @escaping (Result<URL, Error>) -> Void) {
        let result = DataExportService.exportToCSV(
            format: format,
            historyRecorder: historyRecorder,
            peakRecorder: peakRecorder,
            preferences: preferences
        )
        completion(result)
    }

    /// Show save panel and export data
    public func exportDataWithSavePanel(format: DataExportService.ExportFormat, completion: @escaping @Sendable (Bool) -> Void) {
        errorHandler.log("開始數據導出", level: .info, context: "Export")

        DataExportService.showSavePanel(suggestedFilename: format.filename) { [weak self] url in
            Task { @MainActor in
                guard let self = self, let url = url else {
                    self?.errorHandler.log("用戶取消導出或無法取得URL", level: .warning, context: "Export")
                    completion(false)
                    return
                }

                let csvContent = self.generateCSVContent(format: format)
                do {
                    try csvContent.write(to: url, atomically: true, encoding: .utf8)
                    DataExportService.revealInFinder(url: url)
                    self.errorHandler.log("數據導出成功: \(url.lastPathComponent)", level: .info, context: "Export")
                    completion(true)
                } catch {
                    self.errorHandler.logError(
                        NetworkMonitorError.dataExportFailed(error.localizedDescription),
                        context: "Export",
                        severity: .error
                    )
                    completion(false)
                }
            }
        }
    }

    /// Generate CSV content based on format
    private func generateCSVContent(format: DataExportService.ExportFormat) -> String {
        // This is a placeholder - actual implementation uses DataExportService
        return ""
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

        switch preferences.menuBarDisplayMode {
        case .both:
            return "↓ \(downloadText) ↑ \(uploadText) \(unitText)"
        case .downloadOnly:
            return "↓ \(downloadText) \(unitText)"
        case .uploadOnly:
            return "↑ \(uploadText) \(unitText)"
        case .compact:
            return "\(downloadText)/\(uploadText) \(unitText)"
        }
    }

    // Check if peak is concerning (>90% of plan)
    public func isPeakConcerning(speed: Double, planSpeed: Double) -> Bool {
        return speed > (planSpeed * 0.9)
    }

    // Format time for display
    public func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "N/A" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // Get formatted hourly peak text with time
    public func getHourlyPeakText(speed: Double, time: Date?, unit: UserPreferences.SpeedUnit) -> String {
        let speedText = formatSpeed(speed, unit: unit)
        let timeText = formatTime(time)
        return "\(speedText) \(unit.displayName) (\(timeText))"
    }

    // Format relative time in Chinese (e.g., "3天2小時15分鐘前")
    public func formatRelativeTime(_ date: Date?) -> String {
        guard let date = date else { return "" }

        let now = Date()
        let timeInterval = now.timeIntervalSince(date)

        // If negative or zero, return empty string
        guard timeInterval > 0 else { return "" }

        let days = Int(timeInterval / 86400)
        let hours = Int((timeInterval.truncatingRemainder(dividingBy: 86400)) / 3600)
        let minutes = Int((timeInterval.truncatingRemainder(dividingBy: 3600)) / 60)

        var components: [String] = []

        if days > 0 {
            components.append("\(days)天")
        }

        if hours > 0 {
            components.append("\(hours)小時")
        }

        if minutes > 0 {
            components.append("\(minutes)分鐘")
        }

        // If less than 1 minute, show "剛剛"
        if components.isEmpty {
            return "剛剛"
        }

        return components.joined() + "前"
    }

}