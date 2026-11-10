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
        static let bg              = dynamicColor(dark: 0x111215, light: 0xf3f4f7)
        static let surface         = dynamicColor(dark: 0x17181c, light: 0xffffff)
        static let surfaceRaised   = dynamicColor(dark: 0x1e2025, light: 0xffffff)
        static let surfaceHover    = dynamicColor(dark: 0x24272e, light: 0xeff1f5)
        static let surfaceActive   = dynamicColor(dark: 0x2b2e37, light: 0xe6e9f0)
        static let sidebar         = dynamicColor(dark: 0x141518, light: 0xf3f4f7)
        static let segmentActiveFill = dynamicColor(dark: 0x2c2f37, light: 0xffffff)
        static let inputFill       = dynamicColor(dark: 0x141519, light: 0xf5f6f9)

        // Dividers & borders (sign-flipping hairlines)
        static let border          = invertingTint(darkAlpha: 0.08, lightAlpha: 0.09)
        static let borderStrong    = invertingTint(darkAlpha: 0.13, lightAlpha: 0.14)
        static let divider         = invertingTint(darkAlpha: 0.06, lightAlpha: 0.07)

        // Text hierarchy
        static let text            = dynamicColor(dark: 0xeceef2, light: 0x16181d)
        static let textSecondary   = dynamicColor(dark: 0xb2b8c4, light: 0x464b55)
        static let textTertiary    = dynamicColor(dark: 0x8a919e, light: 0x646b78)
        static let textQuaternary  = dynamicColor(dark: 0x6e7583, light: 0x828997)

        // Accent (indigo — deeper in light mode for ≥4.5:1 contrast)
        static let accent          = dynamicColor(dark: 0x7c8cf8, light: 0x4f5fe8)
        static let accentDim       = semanticFill(dark: 0x7c8cf8, darkAlpha: 0.15, light: 0x4f5fe8, lightAlpha: 0.11)
        static let accentBorder    = semanticFill(dark: 0x7c8cf8, darkAlpha: 0.36, light: 0x4f5fe8, lightAlpha: 0.30)
        static let infoBannerFill  = dynamicColor(dark: 0x23273a, light: 0xecf0ff)
        static let infoBannerBorder = dynamicColor(dark: 0x3b4478, light: 0xc7d2fe)

        // Semantic (success / warn / danger)
        static let success         = dynamicColor(dark: 0x5fb37a, light: 0x227a43)
        static let successDim      = semanticFill(dark: 0x5fb37a, darkAlpha: 0.14, light: 0x227a43, lightAlpha: 0.11)
        static let warn            = dynamicColor(dark: 0xd4a35a, light: 0x9a6510)
        static let warnDim         = semanticFill(dark: 0xd4a35a, darkAlpha: 0.14, light: 0x9a6510, lightAlpha: 0.11)
        static let danger          = dynamicColor(dark: 0xd97373, light: 0xbf2c2c)
        static let dangerDim       = semanticFill(dark: 0xd97373, darkAlpha: 0.14, light: 0xbf2c2c, lightAlpha: 0.11)

        // Overlay tints — flip sign between themes
        static let tintSubtle      = invertingTint(darkAlpha: 0.045, lightAlpha: 0.04)
        static let tintMedium      = invertingTint(darkAlpha: 0.07, lightAlpha: 0.055)
        static let tintStrong      = invertingTint(darkAlpha: 0.11, lightAlpha: 0.085)

        // Panel footer subtle bar
        static let scrim           = semanticFill(dark: 0x000000, darkAlpha: 0.22, light: 0x000000, lightAlpha: 0.035)

        // Entry level palette — driven by useCount tiers (see `EntryLevel`)
        static let levelBlue       = dynamicColor(dark: 0x6da8f7, light: 0x3066cc)
        static let levelBlueDim    = semanticFill(dark: 0x6da8f7, darkAlpha: 0.14, light: 0x3066cc, lightAlpha: 0.12)
        static let levelGreen      = dynamicColor(dark: 0x5cb87a, light: 0x247a43)
        static let levelGreenDim   = semanticFill(dark: 0x5cb87a, darkAlpha: 0.14, light: 0x247a43, lightAlpha: 0.12)
        static let levelYellow     = dynamicColor(dark: 0xd9bb56, light: 0x9a6510)
        static let levelYellowDim  = semanticFill(dark: 0xd9bb56, darkAlpha: 0.16, light: 0x9a6510, lightAlpha: 0.13)
        static let levelPink       = dynamicColor(dark: 0xeb87b3, light: 0xc2417d)
        static let levelPinkDim    = semanticFill(dark: 0xeb87b3, darkAlpha: 0.14, light: 0xc2417d, lightAlpha: 0.11)
        static let levelOrange     = dynamicColor(dark: 0xe89455, light: 0xb05418)
        static let levelOrangeDim  = semanticFill(dark: 0xe89455, darkAlpha: 0.14, light: 0xb05418, lightAlpha: 0.12)
        static let levelPurple     = dynamicColor(dark: 0xb084ee, light: 0x6d32b8)
        static let levelPurpleDim  = semanticFill(dark: 0xb084ee, darkAlpha: 0.16, light: 0x6d32b8, lightAlpha: 0.12)
        static let levelMaster     = dynamicColor(dark: 0xeceef2, light: 0x16181d)
        static let levelMasterDim  = semanticFill(dark: 0xeceef2, darkAlpha: 0.18, light: 0x16181d, lightAlpha: 0.10)

        // MARK: - Dynamic color helpers

        private static func dynamicColor(dark: UInt32, light: UInt32) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                nsColor(hex: appearance.isDark ? dark : light)
            })
        }

        private static func invertingTint(darkAlpha: CGFloat, lightAlpha: CGFloat) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: darkAlpha)
                    : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: lightAlpha)
            })
        }

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
        static let sectionSpacing: CGFloat = 12
        static let sectionInset: CGFloat = 14
        static let sectionCornerRadius: CGFloat = 10
        static let compactControlHeight: CGFloat = 24
        static let regularControlHeight: CGFloat = 28
        static let compactRowHeight: CGFloat = 24
        static let regularRowHeight: CGFloat = 28
        static let headerHeight: CGFloat = 36
        static let footerHeight: CGFloat = 24
        static let badgeCornerRadius: CGFloat = 4
        static let chipCornerRadius: CGFloat = 6
    }

    // MARK: - Application Identity

    static let appName = "PromptPanel"
    static let bundleIdentifier = "com.promptpanel.app"

    /// `1.4.0 (8)` — read from `Info.plist` once, not on every SwiftUI pass.
    /// Two settings cards used to derive this independently from `Bundle.main`
    /// inside `body`, in two slightly different shapes.
    static let appVersionDisplay: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let shortVersion = (info["CFBundleShortVersionString"] as? String) ?? "未知"
        let buildVersion = (info["CFBundleVersion"] as? String) ?? "未知"
        return "\(shortVersion) (\(buildVersion))"
    }()

    // MARK: - Data Directories

    /// Resolved once per process.
    ///
    /// This used to be a computed property that ran `createDirectory` + `chmod`
    /// on *every* read. `databaseURL`, `backupDirectory(for:)` and
    /// `recoveryDirectory(for:)` all route through it, and those are read from
    /// SwiftUI `body` and from every storage health refresh — so a settings
    /// repaint cost dozens of filesystem syscalls on the main thread. The
    /// environment override is fixed for the lifetime of the process, so
    /// resolving (and securing) the directory once is equivalent and free.
    private static let resolvedApplicationSupportDirectory: URL = {
        let url = environmentURL(for: appSupportOverrideEnv)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent(appName)
        ensureSecureDirectory(at: url)
        return url
    }()

    static var applicationSupportDirectory: URL {
        resolvedApplicationSupportDirectory
    }

    static let databaseURL: URL = resolvedApplicationSupportDirectory
        .appendingPathComponent("promptpanel.db")

    static func backupDirectory(for databaseURL: URL) -> URL {
        storageRoot(for: databaseURL).appendingPathComponent("Backups", isDirectory: true)
    }

    static func recoveryDirectory(for databaseURL: URL) -> URL {
        storageRoot(for: databaseURL).appendingPathComponent("Recovery", isDirectory: true)
    }

    // MARK: - Log Directories

    /// PromptPanel logs through `os.Logger` (see `PPLogger`), i.e. into the unified log —
    /// it does **not** write log files. This directory exists as the documented place to
    /// drop anything a maintainer collects by hand (`log collect`, a diagnostics bundle),
    /// and as the isolation point `PROMPTPANEL_LOGS_DIR` moves during QA runs. If you go
    /// looking for the code that writes here, there isn't any, and that is intentional.
    private static let resolvedLogsDirectory: URL = {
        let url = environmentURL(for: logsOverrideEnv)
            ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Logs")
                .appendingPathComponent(appName)
        ensureSecureDirectory(at: url)
        return url
    }()

    static var logsDirectory: URL {
        resolvedLogsDirectory
    }

    static let automaticBackupRetentionCount = 7
    /// Snapshots taken automatically before a library import.
    ///
    /// These used to be created through `createManualBackup()`, which meant they
    /// inherited the "never prune" policy that exists to protect backups the user
    /// asked for by hand — so every import left another full database copy behind,
    /// forever. They are machine-made safety copies, not the user's archive, so they
    /// get their own bounded retention. Backups from the 立即备份 button are still
    /// never pruned; see `StorageMaintenanceService.pruneCollectableBackups()`.
    static let importBackupRetentionCount = 5
    /// Time-throttled safety snapshots taken before cloud sync merges remote changes.
    /// Kept in dedicated retention buckets so high-frequency (2.5s) auto-syncs neither
    /// thrash the disk nor evict launch/manual/guard backups.
    static let syncBackupRetentionCount = 6
    static let syncGuardBackupRetentionCount = 5
    static let automaticBackupMinimumInterval: TimeInterval = 12 * 60 * 60
    static let syncBackupMinimumInterval: TimeInterval = 30 * 60
    static let syncGuardBackupMinimumInterval: TimeInterval = 5 * 60
    /// Anti-data-loss circuit breaker thresholds for cloud sync: if a single remote sync
    /// attempts to soft-delete >= 3 active local entries AND >= 25% of the active library
    /// (or all active entries when >= 2), remote deletions are blocked and local entries
    /// self-heal back to the cloud.
    static let syncMassDeleteMinEntryCount = 3
    static let syncMassDeleteRatioThreshold = 0.25
    static let executionLogRetentionDays = 30
    static let recoveryDirectoryRetentionCount = 5
    static let secureDirectoryPermissions = 0o700
    static let secureFilePermissions = 0o600

    // MARK: - Default Project & Built-in Inbox

    static let defaultProjectName = "通用项目"
    static let inboxProjectId = "builtin-inbox"
    static let inboxProjectName = "速记与待办"

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
        static let cloudSyncEndpoint = "cloud_sync_endpoint"
        static let cloudSyncApiKey = "cloud_sync_api_key"
        static let cloudSyncEnabled = "cloud_sync_enabled"
    }

    // MARK: - Entry Types

    enum EntryType: String, CaseIterable, Codable {
        case prompt
        case code
        case todo
        case note
        case reply

        var displayName: String {
            switch self {
            case .prompt: return "提示词"
            case .code: return "代码"
            case .todo: return "待办"
            case .note: return "临时记录"
            case .reply: return "回复"
            }
        }

        var symbolName: String {
            switch self {
            case .prompt: return "text.bubble"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .todo: return "checklist"
            case .note: return "note.text"
            case .reply: return "arrowshape.turn.up.left"
            }
        }

        var accentColor: Color {
            switch self {
            case .prompt: return VisualStyle.accent
            case .code: return VisualStyle.levelGreen
            case .todo: return VisualStyle.warn
            case .note: return VisualStyle.levelBlue
            case .reply: return VisualStyle.levelPurple
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

    static let panelContentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
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
    static let panelExecutionUnlockDelayMs = 24
    static let panelActivationRetryDelayMs = 16
    static let panelActivationMaxAttempts = 8
    static let panelFocusRetryDelayMs = 16
    static let panelFocusMaxAttempts = 10
    static let panelDeactivateCloseGraceMs = 900
    static let panelSearchDebounceMs = 0
    static let mainWindowSearchDebounceMs = 16
    static let searchLatencyTargetMs = 50
    static let executionLatencyTargetMs = 180
    static let targetAppRestorePollIntervalMs = 15
    static let targetAppPasteSettleDelayMs = 60
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
        // Resolved once: every dynamic color in `Constants.VisualStyle` calls
        // this on each appearance change, and `bestMatch` is not free.
        let match = bestMatch(from: [.aqua, .vibrantLight, .darkAqua, .vibrantDark])
        return match == .darkAqua || match == .vibrantDark
    }
}
