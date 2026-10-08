import Foundation
import Observation

@MainActor
@Observable
final class BuildStore {
    enum LoadState: Equatable {
        case noPath
        case loading
        case loaded
        case missingFile(String)
        case failed(String)
    }

    private(set) var records: [BuildRecord] = []
    private(set) var state: LoadState = .noPath
    private(set) var skippedRows = 0
    private(set) var lastLoaded: Date?
    /// Projects in order of first appearance; this order assigns colours.
    private(set) var projects: [String] = []

    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var path: String = ""
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?

    /// Follows the CSV path stored in user defaults (the Settings window writes it).
    init() {
        setPath(Self.configuredPath)
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.setPath(Self.configuredPath)
            }
        }
    }

    private static var configuredPath: String {
        UserDefaults.standard.string(forKey: SettingsKey.csvPath) ?? ""
    }

    /// For tests and previews: no defaults observation.
    init(path: String) {
        setPath(path)
    }

    func setPath(_ newPath: String) {
        let expanded = (newPath as NSString).expandingTildeInPath
        guard expanded != path || watcher == nil else { return }
        path = expanded
        watcher?.cancel()
        watcher = nil
        guard !expanded.isEmpty else {
            records = []
            projects = []
            state = .noPath
            return
        }
        watcher = FileWatcher(url: URL(fileURLWithPath: expanded)) { [weak self] in
            self?.reload()
        }
        reload()
    }

    func reload() {
        let path = self.path
        guard !path.isEmpty else { return }
        if records.isEmpty { state = .loading }
        loadTask?.cancel()
        loadTask = Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Self.load(path: path)
            }.value
            guard !Task.isCancelled, path == self.path else { return }
            self.apply(outcome)
        }
    }

    private enum Outcome: Sendable {
        case success(ParseResult)
        case missing
        case failure(String)
    }

    nonisolated private static func load(path: String) -> Outcome {
        guard FileManager.default.fileExists(atPath: path) else { return .missing }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let text = String(decoding: data, as: UTF8.self)
            return .success(try BuildCSVParser.parse(text))
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func apply(_ outcome: Outcome) {
        switch outcome {
        case .success(let result):
            records = result.records.sorted { $0.plotDate < $1.plotDate }
            skippedRows = result.skippedRows
            var seen = Set<String>()
            // First appearance in file order, so colours never change as rows are added.
            projects = result.records.map(\.projectName).filter { seen.insert($0).inserted }
            state = .loaded
            lastLoaded = .now
        case .missing:
            records = []
            projects = []
            state = .missingFile(path)
        case .failure(let message):
            state = .failed(message)
        }
    }

    var lastCompletedBuild: BuildRecord? {
        records.last(where: \.isCompleted)
    }
}
