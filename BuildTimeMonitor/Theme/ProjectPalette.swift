import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// A colour that resolves differently in light and dark appearances.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// Validated 8-slot categorical palette (dataviz reference instance). Slots are
/// assigned in fixed order by a project's first appearance in the CSV, so a
/// project keeps its colour regardless of filtering.
enum ProjectPalette {
    static let slots: [Color] = [
        Color(light: 0x2A78D6, dark: 0x3987E5), // blue
        Color(light: 0xEB6834, dark: 0xD95926), // orange
        Color(light: 0x1BAF7A, dark: 0x199E70), // aqua
        Color(light: 0xEDA100, dark: 0xC98500), // yellow
        Color(light: 0xE87BA4, dark: 0xD55181), // magenta
        Color(light: 0x008300, dark: 0x008300), // green
        Color(light: 0x4A3AA7, dark: 0x9085E9), // violet
        Color(light: 0xE34948, dark: 0xE66767), // red
    ]

    static let otherName = "Other"
    static let other = Color(light: 0x898781, dark: 0x898781)

    /// Series name for a project: the 9th project onwards folds into "Other".
    static func seriesName(for project: String, in projects: [String]) -> String {
        guard let index = projects.firstIndex(of: project), index < slots.count else { return otherName }
        return project
    }

    /// Series names in slot order, for `chartForegroundStyleScale`.
    static func seriesDomain(for projects: [String]) -> [String] {
        let named = Array(projects.prefix(slots.count))
        return projects.count > slots.count ? named + [otherName] : named
    }

    static func colors(for projects: [String]) -> [Color] {
        let named = Array(slots.prefix(min(projects.count, slots.count)))
        return projects.count > slots.count ? named + [other] : named
    }

    static func color(for project: String, in projects: [String]) -> Color {
        guard let index = projects.firstIndex(of: project), index < slots.count else { return other }
        return slots[index]
    }
}

/// Reserved status colours: never used for series, always paired with an icon.
enum StatusColor {
    static let critical = Color(hex: 0xD03B3B)
    static let good = Color(hex: 0x0CA30C)
}

enum ChartInk {
    static let gridline = Color(light: 0xE1E0D9, dark: 0x2C2C2A)
    static let baseline = Color(light: 0xC3C2B7, dark: 0x383835)
    static let muted = Color(light: 0x898781, dark: 0x898781)
}
