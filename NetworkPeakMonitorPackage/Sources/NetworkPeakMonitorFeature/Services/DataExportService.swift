import Foundation
import AppKit

@MainActor
public class DataExportService {

    public enum ExportFormat: Sendable {
        case todayData          // 今日數據 (過去24小時)
        case peakHistory        // 峰值記錄
        case fullHistory        // 完整歷史記錄

        var filename: String {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HHmm"
            let timestamp = dateFormatter.string(from: Date())

            switch self {
            case .todayData:
                return "network_today_\(timestamp).csv"
            case .peakHistory:
                return "network_peaks_\(timestamp).csv"
            case .fullHistory:
                return "network_full_history_\(timestamp).csv"
            }
        }
    }

    /// Export data to CSV format
    public static func exportToCSV(
        format: ExportFormat,
        historyRecorder: NetworkHistoryRecorder,
        peakRecorder: PeakRecorder,
        preferences: UserPreferences
    ) -> Result<URL, Error> {
        let csvContent: String

        switch format {
        case .todayData:
            csvContent = generateTodayDataCSV(historyRecorder: historyRecorder, unit: preferences.displayUnit)
        case .peakHistory:
            csvContent = generatePeakHistoryCSV(peakRecorder: peakRecorder, unit: preferences.displayUnit)
        case .fullHistory:
            csvContent = generateFullHistoryCSV(historyRecorder: historyRecorder, unit: preferences.displayUnit)
        }

        // Save to Downloads folder
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let fileURL = downloadsURL.appendingPathComponent(format.filename)

        do {
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            return .success(fileURL)
        } catch {
            return .failure(error)
        }
    }

    /// Generate CSV for today's data
    private static func generateTodayDataCSV(historyRecorder: NetworkHistoryRecorder, unit: UserPreferences.SpeedUnit) -> String {
        var csv = "時間,下載速度 (\(unit.displayName)),上傳速度 (\(unit.displayName))\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let now = Date()
        let oneDayAgo = now.addingTimeInterval(-24 * 3600)

        // Filter data from last 24 hours
        let todayData = historyRecorder.oneHourData.filter { $0.timestamp >= oneDayAgo }

        for dataPoint in todayData {
            let timestamp = dateFormatter.string(from: dataPoint.timestamp)
            let download = formatSpeed(dataPoint.downloadSpeed, unit: unit)
            let upload = formatSpeed(dataPoint.uploadSpeed, unit: unit)
            csv += "\(timestamp),\(download),\(upload)\n"
        }

        return csv
    }

    /// Generate CSV for peak history
    private static func generatePeakHistoryCSV(peakRecorder: PeakRecorder, unit: UserPreferences.SpeedUnit) -> String {
        var csv = "類型,峰值速度 (\(unit.displayName)),發生時間\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        // Today's peaks
        if let todayDownloadTime = peakRecorder.todayPeakDownloadTime {
            let timestamp = dateFormatter.string(from: todayDownloadTime)
            let speed = formatSpeed(peakRecorder.todayPeakDownload, unit: unit)
            csv += "今日下載峰值,\(speed),\(timestamp)\n"
        }

        if let todayUploadTime = peakRecorder.todayPeakUploadTime {
            let timestamp = dateFormatter.string(from: todayUploadTime)
            let speed = formatSpeed(peakRecorder.todayPeakUpload, unit: unit)
            csv += "今日上傳峰值,\(speed),\(timestamp)\n"
        }

        // All-time peaks
        if let allTimeDownloadTime = peakRecorder.allTimePeakDownloadTime {
            let timestamp = dateFormatter.string(from: allTimeDownloadTime)
            let speed = formatSpeed(peakRecorder.allTimePeakDownload, unit: unit)
            csv += "歷史下載峰值,\(speed),\(timestamp)\n"
        }

        if let allTimeUploadTime = peakRecorder.allTimePeakUploadTime {
            let timestamp = dateFormatter.string(from: allTimeUploadTime)
            let speed = formatSpeed(peakRecorder.allTimePeakUpload, unit: unit)
            csv += "歷史上傳峰值,\(speed),\(timestamp)\n"
        }

        // Hourly peaks
        if let hourlyDownloadTime = peakRecorder.hourlyPeakDownloadTime {
            let timestamp = dateFormatter.string(from: hourlyDownloadTime)
            let speed = formatSpeed(peakRecorder.hourlyPeakDownload, unit: unit)
            csv += "1小時下載峰值,\(speed),\(timestamp)\n"
        }

        if let hourlyUploadTime = peakRecorder.hourlyPeakUploadTime {
            let timestamp = dateFormatter.string(from: hourlyUploadTime)
            let speed = formatSpeed(peakRecorder.hourlyPeakUpload, unit: unit)
            csv += "1小時上傳峰值,\(speed),\(timestamp)\n"
        }

        return csv
    }

    /// Generate CSV for full history
    private static func generateFullHistoryCSV(historyRecorder: NetworkHistoryRecorder, unit: UserPreferences.SpeedUnit) -> String {
        var csv = "時間,下載速度 (\(unit.displayName)),上傳速度 (\(unit.displayName))\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        // Export all available data
        for dataPoint in historyRecorder.oneHourData {
            let timestamp = dateFormatter.string(from: dataPoint.timestamp)
            let download = formatSpeed(dataPoint.downloadSpeed, unit: unit)
            let upload = formatSpeed(dataPoint.uploadSpeed, unit: unit)
            csv += "\(timestamp),\(download),\(upload)\n"
        }

        return csv
    }

    /// Format speed value based on unit
    private static func formatSpeed(_ speed: Double, unit: UserPreferences.SpeedUnit) -> String {
        switch unit {
        case .mbps:
            return String(format: "%.2f", speed)
        case .mbps_lower:
            return String(format: "%.2f", speed / 8.0)
        }
    }

    /// Open exported file in Finder
    public static func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Show save panel for user to choose location
    @MainActor
    public static func showSavePanel(
        suggestedFilename: String,
        completion: @escaping @Sendable (URL?) -> Void
    ) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = suggestedFilename
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "導出網路數據"
        savePanel.message = "選擇儲存位置"
        savePanel.prompt = "導出"

        savePanel.begin { response in
            if response == .OK {
                completion(savePanel.url)
            } else {
                completion(nil)
            }
        }
    }
}
