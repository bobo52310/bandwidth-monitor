import Foundation
import OSLog
import Observation

/// Centralized error handling and logging service
@MainActor
@Observable
public class ErrorHandler {
    public var recentErrors: [ErrorRecord] = []
    public var isLoggingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isLoggingEnabled, forKey: "errorLoggingEnabled")
        }
    }

    // OSLog for system logging
    private let logger = Logger(subsystem: "com.bandwidthecg", category: "ErrorHandler")

    // Configuration
    private let maxErrorHistory = 100
    private let logToFile: Bool

    // Log file URL
    private var logFileURL: URL? {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let appDirectory = appSupportURL.appendingPathComponent("BandwidthECG", isDirectory: true)

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        return appDirectory.appendingPathComponent("error_log.txt")
    }

    public init(logToFile: Bool = true) {
        self.logToFile = logToFile
        self.isLoggingEnabled = UserDefaults.standard.object(forKey: "errorLoggingEnabled") as? Bool ?? true
    }

    // MARK: - Data Migration

    /// Migrate data from legacy NetworkPeakMonitor app support directory
    public static func migrateDataFromLegacyPath() {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let oldPath = appSupportURL.appendingPathComponent("NetworkPeakMonitor", isDirectory: true)
        let newPath = appSupportURL.appendingPathComponent("BandwidthECG", isDirectory: true)

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: oldPath.path),
              !fileManager.fileExists(atPath: newPath.path) else {
            return
        }

        do {
            try fileManager.moveItem(at: oldPath, to: newPath)
            Logger(subsystem: "com.bandwidthecg", category: "Migration")
                .info("Successfully migrated data from NetworkPeakMonitor to BandwidthECG")
        } catch {
            Logger(subsystem: "com.bandwidthecg", category: "Migration")
                .error("Failed to migrate data: \(error.localizedDescription)")
        }
    }

    // MARK: - Error Logging

    /// Log an error with context
    public func logError(_ error: Error, context: String = "", severity: ErrorSeverity = .error) {
        guard isLoggingEnabled else { return }

        let errorRecord = ErrorRecord(
            error: error,
            context: context,
            severity: severity,
            timestamp: Date()
        )

        recentErrors.insert(errorRecord, at: 0)

        // Limit history
        if recentErrors.count > maxErrorHistory {
            recentErrors.removeLast()
        }

        // Log to system
        logToSystem(errorRecord)

        // Log to file if enabled
        if logToFile {
            logToFileSystem(errorRecord)
        }
    }

    /// Log a custom message
    public func log(_ message: String, level: LogLevel = .info, context: String = "") {
        guard isLoggingEnabled else { return }

        let logEntry = "\(Date().formatted()) [\(level.rawValue)] [\(context.isEmpty ? "App" : context)] \(message)"

        // Log to system
        switch level {
        case .debug:
            logger.debug("\(logEntry)")
        case .info:
            logger.info("\(logEntry)")
        case .warning:
            logger.warning("\(logEntry)")
        case .error:
            logger.error("\(logEntry)")
        case .critical:
            logger.critical("\(logEntry)")
        }

        // Log to file if enabled
        if logToFile {
            writeToFile(logEntry)
        }
    }

    // MARK: - System Logging

    private func logToSystem(_ errorRecord: ErrorRecord) {
        let message = "[\(errorRecord.context)] \(errorRecord.error.localizedDescription)"

        switch errorRecord.severity {
        case .warning:
            logger.warning("\(message)")
        case .error:
            logger.error("\(message)")
        case .critical:
            logger.critical("\(message)")
        }
    }

    // MARK: - File Logging

    private func logToFileSystem(_ errorRecord: ErrorRecord) {
        let timestamp = DateFormatter.localizedString(from: errorRecord.timestamp, dateStyle: .short, timeStyle: .medium)
        let logEntry = "[\(timestamp)] [\(errorRecord.severity.rawValue)] [\(errorRecord.context)] \(errorRecord.error.localizedDescription)"

        writeToFile(logEntry)
    }

    private func writeToFile(_ message: String) {
        guard let logFileURL = logFileURL else { return }

        let logMessage = message + "\n"

        if FileManager.default.fileExists(atPath: logFileURL.path) {
            // Append to existing file
            if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                fileHandle.seekToEndOfFile()
                if let data = logMessage.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            }
        } else {
            // Create new file
            try? logMessage.write(to: logFileURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Error Management

    /// Clear all error history
    public func clearErrors() {
        recentErrors.removeAll()
    }

    /// Clear log file
    public func clearLogFile() {
        guard let logFileURL = logFileURL else { return }
        try? FileManager.default.removeItem(at: logFileURL)
    }

    /// Get log file size
    public func getLogFileSize() -> String? {
        guard let logFileURL = logFileURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let fileSize = attributes[.size] as? Int64 else {
            return nil
        }

        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// Export log file
    public func exportLogFile() -> URL? {
        guard let logFileURL = logFileURL,
              FileManager.default.fileExists(atPath: logFileURL.path) else {
            return nil
        }

        return logFileURL
    }

    /// Get error summary
    public func getErrorSummary() -> ErrorSummary {
        let warnings = recentErrors.filter { $0.severity == .warning }.count
        let errors = recentErrors.filter { $0.severity == .error }.count
        let critical = recentErrors.filter { $0.severity == .critical }.count

        return ErrorSummary(
            totalErrors: recentErrors.count,
            warnings: warnings,
            errors: errors,
            critical: critical
        )
    }
}

// MARK: - Models

public struct ErrorRecord: Identifiable {
    public let id = UUID()
    public let error: Error
    public let context: String
    public let severity: ErrorSeverity
    public let timestamp: Date

    var displayMessage: String {
        if context.isEmpty {
            return error.localizedDescription
        } else {
            return "[\(context)] \(error.localizedDescription)"
        }
    }
}

public enum ErrorSeverity: String {
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"

    var color: String {
        switch self {
        case .warning: return "yellow"
        case .error: return "orange"
        case .critical: return "red"
        }
    }

    var icon: String {
        switch self {
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

public enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"
}

public struct ErrorSummary {
    public let totalErrors: Int
    public let warnings: Int
    public let errors: Int
    public let critical: Int

    public var hasErrors: Bool {
        totalErrors > 0
    }

    public var hasCriticalErrors: Bool {
        critical > 0
    }
}

// MARK: - Custom Error Types

public enum NetworkMonitorError: LocalizedError {
    case networkInterfaceNotFound
    case monitoringFailed(String)
    case dataExportFailed(String)
    case invalidConfiguration(String)
    case permissionDenied

    public var errorDescription: String? {
        switch self {
        case .networkInterfaceNotFound:
            return "找不到網路介面"
        case .monitoringFailed(let reason):
            return "監控失敗: \(reason)"
        case .dataExportFailed(let reason):
            return "數據導出失敗: \(reason)"
        case .invalidConfiguration(let reason):
            return "設定錯誤: \(reason)"
        case .permissionDenied:
            return "權限被拒絕"
        }
    }
}
