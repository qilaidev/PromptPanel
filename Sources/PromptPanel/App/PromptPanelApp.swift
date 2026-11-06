import SwiftUI

/// Main app entry point.
/// Uses NSApplicationDelegateAdaptor to bridge SwiftUI lifecycle with AppKit.
@main
struct PromptPanelApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We use a Settings scene to satisfy SwiftUI App protocol,
        // but actual window management is done via AppDelegate.
        Settings {
            EmptyView()
        }
    }
}
