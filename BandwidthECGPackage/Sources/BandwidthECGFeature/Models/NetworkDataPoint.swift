import Foundation

/// One history point. A single sample has max equal to the average; a 10-second point keeps
/// both the window's average and its highest sample.
public struct NetworkDataPoint: Codable, Identifiable {
    /// For SwiftUI identity only: regenerated on decode and never encoded.
    public let id: UUID
    /// Start of the window (the time of its first sample).
    public let timestamp: Date
    public let downloadSpeed: Double // window average, bytes per second
    public let uploadSpeed: Double   // window average, bytes per second
    public let maxDownloadSpeed: Double // window max, bytes per second
    public let maxUploadSpeed: Double   // window max, bytes per second

    public init(timestamp: Date, downloadSpeed: Double, uploadSpeed: Double,
                maxDownloadSpeed: Double? = nil, maxUploadSpeed: Double? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.maxDownloadSpeed = maxDownloadSpeed ?? downloadSpeed
        self.maxUploadSpeed = maxUploadSpeed ?? uploadSpeed
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp, downloadSpeed, uploadSpeed, maxDownloadSpeed, maxUploadSpeed
    }

    /// Points saved before the max fields existed decode with max equal to the average.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let downloadSpeed = try container.decode(Double.self, forKey: .downloadSpeed)
        let uploadSpeed = try container.decode(Double.self, forKey: .uploadSpeed)
        self.init(
            timestamp: try container.decode(Date.self, forKey: .timestamp),
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed,
            maxDownloadSpeed: try container.decodeIfPresent(Double.self, forKey: .maxDownloadSpeed),
            maxUploadSpeed: try container.decodeIfPresent(Double.self, forKey: .maxUploadSpeed)
        )
    }

    public var maxDownloadMbps: Double {
        maxDownloadSpeed * 8 / 1_000_000
    }

    public var maxUploadMbps: Double {
        maxUploadSpeed * 8 / 1_000_000
    }

    // Helper properties for charts
    public var downloadMbps: Double {
        return downloadSpeed * 8 / 1_000_000 // Convert bytes/s to Mbps
    }

    public var uploadMbps: Double {
        return uploadSpeed * 8 / 1_000_000 // Convert bytes/s to Mbps
    }
}