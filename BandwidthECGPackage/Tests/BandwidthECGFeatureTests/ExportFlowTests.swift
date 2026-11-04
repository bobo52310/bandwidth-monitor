import Testing
import Foundation
@testable import BandwidthECGFeature

/// A presenter that answers the save panel from a script and records what the user was told.
/// `holdPanel` keeps the panel open until `finishPanel(with:)`, which is how a test models the
/// seconds a user spends in it and the popover closing meanwhile.
@MainActor
final class FakeExportPresenter: ExportPresenting {
    var destination: URL?
    var holdPanel = false
    private(set) var suggestedFilenames: [String] = []
    private(set) var reports: [Result<URL, Error>] = []
    private var pending: (@MainActor (URL?) -> Void)?

    init(destination: URL? = nil) {
        self.destination = destination
    }

    func chooseDestination(suggestedFilename: String, completion: @escaping @MainActor (URL?) -> Void) {
        suggestedFilenames.append(suggestedFilename)
        if holdPanel {
            pending = completion
        } else {
            completion(destination)
        }
    }

    func report(_ result: Result<URL, Error>) {
        reports.append(result)
    }

    var isPanelOpen: Bool { pending != nil }

    func finishPanel(with url: URL?) {
        let completion = pending
        pending = nil
        completion?(url)
    }

    var reportedURLs: [URL] {
        reports.compactMap { if case .success(let url) = $0 { url } else { nil } }
    }

    var reportedFailures: Int {
        reports.filter { if case .failure = $0 { true } else { false } }.count
    }
}

/// What a user gets from the export buttons: a file where they chose, in the unit they read, and
/// an answer even when the popover that offered the button is gone by the time it is ready.
@MainActor
@Suite("Export flow")
struct ExportFlowTests {
    private static let bytesPerMbps = 125_000.0

    private func speed(_ mbps: Double) -> NetworkSpeed {
        NetworkSpeed(uploadSpeed: 0, downloadSpeed: mbps * Self.bytesPerMbps)
    }

    /// A view model whose history holds `points` closed 10-second points of 100 Mbps.
    private func makeViewModel(
        _ clock: TestClock,
        presenter: FakeExportPresenter,
        points: Int = 2
    ) -> NetworkMonitorViewModel {
        let viewModel = NetworkMonitorViewModel(dependencies: .test(clock: clock))
        viewModel.exportPresenter = presenter
        for _ in 0...points {
            viewModel.historyRecorder.recordSpeed(speed(100))
            clock.advance(by: 10)
        }
        return viewModel
    }

    private func rows(of url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    // MARK: - Recent data and peaks

    @Test func exportData_writesTheChosenFileAndReportsIt() throws {
        let directory = try DataExportTests.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("chosen.csv")
        let clock = TestClock(2026, 11, 2, 9)
        let presenter = FakeExportPresenter(destination: url)
        let viewModel = makeViewModel(clock, presenter: presenter)
        var completed: [Result<URL?, Error>] = []

        viewModel.exportData(format: .recent24Hours) { completed.append($0) }

        let lines = try rows(of: url)
        #expect(lines.count == 3) // header and two points
        #expect(lines[1].hasPrefix("2026-11-02 09:00:00,100.00,100.00,0.00,0.00"))
        #expect(presenter.suggestedFilenames.count == 1)
        #expect(presenter.suggestedFilenames[0].hasPrefix("network_recent24h_2026-11-02_"))
        #expect(presenter.suggestedFilenames[0].hasSuffix(".csv"))
        #expect(presenter.reportedURLs == [url])
        #expect(presenter.reportedFailures == 0)
        #expect(completed.count == 1)
        if case .success(let reported) = completed[0] { #expect(reported == url) } else { Issue.record("expected success") }
    }

    @Test func exportData_usesTheDisplayUnit() throws {
        let directory = try DataExportTests.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("mbytes.csv")
        let clock = TestClock(2026, 11, 2, 9)
        let viewModel = makeViewModel(clock, presenter: FakeExportPresenter(destination: url))
        viewModel.preferences.displayUnit = .mbps_lower

        viewModel.exportData(format: .recent24Hours)

        #expect(try rows(of: url)[1].hasPrefix("2026-11-02 09:00:00,12.50,12.50"))
    }

    @Test func exportData_peakHistory_savesThePeaks() throws {
        let directory = try DataExportTests.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("peaks.csv")
        let clock = TestClock(2026, 11, 2, 9)
        let presenter = FakeExportPresenter(destination: url)
        let viewModel = makeViewModel(clock, presenter: presenter)
        viewModel.peakRecorder.recordSpeed(speed(80))

        viewModel.exportData(format: .peakHistory)

        let lines = try rows(of: url)
        #expect(lines[0] == [
            L10n.exportColumnType,
            L10n.exportColumnPeakSpeed("Mbps"),
            L10n.exportColumnPeakTime,
        ].joined(separator: ","))
        #expect(lines.contains { $0.hasPrefix(L10n.exportRowAllTimeDownload + ",80.00,") })
        #expect(presenter.suggestedFilenames[0].hasPrefix("network_peaks_"))
        #expect(presenter.reportedURLs == [url])
    }

    // MARK: - Cancel and failure

    @Test func exportData_cancelled_writesNothingAndSaysNothing() throws {
        let directory = try DataExportTests.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestClock(2026, 11, 2, 9)
        let presenter = FakeExportPresenter(destination: nil)
        let viewModel = makeViewModel(clock, presenter: presenter)
        var completed: [Result<URL?, Error>] = []

        viewModel.exportData(format: .recent24Hours) { completed.append($0) }

        #expect(presenter.reports.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        #expect(completed.count == 1)
        if case .success(let url) = completed[0] { #expect(url == nil) } else { Issue.record("a cancel is not a failure") }
    }

    /// The file can no longer be written (a full disk, a removed volume): the user is told, and
    /// the caller's completion sees the failure too.
    @Test func exportData_writeFailure_isReported() throws {
        let directory = try DataExportTests.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unreachable = directory.appendingPathComponent("gone").appendingPathComponent("out.csv")
        let clock = TestClock(2026, 11, 2, 9)
        let presenter = FakeExportPresenter(destination: unreachable)
        let viewModel = makeViewModel(clock, presenter: presenter)
        var completed: [Result<URL?, Error>] = []

        viewModel.exportData(format: .recent24Hours) { completed.append($0) }

        #expect(presenter.reportedFailures == 1)
        #expect(presenter.reportedURLs.isEmpty)
        #expect(completed.count == 1)
        if case .failure = completed[0] {} else { Issue.record("expected a failure") }
        #expect(viewModel.errorHandler.recentErrors.contains { $0.context == "Export" })
    }

    // MARK: - The popover is gone

    /// The popover's button passes no completion, and the popover itself is gone while the panel
    /// is open. The user still gets the answer.
    @Test func exportData_reportsWithoutAnyCaller() throws {
        let directory = try DataExportTests.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("late.csv")
        let clock = TestClock(2026, 11, 2, 9)
        let presenter = FakeExportPresenter()
        presenter.holdPanel = true
        let viewModel = makeViewModel(clock, presenter: presenter)

        viewModel.exportData(format: .recent24Hours)
        #expect(presenter.isPanelOpen)
        #expect(presenter.reports.isEmpty)
        presenter.finishPanel(with: url)

        #expect(presenter.reportedURLs == [url])
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func exportData_failureIsReportedWithoutAnyCaller() throws {
        let directory = try DataExportTests.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestClock(2026, 11, 2, 9)
        let presenter = FakeExportPresenter()
        presenter.holdPanel = true
        let viewModel = makeViewModel(clock, presenter: presenter)

        viewModel.exportData(format: .recent24Hours)
        presenter.finishPanel(with: directory.appendingPathComponent("missing").appendingPathComponent("x.csv"))

        #expect(presenter.reportedFailures == 1)
    }

    /// The file holds what the history and the unit were when the button was pressed, not what
    /// they became while the user chose a folder.
    @Test func exportData_holdsItsOwnData() throws {
        let directory = try DataExportTests.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("snapshot.csv")
        let clock = TestClock(2026, 11, 2, 9)
        let presenter = FakeExportPresenter()
        presenter.holdPanel = true
        let viewModel = makeViewModel(clock, presenter: presenter, points: 2)

        viewModel.exportData(format: .recent24Hours)
        // While the panel is open the history grows and the unit changes.
        for _ in 0..<5 {
            viewModel.historyRecorder.recordSpeed(speed(900))
            clock.advance(by: 10)
        }
        viewModel.preferences.displayUnit = .mbps_lower
        presenter.finishPanel(with: url)

        let lines = try rows(of: url)
        #expect(lines.count == 3)
        #expect(lines[1].contains(",100.00,100.00,"))
        #expect(lines[0].contains("Mbps"))
    }

    // MARK: - Monthly report

    private func monthlySummary(_ viewModel: NetworkMonitorViewModel, _ clock: TestClock) throws -> MonthlySummary {
        for _ in 0..<5 {
            viewModel.dailyStore.ingest(speed(10), planDownloadMbps: 300, planUploadMbps: 300)
            clock.advance(by: 1)
        }
        return try #require(viewModel.monthlyReportService.summary(for: "2026-11"))
    }

    @Test func exportMonthlyReport_writesTheReportAndReportsIt() throws {
        let directory = try DataExportTests.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("report.csv")
        let clock = TestClock(2026, 11, 2, 9)
        let presenter = FakeExportPresenter(destination: url)
        let viewModel = makeViewModel(clock, presenter: presenter)
        let summary = try monthlySummary(viewModel, clock)

        viewModel.exportMonthlyReport(summary)

        #expect(try String(contentsOf: url, encoding: .utf8) == viewModel.monthlyReportService.exportToCSV(summary))
        #expect(presenter.suggestedFilenames == ["monthly_report_2026-11.csv"])
        #expect(presenter.reportedURLs == [url])
    }

    @Test func exportMonthlyReport_failureIsReported() throws {
        let directory = try DataExportTests.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestClock(2026, 11, 2, 9)
        let presenter = FakeExportPresenter(
            destination: directory.appendingPathComponent("missing").appendingPathComponent("report.csv")
        )
        let viewModel = makeViewModel(clock, presenter: presenter)
        let summary = try monthlySummary(viewModel, clock)

        viewModel.exportMonthlyReport(summary)

        #expect(presenter.reportedFailures == 1)
    }

    @Test func exportMonthlyReport_cancelledSaysNothing() throws {
        let clock = TestClock(2026, 11, 2, 9)
        let presenter = FakeExportPresenter(destination: nil)
        let viewModel = makeViewModel(clock, presenter: presenter)
        let summary = try monthlySummary(viewModel, clock)

        viewModel.exportMonthlyReport(summary)

        #expect(presenter.reports.isEmpty)
    }

    // MARK: - Handing the focus back (final review F4)

    /// The save panel and the alert made the app active. When the export is over, whatever the
    /// outcome, the view model says so once, after the user has seen the result, so the focus
    /// can go back to the app the user was in.
    @Test func exportFinished_isAnnouncedOnceForEveryOutcome() throws {
        let directory = try DataExportTests.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outcomes: [(String, URL?)] = [
            ("cancel", nil),
            ("success", directory.appendingPathComponent("ok.csv")),
            ("failure", directory.appendingPathComponent("missing").appendingPathComponent("x.csv")),
        ]
        for (name, destination) in outcomes {
            let clock = TestClock(2026, 11, 2, 9)
            let presenter = FakeExportPresenter(destination: destination)
            presenter.holdPanel = true
            let viewModel = makeViewModel(clock, presenter: presenter)
            var reportsSeenAtFinish: [Int] = []
            viewModel.onExportFinished = { reportsSeenAtFinish.append(presenter.reports.count) }

            viewModel.exportData(format: .recent24Hours)
            #expect(reportsSeenAtFinish.isEmpty, "\(name): announced while the panel is open")

            presenter.finishPanel(with: destination)

            let expectedReports = destination == nil ? 0 : 1
            #expect(reportsSeenAtFinish == [expectedReports], "\(name)")
        }
    }
}
