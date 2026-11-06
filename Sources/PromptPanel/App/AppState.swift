import Foundation
import SwiftUI

/// Central observable state for the application.
/// This is NOT a god-object: repositories, services, and window controllers remain separate.
/// AppState only holds the minimal cross-cutting state that multiple parts of the app need to observe.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Project State

    /// The ID of the currently active project.
    @Published var currentProjectId: String?

    /// The ID of the built-in default project ("通用项目"). Set once during initialization.
    @Published private(set) var defaultProjectId: String?

    // MARK: - Panel State

    @Published var isPanelVisible: Bool = false
    @Published var isPanelPinned: Bool = false
    @Published var panelContentSize: NSSize = Constants.panelContentSize
    @Published var panelWindowOrigin: NSPoint?
    @Published var panelShowFooter: Bool = true
    @Published var panelCompactRows: Bool = false
    @Published var appTheme: AppTheme = .system

    // MARK: - Main Window State

    @Published var isMainWindowVisible: Bool = false

    // MARK: - Permission State

    @Published var hasAccessibilityPermission: Bool = false

    // MARK: - Initialization

    init() {
        PPLogger.app.info("AppState initialized")
    }

    /// Called once after database is ready to load persisted state.
    func loadPersistedState(
        currentProjectId: String?,
        defaultProjectId: String?,
        isPanelPinned: Bool = false,
        panelContentSize: NSSize = Constants.panelContentSize,
        panelWindowOrigin: NSPoint? = nil,
        panelShowFooter: Bool = true,
        panelCompactRows: Bool = false,
        appTheme: AppTheme = .system
    ) {
        self.currentProjectId = currentProjectId
        self.defaultProjectId = defaultProjectId
        self.isPanelPinned = isPanelPinned
        self.panelContentSize = panelContentSize
        self.panelWindowOrigin = panelWindowOrigin
        self.panelShowFooter = panelShowFooter
        self.panelCompactRows = panelCompactRows
        self.appTheme = appTheme
        PPLogger.app.info(
            "Persisted state loaded: currentProject=\(currentProjectId ?? "nil"), defaultProject=\(defaultProjectId ?? "nil"), panelPinned=\(isPanelPinned), panelContentSize=\(Int(panelContentSize.width))x\(Int(panelContentSize.height)), panelWindowOrigin=\(panelWindowOrigin.map { "\(Int($0.x)),\(Int($0.y))" } ?? "nil"), showFooter=\(panelShowFooter), compact=\(panelCompactRows), theme=\(appTheme.rawValue)"
        )
    }

    /// The effective project ID for panel display.
    /// Falls back to defaultProjectId if currentProjectId is nil.
    var effectiveProjectId: String {
        currentProjectId ?? defaultProjectId ?? ""
    }
}
