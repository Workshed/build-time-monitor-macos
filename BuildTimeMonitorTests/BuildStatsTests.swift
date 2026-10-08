import Foundation
import Testing
@testable import BuildTimeMonitor

struct BuildStatsTests {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-10-08 12:00 UTC
    private let now = Date(timeIntervalSince1970: 1_791_460_800)

    private func build(
        id: Int,
        hoursAgo: Double,
        duration: TimeInterval?,
        kind: BuildKind = .incremental,
        project: String = "App",
        artifactUpdated: Bool? = true
    ) -> BuildRecord {
        let completed = now.addingTimeInterval(-hoursAgo * 3600)
        return BuildRecord(
            id: id,
            startedAt: completed.addingTimeInterval(-(duration ?? 0)),
            completedAt: duration == nil ? nil : completed,
            duration: duration,
            kind: kind,
            status: duration == nil ? .failedOrCancelled : .succeeded,
            artifactUpdated: duration == nil ? nil : artifactUpdated,
            scheme: project, configuration: "Debug", sdk: "", project: project,
            user: "", hostname: "", hardwareModel: "", cpuCount: nil,
            xcodeVersion: "", gitBranch: "", gitCommit: ""
        )
    }

    @Test func percentileInterpolates() {
        #expect(BuildStats.percentile([], 0.5) == nil)
        #expect(BuildStats.percentile([10], 0.9) == 10)
        #expect(BuildStats.percentile([1, 2, 3, 4], 0.5) == 2.5)
        #expect(BuildStats.percentile([40, 10, 30, 20, 50], 0.9) == 46)
    }

    @Test func summarySeparatesKindsAndExcludesNoOps() {
        let records = [
            build(id: 0, hoursAgo: 1, duration: 20),
            build(id: 1, hoursAgo: 2, duration: 40),
            build(id: 2, hoursAgo: 3, duration: 2, artifactUpdated: false),
            build(id: 3, hoursAgo: 4, duration: 300, kind: .full),
            build(id: 4, hoursAgo: 5, duration: nil),
        ]
        let summary = BuildStats.summary(records, excludeNoOps: true)
        #expect(summary.buildCount == 5)
        #expect(summary.failedCount == 1)
        #expect(summary.completedCount == 4)
        #expect(summary.averageIncremental == 30)
        #expect(summary.averageFull == 300)
        #expect(summary.totalBuildTime == 362)
        #expect(summary.failureRate == 0.2)

        let withNoOps = BuildStats.summary(records, excludeNoOps: false)
        #expect(withNoOps.averageIncremental == 62.0 / 3)
    }

    @Test func chartableFiltersRangeKindProjectAndNoOps() {
        let records = [
            build(id: 0, hoursAgo: 1, duration: 20),
            build(id: 1, hoursAgo: 30, duration: 25),
            build(id: 2, hoursAgo: 2, duration: 300, kind: .full),
            build(id: 3, hoursAgo: 3, duration: 2, artifactUpdated: false),
            build(id: 4, hoursAgo: 4, duration: nil),
            build(id: 5, hoursAgo: 5, duration: 15, project: "Other"),
        ]
        let filter = BuildFilter(range: .day, kind: .incremental, project: "App", excludeNoOps: true)
        let ids = BuildStats.chartable(records, filter: filter, now: now, calendar: calendar).map(\.id)
        #expect(ids == [0])
    }

    @Test func dailyBucketsUseMedianPerSeries() {
        let records = [
            build(id: 0, hoursAgo: 1, duration: 10),
            build(id: 1, hoursAgo: 2, duration: 20),
            build(id: 2, hoursAgo: 3, duration: 90),
            build(id: 3, hoursAgo: 25, duration: 40),
            build(id: 4, hoursAgo: 1, duration: 5, project: "B"),
        ]
        let points = BuildStats.durationPoints(records, bucket: .day, seriesName: { $0 }, calendar: calendar)
        #expect(points.count == 3)
        let today = points.first { $0.series == "App" && $0.count == 3 }
        #expect(today?.value == 20)
        #expect(today?.min == 10)
        #expect(today?.max == 90)
        #expect(today?.build == nil)
    }

    @Test func unbucketedPointsAreIndividualBuilds() {
        let records = [build(id: 7, hoursAgo: 1, duration: 10)]
        let points = BuildStats.durationPoints(records, bucket: nil, seriesName: { $0 }, calendar: calendar)
        #expect(points.map(\.build?.id) == [7])
    }

    @Test func failureBucketsCoverWholeRange() {
        let records = [
            build(id: 0, hoursAgo: 1, duration: nil),
            build(id: 1, hoursAgo: 2, duration: nil),
            build(id: 2, hoursAgo: 3, duration: 10),
            build(id: 3, hoursAgo: 49, duration: nil),
        ]
        let buckets = BuildStats.failureBuckets(records, range: .week, now: now, calendar: calendar)
        #expect(buckets.count == 8) // partial first day through today
        #expect(buckets.last?.failed == 2)
        #expect(buckets.last?.succeeded == 1)
        #expect(buckets.map(\.failed).reduce(0, +) == 3)
    }

    @Test func failureTallyByCalendarPeriod() {
        let records = [
            build(id: 0, hoursAgo: 1, duration: nil),            // today
            build(id: 1, hoursAgo: 24 * 3, duration: nil),       // this month
            build(id: 2, hoursAgo: 24 * 40, duration: nil),      // this year
            build(id: 3, hoursAgo: 24 * 400, duration: nil),     // last year
            build(id: 4, hoursAgo: 1, duration: 10),             // not failed
        ]
        let tally = BuildStats.failureTally(records, now: now, calendar: calendar)
        #expect(tally == FailureTally(today: 1, thisMonth: 2, thisYear: 3))
    }

    @Test func groupStatsPerProjectAndScheme() {
        let records = [
            build(id: 0, hoursAgo: 1, duration: 10),
            build(id: 1, hoursAgo: 2, duration: 30),
            build(id: 2, hoursAgo: 3, duration: nil),
            build(id: 3, hoursAgo: 1, duration: 100, kind: .full, project: "B"),
        ]
        let stats = BuildStats.groupStats(records, excludeNoOps: true)
        #expect(stats.map(\.project) == ["B", "App"]) // sorted by total time
        let app = stats[1]
        #expect(app.builds == 3)
        #expect(app.failed == 1)
        #expect(app.medianIncremental == 20)
        #expect(app.medianFull == nil)
    }

    @Test func histogramBinsEveryDuration() {
        let bins = BuildStats.histogram([1, 5, 9, 59, 60], targetBins: 6)
        #expect(bins.map(\.count).reduce(0, +) == 5)
        #expect(bins.first?.lower == 0)
    }

    @Test func paletteFoldsNinthProjectIntoOther() {
        let projects = (1...9).map { "P\($0)" }
        #expect(ProjectPalette.seriesName(for: "P8", in: projects) == "P8")
        #expect(ProjectPalette.seriesName(for: "P9", in: projects) == "Other")
        #expect(ProjectPalette.seriesDomain(for: projects).count == 9)
        #expect(ProjectPalette.colors(for: projects).count == 9)
    }

    @Test func durationFormatting() {
        #expect(DurationFormat.short(42) == "42s")
        #expect(DurationFormat.short(90) == "1m 30s")
        #expect(DurationFormat.short(120) == "2m")
        #expect(DurationFormat.short(3900) == "1h 05m")
        #expect(DurationFormat.short(nil) == "–")
        #expect(DurationFormat.total(11_520) == "3h 12m")
        #expect(ChartAxes.durationTicks(maxValue: 50, targetCount: 4) == [0, 15, 30, 45, 60])
    }
}
