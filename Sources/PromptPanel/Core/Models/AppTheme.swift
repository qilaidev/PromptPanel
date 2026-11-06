import SwiftUI

/// User-facing appearance preference.
///
/// `.system` defers to the current macOS appearance; `.light` / `.dark`
/// override it. The selection is persisted under
/// `Constants.SettingsKey.appTheme`.
enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    var systemImageName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    /// Maps to SwiftUI's `.preferredColorScheme`; `nil` means follow system.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    static func resolve(_ rawValue: String?) -> AppTheme {
        guard let rawValue, let theme = AppTheme(rawValue: rawValue) else {
            return .system
        }
        return theme
    }
}
