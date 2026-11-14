import AppKit
import CryptoKit
import Foundation
import Security
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
        let expectedTeamIdentifier: String?

        var isConfigured: Bool {
            feedURL != nil && publicKey?.isEmpty == false
        }

        /// In-place binary replacement without Sparkle requires a Developer ID TeamIdentifier
        /// anchor so ad-hoc / unsigned builds can never silently overwrite `.app` or break TCC
        /// Accessibility permissions.
        var canInstallBuiltInUpdates: Bool {
            guard let teamId = expectedTeamIdentifier else { return false }
            return Self.isValidAppleTeamIdentifier(teamId)
        }

        var statusMessage: String {
            if isConfigured {
                return "Sparkle 签名更新已就绪"
            }
            return "支持检查 GitHub Releases 更新"
        }

        static func isValidAppleTeamIdentifier(_ raw: String) -> Bool {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count == 10 else { return false }
            return trimmed.unicodeScalars.allSatisfy { scalar in
                CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII
            }
        }
    }

    nonisolated static let canonicalGitHubRepo = "qilaidev/PromptPanel"
    nonisolated static let canonicalReleasesURL = URL(string: "https://github.com/qilaidev/PromptPanel/releases")!

    @Published private(set) var canCheckForUpdates: Bool = true
    @Published private(set) var phase: UpdatePhase = .idle {
        didSet {
            onUpdateStateChanged?(phase)
        }
    }
    @Published var autoUpdateEnabled: Bool = false {
        didSet {
            if let updaterController {
                updaterController.updater.automaticallyChecksForUpdates = autoUpdateEnabled
                return
            }
            guard isStarted else { return }
            configurePeriodicCheckTimer()
            if autoUpdateEnabled {
                triggerBackgroundUpdateCheckIfNeeded()
            }
        }
    }

    var syncEndpointProvider: (() -> String)?
    var preInstallBackupHandler: (() -> Void)?
    var onUpdateStateChanged: ((UpdatePhase) -> Void)?

    let configurationState: ConfigurationState
    private let feedDelegate: FeedDelegate?
    private let updaterController: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?
    private var periodicTimer: Timer?
    private var isStarted = false
    private(set) var isUpdateFlowInFlight = false
    private var stagedCandidate: ReleaseCandidate?
    private var stagedAppURL: URL?
    private var stagedRootDir: URL?

    override convenience init() {
        self.init(configurationState: Self.resolveConfiguration(bundle: .main))
    }

    init(configurationState: ConfigurationState) {
        self.configurationState = configurationState
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
            return "\(configurationState.statusMessage) · \(autoUpdateEnabled ? "自动检查已开启" : "默认关闭自动联网检查")"
        }
        switch phase {
        case .idle:
            return "当前 v\(currentShortVersion) (\(currentBuildNumber)) · \(autoUpdateEnabled ? "自动检查新版本" : "手动检查（默认零联网）")"
        case .checking:
            return "正在检查新版本…"
        case .upToDate(let ver):
            return "已是最新版本 v\(ver)"
        case .updateAvailable(let ver, _):
            if configurationState.canInstallBuiltInUpdates {
                return "发现新版本 v\(ver)，点击下载并验证签名后更新"
            }
            return "发现新版本 v\(ver)，点击前往发布页手动更新（防辅助功能权限失效）"
        case .downloading(let ver):
            return "正在下载并校验 v\(ver) 开发者签名…"
        case .readyToInstall(let ver, _):
            return "新版本 v\(ver) 已通过签名校验，点击立即重启更新"
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
            return configurationState.canInstallBuiltInUpdates ? "下载更新 v\(ver)" : "查看 v\(ver) 发布页"
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
            updaterController.updater.automaticallyChecksForUpdates = autoUpdateEnabled
            updaterController.startUpdater()
            if #available(macOS 14.0, *) {
                updaterController.updater.clearFeedURLFromUserDefaults()
            }
            PPLogger.updater.info("Sparkle updater initialized (autoCheck=\(self.autoUpdateEnabled), feed=\(self.configurationState.feedURL?.absoluteString ?? "nil"))")
            return
        }

        configurePeriodicCheckTimer()
        if autoUpdateEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
                self?.triggerBackgroundUpdateCheckIfNeeded()
            }
        }
        PPLogger.updater.info("Release checker initialized (autoCheck=\(self.autoUpdateEnabled), canInstallInPlace=\(self.configurationState.canInstallBuiltInUpdates))")
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

    /// Background check only inspects release metadata and surfaces `.updateAvailable`;
    /// it never downloads or replaces the app bundle silently in the background.
    func triggerBackgroundUpdateCheckIfNeeded() {
        guard autoUpdateEnabled, !configurationState.isConfigured else { return }
        if case .readyToInstall = phase { return }
        guard canCheckForUpdates, !isUpdateFlowInFlight else { return }
        isUpdateFlowInFlight = true
        canCheckForUpdates = false
        phase = .checking
        Task { @MainActor in
            await performNativeUpdateFlow(userInitiated: false)
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
        if case .updateAvailable(let ver, _) = phase, let candidate = stagedCandidate {
            if !configurationState.canInstallBuiltInUpdates {
                return openManualReleaseGuide(for: candidate)
            }
            guard !isUpdateFlowInFlight else {
                return "正在准备 v\(ver) 更新包，请稍候…"
            }
            isUpdateFlowInFlight = true
            canCheckForUpdates = false
            Task { @MainActor in
                await downloadAndStageVerifiedCandidate(candidate)
            }
            return "正在下载并校验 v\(ver) 开发者签名…"
        }
        if isUpdateFlowInFlight {
            if case .downloading(let ver) = phase {
                return "正在下载并校验 v\(ver)，请稍候…"
            }
            return "正在检查新版本，请稍候…"
        }

        isUpdateFlowInFlight = true
        canCheckForUpdates = false
        phase = .checking
        Task { @MainActor in
            await performNativeUpdateFlow(userInitiated: true)
        }
        return "正在检查最新版本…"
    }

    private func openManualReleaseGuide(for candidate: ReleaseCandidate) -> String {
        let targetURL = candidate.releasePageURL
            .flatMap { Self.isAllowedUpdateURL($0) ? $0 : nil }
            ?? Self.canonicalReleasesURL
        NSWorkspace.shared.open(targetURL)
        return "已打开发布页（v\(candidate.version)）。当前构建未配置开发者证书锚定，请手动下载替换；替换后若自动粘贴失效，可在「设置 → 偏好 → 权限与启动」点击重置辅助功能权限。"
    }

    private func performNativeUpdateFlow(userInitiated: Bool) async {
        isUpdateFlowInFlight = true
        defer { isUpdateFlowInFlight = false }
        canCheckForUpdates = false
        phase = .checking
        let localVer = currentShortVersion
        let localBuild = currentBuildNumber
        let syncEndpoint = syncEndpointProvider?() ?? ""

        do {
            let candidate = try await Self.fetchLatestReleaseCandidate(
                syncEndpoint: syncEndpoint,
                forceRefresh: userInitiated
            )

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

            stagedCandidate = candidate
            // Without an anchored Developer ID TeamIdentifier (or on background checks),
            // stop at notification — never auto-download or silently overwrite the binary.
            guard userInitiated, configurationState.canInstallBuiltInUpdates else {
                phase = .updateAvailable(version: candidate.version, build: candidate.build)
                canCheckForUpdates = true
                return
            }

            try await stageVerifiedCandidateInternal(candidate)
        } catch {
            let friendlyMessage = Self.friendlyUpdateErrorMessage(for: error)
            PPLogger.updater.error("Update flow failed: \(friendlyMessage)")
            phase = .failed(message: "更新检查失败：\(friendlyMessage)")
            canCheckForUpdates = true
        }
    }

    private func downloadAndStageVerifiedCandidate(_ candidate: ReleaseCandidate) async {
        isUpdateFlowInFlight = true
        defer { isUpdateFlowInFlight = false }
        do {
            try await stageVerifiedCandidateInternal(candidate)
        } catch {
            let friendlyMessage = Self.friendlyUpdateErrorMessage(for: error)
            PPLogger.updater.error("Update download/verification failed: \(friendlyMessage)")
            phase = .failed(message: "更新校验失败：\(friendlyMessage)")
            canCheckForUpdates = true
        }
    }

    private func stageVerifiedCandidateInternal(_ candidate: ReleaseCandidate) async throws {
        guard let expectedTeamId = configurationState.expectedTeamIdentifier,
              ConfigurationState.isValidAppleTeamIdentifier(expectedTeamId) else {
            phase = .updateAvailable(version: candidate.version, build: candidate.build)
            canCheckForUpdates = true
            return
        }

        phase = .downloading(version: candidate.version)
        let expectedBundleId = Bundle.main.bundleIdentifier
        let (unpackedApp, tempRoot) = try await Self.downloadVerifyAndUnpack(
            candidate: candidate,
            expectedBundleId: expectedBundleId,
            expectedTeamIdentifier: expectedTeamId
        )

        if let oldRoot = stagedRootDir, oldRoot != tempRoot {
            try? FileManager.default.removeItem(at: oldRoot)
        }
        stagedCandidate = candidate
        stagedAppURL = unpackedApp
        stagedRootDir = tempRoot
        phase = .readyToInstall(version: candidate.version, build: candidate.build)
        canCheckForUpdates = true
    }

    @discardableResult
    func installStagedUpdateNow() -> String {
        guard let candidate = stagedCandidate else {
            return checkForUpdates()
        }
        guard configurationState.canInstallBuiltInUpdates,
              let expectedTeamId = configurationState.expectedTeamIdentifier else {
            return openManualReleaseGuide(for: candidate)
        }
        guard let stagedAppURL, FileManager.default.fileExists(atPath: stagedAppURL.path) else {
            return checkForUpdates()
        }

        do {
            try Self.verifyDeveloperIDSignature(
                appURL: stagedAppURL,
                expectedBundleId: Bundle.main.bundleIdentifier,
                expectedTeamIdentifier: expectedTeamId
            )
        } catch {
            let msg = Self.friendlyUpdateErrorMessage(for: error)
            phase = .failed(message: "安装前签名复核未通过：\(msg)")
            return "安装前签名复核未通过：\(msg)"
        }

        let targetAppURL = Bundle.main.bundleURL
        guard targetAppURL.pathExtension == "app" else {
            return openManualReleaseGuide(for: candidate)
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

    // MARK: - Transport & Code Signing Guards

    /// Enforces HTTPS for all update metadata and binary downloads, permitting plain HTTP
    /// strictly for local loopback addresses (`localhost`, `127.0.0.1`, `::1`).
    nonisolated static func isAllowedUpdateURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return false
        }
        if scheme == "https" {
            return true
        }
        if scheme == "http" {
            return isLoopbackHost(host)
        }
        return false
    }

    nonisolated static func isLoopbackHost(_ rawHost: String) -> Bool {
        let cleaned = rawHost
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()
        return cleaned == "localhost" || cleaned == "127.0.0.1" || cleaned == "::1"
    }

    nonisolated static func bundleTeamIdentifier(for bundleURL: URL) -> String? {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return nil
        }
        var signingInfoCF: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInfoCF
        )
        guard infoStatus == errSecSuccess,
              let signingInfo = signingInfoCF as? [String: Any],
              let teamId = (signingInfo[kSecCodeInfoTeamIdentifier as String] as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              ConfigurationState.isValidAppleTeamIdentifier(teamId) else {
            return nil
        }
        return teamId
    }

    /// Verifies that `appURL` is signed with a valid Apple Developer ID Application certificate
    /// anchored to `expectedTeamIdentifier` and matching `expectedBundleId`. Ad-hoc (`--sign -`)
    /// or third-party certificates are rejected.
    nonisolated static func verifyDeveloperIDSignature(
        appURL: URL,
        expectedBundleId: String?,
        expectedTeamIdentifier: String
    ) throws {
        guard ConfigurationState.isValidAppleTeamIdentifier(expectedTeamIdentifier) else {
            throw NSError(domain: "UpdaterService", code: 36, userInfo: [NSLocalizedDescriptionKey: "缺少有效的开发者 Team ID 签名锚点"])
        }
        let bundleClause: String
        if let expectedBundleId, !expectedBundleId.isEmpty {
            let sanitizedBundleId = expectedBundleId.replacingOccurrences(of: "\"", with: "")
            bundleClause = "identifier \"\(sanitizedBundleId)\" and "
        } else {
            bundleClause = ""
        }
        let requirementString = "\(bundleClause)anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = \"\(expectedTeamIdentifier)\""

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementString as CFString, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement else {
            throw NSError(domain: "UpdaterService", code: 36, userInfo: [NSLocalizedDescriptionKey: "无法构建开发者签名校验规则"])
        }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else {
            throw NSError(domain: "UpdaterService", code: 36, userInfo: [NSLocalizedDescriptionKey: "无法读取更新包代码签名"])
        }

        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        var validationError: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(staticCode, flags, requirement, &validationError)
        if status != errSecSuccess {
            _ = validationError?.takeRetainedValue()
            throw NSError(
                domain: "UpdaterService",
                code: 36,
                userInfo: [NSLocalizedDescriptionKey: "更新包未通过 Apple Developer ID (\(expectedTeamIdentifier)) 签名校验，已拒绝安装"]
            )
        }
    }

    // MARK: - Pure Helpers & Async Network Fetch

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
              let initialURL = comps.url,
              isAllowedUpdateURL(initialURL) else {
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
    ) async throws -> ReleaseCandidate {
        if let mirrorURL = resolvedUpdateURL(fromSyncEndpoint: syncEndpoint, forceRefresh: forceRefresh),
           let candidate = try? await fetchFromMirror(mirrorURL: mirrorURL) {
            return candidate
        }
        return try await fetchFromGitHub()
    }

    nonisolated private static func fetchFromMirror(mirrorURL: URL) async throws -> ReleaseCandidate {
        let data = try await performGET(url: mirrorURL, timeout: 8.0)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = (json["version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty,
              let zipDict = json["macosZip"] as? [String: Any] else {
            throw NSError(domain: "UpdaterService", code: 10, userInfo: [NSLocalizedDescriptionKey: "镜像返回格式无效"])
        }
        let build = (json["build"] as? Int) ?? 0
        let sha256 = ((json["macosZip"] as? [String: Any])?["sha256"] as? String ?? "").lowercased()
        let githubURL = (zipDict["githubUrl"] as? String)
            .flatMap(URL.init(string:))
            .flatMap { isAllowedUpdateURL($0) ? $0 : nil }
        var mirrorZipURL: URL?
        if let mirrorPath = zipDict["mirrorPath"] as? String, !mirrorPath.isEmpty,
           var baseComps = URLComponents(url: mirrorURL, resolvingAgainstBaseURL: false) {
            baseComps.path = mirrorPath
            baseComps.query = nil
            if let candidateURL = baseComps.url, isAllowedUpdateURL(candidateURL) {
                mirrorZipURL = candidateURL
            }
        }
        guard let primary = mirrorZipURL ?? githubURL else {
            throw NSError(domain: "UpdaterService", code: 11, userInfo: [NSLocalizedDescriptionKey: "未找到安全的 HTTPS macOS 更新包地址"])
        }
        let releasePage = (json["releaseUrl"] as? String)
            .flatMap(URL.init(string:))
            .flatMap { isAllowedUpdateURL($0) ? $0 : nil }
        return ReleaseCandidate(
            version: version,
            build: build,
            sha256: sha256,
            primaryZipURL: primary,
            fallbackZipURL: (primary == githubURL) ? nil : githubURL,
            releasePageURL: releasePage
        )
    }

    nonisolated private static func fetchFromGitHub() async throws -> ReleaseCandidate {
        guard let apiURL = URL(string: "https://api.github.com/repos/\(canonicalGitHubRepo)/releases/latest") else {
            throw NSError(domain: "UpdaterService", code: 20, userInfo: [NSLocalizedDescriptionKey: "GitHub 地址无效"])
        }
        let data = try await performGET(url: apiURL, timeout: 12.0, accept: "application/vnd.github+json")
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
                  let url = URL(string: urlStr),
                  isAllowedUpdateURL(url) else { continue }
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
           let sumsData = try? await performGET(url: sumsURL, timeout: 10.0),
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

        let releasePage = (json["html_url"] as? String)
            .flatMap(URL.init(string:))
            .flatMap { isAllowedUpdateURL($0) ? $0 : nil }
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
        expectedBundleId: String?,
        expectedTeamIdentifier: String
    ) async throws -> (URL, URL) {
        guard !candidate.sha256.isEmpty else {
            throw NSError(domain: "UpdaterService", code: 30, userInfo: [NSLocalizedDescriptionKey: "缺少发行包 SHA-256 校验值"])
        }

        let zipData: Data
        if let primaryData = try? await performGET(url: candidate.primaryZipURL, timeout: 60.0) {
            zipData = primaryData
        } else if let fallback = candidate.fallbackZipURL {
            zipData = try await performGET(url: fallback, timeout: 90.0)
        } else {
            throw NSError(domain: "UpdaterService", code: 31, userInfo: [NSLocalizedDescriptionKey: "下载更新包失败，请检查网络连接"])
        }

        let actualHash = SHA256.hash(data: zipData).map { String(format: "%02x", $0) }.joined()
        guard actualHash.lowercased() == candidate.sha256.lowercased() else {
            throw NSError(domain: "UpdaterService", code: 32, userInfo: [NSLocalizedDescriptionKey: "更新包 SHA-256 校验未通过，已拦截安装"])
        }

        let unpackResult = try await Task.detached(priority: .utility) { () throws -> (URL, URL) in
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

            do {
                try Self.verifyDeveloperIDSignature(
                    appURL: appURL,
                    expectedBundleId: expectedBundleId,
                    expectedTeamIdentifier: expectedTeamIdentifier
                )
            } catch {
                try? fm.removeItem(at: stageRoot)
                throw error
            }

            try? fm.removeItem(at: zipFile)
            return (appURL, stageRoot)
        }.value

        return unpackResult
    }

    nonisolated private static func performGET(
        url: URL,
        timeout: TimeInterval,
        accept: String = "*/*"
    ) async throws -> Data {
        guard isAllowedUpdateURL(url) else {
            throw NSError(
                domain: "UpdaterService",
                code: 42,
                userInfo: [NSLocalizedDescriptionKey: "安全策略拦截了非加密 HTTP 更新地址（仅支持 https:// 或本机 localhost）"]
            )
        }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.httpMethod = "GET"
        req.setValue("PromptPanel-macOS-Updater", forHTTPHeaderField: "User-Agent")
        req.setValue(accept, forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw NSError(
                domain: "UpdaterService",
                code: 41,
                userInfo: [NSLocalizedDescriptionKey: friendlyUpdateErrorMessage(for: error)]
            )
        }

        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "UpdaterService", code: 40, userInfo: [NSLocalizedDescriptionKey: "网络请求超时，请检查网络连接后重试"])
        }
        guard (200..<300).contains(http.statusCode), !data.isEmpty else {
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
            case .appTransportSecurityRequiresSecureConnection:
                return "系统安全策略要求使用 HTTPS 加密连接"
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

        let resolvedFeedURL = feedURLString
            .flatMap(URL.init(string:))
            .flatMap { isAllowedUpdateURL($0) ? $0 : nil }

        let teamId = bundleTeamIdentifier(for: bundle.bundleURL)

        return ConfigurationState(
            feedURL: resolvedFeedURL,
            publicKey: publicKey,
            expectedTeamIdentifier: teamId
        )
    }
}
