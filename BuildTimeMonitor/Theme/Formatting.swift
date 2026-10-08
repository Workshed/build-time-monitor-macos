import Foundation

enum DurationFormat {
    /// Compact duration: "42s", "1m 30s", "1h 05m".
    static func short(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "–" }
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        return secs == 0 ? "\(minutes)m" : String(format: "%dm %02ds", minutes, secs)
    }

    /// Coarser form for totals: "3h 12m", "45m", "20s".
    static func total(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Axis ticks: whole units only.
    static func axis(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total == 0 { return "0" }
        if total < 60 { return "\(total)s" }
        if total % 60 == 0 && total < 3600 { return "\(total / 60)m" }
        return short(seconds)
    }
}

enum PercentFormat {
    static func string(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value.formatted(.percent.precision(.fractionLength(0)))
    }
}
