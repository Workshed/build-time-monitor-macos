import Foundation
import ServiceManagement

enum SettingsKey {
    static let csvPath = "csvPath"
    static let excludeNoOps = "excludeNoOpBuilds"
    static let showDurationInMenuBar = "showDurationInMenuBar"
    static let timeRange = "timeRange"
    static let buildKind = "buildKind"
}

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
