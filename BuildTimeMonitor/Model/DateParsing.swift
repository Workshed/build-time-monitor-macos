import Foundation

enum RecorderDate {
    /// The recorder writes `date +"%Y-%m-%dT%H:%M:%S%z"`, e.g. `2026-10-08T11:13:00+0100`.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()

    static func parse(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return formatter.date(from: trimmed) ?? (try? Date(trimmed, strategy: .iso8601))
    }
}
