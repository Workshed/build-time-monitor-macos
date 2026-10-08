import Foundation

/// Watches a single file for changes. The recorder only appends, but the file
/// may be deleted, replaced (e.g. by a sync client) or not exist yet, so when
/// the file can't be watched directly we watch its parent directory and
/// re-attach once it appears.
@MainActor
final class FileWatcher {
    private let url: URL
    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var debounce: Task<Void, Never>?
    private var isCancelled = false

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange
        attach()
    }

    func cancel() {
        isCancelled = true
        debounce?.cancel()
        source?.cancel()
        source = nil
    }

    private func attach() {
        source?.cancel()
        source = nil

        let fileExists = FileManager.default.fileExists(atPath: url.path)
        let target = fileExists ? url : url.deletingLastPathComponent()
        let descriptor = open(target.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // Neither the file nor its directory exist yet; poll slowly.
            scheduleReattach(after: .seconds(5))
            return
        }

        let events: DispatchSource.FileSystemEvent = fileExists
            ? [.write, .extend, .delete, .rename, .revoke, .attrib]
            : [.write, .link, .rename]
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: events, queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let source = self.source else { return }
                let data = source.data
                if !fileExists || data.contains(.delete) || data.contains(.rename) || data.contains(.revoke) {
                    // File appeared, vanished or was atomically replaced.
                    self.scheduleReattach(after: .milliseconds(200))
                }
                self.scheduleChange()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func scheduleChange() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, !self.isCancelled else { return }
            self.onChange()
        }
    }

    private func scheduleReattach(after delay: Duration) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !self.isCancelled else { return }
            self.attach()
            self.scheduleChange()
        }
    }
}
