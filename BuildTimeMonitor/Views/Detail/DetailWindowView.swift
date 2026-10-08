import SwiftUI

struct DetailWindowView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case builds = "Builds"
        var id: String { rawValue }
    }

    @Environment(BuildStore.self) private var store
    @AppStorage(SettingsKey.timeRange) private var range: TimeRange = .week
    @AppStorage(SettingsKey.buildKind) private var kind: BuildKind = .incremental
    @AppStorage(SettingsKey.excludeNoOps) private var excludeNoOps = true
    @State private var project: String?
    @State private var tab: Tab = .overview

    var body: some View {
        NavigationSplitView {
            ProjectSidebar(selection: $project)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let dashboard = Dashboard(
                    records: store.records,
                    projects: store.projects,
                    filter: BuildFilter(range: range, kind: kind, project: project, excludeNoOps: excludeNoOps),
                    now: context.date
                )
                switch tab {
                case .overview:
                    OverviewView(dashboard: dashboard, range: range, kind: kind)
                case .builds:
                    BuildsTableView(records: dashboard.inRange, projects: store.projects)
                }
            }
            .navigationTitle(project ?? "All Projects")
            .navigationSubtitle("Last \(range.label)")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Picker("Range", selection: $range) {
                        ForEach(TimeRange.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                    if tab == .overview {
                        Picker("Kind", selection: $kind) {
                            ForEach(BuildKind.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
        }
        .onChange(of: store.projects) { _, projects in
            if let project, !projects.contains(project) { self.project = nil }
        }
        .frame(minWidth: 820, minHeight: 560)
    }
}

private struct ProjectSidebar: View {
    @Environment(BuildStore.self) private var store
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            Label("All Projects", systemImage: "square.stack.3d.up")
                .tag(String?.none)
            Section("Projects") {
                ForEach(store.projects, id: \.self) { project in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(ProjectPalette.color(for: project, in: store.projects))
                            .frame(width: 9, height: 9)
                        Text(project).lineLimit(1)
                        Spacer()
                        Text(count(for: project).formatted())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .tag(String?.some(project))
                }
            }
        }
    }

    private func count(for project: String) -> Int {
        store.records.reduce(0) { $0 + ($1.projectName == project ? 1 : 0) }
    }
}

private struct OverviewView: View {
    @Environment(BuildStore.self) private var store
    let dashboard: Dashboard
    let range: TimeRange
    let kind: BuildKind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StatTilesView(summary: dashboard.summary, columns: 4)

                Card {
                    SectionTitle(
                        title: "\(kind.label) build time",
                        detail: range.durationBucket == nil ? "each build · hover for details" : "\(range.durationBucket == .day ? "daily" : "weekly") median · hover for details"
                    )
                    if dashboard.points.isEmpty {
                        placeholder("No completed \(kind.label.lowercased()) builds in this period.")
                            .frame(height: 320)
                    } else {
                        BuildDurationChart(
                            points: dashboard.points,
                            projects: store.projects,
                            range: range,
                            domain: dashboard.domain,
                            compact: false
                        )
                        .frame(height: 320)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    Card {
                        SectionTitle(title: "Distribution", detail: "\(kind.label.lowercased()) builds")
                        let source = histogramSource
                        if source.isEmpty {
                            placeholder("No builds").frame(height: 160)
                        } else {
                            DurationHistogram(
                                bins: BuildStats.histogram(source),
                                color: dashboard.filter.project.map { ProjectPalette.color(for: $0, in: store.projects) } ?? ProjectPalette.slots[0]
                            )
                            .frame(height: 160)
                        }
                    }
                    Card {
                        SectionTitle(title: "Failed or cancelled", detail: nil)
                        FailureChart(buckets: dashboard.failures, range: range, height: 130)
                        HStack(spacing: 14) {
                            tally("Today", dashboard.tally.today)
                            tally("This month", dashboard.tally.thisMonth)
                            tally("This year", dashboard.tally.thisYear)
                        }
                        .font(.caption)
                    }
                }

                Card {
                    SectionTitle(title: "By project and scheme", detail: "last \(range.label)")
                    GroupStatsGrid(stats: BuildStats.groupStats(dashboard.inRange, excludeNoOps: dashboard.filter.excludeNoOps), projects: store.projects)
                }
            }
            .padding(20)
        }
    }

    /// Raw builds (chart points may be bucket medians).
    private var histogramSource: [TimeInterval] {
        dashboard.inRange
            .filter { $0.isCompleted && $0.kind == kind && !(dashboard.filter.excludeNoOps && $0.isNoOp) }
            .compactMap(\.duration)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tally(_ title: String, _ count: Int) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(count.formatted()).fontWeight(.semibold).monospacedDigit()
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

private struct GroupStatsGrid: View {
    let stats: [GroupStats]
    let projects: [String]

    var body: some View {
        if stats.isEmpty {
            Text("No builds in this period.").foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    Text("Project / scheme")
                    Text("Builds").gridColumnAlignment(.trailing)
                    Text("Failed").gridColumnAlignment(.trailing)
                    Text("Incr. median").gridColumnAlignment(.trailing)
                    Text("Incr. p90").gridColumnAlignment(.trailing)
                    Text("Full median").gridColumnAlignment(.trailing)
                    Text("Full p90").gridColumnAlignment(.trailing)
                    Text("Total time").gridColumnAlignment(.trailing)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                Divider()
                ForEach(stats) { row in
                    GridRow {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(ProjectPalette.color(for: row.project, in: projects))
                                .frame(width: 8, height: 8)
                            Text(row.project)
                            if !row.scheme.isEmpty && row.scheme != row.project {
                                Text(row.scheme).foregroundStyle(.secondary)
                            }
                        }
                        Text(row.builds.formatted())
                        Text(row.failed == 0 ? "0" : "\(row.failed) · \(PercentFormat.string(row.failureRate))")
                        Text(DurationFormat.short(row.medianIncremental))
                        Text(DurationFormat.short(row.p90Incremental))
                        Text(DurationFormat.short(row.medianFull))
                        Text(DurationFormat.short(row.p90Full))
                        Text(DurationFormat.total(row.totalTime))
                    }
                    .monospacedDigit()
                }
            }
            .font(.callout)
        }
    }
}
