import Testing
import Foundation
@testable import BandwidthECGFeature

@Suite("BlobStore Tests")
struct BlobStoreTests {

    /// A store rooted in a fresh, not-yet-created directory under the system temp directory.
    private func makeStore() -> (store: AppSupportBlobStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlobStoreTests-\(UUID().uuidString)", isDirectory: true)
        return (AppSupportBlobStore(directory: directory), directory)
    }

    private func fileNames(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    @Test func readMissingFile_returnsNil() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try store.read("history.json") == nil)
    }

    @Test func writeThenRead_roundTrips() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = Data("hello".utf8)

        try store.write(payload, named: "history.json")

        #expect(try store.read("history.json") == payload)
    }

    @Test func write_replacesAnExistingFile() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.write(Data("old".utf8), named: "history.json")
        try store.write(Data("new".utf8), named: "history.json")

        #expect(try store.read("history.json") == Data("new".utf8))
        // Atomic writes leave no temporary files behind.
        #expect(fileNames(in: directory) == ["history.json"])
    }

    @Test func quarantine_movesTheFileAside() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = Data("{ truncated".utf8)
        try store.write(payload, named: "history.json")

        try store.quarantine("history.json")

        #expect(try store.read("history.json") == nil)
        let names = fileNames(in: directory)
        #expect(names.count == 1)
        let backup = try #require(names.first)
        #expect(backup.hasPrefix("history.json.corrupt-"))
        // The suffix is the unix time in seconds.
        let seconds = try #require(Int(backup.dropFirst("history.json.corrupt-".count)))
        #expect(abs(Double(seconds) - Date().timeIntervalSince1970) < 60)
        #expect(try Data(contentsOf: directory.appendingPathComponent(backup)) == payload)
    }

    @Test func quarantine_missingFile_isANoOp() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.quarantine("history.json")

        #expect(fileNames(in: directory).isEmpty)
    }

    /// Two corrupt files quarantined within the same second must both survive.
    @Test func quarantine_twiceInTheSameSecond_keepsBothFiles() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.write(Data("first".utf8), named: "history.json")
        try store.quarantine("history.json")
        try store.write(Data("second".utf8), named: "history.json")
        try store.quarantine("history.json")

        let names = fileNames(in: directory)
        #expect(names.count == 2)
        let contents = try names.map { try String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8) }
        #expect(Set(contents) == ["first", "second"])
    }

    @Test(arguments: ["", "..", ".", "../escape.json", "nested/file.json"])
    func namesThatCouldLeaveTheDirectory_areRefused(name: String) {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: (any Error).self) { try store.write(Data("x".utf8), named: name) }
        #expect(throws: (any Error).self) { try store.read(name) }
        #expect(throws: (any Error).self) { try store.quarantine(name) }
    }
}
