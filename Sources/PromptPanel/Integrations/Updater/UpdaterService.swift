import Foundation
import Sparkle

@MainActor
final class UpdaterService: NSObject, ObservableObject {
    private final class FeedDelegate: NSObject, SPUUpdaterDelegate {
        private let feedURL: URL

        init(feedURL: URL) {
            self.feedURL = feedURL
        }

        func feedURLString(for updater: SPUUpdater) -> String? {
            feedURL.absoluteString
        }
    }

    struct ConfigurationState {
        let feedURL: URL?
        let publicKey: String?

        var isConfigured: Bool {
            feedURL != nil && publicKey?.isEmpty == false
        }

        var statusMessage: String {
            switch (feedURL, publicKey?.isEmpty == false) {
            case (.some(let feedURL), true):
                return "已接入 Sparkle，当前使用 \(feedURL.absoluteString)"
            case (.none, true):
                return "已接入 Sparkle，但缺少 appcast feed URL。"
            case (.some, false):
                return "已接入 Sparkle，但缺少 SUPublicEDKey。"
            case (.none, false):
                return "已接入 Sparkle，但当前未配置 feed URL 和 SUPublicEDKey。"
            }
        }
    }

    @Published private(set) var canCheckForUpdates: Bool = false

    private let configurationState: ConfigurationState
    private let feedDelegate: FeedDelegate?
    private let updaterController: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?

    override init() {
        self.configurationState = Self.resolveConfiguration(bundle: .main)
        self.feedDelegate = configurationState.feedURL.map(FeedDelegate.init(feedURL:))
        if configurationState.isConfigured {
            self.updaterController = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: feedDelegate,
                userDriverDelegate: nil
            )
        } else {
            self.updaterController = nil
        }
        super.init()

        if let updaterController {
            canCheckObservation = updaterController.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor [weak self] in
                    self?.canCheckForUpdates = updater.canCheckForUpdates
                }
            }
        }
    }

    var statusMessage: String {
        configurationState.statusMessage
    }

    func start() {
        guard let updaterController else {
            PPLogger.updater.info("Sparkle updater left disabled: \(self.statusMessage)")
            return
        }

        updaterController.startUpdater()
        if #available(macOS 14.0, *) {
            updaterController.updater.clearFeedURLFromUserDefaults()
        }
        PPLogger.updater.info("Sparkle updater started with feed=\(self.configurationState.feedURL?.absoluteString ?? "nil")")
    }

    @discardableResult
    func checkForUpdates() -> String {
        guard let updaterController else {
            PPLogger.updater.warning("Manual update check skipped because updater is not configured")
            return statusMessage
        }

        guard canCheckForUpdates else {
            PPLogger.updater.warning("Manual update check skipped because Sparkle cannot check right now")
            return "更新检查暂不可用，请稍后再试。"
        }

        updaterController.checkForUpdates(nil)
        PPLogger.updater.info("Manual Sparkle update check triggered")
        return "已开始检查更新。"
    }

    private static func resolveConfiguration(bundle: Bundle) -> ConfigurationState {
        let info = bundle.infoDictionary ?? [:]
        let env = ProcessInfo.processInfo.environment

        let feedURLString = (env["PROMPTPANEL_SPARKLE_FEED_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? (info["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let publicKey = (env["PROMPTPANEL_SPARKLE_PUBLIC_ED_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        return ConfigurationState(
            feedURL: feedURLString.flatMap(URL.init(string:)),
            publicKey: publicKey
        )
    }
}
