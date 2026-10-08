import Foundation
import Testing
@testable import BuildTimeMonitor

@MainActor
struct BuildStoreTests {
    private let header = "started_at,completed_at,duration_seconds,build_kind,status,artifact_updated,scheme,configuration,sdk,project\n"

    private func row(_ duration: Int, project: String = "App") -> String {
        "\"2026-10-08T10:00:00+0100\",\"2026-10-08T10:00:\(String(format: "%02d", duration))+0100\",\"\(duration)\",\"incremental\",\"succeeded\",\"yes\",\"\(project)\",\"Debug\",\"\",\"\(project)\"\n"
    }

    /// Polls until the condition holds (file events + debounce are async).
    private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func reloadsWhenRowsAreAppended() async throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("build_times.csv")
        try (header + row(10)).write(to: file, atomically: false, encoding: .utf8)

        let store = BuildStore(path: file.path)
        #expect(await waitUntil { store.records.count == 1 })

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(row(20, project: "Second").utf8))
        try handle.close()

        #expect(await waitUntil { store.records.count == 2 })
        #expect(store.projects == ["App", "Second"])
        #expect(store.lastCompletedBuild?.duration != nil)
    }

    @Test func picksUpFileCreatedLaterAndReplacedAtomically() async throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("build_times.csv")

        let store = BuildStore(path: file.path)
        #expect(await waitUntil { if case .missingFile = store.state { true } else { false } })

        try (header + row(10)).write(to: file, atomically: false, encoding: .utf8)
        #expect(await waitUntil { store.records.count == 1 })

        // Atomic replace (what sync clients and editors do) swaps the inode.
        try (header + row(10) + row(11) + row(12)).write(to: file, atomically: true, encoding: .utf8)
        #expect(await waitUntil { store.records.count == 3 })

        try FileManager.default.removeItem(at: file)
        #expect(await waitUntil { if case .missingFile = store.state { true } else { false } })
    }

    @Test func reportsUnrelatedCSVAsFailure() async throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("other.csv")
        try "name,age\nbob,3\n".write(to: file, atomically: false, encoding: .utf8)
        let store = BuildStore(path: file.path)
        #expect(await waitUntil { if case .failed = store.state { true } else { false } })
    }
}
