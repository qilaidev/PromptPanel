import Foundation
import os.log

/// Unified logging wrapper for PromptPanel.
/// Uses Apple's os.log system with structured categories.
/// IMPORTANT: Never log user entry content (title/body) to protect privacy.
enum PPLogger {

    // MARK: - Log Categories

    private static let subsystem = Constants.bundleIdentifier

    static let app = os.Logger(subsystem: subsystem, category: "app")
    static let database = os.Logger(subsystem: subsystem, category: "database")
    static let hotkey = os.Logger(subsystem: subsystem, category: "hotkey")
    static let panel = os.Logger(subsystem: subsystem, category: "panel")
    static let execute = os.Logger(subsystem: subsystem, category: "execute")
    static let clipboard = os.Logger(subsystem: subsystem, category: "clipboard")
    static let paste = os.Logger(subsystem: subsystem, category: "paste")
    static let permission = os.Logger(subsystem: subsystem, category: "permission")
    static let search = os.Logger(subsystem: subsystem, category: "search")
    static let project = os.Logger(subsystem: subsystem, category: "project")
    static let entry = os.Logger(subsystem: subsystem, category: "entry")
    static let tray = os.Logger(subsystem: subsystem, category: "tray")
    static let updater = os.Logger(subsystem: subsystem, category: "updater")
    static let loginItem = os.Logger(subsystem: subsystem, category: "loginItem")
}
