import AppKit
import CryptoKit
import Foundation
import Sparkle

@MainActor
final class UpdaterService: NSObject, ObservableObject {
    enum UpdatePhase: Equatable {
        case idle
        case checking
        case upToDate(version: String)
        case updateAvailable(version: String, build: Int)
        case downloading(version: String)
        case readyToInstall(version: String, build: Int)
        case installing(version: String)
        case failed(message: String)
    }

    struct ReleaseCandidate: Equatable, Sendable {
        let version: String
        let build: Int
        let sha256: String
        let primaryZipURL: URL
        let fallbackZipURL: URL?
        let releasePageURL: URL?
    }

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
            case (.some, true):
                return "Sparkle 已启用"
            default:
                return "GitHub / 同步源自动更新已启用"
            }
        }
    }

    nonisolated static let canonicalGitHubRepo = "qilaidev/PromptPanel"

    @Published private(set) var canCheckForUpdates: Bool = true
    @Published private(set) var phase: UpdatePhase = .idle {
        didSet {
            onUpdateStateChanged?(phase)
        }
    }
    @Published var autoUpdateEnabled: Bool = true {
        didSet {
            guard isStarted, !configurationState.isConfigured else { return }
            configurePeriodicCheckTimer()
            if autoUpdateEnabled {
                triggerBackgroundUpdateCheckIfNeeded()
            }
        }
    }

    var syncEndpointProvider: (() -> String)?
    var preInstallBackupHandler: (() -> Void)?
    var canAutoInstallSilentlyProvider: (() -> Bool)?
    var onUpdateStateChanged: ((UpdatePhase) -> Void)?

    private let configurationState: ConfigurationState
    private let feedDelegate: FeedDelegate?
    private let updaterController: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?
    private var periodicTimer: Timer?
    private var isStarted = false
    private(set) var isUpdateFlowInFlight = false
    private var stagedCandidate: ReleaseCandidate?
    private var stagedAppURL: URL?
    private var stagedRootDir: URL?

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
        } else {
            self.canCheckForUpdates = true
        }
    }

    var currentShortVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "1.0.0"
    }

    var currentBuildNumber: Int {
        let raw = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
        return Int(raw) ?? 0
    }

    var statusMessage: String {
        if configurationState.isConfigured {
            return configurationState.statusMessage
        }
        switch phase {
        case .idle:
            return "当前 v\(currentShortVersion) (\(currentBuildNumber)) · \(autoUpdateEnabled ? "自动更新已开启" : "手动检查")"
        case .checking:
            return "正在检查新版本…"
        case .upToDate(let ver):
            return "已是最新版本 v\(ver)"
        case .updateAvailable(let ver, _):
            return "发现新版本 v\(ver)，点击一键更新"
        case .downloading(let ver):
            return "正在下载并校验 v\(ver)…"
        case .readyToInstall(let ver, _):
            return "新版本 v\(ver) 已就绪，点击立即重启更新"
        case .installing(let ver):
            return "正在安装 v\(ver) 并重启…"
        case .failed(let msg):
            return msg
        }
    }

    var actionButtonTitle: String {
        switch phase {
        case .checking:
            return "检查中…"
        case .downloading(let ver):
            return "下载 v\(ver)…"
        case .installing:
            return "正在重启…"
        case .updateAvailable(let ver, _):
            return "一键更新 v\(ver)"
        case .readyToInstall(let ver, _):
            return "立即重启升至 v\(ver)"
        default:
            return "检查更新"
        }
    }

    var hasPendingUpdate: Bool {
        switch phase {
        case .updateAvailable, .readyToInstall:
            return true
        default:
            return false
        }
    }

    func start() {
        isStarted = true
        if let updaterController {
            updaterController.startUpdater()
            if #available(macOS 14.0, *) {
                updaterController.updater.clearFeedURLFromUserDefaults()
            }
            PPLogger.updater.info("Sparkle updater started with feed=\(self.configurationState.feedURL?.absoluteString ?? "nil")")
            return
        }

        configurePeriodicCheckTimer()
        if autoUpdateEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
                self?.triggerBackgroundUpdateCheckIfNeeded()
            }
        }
        PPLogger.updater.info("Built-in release updater started (autoUpdate=\(self.autoUpdateEnabled))")
    }

    private func configurePeriodicCheckTimer() {
        periodicTimer?.invalidate()
        periodicTimer = nil
        guard autoUpdateEnabled, !configurationState.isConfigured else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.triggerBackgroundUpdateCheckIfNeeded()
            }
        }
        timer.tolerance = 60
        periodicTimer = timer
    }

    func triggerBackgroundUpdateCheckIfNeeded() {
        guard autoUpdateEnabled, !configurationState.isConfigured else { return }
        if case .readyToInstall = phase {
            if canAutoInstallSilentlyProvider?() == true {
                _ = installStagedUpdateNow()
            }
            return
        }
        guard canCheckForUpdates, !isUpdateFlowInFlight else { return }
        isUpdateFlowInFlight = true
        canCheckForUpdates = false
        phase = .checking
        Task { @MainActor in
            await performNativeUpdateFlow(userInitiated: false, autoInstallWhenReady: true)
        }
    }

    @discardableResult
    func checkForUpdates() -> String {
        if let updaterController {
            guard canCheckForUpdates else {
                return "更新检查暂不可用，请稍后再试。"
            }
            updaterController.checkForUpdates(nil)
            PPLogger.updater.info("Manual Sparkle update check triggered")
            return "已开始检查更新。"
        }

        if case .readyToInstall = phase {
            return installStagedUpdateNow()
        }
        if isUpdateFlowInFlight {
            if case .downloading(let ver) = phase {
                return "正在后台下载并校验 v\(ver)，完成后将自动安装…"
            }
            return "正在检查新版本，请稍候…"
        }
        if case .checking = phase {
            return "正在检查新版本，请稍候…"
        }
        if case .downloading(let ver) = phase {
            return "正在后台下载并校验 v\(ver)，完成后将自动安装…"
        }

        isUpdateFlowInFlight = true
        canCheckForUpdates = false
        phase = .checking
        Task { @MainActor in
            await performNativeUpdateFlow(userInitiated: true, autoInstallWhenReady: true)
        }
        return "正在检查最新版本（发现更新将自动下载校验并一键升级）…"
    }

    private func performNativeUpdateFlow(userInitiated: Bool, autoInstallWhenReady: Bool) async {
        isUpdateFlowInFlight = true
        defer { isUpdateFlowInFlight = false }
        canCheckForUpdates = false
        phase = .checking
        let localVer = currentShortVersion
        let localBuild = currentBuildNumber
        let syncEndpoint = syncEndpointProvider?() ?? ""

        do {
            let candidate = try await Task.detached(priority: .utility) {
                try Self.fetchLatestReleaseCandidate(syncEndpoint: syncEndpoint, forceRefresh: userInitiated)
            }.value

            guard Self.isNewerVersion(
                remoteVersion: candidate.version,
                remoteBuild: candidate.build,
                localVersion: localVer,
                localBuild: localBuild
            ) else {
                phase = .upToDate(version: localVer)
                canCheckForUpdates = true
                return
            }

            if !autoInstallWhenReady && !userInitiated && !autoUpdateEnabled {
                stagedCandidate = candidate
                phase = .updateAvailable(version: candidate.version, build: candidate.build)
                canCheckForUpdates = true
                return
            }

            phase = .downloading(version: candidate.version)
            let (unpackedApp, tempRoot) = try await Task.detached(priority: .utility) {
                try Self.downloadVerifyAndUnpack(candidate: candidate, expectedBundleId: Bundle.main.bundleIdentifier)
            }.value

            if let oldRoot = stagedRootDir, oldRoot != tempRoot {
                try? FileManager.default.removeItem(at: oldRoot)
            }
            stagedCandidate = candidate
            stagedAppURL = unpackedApp
            stagedRootDir = tempRoot
            phase = .readyToInstall(version: candidate.version, build: candidate.build)
            canCheckForUpdates = true

            if userInitiated || (autoUpdateEnabled && (canAutoInstallSilentlyProvider?() ?? true)) {
                _ = installStagedUpdateNow()
            }
        } catch {
            let friendlyMessage = Self.friendlyUpdateErrorMessage(for: error)
            PPLogger.updater.error("Update flow failed: \(friendlyMessage)")
            phase = .failed(message: "更新检查失败：\(friendlyMessage)")
            canCheckForUpdates = true
        }
    }

    @discardableResult
    func installStagedUpdateNow() -> String {
        guard let candidate = stagedCandidate, let stagedAppURL, FileManager.default.fileExists(atPath: stagedAppURL.path) else {
            return checkForUpdates()
        }

        let targetAppURL = Bundle.main.bundleURL
        guard targetAppURL.pathExtension == "app" else {
            if let page = candidate.releasePageURL {
                NSWorkspace.shared.open(page)
            }
            return "当前为开发态命令行运行，已打开版本发布页。"
        }

        let parentDir = targetAppURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentDir.path) else {
            NSWorkspace.shared.activateFileViewerSelecting([stagedAppURL])
            return "当前应用所在目录只读（如磁盘镜像内），已在访达中定位新版本 PromptPanel.app，请拖入「应用程序」完成替换。"
        }

        phase = .installing(version: candidate.version)
        preInstallBackupHandler?()

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("promptpanel-apply-update-\(UUID().uuidString).zsh")
        let scriptContent = """
        #!/bin/zsh
        OLD_PID="$1"
        STAGED_APP="$2"
        TARGET_APP="$3"
        STAGE_DIR="$4"
        for _ in {1..50}; do
          kill -0 "$OLD_PID" 2>/dev/null || break
          sleep 0.2
        done
        rm -rf "${TARGET_APP}.old" 2>/dev/null || true
        if [[ -d "$TARGET_APP" ]]; then
          mv "$TARGET_APP" "${TARGET_APP}.old" 2>/dev/null || rm -rf "$TARGET_APP"
        fi
        if /usr/bin/ditto "$STAGED_APP" "$TARGET_APP"; then
          /usr/bin/xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
          rm -rf "${TARGET_APP}.old" "$STAGE_DIR" 2>/dev/null || true
          /usr/bin/open "$TARGET_APP"
        else
          [[ -d "${TARGET_APP}.old" ]] && mv "${TARGET_APP}.old" "$TARGET_APP"
        fi
        rm -f "$0"
        """

        do {
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = [
                scriptURL.path,
                String(ProcessInfo.processInfo.processIdentifier),
                stagedAppURL.path,
                targetAppURL.path,
                stagedRootDir?.path ?? stagedAppURL.deletingLastPathComponent().path,
            ]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try proc.run()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSApp.terminate(nil)
            }
            return "正在安装 v\(candidate.version) 并自动重启…"
        } catch {
            phase = .failed(message: "启动更新安装器失败：\(error.localizedDescription)")
            return "启动更新安装器失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Pure Helpers & Network Fetch

    nonisolated static func isNewerVersion(
        remoteVersion: String,
        remoteBuild: Int,
        localVersion: String,
        localBuild: Int
    ) -> Bool {
        let rParts = parseVersionNumbers(remoteVersion)
        let lParts = parseVersionNumbers(localVersion)
        let count = max(rParts.count, lParts.count)
        for idx in 0..<count {
            let rv = idx < rParts.count ? rParts[idx] : 0
            let lv = idx < lParts.count ? lParts[idx] : 0
            if rv != lv {
                return rv > lv
            }
        }
        if remoteBuild > 0 && localBuild > 0 {
            return remoteBuild > localBuild
        }
        return false
    }

    nonisolated private static func parseVersionNumbers(_ raw: String) -> [Int] {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: "+").first.map(String.init) ?? raw
        return cleaned.split(separator: ".").map { Int($0) ?? 0 }
    }

    nonisolated static func resolvedUpdateURL(fromSyncEndpoint rawEndpoint: String, forceRefresh: Bool = false) -> URL? {
        let trimmed = rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var comps = URLComponents(string: trimmed),
              let scheme = comps.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = comps.host, !host.isEmpty else {
            return nil
        }

        var path = comps.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        let suffixes = ["/v1/sync", "/v1/promptpanel", "/v1/health", "/sync", "/health"]
        var matched = false
        for suffix in suffixes where path.hasSuffix(suffix) {
            path = String(path.dropLast(suffix.count)) + "/v1/update"
            matched = true
            break
        }
        if !matched {
            if path.isEmpty || path == "/" {
                path = "/v1/update"
            } else if !path.hasSuffix("/v1/update") {
                path += "/v1/update"
            }
        }
        comps.path = path
        comps.queryItems = forceRefresh ? [URLQueryItem(name: "force", value: "1")] : nil
        return comps.url
    }

    nonisolated private static func fetchLatestReleaseCandidate(
        syncEndpoint: String,
        forceRefresh: Bool
    ) throws -> ReleaseCandidate {
        if let mirrorURL = resolvedUpdateURL(fromSyncEndpoint: syncEndpoint, forceRefresh: forceRefresh),
           let candidate = try? fetchFromMirror(mirrorURL: mirrorURL) {
            return candidate
        }
        return try fetchFromGitHub()
    }

    nonisolated private static func fetchFromMirror(mirrorURL: URL) throws -> ReleaseCandidate {
        let data = try performSynchronousGET(url: mirrorURL, timeout: 8.0)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = (json["version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty,
              let zipDict = json["macosZip"] as? [String: Any] else {
            throw NSError(domain: "UpdaterService", code: 10, userInfo: [NSLocalizedDescriptionKey: "镜像返回格式无效"])
        }
        let build = (json["build"] as? Int) ?? 0
        let sha256 = ((json["macosZip"] as? [String: Any])?["sha256"] as? String ?? "").lowercased()
        let githubURL = (zipDict["githubUrl"] as? String).flatMap(URL.init(string:))
        var mirrorZipURL: URL?
        if let mirrorPath = zipDict["mirrorPath"] as? String, !mirrorPath.isEmpty,
           var baseComps = URLComponents(url: mirrorURL, resolvingAgainstBaseURL: false) {
            baseComps.path = mirrorPath
            baseComps.query = nil
            mirrorZipURL = baseComps.url
        }
        guard let primary = mirrorZipURL ?? githubURL else {
            throw NSError(domain: "UpdaterService", code: 11, userInfo: [NSLocalizedDescriptionKey: "未找到 macOS 更新包地址"])
        }
        let releasePage = (json["releaseUrl"] as? String).flatMap(URL.init(string:))
        return ReleaseCandidate(
            version: version,
            build: build,
            sha256: sha256,
            primaryZipURL: primary,
            fallbackZipURL: (primary == githubURL) ? nil : githubURL,
            releasePageURL: releasePage
        )
    }

    nonisolated private static func fetchFromGitHub() throws -> ReleaseCandidate {
        guard let apiURL = URL(string: "https://api.github.com/repos/\(canonicalGitHubRepo)/releases/latest") else {
            throw NSError(domain: "UpdaterService", code: 20, userInfo: [NSLocalizedDescriptionKey: "GitHub 地址无效"])
        }
        let data = try performSynchronousGET(url: apiURL, timeout: 12.0, accept: "application/vnd.github+json")
        if CloudSyncService.looksLikeHTMLPayload(data) {
            throw NSError(domain: "UpdaterService", code: 21, userInfo: [NSLocalizedDescriptionKey: "更新源返回了网页而非版本信息，请检查网络或代理设置"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "UpdaterService", code: 21, userInfo: [NSLocalizedDescriptionKey: "无法解析版本响应"])
        }
        let tag = (json["tag_name"] as? String) ?? ""
        var shortVer = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        var buildNum = 0
        let assets = (json["assets"] as? [[String: Any]]) ?? []
        var zipName = ""
        var zipURL: URL?
        var zipDigest = ""
        var sumsURL: URL?

        for asset in assets {
            guard let name = asset["name"] as? String,
                  let urlStr = asset["browser_download_url"] as? String,
                  let url = URL(string: urlStr) else { continue }
            if name == "SHA256SUMS.txt" {
                sumsURL = url
            } else if name.hasSuffix("-macos.zip") {
                zipName = name
                zipURL = url
                if let digest = asset["digest"] as? String, digest.hasPrefix("sha256:") {
                    zipDigest = String(digest.dropFirst("sha256:".count)).lowercased()
                }
                if let range = name.range(of: #"PromptPanel-([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)-"#, options: .regularExpression) {
                    let matched = String(name[range])
                    let core = matched.replacingOccurrences(of: "PromptPanel-", with: "").dropLast()
                    let pieces = core.split(separator: "+")
                    if pieces.count == 2 {
                        shortVer = String(pieces[0])
                        buildNum = Int(pieces[1]) ?? 0
                    }
                }
            }
        }

        guard let resolvedZipURL = zipURL, !shortVer.isEmpty else {
            throw NSError(domain: "UpdaterService", code: 22, userInfo: [NSLocalizedDescriptionKey: "未找到 macOS 发行包"])
        }

        if zipDigest.isEmpty, let sumsURL,
           let sumsData = try? performSynchronousGET(url: sumsURL, timeout: 10.0),
           let sumsText = String(data: sumsData, encoding: .utf8) {
            for line in sumsText.split(whereSeparator: \.isNewline) {
                let parts = line.split(whereSeparator: \.isWhitespace)
                if parts.count >= 2, parts[0].count == 64 {
                    let fileToken = parts.last!.trimmingCharacters(in: CharacterSet(charactersIn: "*./"))
                    if fileToken == zipName {
                        zipDigest = String(parts[0]).lowercased()
                        break
                    }
                }
            }
        }

        let releasePage = (json["html_url"] as? String).flatMap(URL.init(string:))
        return ReleaseCandidate(
            version: shortVer,
            build: buildNum,
            sha256: zipDigest,
            primaryZipURL: resolvedZipURL,
            fallbackZipURL: nil,
            releasePageURL: releasePage
        )
    }

    nonisolated private static func downloadVerifyAndUnpack(
        candidate: ReleaseCandidate,
        expectedBundleId: String?
    ) throws -> (URL, URL) {
        guard !candidate.sha256.isEmpty else {
            throw NSError(domain: "UpdaterService", code: 30, userInfo: [NSLocalizedDescriptionKey: "缺少发行包 SHA-256 校验值"])
        }

        let zipData: Data
        if let primaryData = try? performSynchronousGET(url: candidate.primaryZipURL, timeout: 60.0) {
            zipData = primaryData
        } else if let fallback = candidate.fallbackZipURL {
            zipData = try performSynchronousGET(url: fallback, timeout: 90.0)
        } else {
            throw NSError(domain: "UpdaterService", code: 31, userInfo: [NSLocalizedDescriptionKey: "下载更新包失败，请检查网络连接"])
        }

        let actualHash = SHA256.hash(data: zipData).map { String(format: "%02x", $0) }.joined()
        guard actualHash.lowercased() == candidate.sha256.lowercased() else {
            throw NSError(domain: "UpdaterService", code: 32, userInfo: [NSLocalizedDescriptionKey: "更新包 SHA-256 校验未通过，已拦截安装"])
        }

        let fm = FileManager.default
        let stageRoot = fm.temporaryDirectory.appendingPathComponent("promptpanel-stage-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stageRoot, withIntermediateDirectories: true)

        let zipFile = stageRoot.appendingPathComponent("update.zip")
        let unpackDir = stageRoot.appendingPathComponent("unpacked", isDirectory: true)
        try fm.createDirectory(at: unpackDir, withIntermediateDirectories: true)
        try zipData.write(to: zipFile, options: .atomic)

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipFile.path, unpackDir.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            try? fm.removeItem(at: stageRoot)
            throw NSError(domain: "UpdaterService", code: 33, userInfo: [NSLocalizedDescriptionKey: "解压更新包失败"])
        }

        let appURL = unpackDir.appendingPathComponent("PromptPanel.app", isDirectory: true)
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard fm.fileExists(atPath: plistURL.path),
              let plistData = try? Data(contentsOf: plistURL),
              let plist = (try? PropertyListSerialization.propertyList(from: plistData, format: nil)) as? [String: Any] else {
            try? fm.removeItem(at: stageRoot)
            throw NSError(domain: "UpdaterService", code: 34, userInfo: [NSLocalizedDescriptionKey: "更新包内未找到有效的 PromptPanel.app"])
        }

        if let expectedBundleId, !expectedBundleId.isEmpty,
           let bundleId = plist["CFBundleIdentifier"] as? String,
           bundleId != expectedBundleId {
            try? fm.removeItem(at: stageRoot)
            throw NSError(domain: "UpdaterService", code: 35, userInfo: [NSLocalizedDescriptionKey: "更新包 Bundle ID 不匹配"])
        }

        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--verify", "--deep", "--strict", appURL.path]
        codesign.standardOutput = FileHandle.nullDevice
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        guard codesign.terminationStatus == 0 else {
            try? fm.removeItem(at: stageRoot)
            throw NSError(domain: "UpdaterService", code: 36, userInfo: [NSLocalizedDescriptionKey: "更新包代码签名校验失败"])
        }

        try? fm.removeItem(at: zipFile)
        return (appURL, stageRoot)
    }

    nonisolated private static func performSynchronousGET(
        url: URL,
        timeout: TimeInterval,
        accept: String = "*/*"
    ) throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.httpMethod = "GET"
        req.setValue("PromptPanel-macOS-Updater", forHTTPHeaderField: "User-Agent")
        req.setValue(accept, forHTTPHeaderField: "Accept")

        let sem = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultResp: URLResponse?
        var resultErr: Error?

        let task = URLSession.shared.dataTask(with: req) { data, resp, err in
            resultData = data
            resultResp = resp
            resultErr = err
            sem.signal()
        }
        task.resume()
        if sem.wait(timeout: .now() + timeout + 2.0) == .timedOut {
            task.cancel()
            throw NSError(domain: "UpdaterService", code: 40, userInfo: [NSLocalizedDescriptionKey: "网络请求超时，请检查网络连接后重试"])
        }

        if let resultErr {
            throw NSError(
                domain: "UpdaterService",
                code: 41,
                userInfo: [NSLocalizedDescriptionKey: friendlyUpdateErrorMessage(for: resultErr)]
            )
        }
        guard let http = resultResp as? HTTPURLResponse else {
            throw NSError(domain: "UpdaterService", code: 40, userInfo: [NSLocalizedDescriptionKey: "网络请求超时，请检查网络连接后重试"])
        }
        guard (200..<300).contains(http.statusCode), let data = resultData, !data.isEmpty else {
            throw NSError(
                domain: "UpdaterService",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: friendlyUpdateHTTPErrorMessage(statusCode: http.statusCode)]
            )
        }
        return data
    }

    nonisolated static func friendlyUpdateHTTPErrorMessage(statusCode: Int) -> String {
        switch statusCode {
        case 403, 429:
            return "GitHub 接口请求过于频繁或受限 (HTTP \(statusCode))，请稍后再试或配置同步镜像源"
        case 404:
            return "未找到最新发布版本信息 (HTTP 404)"
        case 500, 502, 503, 504:
            return "更新服务器暂时不可用 (HTTP \(statusCode))，请稍后重试"
        default:
            return "更新服务器返回异常状态 (HTTP \(statusCode))"
        }
    }

    nonisolated static func friendlyUpdateErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == "UpdaterService",
           let message = nsError.userInfo[NSLocalizedDescriptionKey] as? String,
           !message.isEmpty {
            return message
        }
        if nsError.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: nsError.code) {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                return "当前网络未连接，请检查网络设置"
            case .timedOut:
                return "检查更新请求超时，请稍后重试"
            case .cannotFindHost, .dnsLookupFailed:
                return "无法解析更新服务器域名，请检查网络或 DNS 设置"
            case .cannotConnectToHost:
                return "无法连接到更新服务器，请检查网络或代理设置"
            case .networkConnectionLost:
                return "下载更新时网络连接中断，请稍后重试"
            case .secureConnectionFailed,
                 .serverCertificateHasBadDate,
                 .serverCertificateUntrusted,
                 .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid:
                return "HTTPS 安全连接校验失败，请检查系统时间或代理配置"
            default:
                break
            }
        }
        return error.localizedDescription
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
