import Foundation

/// Everything the popover/detail views display for one filter, derived in one pass.
struct Dashboard {
    let filter: BuildFilter
    let domain: DateInterval
    /// All builds in range for the selected project (any kind/status).
    let inRange: [BuildRecord]
    let summary: BuildSummary
    let points: [DurationPoint]
    let failures: [FailureBucket]
    let tally: FailureTally

    init(records: [BuildRecord], projects: [String], filter: BuildFilter, now: Date, calendar: Calendar = .current) {
        self.filter = filter
        domain = filter.range.interval(endingAt: now, calendar: calendar)
        let projectRecords = filter.project.map { project in records.filter { $0.projectName == project } } ?? records
        inRange = BuildStats.inRange(projectRecords, filter.range, now: now, calendar: calendar)
        summary = BuildStats.summary(inRange, excludeNoOps: filter.excludeNoOps)
        points = BuildStats.durationPoints(
            BuildStats.chartable(projectRecords, filter: filter, now: now, calendar: calendar),
            bucket: filter.range.durationBucket,
            seriesName: { ProjectPalette.seriesName(for: $0, in: projects) },
            calendar: calendar
        )
        failures = BuildStats.failureBuckets(projectRecords, range: filter.range, now: now, calendar: calendar)
        tally = BuildStats.failureTally(projectRecords, now: now, calendar: calendar)
    }
}
