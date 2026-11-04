import Testing
import Foundation
@testable import BandwidthECGFeature

/// The error log is a plain text file in Application Support. It must not grow without bound:
/// above 1 MB it rolls over to `error_log.1.txt`, and only one old generation is kept.
@MainActor
@Suite("ErrorHandler log file")
struct ErrorHandlerLogTests {
    private static let oneMegabyte = 1_048_576

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ErrorHandlerLogTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeHandler(in directory: URL) -> ErrorHandler {
        ErrorHandler(logToFile: true, defaults: MemoryDefaults.make(), logDirectory: directory)
    }

    private func size(of url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? Int) ?? -1
    }

    private func seed(_ url: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: UInt8(ascii: "x"), count: bytes).write(to: url)
    }

    @Test func rotatesAboveOneMegabyte() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let current = directory.appendingPathComponent("error_log.txt")
        let rotated = directory.appendingPathComponent("error_log.1.txt")
        try seed(current, bytes: Self.oneMegabyte + 1)

        makeHandler(in: directory).log("after rotation", context: "Test")

        #expect(FileManager.default.fileExists(atPath: rotated.path))
        #expect(size(of: rotated) == Self.oneMegabyte + 1)
        let fresh = try String(contentsOf: current, encoding: .utf8)
        #expect(fresh.contains("after rotation"))
        #expect(size(of: current) < 1_000)
    }

    @Test func keepsOnlyOneOldGeneration() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let current = directory.appendingPathComponent("error_log.txt")
        let rotated = directory.appendingPathComponent("error_log.1.txt")
        try seed(rotated, bytes: 10)
        try seed(current, bytes: Self.oneMegabyte + 1)

        makeHandler(in: directory).log("second", context: "Test")

        // The earlier generation is replaced, not stacked next to a `.2`.
        #expect(size(of: rotated) == Self.oneMegabyte + 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(names == ["error_log.1.txt", "error_log.txt"])
    }

    @Test func belowTheLimitAppendsWithoutRotating() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let current = directory.appendingPathComponent("error_log.txt")
        try seed(current, bytes: 1_000)

        makeHandler(in: directory).log("still small", context: "Test")

        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("error_log.1.txt").path))
        let text = try String(contentsOf: current, encoding: .utf8)
        #expect(text.hasSuffix("still small\n"))
        #expect(size(of: current) > 1_000)
    }

    @Test func createsTheDirectoryAndFileOnFirstWrite() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(!FileManager.default.fileExists(atPath: directory.path))

        makeHandler(in: directory).log("first line", context: "Test")

        let text = try String(contentsOf: directory.appendingPathComponent("error_log.txt"), encoding: .utf8)
        #expect(text.contains("first line"))
    }

    @Test func initDoesNotTouchTheDisk() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = makeHandler(in: directory)

        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func clearLogFileRemovesBothGenerations() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seed(directory.appendingPathComponent("error_log.txt"), bytes: 10)
        try seed(directory.appendingPathComponent("error_log.1.txt"), bytes: 10)

        makeHandler(in: directory).clearLogFile()

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names.isEmpty)
    }
}
