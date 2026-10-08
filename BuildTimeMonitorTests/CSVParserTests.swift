import Foundation
import Testing
@testable import BuildTimeMonitor

struct CSVParserTests {
    private func fixture() throws -> String {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "build_times_fixture", withExtension: "csv"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func splitsQuotedFieldsWithCommasQuotesAndNewlines() {
        let rows = CSV.rows(in: "a,b,c\n\"1,2\",\"say \"\"hi\"\"\",\"line\nbreak\"\r\nx,,z")
        #expect(rows == [["a", "b", "c"], ["1,2", "say \"hi\"", "line\nbreak"], ["x", "", "z"]])
    }

    @Test func ignoresTrailingNewline() {
        #expect(CSV.rows(in: "a,b\n1,2\n") == [["a", "b"], ["1", "2"]])
    }

    @Test func parsesRecorderFixture() throws {
        let result = try BuildCSVParser.parse(fixture())
        #expect(result.records.count == 5)
        #expect(result.skippedRows == 1)

        let full = result.records[0]
        #expect(full.kind == .full)
        #expect(full.duration == 250)
        #expect(full.isCompleted)
        #expect(full.cpuCount == 12)
        #expect(full.xcodeVersionDisplay == "26.0")

        #expect(result.records[1].gitBranch == "feature/a, b")

        let failed = result.records[2]
        #expect(failed.isFailed)
        #expect(failed.duration == nil)
        #expect(failed.completedAt == nil)
        #expect(!failed.isCompleted)

        let noOp = result.records[3]
        #expect(noOp.isNoOp)
        #expect(noOp.gitBranch == "say \"hi\"")

        #expect(result.records[4].projectName == "OtherApp")
        #expect(result.records[4].xcodeVersionDisplay == "26.1")
    }

    @Test func headerOnlyFileHasNoRecords() throws {
        let result = try BuildCSVParser.parse("started_at,completed_at,duration_seconds,build_kind,status\n")
        #expect(result.records.isEmpty)
        #expect(result.skippedRows == 0)
    }

    @Test func emptyFileHasNoRecords() throws {
        #expect(try BuildCSVParser.parse("").records.isEmpty)
    }

    @Test func rejectsUnrelatedCSV() {
        #expect(throws: BuildCSVParser.ParseError.self) {
            try BuildCSVParser.parse("name,age\nbob,3\n")
        }
    }

    @Test func toleratesReorderedColumns() throws {
        let text = "status,build_kind,started_at,duration_seconds\n\"succeeded\",\"incremental\",\"2026-10-07T09:00:00+0100\",\"12\"\n"
        let record = try #require(try BuildCSVParser.parse(text).records.first)
        #expect(record.duration == 12)
        #expect(record.kind == .incremental)
    }
}

final class BundleToken {}

struct DateParsingTests {
    @Test func parsesOffsetWithoutColon() throws {
        let date = try #require(RecorderDate.parse("2026-10-08T11:13:00+0100"))
        #expect(date == Date(timeIntervalSince1970: 1_791_454_380))
    }

    @Test func parsesOffsetWithColonAndZulu() {
        #expect(RecorderDate.parse("2026-10-08T10:13:00Z") == Date(timeIntervalSince1970: 1_791_454_380))
        #expect(RecorderDate.parse("2026-10-08T11:13:00+01:00") == Date(timeIntervalSince1970: 1_791_454_380))
    }

    @Test func rejectsGarbage() {
        #expect(RecorderDate.parse("") == nil)
        #expect(RecorderDate.parse("yesterday") == nil)
    }
}
