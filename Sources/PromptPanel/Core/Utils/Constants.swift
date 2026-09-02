import AppKit
import Foundation
import SwiftUI

/// Global constants for PromptPanel
enum Constants {
    private static let appSupportOverrideEnv = "PROMPTPANEL_APP_SUPPORT_DIR"
    private static let logsOverrideEnv = "PROMPTPANEL_LOGS_DIR"

    // MARK: - Visual system (PromptPanel front-end baseline)
    //
    // All colors are *dynamic*: they resolve at render time via
    // `NSColor(name:dynamicProvider:)`, so switching `.preferredColorScheme`
    // (or the system appearance) automatically re-renders every view without
    // any explicit bridging.
    //
    // Naming contract:
    //   - `bg / surface / surfaceRaised / surfaceHover / surfaceActive / sidebar`
    //     are concrete surface colors (do NOT flip sign).
    //   - `tintSubtle / tintMedium / tintStrong` are overlay tints that flip
    //     sign between themes (white in dark, black in light). Use these
    //     instead of hardcoded `Color.white.opacity(x)` / `Color.black.opacity(x)`.
    //   - `border / borderStrong / divider` are hairline dividers; they also
    //     flip sign so contrast stays legible.
    //   - `text / textSecondary / textTertiary / textQuaternary` are the
    //     text hierarchy; secondary/tertiary/quaternary get *more* contrast
    //     in light mode because light backgrounds need it.
    //   - `accent*`, `success*`, `warn*`, `danger*` are semantic colors; the
    //     solid tone is re-tuned for light mode so it stays readable, and the
    //     `*Dim` fill gets slightly more opacity so a light fill is visible.
    enum VisualStyle {
        // Surfaces
        static let bg              = dynamicColor(dark: 0x0e0f11, light: 0xf4f5f7)
        static let surface         = dynamicColor(dark: 0x17181b, light: 0xffffff)
        static let surfaceRaised   = dynamicColor(dark: 0x1e1f23, light: 0xf6f7f9)
        static let surfaceHover    = dynamicColor(dark: 0x24262b, light: 0xeceff3)
        static let surfaceActive   = dynamicColor(dark: 0x2b2e34, light: 0xe3e6ec)
        static let sidebar         = dynamicColor(dark: 0x141518, light: 0xeef0f4)

        // Dividers & borders (sign-flipping hairlines)
        static let border          = invertingTint(darkAlpha: 0.06, lightAlpha: 0.10)
        static let borderStrong    = invertingTint(darkAlpha: 0.10, lightAlpha: 0.14)
        static let divider         = invertingTint(darkAlpha: 0.04, lightAlpha: 0.07)

        // Text hierarchy
        static let text            = dynamicColor(dark: 0xe8e9ec, light: 0x1a1c20)
        static let textSecondary   = dynamicColor(dark: 0xaeb3bc, light: 0x4e525b)
        static let textTertiary    = dynamicColor(dark: 0x858b96, light: 0x7a7e87)
        static let textQuaternary  = dynamicColor(dark: 0x666d78, light: 0xadb1b9)

        // Accent (indigo 7c8cf8 — slightly deeper in light mode for contrast)
        static let accent          = dynamicColor(dark: 0x7c8cf8, light: 0x5667e6)
        static let accentDim       = semanticFill(dark: 0x7c8cf8, darkAlpha: 0.14, light: 0x5667e6, lightAlpha: 0.12)
        static let accentBorder    = semanticFill(dark: 0x7c8cf8, darkAlpha: 0.35, light: 0x5667e6, lightAlpha: 0.32)
        static let infoBannerFill  = dynamicColor(dark: 0x25283b, light: 0xe7ecff)
        static let infoBannerBorder = dynamicColor(dark: 0x3d467c, light: 0xc4cffc)

        // Semantic (success / warn / danger)
        static let success         = dynamicColor(dark: 0x5fb37a, light: 0x2f8a4f)
        static let successDim      = semanticFill(dark: 0x5fb37a, darkAlpha: 0.12, light: 0x2f8a4f, lightAlpha: 0.14)
        static let warn            = dynamicColor(dark: 0xd4a35a, light: 0x9b6f1a)
        static let warnDim         = semanticFill(dark: 0xd4a35a, darkAlpha: 0.12, light: 0x9b6f1a, lightAlpha: 0.14)
        static let danger          = dynamicColor(dark: 0xd47070, light: 0xb63030)
        static let dangerDim       = semanticFill(dark: 0xd47070, darkAlpha: 0.12, light: 0xb63030, lightAlpha: 0.12)

        // Overlay tints — flip sign between themes. Use instead of
        // raw `Color.white.opacity(x)` / `Color.black.opacity(x)`.
        static let tintSubtle      = invertingTint(darkAlpha: 0.04, lightAlpha: 0.035)
        static let tintMedium      = invertingTint(darkAlpha: 0.06, lightAlpha: 0.05)
        static let tintStrong      = invertingTint(darkAlpha: 0.10, lightAlpha: 0.08)

        // Convenience: dark "scrim" used for panel footers — always darker
        // than the surface (black-tinted even in light mode).
        static let scrim           = semanticFill(dark: 0x000000, darkAlpha: 0.20, light: 0x000000, lightAlpha: 0.05)

        // Entry level palette — driven by useCount tiers (see `EntryLevel`).
        // `master` flips to near-white in dark mode so the rare top tier
        // still stands out against the dark surface.
        static let levelBlue       = dynamicColor(dark: 0x6da8f7, light: 0x3066cc)
        static let levelBlueDim    = semanticFill(dark: 0x6da8f7, darkAlpha: 0.14, light: 0x3066cc, lightAlpha: 0.12)
        static let levelGreen      = dynamicColor(dark: 0x5cb87a, light: 0x2f8a4f)
        static let levelGreenDim   = semanticFill(dark: 0x5cb87a, darkAlpha: 0.14, light: 0x2f8a4f, lightAlpha: 0.13)
        static let levelYellow     = dynamicColor(dark: 0xd9bb56, light: 0x9b6f1a)
        static let levelYellowDim  = semanticFill(dark: 0xd9bb56, darkAlpha: 0.16, light: 0x9b6f1a, lightAlpha: 0.14)
        static let levelPink       = dynamicColor(dark: 0xeb87b3, light: 0xc94785)
        static let levelPinkDim    = semanticFill(dark: 0xeb87b3, darkAlpha: 0.14, light: 0xc94785, lightAlpha: 0.12)
        static let levelOrange     = dynamicColor(dark: 0xe89455, light: 0xb05418)
        static let levelOrangeDim  = semanticFill(dark: 0xe89455, darkAlpha: 0.14, light: 0xb05418, lightAlpha: 0.12)
        static let levelPurple     = dynamicColor(dark: 0xb084ee, light: 0x7335bf)
        static let levelPurpleDim  = semanticFill(dark: 0xb084ee, darkAlpha: 0.16, light: 0x7335bf, lightAlpha: 0.13)
        static let levelMaster     = dynamicColor(dark: 0xe8e9ec, light: 0x111418)
        static let levelMasterDim  = semanticFill(dark: 0xe8e9ec, darkAlpha: 0.18, light: 0x111418, lightAlpha: 0.10)

        // MARK: - Dynamic color helpers

        /// Resolves `dark` / `light` hex values based on the current appearance.
        private static func dynamicColor(dark: UInt32, light: UInt32) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                nsColor(hex: appearance.isDark ? dark : light)
            })
        }

        /// Hairline tint that flips sign: white overlay in dark mode, black in
        /// light mode. Used for borders, dividers, and subtle fills.
        private static func invertingTint(darkAlpha: CGFloat, lightAlpha: CGFloat) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: darkAlpha)
                    : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: lightAlpha)
            })
        }

        /// Semantic fill with per-mode hue + alpha.
        private static func semanticFill(dark: UInt32, darkAlpha: CGFloat, light: UInt32, lightAlpha: CGFloat) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark
                    ? nsColor(hex: dark, alpha: darkAlpha)
                    : nsColor(hex: light, alpha: lightAlpha)
            })
        }

        private static func nsColor(hex: UInt32, alpha: CGFloat = 1) -> NSColor {
            let r = CGFloat((hex >> 16) & 0xff) / 255
            let g = CGFloat((hex >> 8) & 0xff) / 255
            let b = CGFloat(hex & 0xff) / 255
            return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
        }
    }

    /// Layout metrics.
    ///
    /// The panel and the library are scanning surfaces: what matters is how
    /// many entries fit on screen, so padding is kept to the minimum that still
    /// separates rows, and control heights stay large enough to click.
    /// `hairline` is the single line weight used by every divider and border —
    /// 0.5pt renders as one physical pixel on Retina.
    enum Layout {
        static let hairline: CGFloat = 0.5
        static let sectionSpacing: CGFloat = 10
        static let sectionInset: CGFloat = 10
        static let sectionCornerRadius: CGFloat = 9
        static let compactControlHeight: CGFloat = 24
        static let regularControlHeight: CGFloat = 26
        static let compactRowHeight: CGFloat = 24
        static let regularRowHeight: CGFloat = 28
        static let headerHeight: CGFloat = 32
        static let footerHeight: CGFloat = 24
        static let badgeCornerRadius: CGFloat = 4
        static let chipCornerRadius: CGFloat = 5
    }

    // MARK: - Application Identity

    static let appName = "PromptPanel"
    static let bundleIdentifier = "com.promptpanel.app"

    // MARK: - Data Directories

    static var applicationSupportDirectory: URL {
        let url = environmentURL(for: appSupportOverrideEnv)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent(appName)
        ensureSecureDirectory(at: url)
        return url
    }

    static var databaseURL: URL {
        applicationSupportDirectory.appendingPathComponent("promptpanel.db")
    }

    static func backupDirectory(for databaseURL: URL) -> URL {
        storageRoot(for: databaseURL).appendingPathComponent("Backups", isDirectory: true)
    }

    static func recoveryDirectory(for databaseURL: URL) -> URL {
        storageRoot(for: databaseURL).appendingPathComponent("Recovery", isDirectory: true)
    }

    // MARK: - Log Directories

    static var logsDirectory: URL {
        let url = environmentURL(for: logsOverrideEnv)
            ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Logs")
                .appendingPathComponent(appName)
        ensureSecureDirectory(at: url)
        return url
    }

    static let automaticBackupRetentionCount = 7
    static let automaticBackupMinimumInterval: TimeInterval = 12 * 60 * 60
    static let executionLogRetentionDays = 30
    static let recoveryDirectoryRetentionCount = 5
    static let secureDirectoryPermissions = 0o700
    static let secureFilePermissions = 0o600

    // MARK: - Default Project

    static let defaultProjectName = "通用项目"

    // MARK: - Settings Keys

    enum SettingsKey {
        static let currentProjectId = "current_project_id"
        static let panelPinned = "panel_pinned"
        static let panelContentWidth = "panel_content_width"
        static let panelContentHeight = "panel_content_height"
        static let panelWindowOriginX = "panel_window_origin_x"
        static let panelWindowOriginY = "panel_window_origin_y"
        static let panelShowFooter = "panel_show_footer"
        static let panelCompactRows = "panel_compact_rows"
        static let appTheme = "app_theme"
        static let entrySortMode = "entry_sort_mode"
    }

    // MARK: - Entry Types

    enum EntryType: String, CaseIterable, Codable {
        case prompt
        case code
        case reply
        case note

        var displayName: String {
            switch self {
            case .prompt: return "Prompt"
            case .code: return "代码"
            case .reply: return "回复"
            case .note: return "说明"
            }
        }

        var symbolName: String {
            switch self {
            case .prompt: return "text.bubble.fill"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .reply: return "arrowshape.turn.up.left.fill"
            case .note: return "note.text"
            }
        }

        var accentColor: Color {
            switch self {
            case .prompt: return Color(red: 0.36, green: 0.62, blue: 0.95)
            case .code: return Color(red: 0.36, green: 0.78, blue: 0.56)
            case .reply: return Color(red: 0.96, green: 0.65, blue: 0.30)
            case .note: return Color(red: 0.65, green: 0.55, blue: 0.86)
            }
        }

        static func resolve(_ rawValue: String?) -> EntryType {
            guard let rawValue, let parsed = EntryType(rawValue: rawValue) else {
                return .prompt
            }
            return parsed
        }
    }

    // MARK: - Entry Levels (use-count tiers)

    /// Visible "level" for an entry, derived purely from `useCount`.
    ///
    /// Why: gives the user instant feedback that an entry is being used —
    /// the icon and use-count chip subtly change color as they level up.
    /// Thresholds ramp like an XP curve (fast → slow), so the first few
    /// uses bump tiers quickly, while the legendary tier ("master") stays
    /// rare. Most heavy-use entries land on `.purple`.
    enum EntryLevel: Int, CaseIterable {
        case rookie = 0    // blue
        case bronze = 1    // green
        case silver = 2    // yellow
        case gold = 3      // pink
        case platinum = 4  // orange
        case diamond = 5   // purple
        case master = 6    // black / inverted-white in dark

        static func resolve(useCount: Int) -> EntryLevel {
            switch max(useCount, 0) {
            case 0:        return .rookie
            case 1...3:    return .bronze
            case 4...9:    return .silver
            case 10...24:  return .gold
            case 25...59:  return .platinum
            case 60...149: return .diamond
            default:       return .master
            }
        }

        var displayName: String {
            switch self {
            case .rookie:   return "新词条"
            case .bronze:   return "上手"
            case .silver:   return "熟练"
            case .gold:     return "常用"
            case .platinum: return "高频"
            case .diamond:  return "重度"
            case .master:   return "传奇"
            }
        }

        /// Foreground color used for icons and the use-count chip text.
        var color: Color {
            switch self {
            case .rookie:   return VisualStyle.levelBlue
            case .bronze:   return VisualStyle.levelGreen
            case .silver:   return VisualStyle.levelYellow
            case .gold:     return VisualStyle.levelPink
            case .platinum: return VisualStyle.levelOrange
            case .diamond:  return VisualStyle.levelPurple
            case .master:   return VisualStyle.levelMaster
            }
        }

        /// Subtle background fill (for chips / pills).
        var fillColor: Color {
            switch self {
            case .rookie:   return VisualStyle.levelBlueDim
            case .bronze:   return VisualStyle.levelGreenDim
            case .silver:   return VisualStyle.levelYellowDim
            case .gold:     return VisualStyle.levelPinkDim
            case .platinum: return VisualStyle.levelOrangeDim
            case .diamond:  return VisualStyle.levelPurpleDim
            case .master:   return VisualStyle.levelMasterDim
            }
        }
    }

    // MARK: - Execution Results

    enum ExecutionResult: String, Codable {
        case success
        case clipboardOnly = "clipboard_only"
        case failed
    }

    enum ExecutionTrigger: String, Codable {
        case keyboardSubmit = "keyboard_submit"
        case pointerClick = "pointer_click"
    }

    // MARK: - Window Layout

    /// The main window is a three-column master/detail surface (projects →
    /// entries → preview), so it stays landscape by construction; the default
    /// is only tightened towards 4:3 so it reads as a document window rather
    /// than a wide dashboard.
    enum MainWindowLayout {
        static let defaultContentSize = NSSize(width: 1040, height: 760)
        static let minContentSize = NSSize(width: 920, height: 620)
    }

    static let panelContentInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    /// The quick panel is a single-column scanner: width only has to hold one
    /// row, height decides how many candidates are visible at a glance. So the
    /// default is portrait 4:5 rather than the old landscape 780×440 — the same
    /// pixels buy roughly twice as many visible rows.
    static let panelContentSize = NSSize(width: 560, height: 700)
    static let panelMinContentSize = NSSize(width: 440, height: 320)
    static let panelMaxContentSize = NSSize(width: 1120, height: 1040)
    static func panelWindowContentSize(for panelContentSize: NSSize) -> NSSize {
        NSSize(
            width: panelContentSize.width + panelContentInsets.left + panelContentInsets.right,
            height: panelContentSize.height + panelContentInsets.top + panelContentInsets.bottom
        )
    }
    static var panelWindowSize: NSSize {
        panelWindowContentSize(for: panelContentSize)
    }

    /// Pure geometry shared by the quick panel and the main window so both
    /// surfaces degrade the same way on small displays.
    enum WindowPlacement {
        /// Breathing room kept between a window and the edge of the screen's
        /// visible frame. A default size larger than the display shrinks to fit
        /// instead of hanging off the bottom.
        static let screenMargin: CGFloat = 24

        /// Share of the visible height left above the panel. Launcher-style
        /// upper-third anchoring reads better than dead-center for a tall list,
        /// and keeps the search field near where the eye already is.
        static let panelTopBias: CGFloat = 0.12

        /// Shrink `size` until it fits `visibleFrame` (minus `margin`), never
        /// going below `minimum` — unless the minimum itself does not fit, in
        /// which case the screen wins. AppKit still enforces the window's own
        /// `contentMinSize` on top of this, so a display smaller than the
        /// minimum is clipped rather than shrunk further.
        static func fittedSize(
            _ size: NSSize,
            minimum: NSSize,
            in visibleFrame: NSRect,
            margin: CGFloat = screenMargin
        ) -> NSSize {
            func fit(_ value: CGFloat, _ minimumValue: CGFloat, _ available: CGFloat) -> CGFloat {
                let roomy = max(available - margin * 2, 0)
                return max(min(value, roomy), min(minimumValue, available))
            }
            return NSSize(
                width: fit(size.width, minimum.width, visibleFrame.width),
                height: fit(size.height, minimum.height, visibleFrame.height)
            )
        }

        /// Where the panel lands the first time, before the user drags it:
        /// horizontally centred, anchored in the upper third.
        static func defaultPanelOrigin(panelSize: NSSize, screenFrame: NSRect) -> NSPoint {
            NSPoint(
                x: screenFrame.midX - panelSize.width / 2,
                y: screenFrame.maxY - panelSize.height - screenFrame.height * panelTopBias
            )
        }

        /// Keep a window's origin inside the visible frame.
        static func clampedOrigin(_ origin: NSPoint, size: NSSize, screenFrame: NSRect) -> NSPoint {
            NSPoint(
                x: min(max(origin.x, screenFrame.minX), max(screenFrame.minX, screenFrame.maxX - size.width)),
                y: min(max(origin.y, screenFrame.minY), max(screenFrame.minY, screenFrame.maxY - size.height))
            )
        }
    }

    // MARK: - Panel Performance

    static let panelOpenLatencyTargetMs = 300
    static let panelExecutionUnlockDelayMs = 50
    static let panelActivationRetryDelayMs = 60
    static let panelActivationMaxAttempts = 8
    static let panelFocusRetryDelayMs = 60
    static let panelFocusMaxAttempts = 10
    static let panelDeactivateCloseGraceMs = 900
    static let panelSearchDebounceMs = 80
    static let mainWindowSearchDebounceMs = 120
    static let searchLatencyTargetMs = 80
    static let executionLatencyTargetMs = 250
    static let targetAppRestorePollIntervalMs = 40
    static let targetAppPasteSettleDelayMs = 120
    static let targetAppRestoreTimeoutMs = 700

    enum ExecutionFailureReason: String, Codable {
        case clipboardWriteFailed = "clipboard_write_failed"
        case accessibilityNotGranted = "accessibility_not_granted"
        case targetAppNotRestored = "target_app_not_restored"
        case pasteEventCreationFailed = "paste_event_creation_failed"
    }

    private static func storageRoot(for databaseURL: URL) -> URL {
        let normalizedDatabaseURL = databaseURL.standardizedFileURL
        if normalizedDatabaseURL == self.databaseURL.standardizedFileURL {
            return applicationSupportDirectory
        }
        return normalizedDatabaseURL.deletingLastPathComponent()
    }

    /// Create (or tighten) a per-user data directory to 0700 so no other local
    /// account can traverse or read PromptPanel storage. Mirrors the permission
    /// contract already enforced in DatabaseManager / StorageMaintenanceService;
    /// applying it here closes the window where a freshly created directory would
    /// otherwise inherit the umask default (typically 0755).
    private static func ensureSecureDirectory(at url: URL) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: secureDirectoryPermissions]
        )
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.setAttributes(
                [.posixPermissions: secureDirectoryPermissions],
                ofItemAtPath: url.path
            )
        }
    }

    private static func environmentURL(for key: String) -> URL? {
        let rawValue = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: rawValue, isDirectory: true)
    }
}

extension NSAppearance {
    /// True when the appearance resolves to a dark variant. Used by the
    /// dynamic color providers in `Constants.VisualStyle`.
    var isDark: Bool {
        bestMatch(from: [.aqua, .vibrantLight, .darkAqua, .vibrantDark]) == .darkAqua
            || bestMatch(from: [.aqua, .vibrantLight, .darkAqua, .vibrantDark]) == .vibrantDark
    }
}
