import Testing
import Foundation
@testable import BandwidthECGFeature

@Suite("DailyRecord")
struct DailyRecordTests {

    @Test func isCounted_boundary() {
        var record = DailyRecord(dayKey: "2026-11-02")
        record.sampleCount = 599
        #expect(record.isCounted == false)
        record.sampleCount = 600
        #expect(record.isCounted)
    }

    @Test func decode_missingFields_defaultsToZero() throws {
        let record = try JSONDecoder().decode(DailyRecord.self, from: Data(#"{"dayKey":"2026-11-02"}"#.utf8))

        #expect(record == DailyRecord(dayKey: "2026-11-02"))
        #expect(record.sustainedPeakDownloadTime == nil)
        #expect(record.sustainedPeakUploadTime == nil)
    }

    @Test func decode_missingDayKey_throws() {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(DailyRecord.self, from: Data(#"{"sampleCount":5}"#.utf8))
        }
    }

    /// A record written before the peak times existed keeps every other value.
    @Test func decode_recordWithoutPeakTimes_keepsItsValues() throws {
        let json = #"{"dayKey":"2026-11-02","sustainedPeakDownloadMbps":280,"sustainedPeakUploadMbps":90,"sampleCount":700}"#

        let record = try JSONDecoder().decode(DailyRecord.self, from: Data(json.utf8))

        #expect(record.sustainedPeakDownloadMbps == 280)
        #expect(record.sustainedPeakUploadMbps == 90)
        #expect(record.sampleCount == 700)
        #expect(record.sustainedPeakDownloadTime == nil)
        #expect(record.sustainedPeakUploadTime == nil)
    }

    @Test func codable_roundTripKeepsEveryField() throws {
        var record = DailyRecord(dayKey: "2026-11-02")
        record.sustainedPeakDownloadMbps = 280
        record.sustainedPeakUploadMbps = 90
        record.sustainedPeakDownloadTime = Date(timeIntervalSince1970: 1_793_580_645.25)
        record.sustainedPeakUploadTime = Date(timeIntervalSince1970: 1_793_580_700.5)
        record.downloadSum = 1
        record.uploadSum = 2
        record.sampleCount = 3
        record.approachCount = 4
        record.latencySum = 5
        record.latencyCount = 6
        record.latencyFailures = 7
        record.jitterSum = 8
        record.jitterCount = 9
        record.disconnectCount = 10
        record.downtimeSeconds = 11
        record.planDownloadMbps = 300
        record.planUploadMbps = 100

        let decoded = try JSONDecoder().decode(DailyRecord.self, from: JSONEncoder().encode(record))

        #expect(decoded == record)
    }

    @Test func peakRatios_useThatDaysPlan() {
        var record = DailyRecord(dayKey: "2026-11-02", planDownloadMbps: 300, planUploadMbps: 100)
        record.sustainedPeakDownloadMbps = 150
        record.sustainedPeakUploadMbps = 25

        #expect(record.downloadPeakRatio == 0.5)
        #expect(record.uploadPeakRatio == 0.25)
    }

    @Test func peakRatios_withoutAPlan_areZero() {
        var record = DailyRecord(dayKey: "2026-11-02")
        record.sustainedPeakDownloadMbps = 150
        record.sustainedPeakUploadMbps = 25

        #expect(record.downloadPeakRatio == 0)
        #expect(record.uploadPeakRatio == 0)
    }

    @Test func isSaturated_needsMoreThanTheRatioInEitherDirection() {
        var record = DailyRecord(dayKey: "2026-11-02", planDownloadMbps: 300, planUploadMbps: 300)
        record.sustainedPeakDownloadMbps = 270
        record.sustainedPeakUploadMbps = 270
        #expect(record.isSaturated == false)

        record.sustainedPeakDownloadMbps = 271
        #expect(record.isSaturated)

        record.sustainedPeakDownloadMbps = 0
        record.sustainedPeakUploadMbps = 271
        #expect(record.isSaturated)
    }
}
