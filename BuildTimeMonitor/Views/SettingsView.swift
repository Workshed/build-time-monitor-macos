import SwiftUI

struct SettingsView: View {
    @Environment(BuildStore.self) private var store
    @AppStorage(SettingsKey.csvPath) private var csvPath = ""
    @AppStorage(SettingsKey.excludeNoOps) private var excludeNoOps = true
    @AppStorage(SettingsKey.showDurationInMenuBar) private var showDurationInMenuBar = true
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("CSV file") {
                    HStack {
                        TextField("CSV file", text: $csvPath, prompt: Text("~/Projects/MyApp/build_times.csv"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                        Button("Choose…") {
                            if let path = CSVFilePicker.choose(startingAt: csvPath) {
                                csvPath = (path as NSString).abbreviatingWithTildeInPath
                            }
                        }
                    }
                }
                LabeledContent("Status") {
                    HStack(spacing: 8) {
                        statusText
                        Spacer()
                        Button("Reveal in Finder", systemImage: "magnifyingglass") {
                            let url = URL(fileURLWithPath: (csvPath as NSString).expandingTildeInPath)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(!store.state.isLoaded)
                    }
                }
            } header: {
                Text("Data")
            } footer: {
                Text("The file written by xcode-build-time-recorder: `build_times.csv` in your project root by default, or the path in its `.buildtimes-path`. It's re-read automatically whenever a build is recorded.")
                    .foregroundStyle(.secondary)
            }

            Section("Display") {
                Toggle("Show last build time in the menu bar", isOn: $showDurationInMenuBar)
                Toggle(isOn: $excludeNoOps) {
                    Text("Exclude no-op builds from charts and averages")
                    Text("Builds where nothing changed and the product wasn't rebuilt.")
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LaunchAtLogin.set(enabled)
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var statusText: some View {
        switch store.state {
        case .noPath:
            Text("No file selected").foregroundStyle(.secondary)
        case .loading:
            Text("Loading…").foregroundStyle(.secondary)
        case .loaded:
            Label {
                Text(loadedSummary).foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(StatusColor.good)
            }
        case .missingFile:
            Label("File not found yet", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label {
                Text(message).foregroundStyle(.secondary).lineLimit(2)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(StatusColor.critical)
            }
        }
    }

    private var loadedSummary: String {
        var text = "\(store.records.count.formatted()) builds"
        if store.projects.count > 1 { text += " · \(store.projects.count) projects" }
        if store.skippedRows > 0 { text += " · \(store.skippedRows) row\(store.skippedRows == 1 ? "" : "s") skipped" }
        return text
    }
}

extension BuildStore.LoadState {
    var isLoaded: Bool { if case .loaded = self { true } else { false } }
}
