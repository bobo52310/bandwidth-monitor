import Foundation
import AppKit

/// The two things an export needs from the screen: a place to save, and a way to tell the user
/// how it went.
///
/// The popover closes when the save panel appears (the panel is a separate process, so the app
/// loses focus), and its views are released when it does. Both calls are therefore made by the
/// view model, which outlives the popover, and `report(_:)` shows its result in an alert of the
/// app's own instead of in a view that may be gone.
@MainActor
public protocol ExportPresenting {
    /// Asks where to save. `completion` receives the chosen URL, or `nil` if the user cancelled.
    func chooseDestination(suggestedFilename: String, completion: @escaping @MainActor (URL?) -> Void)
    /// Tells the user an export reached its file, or why it did not. Not called for a cancel.
    func report(_ result: Result<URL, Error>)
}

@MainActor
public class DataExportService {

    public enum ExportFormat: Sendable {
        /// Every 10-second point of the last 24 hours: window average and window maximum.
        case recent24Hours
        /// The today, all-time and last-hour peaks.
        case peakHistory
    }

    // MARK: - Names and timestamps

    /// A formatter whose output never depends on the Mac's region settings: Latin digits, a
    /// Gregorian year (a Minguo or Buddhist system calendar would otherwise print 115 or 2569)
    /// and a 24-hour clock.
    nonisolated static func makePOSIXFormatter(format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    /// "2026-11-02 09:00:00", the time column of the CSV files.
    nonisolated public static func makeTimestampFormatter(timeZone: TimeZone) -> DateFormatter {
        makePOSIXFormatter(format: "yyyy-MM-dd HH:mm:ss", timeZone: timeZone)
    }

    /// The name the save panel offers, for example `network_recent24h_2026-11-02_0900.csv`.
    static func filename(for format: ExportFormat, clock: AppClock) -> String {
        let stamp = makePOSIXFormatter(format: "yyyy-MM-dd_HHmm", timeZone: clock.calendar.timeZone)
            .string(from: clock.now())
        switch format {
        case .recent24Hours:
            return "network_recent24h_\(stamp).csv"
        case .peakHistory:
            return "network_peaks_\(stamp).csv"
        }
    }

    // MARK: - CSV

    /// The file's content. Speeds are in `unit`, so a column never mixes Mbps with bytes per second.
    static func csv(
        _ format: ExportFormat,
        history: NetworkHistoryRecorder,
        peaks: PeakRecorder,
        unit: UserPreferences.SpeedUnit,
        clock: AppClock
    ) -> String {
        let timestamps = makeTimestampFormatter(timeZone: clock.calendar.timeZone)
        switch format {
        case .recent24Hours:
            return recent24HoursCSV(history: history, unit: unit, clock: clock, timestamps: timestamps)
        case .peakHistory:
            return peakHistoryCSV(peaks: peaks, unit: unit, timestamps: timestamps)
        }
    }

    private static func recent24HoursCSV(
        history: NetworkHistoryRecorder,
        unit: UserPreferences.SpeedUnit,
        clock: AppClock,
        timestamps: DateFormatter
    ) -> String {
        let unitName = unit.displayName
        var rows = [row([
            L10n.exportColumnTime,
            L10n.exportColumnAvgDownload(unitName),
            L10n.exportColumnMaxDownload(unitName),
            L10n.exportColumnAvgUpload(unitName),
            L10n.exportColumnMaxUpload(unitName),
        ])]

        let cutoff = clock.now().addingTimeInterval(-24 * 3600)
        for point in history.oneHourData where point.timestamp >= cutoff {
            rows.append(row([
                timestamps.string(from: point.timestamp),
                formatSpeed(point.downloadMbps, unit: unit),
                formatSpeed(point.maxDownloadMbps, unit: unit),
                formatSpeed(point.uploadMbps, unit: unit),
                formatSpeed(point.maxUploadMbps, unit: unit),
            ]))
        }
        return rows.joined()
    }

    private static func peakHistoryCSV(
        peaks: PeakRecorder,
        unit: UserPreferences.SpeedUnit,
        timestamps: DateFormatter
    ) -> String {
        var rows = [row([
            L10n.exportColumnType,
            L10n.exportColumnPeakSpeed(unit.displayName),
            L10n.exportColumnPeakTime,
        ])]

        // Peaks are kept in Mbps.
        let entries: [(label: String, mbps: Double, time: Date?)] = [
            (L10n.exportRowTodayDownload, peaks.todayPeakDownload, peaks.todayPeakDownloadTime),
            (L10n.exportRowTodayUpload, peaks.todayPeakUpload, peaks.todayPeakUploadTime),
            (L10n.exportRowAllTimeDownload, peaks.allTimePeakDownload, peaks.allTimePeakDownloadTime),
            (L10n.exportRowAllTimeUpload, peaks.allTimePeakUpload, peaks.allTimePeakUploadTime),
            (L10n.exportRowHourDownload, peaks.hourlyPeakDownload, peaks.hourlyPeakDownloadTime),
            (L10n.exportRowHourUpload, peaks.hourlyPeakUpload, peaks.hourlyPeakUploadTime),
        ]
        for entry in entries {
            guard let time = entry.time else { continue }
            rows.append(row([entry.label, formatSpeed(entry.mbps, unit: unit), timestamps.string(from: time)]))
        }
        return rows.joined()
    }

    /// One CSV line. A field with a comma, a quote or a line break is quoted.
    private static func row(_ fields: [String]) -> String {
        fields.map { field in
            guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }.joined(separator: ",") + "\n"
    }

    /// `mbps` in the unit the user reads speeds in, with two decimals.
    private static func formatSpeed(_ mbps: Double, unit: UserPreferences.SpeedUnit) -> String {
        switch unit {
        case .mbps:
            return String(format: "%.2f", mbps)
        case .mbps_lower:
            return String(format: "%.2f", mbps / 8.0)
        }
    }

    // MARK: - Writing

    /// Writes the file. Throws if it cannot, for example when the disk is full or the location
    /// is no longer there; the caller must tell the user.
    ///
    /// The write is atomic, so a failure part way leaves no half-written file. An atomic write
    /// needs a temporary file next to the target, and a sandboxed app is only sure to be allowed
    /// to write the file the user chose in the save panel. If the temporary file is refused, the
    /// file itself is written instead.
    nonisolated public static func write(_ csv: String, to url: URL) throws {
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            try csv.write(to: url, atomically: false, encoding: .utf8)
        }
    }

    /// Open exported file in Finder
    public static func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// The live presenter: a save panel, and an alert that stands on its own.
@MainActor
public struct SystemExportPresenter: ExportPresenting {
    public init() {}

    public func chooseDestination(suggestedFilename: String, completion: @escaping @MainActor (URL?) -> Void) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = suggestedFilename
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = L10n.exportPanelTitle
        savePanel.message = L10n.exportPanelMessage
        savePanel.prompt = L10n.exportPanelPrompt

        savePanel.begin { response in
            completion(response == .OK ? savePanel.url : nil)
        }
    }

    public func report(_ result: Result<URL, Error>) {
        let alert = NSAlert()
        var revealURL: URL?
        switch result {
        case .success(let url):
            alert.alertStyle = .informational
            alert.messageText = L10n.exportSuccessTitle
            alert.informativeText = L10n.exportSuccessDetail(url.lastPathComponent)
            alert.addButton(withTitle: L10n.buttonOK)
            alert.addButton(withTitle: L10n.exportRevealInFinder)
            revealURL = url
        case .failure(let error):
            alert.alertStyle = .warning
            alert.messageText = L10n.exportFailure
            alert.informativeText = L10n.exportFailureDetail(error.localizedDescription)
            alert.addButton(withTitle: L10n.buttonOK)
        }

        // The popover has closed by now, so the app is in the background; the alert would
        // otherwise open behind other windows. It is the answer to something the user just did.
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        // Finder opens only when asked for, instead of taking the focus on its own.
        if response == .alertSecondButtonReturn, let revealURL {
            DataExportService.revealInFinder(url: revealURL)
        }
    }
}
