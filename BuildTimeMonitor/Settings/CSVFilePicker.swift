import AppKit
import UniformTypeIdentifiers

@MainActor
enum CSVFilePicker {
    /// Returns the chosen CSV path, or nil if cancelled.
    static func choose(startingAt current: String = "") -> String? {
        let panel = NSOpenPanel()
        panel.title = "Choose Build Times CSV"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if !current.isEmpty {
            let url = URL(fileURLWithPath: (current as NSString).expandingTildeInPath)
            panel.directoryURL = url.deletingLastPathComponent()
        }
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
