import Foundation
import Observation
import SystemConfiguration

@Observable
public class NetworkMonitor {
    public var currentSpeed = NetworkSpeed(uploadSpeed: 0, downloadSpeed: 0)
    public var isMonitoring = false

    /// Callback fired on each speed update, allowing the ViewModel to react without Combine.
    public var onSpeedUpdate: ((NetworkSpeed) -> Void)?

    private var timer: Timer?
    private var lastUploadBytes: UInt64 = 0
    private var lastDownloadBytes: UInt64 = 0
    private var lastUpdateTime: Date = Date()

    public init() {}

    @MainActor
    public func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        updateInitialValues()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateNetworkSpeed()
            }
        }
    }

    @MainActor
    public func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
    }

    private func updateInitialValues() {
        let (upload, download) = getCurrentNetworkBytes()
        lastUploadBytes = upload
        lastDownloadBytes = download
        lastUpdateTime = Date()
    }

    @MainActor
    private func updateNetworkSpeed() {
        let currentTime = Date()
        let (currentUpload, currentDownload) = getCurrentNetworkBytes()

        let timeInterval = currentTime.timeIntervalSince(lastUpdateTime)
        guard timeInterval > 0 else { return }

        let uploadDiff = currentUpload > lastUploadBytes ? currentUpload - lastUploadBytes : 0
        let downloadDiff = currentDownload > lastDownloadBytes ? currentDownload - lastDownloadBytes : 0

        let uploadSpeed = Double(uploadDiff) / timeInterval
        let downloadSpeed = Double(downloadDiff) / timeInterval

        let newSpeed = NetworkSpeed(
            uploadSpeed: uploadSpeed,
            downloadSpeed: downloadSpeed
        )
        self.currentSpeed = newSpeed
        self.onSpeedUpdate?(newSpeed)

        lastUploadBytes = currentUpload
        lastDownloadBytes = currentDownload
        lastUpdateTime = currentTime
    }

    private func getCurrentNetworkBytes() -> (upload: UInt64, download: UInt64) {
        var uploadBytes: UInt64 = 0
        var downloadBytes: UInt64 = 0

        var ifaddrs: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddrs) == 0 {
            var ptr = ifaddrs
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }

                guard let interface = ptr?.pointee else { continue }
                let name = String(cString: interface.ifa_name)

                // Only count active network interfaces (exclude loopback)
                if name.hasPrefix("en") || name.hasPrefix("wi") {
                    if let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                        uploadBytes += UInt64(data.pointee.ifi_obytes)
                        downloadBytes += UInt64(data.pointee.ifi_ibytes)
                    }
                }
            }
            freeifaddrs(ifaddrs)
        }

        return (uploadBytes, downloadBytes)
    }

    deinit {
        timer?.invalidate()
    }
}