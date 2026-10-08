import SwiftUI

struct BuildsTableView: View {
    let records: [BuildRecord]
    let projects: [String]

    @State private var sortOrder = [KeyPathComparator(\BuildRecord.plotDate, order: .reverse)]
    @State private var selection: BuildRecord.ID?
    @State private var statusFilter: StatusFilter = .all

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case succeeded = "Succeeded"
        case failed = "Failed"
        var id: String { rawValue }
    }

    private var rows: [BuildRecord] {
        records
            .filter { record in
                switch statusFilter {
                case .all: true
                case .succeeded: record.isCompleted
                case .failed: record.isFailed
                }
            }
            .sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Status", selection: $statusFilter) {
                    ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Text("\(rows.count.formatted()) builds")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Time", value: \.plotDate) { record in
                    Text(record.plotDate.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                        .monospacedDigit()
                }
                .width(min: 110, ideal: 120)
                TableColumn("Project", value: \.projectName) { record in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ProjectPalette.color(for: record.projectName, in: projects))
                            .frame(width: 8, height: 8)
                        Text(record.projectName)
                    }
                }
                TableColumn("Scheme", value: \.scheme)
                TableColumn("Kind", value: \.kind.rawValue) { record in
                    Text(record.kind.label)
                }
                .width(min: 70, ideal: 80)
                TableColumn("Status", value: \.statusSortKey) { record in
                    if record.isFailed {
                        Label("Failed", systemImage: "xmark.octagon.fill")
                            .foregroundStyle(StatusColor.critical)
                    } else if record.isNoOp {
                        Label("No-op", systemImage: "equal.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Succeeded", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 90, ideal: 100)
                TableColumn("Duration", value: \.durationSortKey) { record in
                    Text(DurationFormat.short(record.duration))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 64, ideal: 72)
                TableColumn("Branch", value: \.gitBranch) { record in
                    Text(record.gitCommit.isEmpty ? record.gitBranch : "\(record.gitBranch) @ \(record.gitCommit)")
                        .foregroundStyle(.secondary)
                }
                TableColumn("Config", value: \.configuration) { record in
                    Text([record.configuration, record.sdk].filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
                TableColumn("Machine", value: \.hostname) { record in
                    Text([record.user, record.hostname].filter { !$0.isEmpty }.joined(separator: "@"))
                        .foregroundStyle(.secondary)
                        .help([record.hardwareModel, record.cpuCount.map { "\($0) cores" } ?? "", record.xcodeVersion.isEmpty ? "" : "Xcode \(record.xcodeVersionDisplay)"].filter { !$0.isEmpty }.joined(separator: " · "))
                }
            }
        }
    }
}

extension BuildRecord {
    var durationSortKey: Double { duration ?? -1 }
    var statusSortKey: Int { isFailed ? 0 : (isNoOp ? 1 : 2) }
}
