import Foundation

/// Named-file storage for data that is too big or too important for `UserDefaults`.
public protocol BlobStore: Sendable {
    /// `nil` means the file does not exist. Any other failure throws.
    func read(_ name: String) throws -> Data?
    /// Writes atomically: readers see the old file or the new one, never a partial file.
    func write(_ data: Data, named name: String) throws
    /// Renames a file that could not be decoded to `<name>.corrupt-<unix-seconds>` so it is
    /// kept for inspection and is no longer picked up as the live file. A missing file is a no-op.
    func quarantine(_ name: String) throws
}

/// Stores blobs as files in a directory, `Application Support/BandwidthECG` by default.
public struct AppSupportBlobStore: BlobStore {
    private let directory: URL

    public init() {
        self.directory = AppPaths.supportDirectory
    }

    public init(directory: URL) {
        self.directory = directory
    }

    public func read(_ name: String) throws -> Data? {
        let url = try fileURL(for: name)
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
    }

    public func write(_ data: Data, named name: String) throws {
        let url = try fileURL(for: name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public func quarantine(_ name: String) throws {
        let source = try fileURL(for: name)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return }

        let stamp = Int(Date().timeIntervalSince1970)
        var destination = try fileURL(for: "\(name).corrupt-\(stamp)")
        // Two corrupt files in the same second must not overwrite each other.
        var suffix = 1
        while fileManager.fileExists(atPath: destination.path) {
            destination = try fileURL(for: "\(name).corrupt-\(stamp)-\(suffix)")
            suffix += 1
        }
        try fileManager.moveItem(at: source, to: destination)
    }

    /// Blob names are plain file names; anything that could leave the directory is refused.
    private func fileURL(for name: String) throws -> URL {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        return directory.appendingPathComponent(name)
    }
}
