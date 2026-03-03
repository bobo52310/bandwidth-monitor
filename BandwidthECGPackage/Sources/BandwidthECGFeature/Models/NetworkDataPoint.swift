import Foundation

public struct NetworkDataPoint: Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let downloadSpeed: Double // bytes per second
    public let uploadSpeed: Double   // bytes per second

    public init(timestamp: Date, downloadSpeed: Double, uploadSpeed: Double) {
        self.id = UUID()
        self.timestamp = timestamp
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
    }

    // Helper properties for charts
    public var downloadMbps: Double {
        return downloadSpeed * 8 / 1_000_000 // Convert bytes/s to Mbps
    }

    public var uploadMbps: Double {
        return uploadSpeed * 8 / 1_000_000 // Convert bytes/s to Mbps
    }
}

public struct HourlyDataPoint: Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let avgDownloadSpeed: Double  // bytes per second
    public let avgUploadSpeed: Double    // bytes per second
    public let maxDownloadSpeed: Double  // bytes per second
    public let maxUploadSpeed: Double    // bytes per second

    public init(timestamp: Date, avgDownloadSpeed: Double, avgUploadSpeed: Double, maxDownloadSpeed: Double, maxUploadSpeed: Double) {
        self.id = UUID()
        self.timestamp = timestamp
        self.avgDownloadSpeed = avgDownloadSpeed
        self.avgUploadSpeed = avgUploadSpeed
        self.maxDownloadSpeed = maxDownloadSpeed
        self.maxUploadSpeed = maxUploadSpeed
    }

    // Helper properties for charts
    public var avgDownloadMbps: Double {
        return avgDownloadSpeed * 8 / 1_000_000
    }

    public var avgUploadMbps: Double {
        return avgUploadSpeed * 8 / 1_000_000
    }

    public var maxDownloadMbps: Double {
        return maxDownloadSpeed * 8 / 1_000_000
    }

    public var maxUploadMbps: Double {
        return maxUploadSpeed * 8 / 1_000_000
    }
}