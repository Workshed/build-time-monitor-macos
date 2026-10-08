import Foundation

/// Minimal RFC 4180 CSV reader: quoted fields, `""` escapes, embedded commas
/// and newlines, CRLF or LF line endings.
enum CSV {
    static func rows(in text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = nil

        func next() -> Unicode.Scalar? {
            if let scalar = pending { pending = nil; return scalar }
            return iterator.next()
        }

        while let scalar = next() {
            if inQuotes {
                if scalar == "\"" {
                    if let following = next() {
                        if following == "\"" {
                            field.unicodeScalars.append("\"")
                        } else {
                            inQuotes = false
                            pending = following
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                }
                continue
            }
            switch scalar {
            case "\"":
                inQuotes = true
            case ",":
                row.append(field)
                field = ""
            case "\r":
                break
            case "\n":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            default:
                field.unicodeScalars.append(scalar)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

struct ParseResult: Sendable {
    var records: [BuildRecord]
    var skippedRows: Int
}

enum BuildCSVParser {
    enum ParseError: LocalizedError {
        case missingColumns([String])

        var errorDescription: String? {
            switch self {
            case .missingColumns(let columns):
                "This doesn't look like a build times CSV (missing \(columns.joined(separator: ", ")))."
            }
        }
    }

    static let requiredColumns = ["started_at", "build_kind", "status"]

    static func parse(_ text: String) throws -> ParseResult {
        let rows = CSV.rows(in: text).filter { !($0.count == 1 && $0[0].isEmpty) }
        guard let header = rows.first else { return ParseResult(records: [], skippedRows: 0) }

        var index: [String: Int] = [:]
        for (position, name) in header.enumerated() {
            index[name.trimmingCharacters(in: .whitespaces).lowercased()] = position
        }
        let missing = requiredColumns.filter { index[$0] == nil }
        guard missing.isEmpty else { throw ParseError.missingColumns(missing) }

        var records: [BuildRecord] = []
        records.reserveCapacity(rows.count)
        var skipped = 0

        for (rowNumber, row) in rows.dropFirst().enumerated() {
            func value(_ column: String) -> String {
                guard let position = index[column], position < row.count else { return "" }
                return row[position].trimmingCharacters(in: .whitespaces)
            }
            guard
                let startedAt = RecorderDate.parse(value("started_at")),
                let kind = BuildKind(rawValue: value("build_kind")),
                let status = BuildStatus(rawValue: value("status"))
            else {
                skipped += 1
                continue
            }
            let artifact: Bool? = switch value("artifact_updated") {
            case "yes": true
            case "no": false
            default: nil
            }
            records.append(BuildRecord(
                id: rowNumber,
                startedAt: startedAt,
                completedAt: RecorderDate.parse(value("completed_at")),
                duration: TimeInterval(value("duration_seconds")),
                kind: kind,
                status: status,
                artifactUpdated: artifact,
                scheme: value("scheme"),
                configuration: value("configuration"),
                sdk: value("sdk"),
                project: value("project"),
                user: value("user"),
                hostname: value("hostname"),
                hardwareModel: value("hardware_model"),
                cpuCount: Int(value("cpu_count")),
                xcodeVersion: value("xcode_version"),
                gitBranch: value("git_branch"),
                gitCommit: value("git_commit")
            ))
        }
        return ParseResult(records: records, skippedRows: skipped)
    }
}
