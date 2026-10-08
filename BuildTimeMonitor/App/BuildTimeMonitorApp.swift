import SwiftUI

enum WindowID {
    static let detail = "detail"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = BuildStore()
    private var previewWindows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // `-PreviewPopover YES` shows the popover content in a regular window,
        // which makes screenshots and UI iteration easier.
        if UserDefaults.standard.bool(forKey: "PreviewPopover") {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 440, height: 600),
                    styleMask: [.titled, .closable, .fullSizeContentView],
                    backing: .buffered, defer: false
                )
                window.title = "Popover Preview"
                window.titlebarAppearsTransparent = true
                window.appearance = NSAppearance(named: appearance)
                window.contentView = NSHostingView(rootView: MenuBarPopoverView().environment(store))
                window.setFrameTopLeftPoint(NSPoint(x: appearance == .aqua ? 40 : 520, y: (NSScreen.main?.frame.maxY ?? 900) - 60))
                window.makeKeyAndOrderFront(nil)
                previewWindows.append(window)
            }
            NSApp.activate()
            if let directory = UserDefaults.standard.string(forKey: "SnapshotDir") {
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    for (index, window) in previewWindows.enumerated() {
                        Self.snapshot(window, to: URL(fileURLWithPath: directory).appendingPathComponent("popover-\(index == 0 ? "light" : "dark").png"))
                    }
                }
            }
        }
        #endif
    }

    #if DEBUG
    static func snapshot(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
    #endif
}

@main
struct BuildTimeMonitorApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    private var store: BuildStore { appDelegate.store }
    @AppStorage(SettingsKey.showDurationInMenuBar) private var showDurationInMenuBar = true

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environment(store)
        } label: {
            MenuBarLabel(store: store, showDuration: showDurationInMenuBar)
        }
        .menuBarExtraStyle(.window)

        Window("Build Times", id: WindowID.detail) {
            DetailWindowView()
                .environment(store)
        }
        .defaultSize(width: 1000, height: 720)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

private struct MenuBarLabel: View {
    let store: BuildStore
    let showDuration: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "hammer.fill")
            if showDuration, let last = store.lastCompletedBuild {
                Text(DurationFormat.short(last.duration)).monospacedDigit()
            }
        }
    }
}
