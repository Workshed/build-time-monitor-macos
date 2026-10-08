import Foundation

enum TimeRange: String, CaseIterable, Identifiable, Sendable {
    case day = "24h"
    case week = "7d"
    case month = "30d"
    case year = "1y"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: "24 hours"
        case .week: "7 days"
        case .month: "30 days"
        case .year: "Year"
        }
    }

    func interval(endingAt now: Date, calendar: Calendar = .current) -> DateInterval {
        let start: Date = switch self {
        case .day: now.addingTimeInterval(-24 * 3600)
        case .week: calendar.date(byAdding: .day, value: -7, to: now)!
        case .month: calendar.date(byAdding: .day, value: -30, to: now)!
        case .year: calendar.date(byAdding: .year, value: -1, to: now)!
        }
        return DateInterval(start: start, end: now)
    }

    /// How the duration chart aggregates: nil plots each build individually.
    var durationBucket: Calendar.Component? {
        switch self {
        case .day, .week: nil
        case .month: .day
        case .year: .weekOfYear
        }
    }

    /// Bucket size for the failures strip.
    var failureBucket: Calendar.Component {
        switch self {
        case .day: .hour
        case .week, .month: .day
        case .year: .month
        }
    }
}

struct BuildFilter: Sendable, Equatable {
    var range: TimeRange = .week
    var kind: BuildKind? = .incremental
    var project: String? = nil
    var excludeNoOps = true
}

/// A point on the duration chart: either a single build or an aggregate bucket.
struct DurationPoint: Identifiable, Sendable, Hashable {
    let id: String
    let series: String
    let date: Date
    /// Median for buckets, the build's duration for single builds.
    let value: TimeInterval
    let count: Int
    let min: TimeInterval
    let max: TimeInterval
    let bucket: Calendar.Component?
    let build: BuildRecord?
}

/// Smoothed trend line through individual builds.
struct TrendPoint: Identifiable, Sendable, Hashable {
    var id: String { "\(series)|\(date.timeIntervalSinceReferenceDate)" }
    let series: String
    let date: Date
    let value: TimeInterval
}

struct FailureBucket: Identifiable, Sendable, Hashable {
    var id: Date { date }
    let date: Date
    let failed: Int
    let succeeded: Int

    var total: Int { failed + succeeded }
}

struct BuildSummary: Sendable, Equatable {
    var buildCount = 0
    var completedCount = 0
    var failedCount = 0
    var averageIncremental: TimeInterval?
    var averageFull: TimeInterval?
    var medianIncremental: TimeInterval?
    var medianFull: TimeInterval?
    var totalBuildTime: TimeInterval = 0
    var incrementalCount = 0
    var fullCount = 0

    var failureRate: Double? {
        buildCount == 0 ? nil : Double(failedCount) / Double(buildCount)
    }
}

struct FailureTally: Sendable, Equatable {
    var today = 0
    var thisMonth = 0
    var thisYear = 0
}

struct GroupStats: Identifiable, Sendable, Hashable {
    var id: String { "\(project)|\(scheme)" }
    let project: String
    let scheme: String
    let builds: Int
    let failed: Int
    let medianIncremental: TimeInterval?
    let p90Incremental: TimeInterval?
    let medianFull: TimeInterval?
    let p90Full: TimeInterval?
    let totalTime: TimeInterval

    var failureRate: Double { builds == 0 ? 0 : Double(failed) / Double(builds) }
}

struct HistogramBin: Identifiable, Sendable, Hashable {
    var id: Double { lower }
    let lower: TimeInterval
    let upper: TimeInterval
    let count: Int
}

enum BuildStats {
    // MARK: Filtering

    static func inRange(_ records: [BuildRecord], _ range: TimeRange, now: Date, calendar: Calendar = .current) -> [BuildRecord] {
        let interval = range.interval(endingAt: now, calendar: calendar)
        return records.filter { interval.contains($0.plotDate) }
    }

    /// Builds that belong on the duration chart: completed, matching kind/project.
    static func chartable(_ records: [BuildRecord], filter: BuildFilter, now: Date, calendar: Calendar = .current) -> [BuildRecord] {
        inRange(records, filter.range, now: now, calendar: calendar).filter { record in
            record.isCompleted
                && (filter.kind == nil || record.kind == filter.kind)
                && (filter.project == nil || record.projectName == filter.project)
                && !(filter.excludeNoOps && record.isNoOp)
        }
    }

    // MARK: Summary

    static func summary(_ records: [BuildRecord], excludeNoOps: Bool) -> BuildSummary {
        var summary = BuildSummary()
        var incremental: [TimeInterval] = []
        var full: [TimeInterval] = []
        for record in records {
            summary.buildCount += 1
            if record.isFailed {
                summary.failedCount += 1
                continue
            }
            guard let duration = record.duration else { continue }
            summary.completedCount += 1
            summary.totalBuildTime += duration
            if excludeNoOps && record.isNoOp { continue }
            switch record.kind {
            case .incremental: incremental.append(duration)
            case .full: full.append(duration)
            }
        }
        summary.incrementalCount = incremental.count
        summary.fullCount = full.count
        summary.averageIncremental = mean(incremental)
        summary.averageFull = mean(full)
        summary.medianIncremental = percentile(incremental, 0.5)
        summary.medianFull = percentile(full, 0.5)
        return summary
    }

    static func failureTally(_ records: [BuildRecord], now: Date, calendar: Calendar = .current) -> FailureTally {
        var tally = FailureTally()
        for record in records where record.isFailed {
            let date = record.plotDate
            guard date <= now else { continue }
            if calendar.isDate(date, equalTo: now, toGranularity: .year) {
                tally.thisYear += 1
                if calendar.isDate(date, equalTo: now, toGranularity: .month) {
                    tally.thisMonth += 1
                    if calendar.isDate(date, inSameDayAs: now) {
                        tally.today += 1
                    }
                }
            }
        }
        return tally
    }

    // MARK: Series

    static func durationPoints(
        _ records: [BuildRecord],
        bucket: Calendar.Component?,
        seriesName: (String) -> String,
        calendar: Calendar = .current
    ) -> [DurationPoint] {
        guard let bucket else {
            return records.compactMap { record in
                guard let duration = record.duration else { return nil }
                return DurationPoint(
                    id: "b\(record.id)", series: seriesName(record.projectName), date: record.plotDate,
                    value: duration, count: 1, min: duration, max: duration, bucket: nil, build: record
                )
            }
        }

        struct Key: Hashable { let series: String; let start: Date }
        var groups: [Key: [TimeInterval]] = [:]
        for record in records {
            guard let duration = record.duration,
                  let start = calendar.dateInterval(of: bucket, for: record.plotDate)?.start else { continue }
            groups[Key(series: seriesName(record.projectName), start: start), default: []].append(duration)
        }
        return groups.map { key, durations in
            DurationPoint(
                id: "\(key.series)|\(key.start.timeIntervalSinceReferenceDate)",
                series: key.series,
                // Centre the point in its bucket so it lines up with axis labels.
                date: calendar.dateInterval(of: bucket, for: key.start).map { $0.start.addingTimeInterval($0.duration / 2) } ?? key.start,
                value: percentile(durations, 0.5) ?? 0,
                count: durations.count,
                min: durations.min() ?? 0,
                max: durations.max() ?? 0,
                bucket: bucket,
                build: nil
            )
        }
        .sorted { ($0.series, $0.date) < ($1.series, $1.date) }
    }

    /// Rolling median over the last `window` builds of each series (only for
    /// unbucketed points; buckets are already medians).
    static func trend(_ points: [DurationPoint], window: Int = 7) -> [TrendPoint] {
        let bySeries = Dictionary(grouping: points.filter { $0.bucket == nil }, by: \.series)
        return bySeries.flatMap { series, seriesPoints in
            let sorted = seriesPoints.sorted { $0.date < $1.date }
            return sorted.indices.map { index in
                let slice = sorted[Swift.max(0, index - window + 1)...index].map(\.value)
                return TrendPoint(series: series, date: sorted[index].date, value: percentile(slice, 0.5) ?? 0)
            }
        }
        .sorted { ($0.series, $0.date) < ($1.series, $1.date) }
    }

    static func failureBuckets(
        _ records: [BuildRecord],
        range: TimeRange,
        now: Date,
        calendar: Calendar = .current
    ) -> [FailureBucket] {
        let component = range.failureBucket
        let interval = range.interval(endingAt: now, calendar: calendar)
        var failed: [Date: Int] = [:]
        var succeeded: [Date: Int] = [:]
        for record in records where interval.contains(record.plotDate) {
            guard let start = calendar.dateInterval(of: component, for: record.plotDate)?.start else { continue }
            if record.isFailed {
                failed[start, default: 0] += 1
            } else if record.isCompleted {
                succeeded[start, default: 0] += 1
            }
        }
        // Emit every bucket in the range so empty periods render as gaps, not missing bars.
        var buckets: [FailureBucket] = []
        guard var cursor = calendar.dateInterval(of: component, for: interval.start)?.start else { return [] }
        while cursor <= now {
            buckets.append(FailureBucket(date: cursor, failed: failed[cursor] ?? 0, succeeded: succeeded[cursor] ?? 0))
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor) else { break }
            cursor = next
        }
        return buckets
    }

    static func groupStats(_ records: [BuildRecord], excludeNoOps: Bool) -> [GroupStats] {
        let grouped = Dictionary(grouping: records) { "\($0.projectName)|\($0.scheme)" }
        return grouped.values.compactMap { group in
            guard let first = group.first else { return nil }
            let completed = group.filter { $0.isCompleted && !(excludeNoOps && $0.isNoOp) }
            let incremental = completed.filter { $0.kind == .incremental }.compactMap(\.duration)
            let full = completed.filter { $0.kind == .full }.compactMap(\.duration)
            return GroupStats(
                project: first.projectName,
                scheme: first.scheme,
                builds: group.count,
                failed: group.filter(\.isFailed).count,
                medianIncremental: percentile(incremental, 0.5),
                p90Incremental: percentile(incremental, 0.9),
                medianFull: percentile(full, 0.5),
                p90Full: percentile(full, 0.9),
                totalTime: group.compactMap(\.duration).reduce(0, +)
            )
        }
        .sorted { $0.totalTime > $1.totalTime }
    }

    static func histogram(_ durations: [TimeInterval], targetBins: Int = 20) -> [HistogramBin] {
        guard let maxValue = durations.max(), maxValue > 0 else { return [] }
        let width = niceBinWidth(maxValue / Double(targetBins))
        let binCount = Int((maxValue / width).rounded(.down)) + 1
        var counts = Array(repeating: 0, count: binCount)
        for duration in durations {
            counts[min(Int(duration / width), binCount - 1)] += 1
        }
        return counts.enumerated().map { index, count in
            HistogramBin(lower: Double(index) * width, upper: Double(index + 1) * width, count: count)
        }
    }

    // MARK: Maths

    static func mean(_ values: [TimeInterval]) -> TimeInterval? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Linear-interpolated percentile, p in 0...1.
    static func percentile(_ values: [TimeInterval], _ p: Double) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Swift.min(lower + 1, sorted.count - 1)
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    private static func niceBinWidth(_ raw: Double) -> Double {
        let steps: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]
        return steps.first { $0 >= raw } ?? (raw / 3600).rounded(.up) * 3600
    }
}
