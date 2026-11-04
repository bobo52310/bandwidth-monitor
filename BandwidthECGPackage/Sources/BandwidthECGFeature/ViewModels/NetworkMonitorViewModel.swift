import Foundation
import Observation
import OSLog

@MainActor
@Observable
public class NetworkMonitorViewModel {
    public var currentSpeed = NetworkSpeed(uploadSpeed: 0, downloadSpeed: 0)
    public var preferences: UserPreferences
    public var peakRecorder: PeakRecorder
    public var peakApproachTracker: PeakApproachTracker
    public var historyRecorder: NetworkHistoryRecorder
    public var notificationService: NotificationService
    public var anomalyDetector: NetworkAnomalyDetector
    public var errorHandler: ErrorHandler
    public var latencyMonitor: LatencyMonitor
    public var disconnectTracker: DisconnectTracker
    public var monthlyReportService: MonthlyReportService
    public let dailyStore: DailyRecordStore
    /// The store every setting lives in. The status bar controller keeps onboarding and the
    /// floating panel's frame here too, so tests and the app agree on where state goes.
    public let defaults: UserDefaults
    /// The save panel and the result alert of an export. A test replaces it.
    @ObservationIgnored public var exportPresenter: any ExportPresenting = SystemExportPresenter()
    /// Called once when an export is over: after a cancel, or after the user has dismissed the
    /// result. The save panel and the alert made the app active; the status bar controller uses
    /// this to give the focus back (final review F4) without the view model touching AppKit.
    @ObservationIgnored public var onExportFinished: (@MainActor () -> Void)?

    // Chart choices. The popover's views are released when it closes (D10), so what must
    // survive a close and reopen lives here. Not persisted: a relaunch starts from the defaults.
    public var chartRange: NetworkChartView.TimeRange = .oneHour
    public var showDownload = true
    public var showUpload = true
    public var chartBannerDismissed = false

    /// How close the speed is to the plan, for the menu bar (D18): the level of the latest
    /// sample, held for 3 seconds on the way down so it does not flicker at 1 Hz.
    public private(set) var menuBarAlertLevel: MenuBarAlertLevel = .normal
    @ObservationIgnored private var alertTracker = MenuBarAlertTracker()

    let networkMonitor: NetworkMonitor
    private let clock: AppClock
    private let logger = Logger(subsystem: "com.bandwidthecg", category: "Network")
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    public init(dependencies: AppDependencies = .live) {
        let defaults = dependencies.defaults
        let clock = dependencies.clock
        self.clock = clock
        self.defaults = defaults
        self.preferences = UserPreferences(defaults: defaults, loginItems: dependencies.loginItems)
        self.peakRecorder = PeakRecorder(defaults: defaults, clock: clock)
        self.peakApproachTracker = PeakApproachTracker(defaults: defaults, clock: clock)
        self.historyRecorder = NetworkHistoryRecorder(
            defaults: defaults,
            clock: clock,
            store: dependencies.blobStore
        )
        self.notificationService = NotificationService(
            defaults: defaults,
            clock: clock,
            delivery: dependencies.notifications
        )
        self.anomalyDetector = NetworkAnomalyDetector(defaults: defaults, clock: clock)
        self.errorHandler = ErrorHandler(logToFile: dependencies.logToFile, defaults: defaults)
        self.latencyMonitor = LatencyMonitor(
            defaults: defaults,
            clock: clock,
            probe: dependencies.latencyProbe
        )
        self.disconnectTracker = DisconnectTracker(
            defaults: defaults,
            clock: clock,
            pathSource: dependencies.pathSource
        )
        let dailyStore = DailyRecordStore(store: dependencies.blobStore, clock: clock)
        self.dailyStore = dailyStore
        self.monthlyReportService = MonthlyReportService(userDefaults: defaults, dailyStore: dailyStore, clock: clock)
        self.networkMonitor = NetworkMonitor(source: dependencies.counterSource, clock: clock)
        setupBindings()
    }

    public func initialize() {
        errorHandler.log("應用程式初始化", level: .info, context: "Lifecycle")
        startMonitoring()
        latencyMonitor.startMonitoring()
        disconnectTracker.startMonitoring()
    }

    private func setupBindings() {
        // Use callback pattern instead of Combine's $currentSpeed.sink
        networkMonitor.onSpeedUpdate = { [weak self] speed in
            self?.handleSample(speed)
        }
        latencyMonitor.onMeasurement = { [weak self] measurement in
            guard let self else { return }
            switch measurement {
            case .success(let latencyMs, _):
                // The monitor sets `currentJitter` just before it reports, and leaves it `nil`
                // for a reading made from a single sample, which has no jitter to record.
                dailyStore.recordLatency(latencyMs: latencyMs, jitterMs: latencyMonitor.currentJitter)
                disconnectTracker.noteProbe(success: true)
            case .failure:
                dailyStore.recordLatencyFailure()
                disconnectTracker.noteProbe(success: false)
            }
            syncConnectivity()
        }
        latencyMonitor.onEnabledChange = { [weak self] isEnabled in
            guard let self, !isEnabled else { return }
            // Only the path is watched from now on.
            disconnectTracker.clearProbeFailures()
            syncConnectivity()
        }
        disconnectTracker.onConnectivityChange = { [weak self] _ in
            self?.syncConnectivity()
        }
        disconnectTracker.onEvent = { [weak self] event in
            self?.dailyStore.recordDisconnect(start: event.startTime, end: event.endTime)
            self?.anomalyDetector.recordConnectionDrop(duration: event.duration)
        }
    }

    /// "Stable" in the popover follows the same path and probe state as the disconnect record,
    /// so the two never disagree.
    private func syncConnectivity() {
        anomalyDetector.updateConnectivity(
            pathSatisfied: disconnectTracker.isPathSatisfied,
            probeFailures: disconnectTracker.consecutiveProbeFailures
        )
    }

    private func handleSample(_ speed: NetworkSpeed) {
        // A measurement error must not reach anything downstream, the screen included.
        guard speed.downloadMbps <= SampleGuard.maxPlausibleMbps,
              speed.uploadMbps <= SampleGuard.maxPlausibleMbps else {
            logger.warning("Ignored implausible sample: download \(speed.downloadMbps) Mbps, upload \(speed.uploadMbps) Mbps")
            return
        }

        currentSpeed = speed
        updateMenuBarAlert(for: speed)
        peakRecorder.recordSpeed(speed)
        historyRecorder.recordSpeed(speed)
        dailyStore.ingest(
            speed,
            planDownloadMbps: preferences.downloadPlanSpeed,
            planUploadMbps: preferences.uploadPlanSpeed
        )
        let isApproachEvent = peakApproachTracker.checkForApproach(
            speed,
            downloadPlanSpeed: preferences.downloadPlanSpeed,
            uploadPlanSpeed: preferences.uploadPlanSpeed
        )
        if isApproachEvent {
            dailyStore.recordApproachEvent()
        }
        // Check and send notification if speed approaches limit
        notificationService.checkAndNotify(
            downloadSpeed: speed.downloadMbps,
            uploadSpeed: speed.uploadMbps,
            downloadPlanSpeed: preferences.downloadPlanSpeed,
            uploadPlanSpeed: preferences.uploadPlanSpeed
        )
        // Analyze for network anomalies
        anomalyDetector.analyzeSpeed(speed)
    }

    /// Runs on every sample, not only when the title changes, so the hold on the way down runs
    /// out even while the speed itself stays the same.
    private func updateMenuBarAlert(for speed: NetworkSpeed) {
        let instant = MenuBarAlertLevel.evaluate(
            downloadMbps: speed.downloadMbps,
            uploadMbps: speed.uploadMbps,
            planDownloadMbps: preferences.downloadPlanSpeed,
            planUploadMbps: preferences.uploadPlanSpeed,
            warningRatio: notificationService.threshold
        )
        menuBarAlertLevel = alertTracker.update(instant, at: clock.monotonic())
    }

    public func startMonitoring() {
        errorHandler.log("開始網路監控", level: .info, context: "Network")
        networkMonitor.startMonitoring()
    }

    public func stopMonitoring() {
        errorHandler.log("停止網路監控", level: .info, context: "Network")
        networkMonitor.stopMonitoring()
        latencyMonitor.stopMonitoring()
        disconnectTracker.stopMonitoring()
    }

    /// Clears the peaks, the approach counter and the chart history. Daily records are left
    /// alone: the monthly report is derived from them.
    public func resetPeaks() {
        errorHandler.log("重置所有峰值記錄", level: .info, context: "Data")
        peakRecorder.resetPeaks()
        peakApproachTracker.resetApproachData()
        historyRecorder.clearHistory()
    }

    /// Removes one all-time peak, for example one left behind by a bad sample.
    public func clearAllTimePeak(_ direction: PeakDirection) {
        errorHandler.log("清除歷史峰值：\(direction == .download ? "下載" : "上傳")", level: .info, context: "Data")
        peakRecorder.clearAllTimePeak(direction)
    }

    // MARK: - Data Export

    /// Asks where to save, writes the CSV there and tells the user how it went.
    ///
    /// The save panel closes the popover and the popover's views are released with it, so nothing
    /// here may depend on the caller still being on screen: the data is captured now, and the
    /// result goes to `exportPresenter` rather than only to `completion`. `completion` is for a
    /// caller that wants to know too; the URL is `nil` when the user cancelled.
    public func exportData(
        format: DataExportService.ExportFormat,
        completion: @escaping @MainActor (Result<URL?, Error>) -> Void = { _ in }
    ) {
        let csv = DataExportService.csv(
            format,
            history: historyRecorder,
            peaks: peakRecorder,
            unit: preferences.displayUnit,
            clock: clock
        )
        save(csv, suggestedFilename: DataExportService.filename(for: format, clock: clock), completion: completion)
    }

    /// Saves one month's report as CSV, the same way as `exportData`.
    public func exportMonthlyReport(
        _ summary: MonthlySummary,
        completion: @escaping @MainActor (Result<URL?, Error>) -> Void = { _ in }
    ) {
        let csv = monthlyReportService.exportToCSV(summary)
        let month = summary.formattedMonth.replacingOccurrences(of: "/", with: "-")
        save(csv, suggestedFilename: "monthly_report_\(month).csv", completion: completion)
    }

    private func save(
        _ csv: String,
        suggestedFilename: String,
        completion: @escaping @MainActor (Result<URL?, Error>) -> Void
    ) {
        errorHandler.log("Export started: \(suggestedFilename)", level: .info, context: "Export")
        let presenter = exportPresenter
        let errorHandler = errorHandler
        // The closure owns the data, the presenter and the logger. It outlives any view.
        presenter.chooseDestination(suggestedFilename: suggestedFilename) { [weak self] url in
            // `report` is modal, so this runs once the user has seen the result.
            defer { self?.onExportFinished?() }
            guard let url else {
                errorHandler.log("Export cancelled", level: .info, context: "Export")
                completion(.success(nil))
                return
            }
            do {
                try DataExportService.write(csv, to: url)
                errorHandler.log("Export saved: \(url.lastPathComponent)", level: .info, context: "Export")
                completion(.success(url))
                presenter.report(.success(url))
            } catch {
                errorHandler.logError(
                    NetworkMonitorError.dataExportFailed(error.localizedDescription),
                    context: "Export",
                    severity: .error
                )
                completion(.failure(error))
                presenter.report(.failure(error))
            }
        }
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
            return "↓\(downloadText)/↑\(uploadText) \(unitText)"
        }
    }

    /// The menu bar item: the speed text, with a warning prefix near the plan. The status bar
    /// controller observes this, so it follows the speed, the display mode, the unit and the alert.
    var menuBarTitle: MenuBarTitle {
        MenuBarTitle.make(base: menuBarText, level: menuBarAlertLevel)
    }

    /// Whether `speed` has reached the share of `planSpeed` the user set as the notification
    /// threshold (R12). The popover, the chart tooltip, the menu bar and the notification all
    /// use that one threshold.
    public func isPeakConcerning(speed: Double, planSpeed: Double) -> Bool {
        guard planSpeed.isFinite, planSpeed > 0, speed.isFinite else { return false }
        return speed / planSpeed >= notificationService.threshold
    }

    // Format time for display
    public func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "N/A" }
        return Self.timeFormatter.string(from: date)
    }

    // Get formatted hourly peak text with time
    public func getHourlyPeakText(speed: Double, time: Date?, unit: UserPreferences.SpeedUnit) -> String {
        let speedText = formatSpeed(speed, unit: unit)
        let timeText = formatTime(time)
        return "\(speedText) \(unit.displayName) (\(timeText))"
    }

    // Format relative time (e.g., "3天2小時前")
    public func formatRelativeTime(_ date: Date?) -> String {
        guard let date = date else { return "" }

        let now = clock.now()
        let timeInterval = now.timeIntervalSince(date)

        // If negative or zero, return empty string
        guard timeInterval > 0 else { return "" }

        let days = Int(timeInterval / 86400)
        let hours = Int((timeInterval.truncatingRemainder(dividingBy: 86400)) / 3600)
        let minutes = Int((timeInterval.truncatingRemainder(dividingBy: 3600)) / 60)

        if days > 0 && hours > 0 {
            return L10n.timeDaysHoursAgo(days, hours)
        } else if days > 0 {
            return L10n.timeDaysAgo(days)
        } else if hours > 0 {
            return L10n.timeHoursAgo(hours)
        } else if minutes > 0 {
            return L10n.timeMinutesAgo(minutes)
        } else {
            return L10n.timeJustNow
        }
    }

    // MARK: - Sleep

    /// Before the Mac sleeps. Sleep is not downtime, so an open outage ends here; then pending
    /// data is written, the outage included.
    public func handleSleep() {
        disconnectTracker.handleSleep()
        syncConnectivity()
        flushPersistence()
    }

    /// After wake: the network gets a short grace to come back, and the latency probe starts
    /// on a cold connection again.
    public func handleWake() {
        disconnectTracker.handleWake()
        latencyMonitor.handleWake()
        syncConnectivity()
    }

    // MARK: - Persistence

    /// On quit: stops monitoring, which ends and records an open outage (final review F2), then
    /// writes pending data, that outage included.
    public func prepareForQuit() {
        stopMonitoring()
        flushPersistence()
    }

    /// Writes pending data now. Called before sleep and on quit.
    public func flushPersistence() {
        dailyStore.flush()
        historyRecorder.flush()
    }
}
