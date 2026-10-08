import Foundation

enum ChartAxes {
    /// Evenly spaced duration ticks at human-friendly steps (15s, 30s, 1m, 5m…).
    static func durationTicks(maxValue: TimeInterval, targetCount: Int = 4) -> [TimeInterval] {
        let steps: [TimeInterval] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200]
        let upper = max(maxValue, 1)
        let step = steps.first { upper / $0 <= Double(targetCount) } ?? (upper / Double(targetCount)).rounded(.up)
        let top = (upper / step).rounded(.up) * step
        return stride(from: 0, through: top, by: step).map { $0 }
    }

    static func dateFormat(for range: TimeRange) -> Date.FormatStyle {
        switch range {
        case .day: .dateTime.hour()
        case .week: .dateTime.weekday(.abbreviated)
        case .month: .dateTime.day().month(.abbreviated)
        case .year: .dateTime.month(.abbreviated)
        }
    }
}
