import Foundation

public struct NetworkSpeed {
    public let uploadSpeed: Double    // bytes per second
    public let downloadSpeed: Double  // bytes per second
    public let timestamp: Date

    public init(uploadSpeed: Double, downloadSpeed: Double, timestamp: Date = Date()) {
        self.uploadSpeed = uploadSpeed
        self.downloadSpeed = downloadSpeed
        self.timestamp = timestamp
    }

    // Convert bytes per second to Mbps
    public var uploadMbps: Double {
        return (uploadSpeed * 8.0) / 1_000_000.0
    }

    public var downloadMbps: Double {
        return (downloadSpeed * 8.0) / 1_000_000.0
    }

    // Convert bytes per second to MB/s
    public var uploadMBps: Double {
        return uploadSpeed / 1_000_000.0
    }

    public var downloadMBps: Double {
        return downloadSpeed / 1_000_000.0
    }
}