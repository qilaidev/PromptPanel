import AppKit

/// Main app entry point.
/// Uses pure AppKit NSApplication lifecycle directly with AppDelegate instead of SwiftUI `App`
/// so SwiftUI never registers a dummy `Settings { EmptyView() }` scene (`“项目快贴”设置` blank window).
@main
struct PromptPanelApp {
    @MainActor
    private static var retainedDelegate: AppDelegate?

    @MainActor
    static func main() {
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame com_apple_SwiftUI_Settings_window")
        if let bundleId = Bundle.main.bundleIdentifier,
           let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let savedStateDir = libraryDir
                .appendingPathComponent("Saved Application State", isDirectory: true)
                .appendingPathComponent("\(bundleId).savedState", isDirectory: true)
            try? FileManager.default.removeItem(at: savedStateDir)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.run()
    }
}
