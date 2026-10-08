import Foundation

enum BuildKind: String, Sendable, CaseIterable, Identifiable {
    case incremental
    case full

    var id: String { rawValue }

    var label: String {
        switch self {
        case .incremental: "Incremental"
        case .full: "Full"
        }
    }
}

enum BuildStatus: String, Sendable {
    case succeeded
    case failedOrCancelled = "failed-or-cancelled"
}

/// One row of the CSV written by xcode-build-time-recorder.
struct BuildRecord: Identifiable, Sendable, Hashable {
    /// Row index in the file; stable while the file is append-only.
    let id: Int
    let startedAt: Date
    let completedAt: Date?
    let duration: TimeInterval?
    let kind: BuildKind
    let status: BuildStatus
    let artifactUpdated: Bool?
    let scheme: String
    let configuration: String
    let sdk: String
    let project: String
    let user: String
    let hostname: String
    let hardwareModel: String
    let cpuCount: Int?
    let xcodeVersion: String
    let gitBranch: String
    let gitCommit: String

    var isCompleted: Bool { status == .succeeded && duration != nil }
    var isFailed: Bool { status == .failedOrCancelled }

    /// Nothing changed: the product wasn't rebuilt.
    var isNoOp: Bool { isCompleted && artifactUpdated == false }

    /// The time the build is plotted at (its completion when known).
    var plotDate: Date { completedAt ?? startedAt }

    /// "1620" -> "16.2", "2600" -> "26.0", "2610" -> "26.1".
    var xcodeVersionDisplay: String {
        guard let value = Int(xcodeVersion), value >= 100 else { return xcodeVersion }
        let major = value / 100
        let minor = (value % 100) / 10
        let patch = value % 10
        return patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }

    /// Display name used for grouping; empty project names fall back to scheme.
    var projectName: String { project.isEmpty ? (scheme.isEmpty ? "Unknown" : scheme) : project }
}
