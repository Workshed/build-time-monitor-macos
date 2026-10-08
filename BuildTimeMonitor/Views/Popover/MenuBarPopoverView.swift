import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(BuildStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @AppStorage(SettingsKey.timeRange) private var range: TimeRange = .week
    @AppStorage(SettingsKey.buildKind) private var kind: BuildKind = .incremental
    @AppStorage(SettingsKey.excludeNoOps) private var excludeNoOps = true
    @State private var project: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            switch store.state {
            case .loaded where !store.records.isEmpty:
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    content(now: context.date)
                }
            case .loaded:
                EmptyStateView(
                    symbol: "hammer",
                    title: "No builds yet",
                    message: "Builds appear here as soon as the recorder writes them.",
                    action: nil
                )
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            case .noPath:
                EmptyStateView(
                    symbol: "doc.badge.gearshape",
                    title: "Choose your build log",
                    message: "Point Build Time Monitor at the CSV written by xcode-build-time-recorder.",
                    action: ("Choose CSV…", chooseFile)
                )
            case .missingFile(let path):
                EmptyStateView(
                    symbol: "questionmark.folder",
                    title: "Waiting for the CSV",
                    message: "\((path as NSString).abbreviatingWithTildeInPath) doesn't exist yet. It's created by the first recorded build.",
                    action: ("Settings…", showSettings)
                )
            case .failed(let message):
                EmptyStateView(
                    symbol: "exclamationmark.triangle",
                    title: "Couldn't read the CSV",
                    message: message,
                    action: ("Settings…", showSettings)
                )
            }
        }
        .padding(14)
        .frame(width: 440)
        .onChange(of: store.projects) { _, projects in
            if let project, !projects.contains(project) { self.project = nil }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Build Times").font(.headline)
                    .lineLimit(1)
                if let last = store.lastCompletedBuild {
                    Text("\(last.projectName) · \(DurationFormat.short(last.duration)) · \(last.plotDate.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if store.projects.count > 1, store.state.isLoaded {
                ProjectPicker(selection: $project, projects: store.projects)
                    .controlSize(.small)
            }
            HStack(spacing: 2) {
                Button("Open Dashboard", systemImage: "macwindow", action: showDetail)
                Button("Settings", systemImage: "gearshape", action: showSettings)
                Menu {
                    Button("Reload") { store.reload() }
                    Divider()
                    Button("Quit Build Time Monitor") { NSApp.terminate(nil) }
                        .keyboardShortcut("q")
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let filter = BuildFilter(range: range, kind: kind, project: project, excludeNoOps: excludeNoOps)
        let dashboard = Dashboard(records: store.records, projects: store.projects, filter: filter, now: now)

        controls

        StatTilesView(summary: dashboard.summary)

        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(
                title: "\(kind.label) build time",
                detail: range.durationBucket == nil ? "each build · line is rolling median" : "\(range.durationBucket == .day ? "daily" : "weekly") median"
            )
            if dashboard.points.isEmpty {
                Text("No completed \(kind.label.lowercased()) builds in the last \(range.label).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                BuildDurationChart(
                    points: dashboard.points,
                    projects: store.projects,
                    range: range,
                    domain: dashboard.domain
                )
                .frame(height: 210)
            }
        }
        .padding(.bottom, 2)

        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: "Failed or cancelled", detail: nil)
            FailureChart(buckets: dashboard.failures, range: range)
            HStack(spacing: 12) {
                tally("Today", dashboard.tally.today)
                tally("This month", dashboard.tally.thisMonth)
                tally("This year", dashboard.tally.thisYear)
            }
            .font(.caption)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Picker("Range", selection: $range) {
                ForEach(TimeRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Picker("Kind", selection: $kind) {
                ForEach(BuildKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Spacer(minLength: 0)
        }
        .labelsHidden()
        .controlSize(.small)
    }

    private func tally(_ title: String, _ count: Int) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(count.formatted()).fontWeight(.semibold).monospacedDigit()
        }
    }

    // MARK: Actions

    private func showDetail() {
        openWindow(id: WindowID.detail)
        NSApp.activate()
    }

    private func showSettings() {
        openSettings()
        NSApp.activate()
    }

    private func chooseFile() {
        if let path = CSVFilePicker.choose() {
            UserDefaults.standard.set(path, forKey: SettingsKey.csvPath)
        }
    }
}

struct SectionTitle: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ProjectPicker: View {
    @Binding var selection: String?
    let projects: [String]

    var body: some View {
        Menu {
            Picker("Project", selection: $selection) {
                Text("All projects").tag(String?.none)
                Divider()
                ForEach(projects, id: \.self) { project in
                    Text(project).tag(String?.some(project))
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                if let selection {
                    Circle()
                        .fill(ProjectPalette.color(for: selection, in: projects))
                        .frame(width: 7, height: 7)
                }
                Text(selection ?? "All projects").lineLimit(1)
            }
        }
        .menuStyle(.button)
        .fixedSize()
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    let action: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.glassProminent)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}
