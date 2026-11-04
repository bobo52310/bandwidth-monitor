import Foundation

/// File-system locations owned by the app.
public enum AppPaths {
    /// `Application Support/BandwidthECG`. Inside the sandbox this resolves to the app's container.
    /// The directory is not created here; writers create it on demand.
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("BandwidthECG", isDirectory: true)
    }
}
