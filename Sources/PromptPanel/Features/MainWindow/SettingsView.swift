import AppKit
import CoreImage.CIFilterBuiltins
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: MainWindowViewModel

    private let columnSpacing: CGFloat = Constants.Layout.sectionSpacing

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.Layout.sectionSpacing) {
                HStack(alignment: .center, spacing: 12) {
                    SettingsAreaPicker(selection: $viewModel.selectedSettingsArea)
                    Spacer(minLength: 8)
                    SettingsHealthSummaryInline(viewModel: viewModel)
                }

                if let issue = SettingsHealthStrip.resolvePrimaryIssue(viewModel: viewModel) {
                    SettingsHealthIssueBanner(issue: issue)
                }

                selectedAreaContent
            }
            .padding(.horizontal, 16)
            .padding(.top, Design.Space.lg)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(Constants.VisualStyle.bg)
    }

    @ViewBuilder
    private var selectedAreaContent: some View {
        switch viewModel.selectedSettingsArea {
        case .preferences:
            HStack(alignment: .top, spacing: columnSpacing) {
                SettingsColumn {
                    GeneralSettingsSection(viewModel: viewModel)
                    PanelBehaviorSection(viewModel: viewModel)
                    GlobalHotkeysSection()
                }

                SettingsColumn {
                    CloudSyncSection(viewModel: viewModel)
                    PermissionSection(viewModel: viewModel)
                }
            }
        case .maintenance:
            VStack(alignment: .leading, spacing: Constants.Layout.sectionSpacing) {
                HStack(alignment: .top, spacing: columnSpacing) {
                    SettingsColumn {
                        OperationOverviewSection(viewModel: viewModel)
                    }

                    SettingsColumn {
                        MaintenanceSection(viewModel: viewModel)
                    }
                }

                DataLocationSection(viewModel: viewModel)
                RecentExecutionsSection(viewModel: viewModel)
            }
        }
    }
}

/// Two areas, not three.
///
/// 偏好 / 权限 / 维护 split eight short cards across three tabs, and the first two
/// each filled well under half of a 1040x760 window — the settings tab opened on a
/// screen that was mostly empty, and the permission controls sat a tab away from
/// everything else you configure once and forget. 权限 folds into 偏好, which is
/// what it always was: something you set once. The two names are unchanged, so
/// every documented `设置 → 偏好 → …` path still resolves.
enum SettingsArea: String, CaseIterable, Identifiable {
    case preferences
    case maintenance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preferences: return "偏好"
        case .maintenance: return "维护"
        }
    }

    var systemImage: String {
        switch self {
        case .preferences: return "slider.horizontal.3"
        case .maintenance: return "externaldrive"
        }
    }
}

private struct SettingsAreaPicker: View {
    @Binding var selection: SettingsArea

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsArea.allCases) { area in
                option(for: area)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Constants.VisualStyle.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
        )
    }

    private func option(for area: SettingsArea) -> some View {
        let isActive = selection == area
        return Button {
            selection = area
        } label: {
            HStack(spacing: 6) {
                Image(systemName: area.systemImage)
                    .font(.icon(.small))
                Text(area.title)
                    .font(.ui(.body, weight: .medium))
            }
            .foregroundStyle(isActive ? Constants.VisualStyle.text : Constants.VisualStyle.textTertiary)
            .padding(.horizontal, 12)
            .frame(height: Constants.Layout.compactControlHeight)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Constants.VisualStyle.accentDim : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isActive ? Constants.VisualStyle.accentBorder : Color.clear, lineWidth: Constants.Layout.hairline)
            )
            .hoverHighlight(cornerRadius: 6, isEnabled: !isActive)
            .roundedHitTarget(cornerRadius: 6)
        }
        .buttonStyle(PPInteractiveButtonStyle(cornerRadius: 6))
    }
}

// MARK: - Shared primitives

private struct SettingsColumn<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Layout.sectionSpacing) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct SettingsCard<Content: View, Accessory: View>: View {
    let title: String
    let accessory: () -> Accessory
    let content: () -> Content

    init(
        _ title: String,
        @ViewBuilder accessory: @escaping () -> Accessory,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack(alignment: .center, spacing: Design.Space.sm) {
                SectionHeading(title)
                Spacer(minLength: Design.Space.md)
                accessory()
            }
            .frame(minHeight: Constants.Layout.compactControlHeight - 4)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
        }
        .padding(Constants.Layout.sectionInset)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.sectionCornerRadius, style: .continuous)
                .fill(Constants.VisualStyle.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Constants.Layout.sectionCornerRadius, style: .continuous)
                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
        )
    }
}

extension SettingsCard where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, accessory: { EmptyView() }, content: content)
    }
}

struct SettingsBanner: View {
    let message: String
    /// True while a maintenance action is still running: the same strip doubles as
    /// the progress indicator so a long export is visibly in flight rather than
    /// looking like a frozen window.
    var isBusy: Bool = false
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "info.circle.fill")
                    .font(.icon(.base))
                    .foregroundStyle(Constants.VisualStyle.accent)
            }
            Text(message)
                .font(.ui(.body))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let onDismiss, !isBusy {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.icon(.micro, weight: .semibold))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                        .frame(width: 18, height: 18)
                        .roundedHitTarget(cornerRadius: 5)
                }
                .buttonStyle(.plain)
                .help("关闭提示")
            }
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.sectionCornerRadius, style: .continuous)
                .fill(Constants.VisualStyle.infoBannerFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Constants.Layout.sectionCornerRadius, style: .continuous)
                .strokeBorder(Constants.VisualStyle.infoBannerBorder, lineWidth: Constants.Layout.hairline)
        )
    }
}

private enum SettingsHealthStrip {
    struct Issue {
        let message: String
        let systemImage: String
        let color: Color
        let background: Color
    }

    @MainActor
    static func resolvePrimaryIssue(viewModel: MainWindowViewModel) -> Issue? {
        if viewModel.hasAccessibilityPermission == false {
            return Issue(
                message: "未开启辅助功能权限，当前仅支持复制到剪贴板",
                systemImage: "exclamationmark.triangle.fill",
                color: Constants.VisualStyle.warn,
                background: Constants.VisualStyle.warnDim
            )
        }
        if let snapshot = viewModel.storageHealthSnapshot, snapshot.backupCount == 0 {
            return Issue(
                message: "暂无本地备份，建议手动备份一次",
                systemImage: "externaldrive.badge.exclamationmark",
                color: Constants.VisualStyle.warn,
                background: Constants.VisualStyle.warnDim
            )
        }
        if let summary = viewModel.executionHealthSummary, summary.failedCount > 0 {
            return Issue(
                message: "近 7 天有 \(summary.failedCount) 次执行失败",
                systemImage: "exclamationmark.octagon.fill",
                color: Constants.VisualStyle.danger,
                background: Constants.VisualStyle.dangerDim
            )
        }
        return nil
    }
}

private struct SettingsHealthSummaryInline: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.hasAccessibilityPermission ? Constants.VisualStyle.success : Constants.VisualStyle.warn)
                .frame(width: 6, height: 6)
            Text(summaryText)
                .font(.ui(.caption, weight: .medium))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
            Text("·")
                .font(.ui(.caption))
                .foregroundStyle(Constants.VisualStyle.textQuaternary)
            Text("v" + Constants.appVersionDisplay)
                .font(.ui(.caption, weight: .medium, mono: true))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
        }
    }

    private var summaryText: String {
        let statusPrefix = viewModel.hasAccessibilityPermission ? "已授权" : "未授权"
        let backupText = viewModel.storageHealthSnapshot.map { "备份 \($0.backupCount)" } ?? "备份 --"
        return "\(statusPrefix) · \(backupText)"
    }
}

private struct SettingsHealthIssueBanner: View {
    let issue: SettingsHealthStrip.Issue

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: issue.systemImage)
                .font(.icon(.base))
                .foregroundStyle(issue.color)
            Text(issue.message)
                .font(.ui(.body, weight: .medium))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.sectionCornerRadius, style: .continuous)
                .fill(issue.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Constants.Layout.sectionCornerRadius, style: .continuous)
                .strokeBorder(issue.color.opacity(0.28), lineWidth: Constants.Layout.hairline)
        )
    }
}

struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        SectionHeading(title)
    }
}

struct SettingsRow<Control: View>: View {
    let label: String
    let hint: String?
    let control: Control
    let dense: Bool
    /// Rows separate themselves from the row below. The last row in a card has no
    /// row below it, so its hairline used to float against the card's inner padding
    /// as a stray line — pass `showsDivider: false` there.
    let showsDivider: Bool

    init(
        label: String,
        hint: String? = nil,
        dense: Bool = false,
        showsDivider: Bool = true,
        @ViewBuilder control: () -> Control
    ) {
        self.label = label
        self.hint = hint
        self.dense = dense
        self.showsDivider = showsDivider
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Design.Space.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.ui(.title, weight: .medium))
                    .foregroundStyle(Constants.VisualStyle.text)
                if let hint {
                    Text(hint)
                        .font(.ui(.caption))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            control
        }
        .padding(.vertical, dense ? Design.Space.xs : Design.Space.sm)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Constants.VisualStyle.divider)
                    .frame(height: Constants.Layout.hairline)
            }
        }
    }
}

struct SettingsPillButton: View {
    let title: String
    let systemImage: String?
    let tone: Tone
    let fillsAvailableWidth: Bool
    let action: () -> Void

    enum Tone {
        case neutral
        case primary
        case danger
    }

    init(
        _ title: String,
        systemImage: String? = nil,
        tone: Tone = .neutral,
        fillsAvailableWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.fillsAvailableWidth = fillsAvailableWidth
        self.action = action
    }

    var body: some View {
        PPActionButton(
            title,
            systemImage: systemImage,
            variant: mappedVariant,
            size: .compact,
            fillsAvailableWidth: fillsAvailableWidth,
            action: action
        )
    }

    private var mappedVariant: PPActionButton.Variant {
        switch tone {
        case .primary: return .primary
        case .neutral: return .secondary
        case .danger: return .danger
        }
    }
}

// MARK: - Left column sections

private struct GeneralSettingsSection: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        SettingsCard("通用") {
            SettingsRow(label: "主题") {
                ThemeSegmentedPicker(selection: Binding(
                    get: { viewModel.appTheme },
                    set: { viewModel.setAppTheme($0) }
                ))
            }
            SettingsRow(label: "默认排序") {
                EntrySortSegmentedPicker(selection: Binding(
                    get: { viewModel.entrySortMode },
                    set: { viewModel.entrySortMode = $0 }
                ))
            }
            SettingsRow(label: "登录时启动") {
                Toggle("", isOn: Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { viewModel.setLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            SettingsRow(label: "自动更新") {
                Toggle("", isOn: Binding(
                    get: { viewModel.autoUpdateEnabled },
                    set: { viewModel.setAutoUpdateEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            SettingsRow(label: "软件版本", showsDivider: false) {
                HStack(spacing: Design.Space.sm) {
                    Text(viewModel.updaterStatusMessage)
                        .font(.ui(.caption))
                        .foregroundStyle(
                            viewModel.hasPendingAppUpdate
                                ? Constants.VisualStyle.accent
                                : Constants.VisualStyle.textSecondary
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                    PPActionButton(
                        viewModel.updaterActionTitle,
                        systemImage: "arrow.triangle.2.circlepath",
                        variant: viewModel.hasPendingAppUpdate ? .primary : .secondary,
                        size: .compact
                    ) {
                        viewModel.checkForUpdates()
                    }
                }
            }
        }
    }
}

/// Every global action with its own set of interchangeable shortcuts.
private struct GlobalHotkeysSection: View {
    var body: some View {
        SettingsCard("全局快捷键", accessory: {
            Text("每项最多 \(GlobalHotkeyAction.maxBindings) 个 · 仅本机生效")
                .font(.ui(.caption))
                .foregroundStyle(Constants.VisualStyle.textQuaternary)
        }) {
            ForEach(GlobalHotkeyAction.allCases) { action in
                SettingsRow(
                    label: action.title,
                    hint: action.hint,
                    showsDivider: action != GlobalHotkeyAction.allCases.last
                ) {
                    MultiHotkeyBindingsField(action: action)
                }
            }
        }
    }
}

private struct ThemeSegmentedPicker: View {
    @Binding var selection: AppTheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTheme.allCases) { theme in
                option(for: theme)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Constants.VisualStyle.inputFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
        )
    }

    private func option(for theme: AppTheme) -> some View {
        let isActive = selection == theme
        return Button {
            selection = theme
        } label: {
            HStack(spacing: 5) {
                Image(systemName: theme.systemImageName)
                    .font(.icon(.small))
                Text(theme.title)
                    .font(.ui(.body, weight: .medium))
            }
            .foregroundStyle(isActive ? Constants.VisualStyle.text : Constants.VisualStyle.textTertiary)
            .padding(.horizontal, Design.Space.md)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isActive ? Constants.VisualStyle.segmentActiveFill : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isActive ? Constants.VisualStyle.border : Color.clear, lineWidth: Constants.Layout.hairline)
            )
            .hoverHighlight(cornerRadius: 5, isEnabled: !isActive)
            .roundedHitTarget(cornerRadius: 5)
        }
        .buttonStyle(PPInteractiveButtonStyle(cornerRadius: 5))
    }
}

private struct EntrySortSegmentedPicker: View {
    @Binding var selection: MainWindowViewModel.EntrySortMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MainWindowViewModel.EntrySortMode.allCases) { mode in
                option(for: mode)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Constants.VisualStyle.inputFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
        )
    }

    private func option(for mode: MainWindowViewModel.EntrySortMode) -> some View {
        let isActive = selection == mode
        return Button {
            selection = mode
        } label: {
            Text(mode.title)
                .font(.ui(.body, weight: .medium))
                .foregroundStyle(isActive ? Constants.VisualStyle.text : Constants.VisualStyle.textTertiary)
                .padding(.horizontal, Design.Space.md)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isActive ? Constants.VisualStyle.segmentActiveFill : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(isActive ? Constants.VisualStyle.border : Color.clear, lineWidth: Constants.Layout.hairline)
                )
                .hoverHighlight(cornerRadius: 5, isEnabled: !isActive)
                .roundedHitTarget(cornerRadius: 5)
        }
        .buttonStyle(PPInteractiveButtonStyle(cornerRadius: 5))
    }
}

private struct PanelBehaviorSection: View {
    @ObservedObject var viewModel: MainWindowViewModel
    @AppStorage(Constants.LocalDefaultsKey.restoreClipboardAfterPaste) private var restoreClipboardAfterPaste = false

    var body: some View {
        SettingsCard("快捷面板") {
            SettingsRow(
                label: "粘贴后恢复剪贴板",
                hint: "自动粘贴成功后放回你原来复制的内容；仅复制时保留词条"
            ) {
                Toggle("", isOn: $restoreClipboardAfterPaste)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            SettingsRow(label: "固定面板") {
                Toggle("", isOn: Binding(
                    get: { viewModel.isPanelPinned },
                    set: { viewModel.setPanelPinned($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            SettingsRow(label: "显示底栏键位") {
                Toggle("", isOn: Binding(
                    get: { viewModel.panelShowFooter },
                    set: { viewModel.setPanelShowFooter($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            SettingsRow(label: "紧凑行高") {
                Toggle("", isOn: Binding(
                    get: { viewModel.panelCompactRows },
                    set: { viewModel.setPanelCompactRows($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            SettingsRow(label: "面板尺寸", showsDivider: false) {
                PanelSizeControls(viewModel: viewModel)
            }
        }
    }
}

private struct PanelSizeControls: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        HStack(spacing: 6) {
            dimensionStepper(
                label: "宽",
                value: Binding(
                    get: { Int(viewModel.panelContentSize.width.rounded()) },
                    set: { viewModel.setPanelContentWidth($0) }
                ),
                bounds: Int(Constants.panelMinContentSize.width)...Int(Constants.panelMaxContentSize.width)
            )
            dimensionStepper(
                label: "高",
                value: Binding(
                    get: { Int(viewModel.panelContentSize.height.rounded()) },
                    set: { viewModel.setPanelContentHeight($0) }
                ),
                bounds: Int(Constants.panelMinContentSize.height)...Int(Constants.panelMaxContentSize.height)
            )
            PPActionButton(
                systemImage: "arrow.counterclockwise",
                variant: .secondary,
                size: .compact
            ) {
                viewModel.resetPanelContentSize()
            }
            .help("恢复默认面板尺寸 (560 × 700)")
        }
    }

    private func dimensionStepper(label: String, value: Binding<Int>, bounds: ClosedRange<Int>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.ui(.caption, weight: .medium))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
            Text("\(value.wrappedValue)")
                .font(.ui(.body, weight: .medium, mono: true))
                .foregroundStyle(Constants.VisualStyle.text)
                .frame(width: 34, alignment: .trailing)
            Stepper("", value: value, in: bounds, step: 20)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
        }
        .padding(.leading, 7)
        .padding(.trailing, 3)
        .frame(height: Constants.Layout.compactControlHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Constants.VisualStyle.inputFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
        )
    }
}

private struct PermissionSection: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        SettingsCard("辅助功能权限") {
            permissionPill
        } content: {
            if !viewModel.hasAccessibilityPermission {
                Text("未授权时仅支持复制到剪贴板。若系统设置已勾选仍显示未授权，可先重置授权再重新开启 PromptPanel.app。")
                    .font(.ui(.caption))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Design.Space.sm)

                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: Design.Space.xs),
                        count: 2
                    ),
                    alignment: .leading,
                    spacing: Design.Space.xs
                ) {
                    PPActionButton("请求授权", systemImage: "hand.raised", variant: .primary, size: .compact, fillsAvailableWidth: true) {
                        viewModel.requestAccessibilityPermission()
                    }
                    PPActionButton("系统设置", systemImage: "arrow.up.forward", variant: .secondary, size: .compact, fillsAvailableWidth: true) {
                        viewModel.openAccessibilitySettings()
                    }
                    PPActionButton("重新检测", systemImage: "arrow.clockwise", variant: .secondary, size: .compact, fillsAvailableWidth: true) {
                        viewModel.refreshPermissionState()
                    }
                    PPActionButton("重置授权", systemImage: "arrow.counterclockwise", variant: .secondary, size: .compact, fillsAvailableWidth: true) {
                        viewModel.resetAccessibilityApproval()
                    }
                }
            } else {
                HStack(spacing: Design.Space.xs) {
                    PPActionButton("系统设置", systemImage: "arrow.up.forward", variant: .secondary, size: .compact, fillsAvailableWidth: true) {
                        viewModel.openAccessibilitySettings()
                    }
                    PPActionButton("重新检测", systemImage: "arrow.clockwise", variant: .secondary, size: .compact, fillsAvailableWidth: true) {
                        viewModel.refreshPermissionState()
                    }
                    PPActionButton("重置授权", systemImage: "arrow.counterclockwise", variant: .secondary, size: .compact, fillsAvailableWidth: true) {
                        viewModel.resetAccessibilityApproval()
                    }
                }
            }
        }
    }

    private var permissionPill: some View {
        let granted = viewModel.hasAccessibilityPermission
        let color: Color = granted ? Constants.VisualStyle.success : Constants.VisualStyle.warn
        let dim: Color = granted ? Constants.VisualStyle.successDim : Constants.VisualStyle.warnDim
        return HStack(spacing: 4) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.icon(.micro, weight: .semibold))
            Text(granted ? "已授权" : "未授权")
                .font(.ui(.body, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(dim)
        )
    }
}

// MARK: - Right column & maintenance sections

private struct OperationOverviewSection: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        SettingsCard("运行概况") {
            QuietIconButton(systemImage: "arrow.clockwise", help: "刷新运行状态") {
                viewModel.refreshOperationalStatus()
                viewModel.refreshUpdaterStatus()
                viewModel.refreshLogs()
            }
        } content: {
            SettingsRow(label: "当前版本", dense: true) {
                valueText(Constants.appVersionDisplay, monospaced: true)
            }
            SettingsRow(label: "更新状态", dense: true) {
                Text(viewModel.updaterStatusMessage)
                    .font(.ui(.body))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 240, alignment: .trailing)
            }

            if let snapshot = viewModel.storageHealthSnapshot {
                SettingsRow(label: "数据大小", dense: true) {
                    valueText(ByteCountFormatter.string(fromByteCount: snapshot.databaseSizeBytes, countStyle: .file))
                }
                SettingsRow(label: "本地备份", dense: true) {
                    valueText("\(snapshot.backupCount) / \(Constants.automaticBackupRetentionCount) 份")
                }
                SettingsRow(label: "最近备份", dense: true) {
                    valueText(format(date: snapshot.latestBackupModifiedAt))
                }
            }

            if let summary = viewModel.executionHealthSummary {
                VStack(alignment: .leading, spacing: Design.Space.xs) {
                    Text("近 7 天执行")
                        .font(.ui(.caption))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                    HStack(spacing: 0) {
                        executionStatCell(title: "总计", value: "\(summary.totalCount)", accentValue: false)
                        statDivider
                        executionStatCell(title: "成功", value: "\(summary.successCount)", accentValue: false)
                        statDivider
                        executionStatCell(title: "仅复制", value: "\(summary.clipboardOnlyCount)", accentValue: false)
                        statDivider
                        executionStatCell(
                            title: "失败",
                            value: "\(summary.failedCount)",
                            accentValue: summary.failedCount > 0
                        )
                    }
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Constants.VisualStyle.tintSubtle)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                    )
                }
                .padding(.vertical, Design.Space.sm)
                .overlay(
                    Rectangle()
                        .fill(Constants.VisualStyle.divider)
                        .frame(height: Constants.Layout.hairline),
                    alignment: .bottom
                )

                SettingsRow(
                    label: "最近执行",
                    dense: true,
                    showsDivider: summary.latestFailureAt != nil
                ) {
                    valueText(format(date: summary.latestExecutionAt))
                }
                if let latestFailureAt = summary.latestFailureAt {
                    SettingsRow(label: "最近异常", dense: true, showsDivider: false) {
                        valueText(format(date: latestFailureAt))
                    }
                }
            } else {
                Text("暂无执行统计")
                    .font(.ui(.body))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
                    .padding(.vertical, Design.Space.md)
            }
        }
    }

    private func valueText(_ value: String, monospaced: Bool = false) -> some View {
        Text(value)
            .font(.ui(.body, weight: .medium, mono: monospaced))
            .foregroundStyle(Constants.VisualStyle.textSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func format(date: Date?) -> String {
        guard let date else { return "暂无" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Constants.VisualStyle.divider)
            .frame(width: Constants.Layout.hairline, height: 22)
    }

    private func executionStatCell(title: String, value: String, accentValue: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.ui(.caption))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
            Text(value)
                .font(.ui(.body, weight: .semibold, mono: true))
                .foregroundStyle(accentValue ? Constants.VisualStyle.danger : Constants.VisualStyle.text)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MaintenanceSection: View {
    @ObservedObject var viewModel: MainWindowViewModel

    private var isBusy: Bool {
        viewModel.activeMaintenanceTask != nil
    }

    var body: some View {
        SettingsCard("维护操作") {
            actionGroup(title: "备份与数据", columns: 3) {
                PPActionButton("立即备份", systemImage: "plus", variant: .primary, size: .compact, fillsAvailableWidth: true) {
                    viewModel.createBackupNow()
                }
                PPActionButton("数据目录", systemImage: "folder", variant: .secondary, size: .compact, fillsAvailableWidth: true) {
                    viewModel.openDataDirectory()
                }
                PPActionButton("备份目录", systemImage: "tray.full", variant: .secondary, size: .compact, fillsAvailableWidth: true) {
                    viewModel.openBackupDirectory()
                }
            }

            actionGroup(title: "导入与导出", columns: 2) {
                PPActionButton("导出 JSON", systemImage: "square.and.arrow.up", variant: .secondary, size: .compact, fillsAvailableWidth: true) {
                    viewModel.exportLibraryAsJSON()
                }
                PPActionButton("导出 MD", systemImage: "doc.text", variant: .secondary, size: .compact, fillsAvailableWidth: true) {
                    viewModel.exportLibraryAsMarkdown()
                }
                PPActionButton("导入 JSON", systemImage: "square.and.arrow.down", variant: .secondary, size: .compact, fillsAvailableWidth: true) {
                    viewModel.importLibraryFromJSON()
                }
                PPActionButton("导入 MD", systemImage: "doc.text.fill", variant: .secondary, size: .compact, fillsAvailableWidth: true) {
                    viewModel.importLibraryFromMarkdown()
                }
            }

            actionGroup(title: "诊断与清理", columns: 3) {
                PPActionButton(
                    viewModel.updaterActionTitle,
                    systemImage: "arrow.down.circle",
                    variant: viewModel.hasPendingAppUpdate ? .primary : .secondary,
                    size: .compact,
                    fillsAvailableWidth: true
                ) {
                    viewModel.checkForUpdates()
                }
                PPActionButton("导出诊断", systemImage: "doc.zipper", variant: .secondary, size: .compact, fillsAvailableWidth: true) {
                    viewModel.exportDiagnosticsBundle()
                }
                PPActionButton("清理日志", systemImage: "trash", variant: .danger, size: .compact, fillsAvailableWidth: true) {
                    viewModel.cleanupLogs()
                }
            }

            Text(footnote)
                .font(.ui(.caption))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Design.Space.xs)
        }
    }

    private var footnote: String {
        if let task = viewModel.activeMaintenanceTask {
            return "正在\(task)…"
        }
        return "导入前自动备份；手动备份不会自动清理"
    }

    @ViewBuilder
    private func actionGroup<Content: View>(
        title: String,
        columns: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            Text(title)
                .font(.ui(.caption, weight: .medium))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: Design.Space.xs),
                    count: columns
                ),
                alignment: .leading,
                spacing: Design.Space.xs
            ) {
                content()
            }
        }
        .padding(.vertical, Design.Space.xs)
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
    }
}

// MARK: - Bottom full-width sections

private struct DataLocationSection: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        SettingsCard("数据位置") {
            if let snapshot = viewModel.storageHealthSnapshot {
                VStack(alignment: .leading, spacing: Design.Space.xs) {
                    pathRow(title: "数据库", value: snapshot.databaseURL.path)
                    pathRow(title: "备份目录", value: snapshot.backupDirectoryURL.path)
                    pathRow(title: "恢复隔离", value: snapshot.recoveryDirectoryURL.path)
                    pathRow(title: "日志目录", value: snapshot.logsDirectoryURL.path)
                    if let url = snapshot.latestBackupURL {
                        pathRow(title: "最近备份", value: url.path)
                    }
                }
            } else {
                Text("正在加载路径…")
                    .font(.ui(.body))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
            }
        }
    }

    private func pathRow(title: String, value: String) -> some View {
        HStack(spacing: Design.Space.sm) {
            Text(title)
                .font(.ui(.caption, weight: .medium))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.ui(.caption, mono: true))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, Design.Space.md)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Constants.VisualStyle.tintSubtle)
                )
            QuietIconButton(systemImage: "doc.on.doc", help: "复制路径") {
                copyPath(value)
            }
        }
    }

    private func copyPath(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }
}

private struct RecentExecutionsSection: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        SettingsCard("最近执行记录") {
            if viewModel.recentExecutionLogs.isEmpty {
                HStack(spacing: Design.Space.sm) {
                    Image(systemName: "tray")
                        .font(.icon(.base))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                    Text("暂无执行记录")
                        .font(.ui(.body))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Design.Space.xs)
            } else {
                VStack(spacing: Design.Space.xs) {
                    ForEach(viewModel.recentExecutionLogs.prefix(6)) { log in
                        ExecutionLogRow(log: log, projectName: viewModel.projectName(for: log.projectId))
                    }
                }
                .padding(.top, 1)
            }
        }
    }
}

private struct ExecutionLogRow: View {
    let log: ExecutionLog
    let projectName: String

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            HStack(spacing: Design.Space.sm) {
                Text(resultTitle)
                    .font(.ui(.body, weight: .semibold))
                    .foregroundStyle(resultColor)
                Text(projectName)
                    .font(.ui(.caption))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                Spacer(minLength: 0)
                Text(log.createdAt.formatted(date: .abbreviated, time: .standard))
                    .font(.ui(.caption))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
            }
            HStack(spacing: Design.Space.lg) {
                metaField(title: "目标应用", value: log.frontAppBundleId ?? "未知", mono: true)
                if let durationText {
                    metaField(title: "耗时", value: durationText, mono: true)
                }
                metaField(title: "权限", value: log.hasAccessibility ? "已授权" : "未授权")
                metaField(title: "自动粘贴", value: log.pasteAttempted ? (log.pasteSuccess ? "成功" : "失败") : "未尝试")
                Spacer(minLength: 0)
            }
            if let failureReasonTitle {
                metaField(title: "失败原因", value: failureReasonTitle, isAlert: true)
            }
        }
        .padding(Design.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Constants.VisualStyle.tintSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
        )
    }

    private var resultTitle: String {
        switch log.result {
        case Constants.ExecutionResult.success.rawValue: return "成功"
        case Constants.ExecutionResult.clipboardOnly.rawValue: return "仅复制"
        default: return "失败"
        }
    }

    private var resultColor: Color {
        switch log.result {
        case Constants.ExecutionResult.success.rawValue: return Constants.VisualStyle.success
        case Constants.ExecutionResult.clipboardOnly.rawValue: return Constants.VisualStyle.warn
        default: return Constants.VisualStyle.danger
        }
    }

    private var durationText: String? {
        guard let totalDurationMs = log.totalDurationMs else { return nil }
        return "\(totalDurationMs) ms"
    }

    private var failureReasonTitle: String? {
        guard let failureReason = log.failureReason else { return nil }
        switch failureReason {
        case Constants.ExecutionFailureReason.clipboardWriteFailed.rawValue: return "剪贴板写入失败"
        case Constants.ExecutionFailureReason.accessibilityNotGranted.rawValue: return "辅助功能权限未授权"
        case Constants.ExecutionFailureReason.targetAppNotRestored.rawValue: return "原目标应用未恢复前台"
        case Constants.ExecutionFailureReason.pasteEventCreationFailed.rawValue: return "自动粘贴事件创建失败"
        default: return "未分类"
        }
    }

    private func metaField(title: String, value: String, mono: Bool = false, isAlert: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.ui(.micro, weight: .medium))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
            Text(value)
                .font(.ui(.caption, weight: .medium, mono: mono))
                .foregroundStyle(isAlert ? Constants.VisualStyle.danger : Constants.VisualStyle.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct CloudSyncSection: View {
    @ObservedObject var viewModel: MainWindowViewModel

    private enum CloudSyncField: Hashable {
        case endpoint
        case apiKey
    }

    @FocusState private var focusedField: CloudSyncField?
    private var _savedEndpoint = SwiftUI.State(initialValue: "")
    private var _savedApiKey = SwiftUI.State(initialValue: "")
    private var _isShowingTrashRecoverySheet = SwiftUI.State(initialValue: false)
    private var _isShowingForceOverwriteAlert = SwiftUI.State(initialValue: false)

    private var savedEndpoint: String {
        get { _savedEndpoint.wrappedValue }
        nonmutating set { _savedEndpoint.wrappedValue = newValue }
    }

    private var savedApiKey: String {
        get { _savedApiKey.wrappedValue }
        nonmutating set { _savedApiKey.wrappedValue = newValue }
    }

    private var isShowingTrashRecoverySheet: Bool {
        get { _isShowingTrashRecoverySheet.wrappedValue }
        nonmutating set { _isShowingTrashRecoverySheet.wrappedValue = newValue }
    }

    private var isShowingForceOverwriteAlert: Bool {
        get { _isShowingForceOverwriteAlert.wrappedValue }
        nonmutating set { _isShowingForceOverwriteAlert.wrappedValue = newValue }
    }

    private var isBusy: Bool {
        viewModel.activeMaintenanceTask != nil
    }

    private var trimmedEndpoint: String {
        viewModel.cloudSyncEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isConfigured: Bool {
        !trimmedEndpoint.isEmpty
    }

    private var hasUnsavedConfig: Bool {
        viewModel.cloudSyncEndpoint != savedEndpoint || viewModel.cloudSyncApiKey != savedApiKey
    }

    private var autoSyncModeDescription: String {
        viewModel.cloudSyncEnabled
            ? "已开启自动双向同步：启动、切回前台、本地修改 2 秒后及每 45 秒自动检查云端，先拉取合并远端变更，再推送本地新变更"
            : "当前为手动同步模式：不会后台自动传输；仅在点击“立即双向同步”时先拉取远端新变更合并，再推送本地修改"
    }

    private var channelDisplayName: String {
        if let kind = viewModel.lastSyncReport?.channelKind {
            return kind == "https" ? "HTTPS 端到端加密" : "本地或 iCloud 文件"
        }
        let lower = trimmedEndpoint.lowercased()
        if lower.hasPrefix("https://") || lower.hasPrefix("http://") {
            return "HTTPS 端到端加密"
        }
        return isConfigured ? "本地或 iCloud 文件" : "未配置通道"
    }

    private var effectiveRevisionText: String {
        if let rev = viewModel.cloudRemoteRevision ?? viewModel.lastSyncReport?.remoteRevision, rev > 0 {
            return "r\(rev)"
        }
        return "待首次对齐"
    }

    private var localDeltaStatusText: String {
        if viewModel.hasPendingLocalChanges {
            let count = max(viewModel.pendingLocalDelta, 1)
            return "有 \(count) 项本地待推送"
        }
        return "与云端一致"
    }

    var body: some View {
        SettingsCard("云端同步") {
            SyncStatusBadge(state: viewModel.syncBadgeState)
        } content: {
            SettingsRow(
                label: "自动同步",
                hint: autoSyncModeDescription,
                showsDivider: false
            ) {
                Toggle("", isOn: Binding(
                    get: { viewModel.cloudSyncEnabled },
                    set: { viewModel.setCloudSyncEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if viewModel.isSyncAuthPaused {
                authPausedBanner
                    .padding(.top, Design.Space.xs)
            }

            telemetryOverviewCard
                .padding(.top, Design.Space.sm)

            VStack(alignment: .leading, spacing: Design.Space.sm) {
                HStack(alignment: .center) {
                    Text("同步地址")
                        .font(.ui(.caption, weight: .medium))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                    Spacer()
                    Button {
                        viewModel.chooseCloudSyncFileLocation()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "folder")
                                .font(.icon(.micro))
                            Text("选择本地文件…")
                                .font(.ui(.caption, weight: .medium))
                        }
                        .foregroundStyle(Constants.VisualStyle.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .hoverHighlight(cornerRadius: 4)
                    }
                    .buttonStyle(PPInteractiveButtonStyle(cornerRadius: 4))
                }

                TextField("https://... 或本地文件路径", text: $viewModel.cloudSyncEndpoint)
                    .textFieldStyle(.plain)
                    .font(.ui(.caption, mono: true))
                    .foregroundStyle(Constants.VisualStyle.text)
                    .focused($focusedField, equals: .endpoint)
                    .padding(.horizontal, Design.Space.md)
                    .frame(height: 26)
                    .focusableInputSurface(isFocused: focusedField == .endpoint, cornerRadius: 6)
                    .onSubmit {
                        commitCloudSyncConfig()
                    }

                HStack(alignment: .center) {
                    Text("访问令牌 (Token)")
                        .font(.ui(.caption, weight: .medium))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                    Spacer()
                    Button {
                        viewModel.generateNewCloudSyncToken()
                        syncSavedConfigSnapshot()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "key")
                                .font(.icon(.micro))
                            Text("生成 Token")
                                .font(.ui(.caption, weight: .medium))
                        }
                        .foregroundStyle(Constants.VisualStyle.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .hoverHighlight(cornerRadius: 4)
                    }
                    .buttonStyle(PPInteractiveButtonStyle(cornerRadius: 4))
                }

                SecureField("不少于 12 位字符（本地文件同步可留空）", text: $viewModel.cloudSyncApiKey)
                    .textFieldStyle(.plain)
                    .font(.ui(.caption, mono: true))
                    .foregroundStyle(Constants.VisualStyle.text)
                    .focused($focusedField, equals: .apiKey)
                    .padding(.horizontal, Design.Space.md)
                    .frame(height: 26)
                    .focusableInputSurface(isFocused: focusedField == .apiKey, cornerRadius: 6)
                    .onSubmit {
                        commitCloudSyncConfig()
                    }

                configPersistenceBar

                VStack(alignment: .leading, spacing: Design.Space.xs) {
                    PPActionButton(
                        "立即双向同步",
                        systemImage: "arrow.triangle.2.circlepath",
                        variant: .primary,
                        size: .regular,
                        fillsAvailableWidth: true
                    ) {
                        commitCloudSyncConfig(showBanner: false)
                        viewModel.syncCloudNow()
                    }
                    .disabled(isBusy || !isConfigured)
                    .help("先拉取云端更新并合并冲突，再推送本地新变更")

                    Text("先拉取云端更新并合并冲突，再推送本地新变更")
                        .font(.ui(.micro))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                        .padding(.horizontal, 2)
                }
                .padding(.top, 2)

                HStack(spacing: Design.Space.xs) {
                    PPActionButton("测试连接", systemImage: "bolt.horizontal.circle", variant: .secondary, size: .compact, fillsAvailableWidth: true) {
                        commitCloudSyncConfig(showBanner: false)
                        viewModel.testCloudSyncConnection()
                    }
                    .disabled(isBusy || !isConfigured)

                    PPActionButton("扫码配对手机", systemImage: "qrcode", variant: .secondary, size: .compact, fillsAvailableWidth: true) {
                        commitCloudSyncConfig(showBanner: false)
                        viewModel.openMobilePairingQRSheet()
                    }
                    .disabled(!isConfigured)

                    PPActionButton("复制手机配置", systemImage: "iphone.and.arrow.forward", variant: .secondary, size: .compact, fillsAvailableWidth: true) {
                        commitCloudSyncConfig(showBanner: false)
                        viewModel.copyMobileSyncBundleToClipboard()
                    }
                    .disabled(!isConfigured)
                }

                HStack(spacing: Design.Space.xs) {
                    Menu {
                        Button("仅从云端拉取合并到本地") {
                            commitCloudSyncConfig(showBanner: false)
                            viewModel.pullCloudOnly()
                        }
                        .disabled(isBusy || !isConfigured)

                        Button("查看最近 30 天已删除（按条恢复）") {
                            viewModel.refreshRecentSoftDeletedEntries()
                            isShowingTrashRecoverySheet = true
                        }

                        Divider()

                        Button("强制以本机覆盖云端…", role: .destructive) {
                            isShowingForceOverwriteAlert = true
                        }
                        .disabled(isBusy || !isConfigured)

                        Divider()

                        Button("复制服务端部署命令") {
                            viewModel.copyOpenSourceDeployCommand()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "slider.horizontal.below.rectangle")
                                .font(.icon(.small, weight: .medium))
                            Text("高级操作")
                                .font(.ui(.caption, weight: .medium))
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.down")
                                .font(.icon(.nano, weight: .semibold))
                                .foregroundStyle(Constants.VisualStyle.textTertiary)
                        }
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                        .padding(.horizontal, 9)
                        .frame(maxWidth: .infinity)
                        .frame(height: Constants.Layout.compactControlHeight)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Constants.VisualStyle.tintSubtle)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                        )
                        .hoverHighlight(cornerRadius: 6)
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            .padding(.top, Design.Space.md)
        }
        .onAppear {
            syncSavedConfigSnapshot()
        }
        .onChange(of: viewModel.bannerMessage) { _, message in
            if message == "云端同步配置已保存。" || message == "已生成 Token 并复制到剪贴板。" {
                syncSavedConfigSnapshot()
            }
        }
        .sheet(isPresented: $viewModel.isShowingMobilePairingQR) {
            MobilePairingQRSheet(viewModel: viewModel)
        }
        .sheet(isPresented: _isShowingTrashRecoverySheet.projectedValue) {
            SoftDeletedEntriesRecoverySheet(viewModel: viewModel)
        }
        .alert("确认强制以本机覆盖云端？", isPresented: _isShowingForceOverwriteAlert.projectedValue) {
            Button("取消", role: .cancel) {}
            Button("强制覆盖云端", role: .destructive) {
                commitCloudSyncConfig(showBanner: false)
                viewModel.forcePushLocalToCloud()
            }
        } message: {
            Text("此操作将以当前 Mac 的本地数据作为唯一基准覆盖云端快照，并软删云端多出的非内置分组与词条。操作前请确认其他设备没有尚未合并的修改。")
        }
    }

    private var authPausedBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.icon(.base, weight: .semibold))
                .foregroundStyle(Constants.VisualStyle.danger)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("云端同步鉴权异常，后台自动同步已暂停")
                    .font(.ui(.body, weight: .semibold))
                    .foregroundStyle(Constants.VisualStyle.danger)
                Text("请核对访问令牌 (Token) 或同步地址并保存配置，然后点击“测试连接”或“立即双向同步”手动重试。")
                    .font(.ui(.caption))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Constants.VisualStyle.dangerDim)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Constants.VisualStyle.danger.opacity(0.32), lineWidth: Constants.Layout.hairline)
        )
    }

    private var telemetryOverviewCard: some View {
        let report = viewModel.lastSyncReport
        return VStack(alignment: .leading, spacing: Design.Space.sm) {
            HStack(spacing: 6) {
                Text("同步状态与遥测概览")
                    .font(.ui(.caption, weight: .semibold))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                Spacer(minLength: 0)
                if viewModel.cloudSyncConnectionStatus != "未检测" && viewModel.cloudSyncConnectionStatus != "未配置同步地址" {
                    Text(viewModel.cloudSyncConnectionStatus)
                        .font(.ui(.micro, weight: .medium))
                        .foregroundStyle(
                            viewModel.cloudSyncConnectionHealthy == false
                                ? Constants.VisualStyle.danger
                                : Constants.VisualStyle.textTertiary
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                telemetryRow(
                    label: "通道与设备",
                    value: "\(channelDisplayName) · \(report?.deviceId ?? "本机待生成")",
                    monospaced: true
                )

                telemetryRow(
                    label: "版本与状态",
                    value: "云端 \(effectiveRevisionText) · \(localDeltaStatusText)",
                    valueColor: viewModel.hasPendingLocalChanges ? Constants.VisualStyle.warn : Constants.VisualStyle.textSecondary,
                    monospaced: true
                )

                if let report {
                    telemetryRow(
                        label: "上次同步",
                        value: "\(report.syncedAt.formatted(date: .abbreviated, time: .shortened)) · \(report.direction.displayName)"
                    )

                    Rectangle()
                        .fill(Constants.VisualStyle.divider)
                        .frame(height: Constants.Layout.hairline)
                        .padding(.vertical, 2)

                    HStack(alignment: .top, spacing: Design.Space.md) {
                        telemetryStatColumn(
                            title: "拉取入库",
                            detail: pullStatsSummary(report)
                        )
                        telemetryStatColumn(
                            title: "推送上云",
                            detail: pushStatsSummary(report)
                        )
                        telemetryStatColumn(
                            title: "冲突保留",
                            detail: "\(report.conflictsPreserved) 处（已自动留存历史版本）",
                            highlight: report.conflictsPreserved > 0 ? Constants.VisualStyle.warn : nil
                        )
                    }

                    if let errorMessage = report.errorMessage, !errorMessage.isEmpty {
                        Text("最近异常：\(errorMessage)")
                            .font(.ui(.caption))
                            .foregroundStyle(Constants.VisualStyle.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    telemetryRow(
                        label: "上次同步",
                        value: viewModel.cloudSyncLastStatus,
                        valueColor: Constants.VisualStyle.textTertiary
                    )
                }
            }
        }
        .padding(Design.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Constants.VisualStyle.tintSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
        )
    }

    private var configPersistenceBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(hasUnsavedConfig ? Constants.VisualStyle.warn : Constants.VisualStyle.textQuaternary)
                    .frame(width: 5, height: 5)
                Text(hasUnsavedConfig ? "配置未保存" : (isConfigured ? "配置已保存" : "填写同步地址后保存"))
                    .font(.ui(.caption, weight: hasUnsavedConfig ? .medium : .regular))
                    .foregroundStyle(hasUnsavedConfig ? Constants.VisualStyle.warn : Constants.VisualStyle.textTertiary)
            }
            Spacer(minLength: 0)
            PPActionButton(
                "保存配置",
                systemImage: "checkmark",
                variant: hasUnsavedConfig ? .primary : .secondary,
                size: .compact
            ) {
                commitCloudSyncConfig(showBanner: true)
            }
            .disabled(!hasUnsavedConfig && isConfigured)
        }
        .padding(.top, 2)
    }

    private func telemetryRow(
        label: String,
        value: String,
        valueColor: Color = Constants.VisualStyle.textSecondary,
        monospaced: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.ui(.caption))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
                .frame(width: 66, alignment: .leading)
            Text(value)
                .font(.ui(.caption, weight: .medium, mono: monospaced))
                .foregroundStyle(valueColor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func telemetryStatColumn(title: String, detail: String, highlight: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.ui(.micro, weight: .medium))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
            Text(detail)
                .font(.ui(.caption, weight: .medium))
                .foregroundStyle(highlight ?? Constants.VisualStyle.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pullStatsSummary(_ report: CloudSyncReport) -> String {
        let groupDelta = "分组 +\(report.pulledProjectsCreated)/更\(report.pulledProjectsUpdated)"
        let entryDelta = "词条 +\(report.pulledEntriesCreated)/更\(report.pulledEntriesUpdated)"
        let deletePart = report.pulledDeletionsCount > 0 ? " · 删\(report.pulledDeletionsCount)" : ""
        return "\(groupDelta) · \(entryDelta)\(deletePart)"
    }

    private func pushStatsSummary(_ report: CloudSyncReport) -> String {
        if report.pushedChangesCount > 0 {
            return "已推送 \(report.pushedChangesCount) 项"
        }
        if let reason = report.skippedPushReason, !reason.isEmpty {
            return reason
        }
        if report.actionMode == .pullOnly {
            return "仅拉取模式，未推送"
        }
        return "本地无新变更，未推送"
    }

    private func commitCloudSyncConfig(showBanner: Bool = true) {
        viewModel.saveCloudSyncSettings(showBanner: showBanner)
        syncSavedConfigSnapshot()
    }

    private func syncSavedConfigSnapshot() {
        savedEndpoint = viewModel.cloudSyncEndpoint
        savedApiKey = viewModel.cloudSyncApiKey
    }
}

private struct SoftDeletedEntriesRecoverySheet: View {
    @ObservedObject var viewModel: MainWindowViewModel
    @Environment(\.dismiss) private var dismiss

    private var _selectedIds = SwiftUI.State(initialValue: Set<String>())
    private var selectedIds: Set<String> {
        get { _selectedIds.wrappedValue }
        nonmutating set { _selectedIds.wrappedValue = newValue }
    }

    private var allSelected: Bool {
        !viewModel.recentSoftDeletedEntries.isEmpty
            && selectedIds.count == viewModel.recentSoftDeletedEntries.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "trash.slash")
                    .font(.icon(.base, weight: .semibold))
                    .foregroundStyle(Constants.VisualStyle.accent)
                Text("最近 30 天已删除词条")
                    .font(.ui(.heading, weight: .semibold))
                    .foregroundStyle(Constants.VisualStyle.text)
                if !viewModel.recentSoftDeletedEntries.isEmpty {
                    Text("\(viewModel.recentSoftDeletedEntries.count) 条")
                        .font(.ui(.caption, weight: .medium, mono: true))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                }
                Spacer(minLength: 0)
                QuietIconButton(systemImage: "arrow.clockwise", help: "刷新最近删除记录") {
                    viewModel.refreshRecentSoftDeletedEntries()
                }
                PPActionButton("关闭", variant: .ghost, size: .compact) {
                    dismiss()
                }
            }

            Text("按需勾选单条或多条已删除词条进行恢复；已恢复的词条会在下次同步时安全同步到云端，不再无差别复活全历史墓碑。")
                .font(.ui(.caption))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.recentSoftDeletedEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.icon(.hero, weight: .light))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                    Text("最近 30 天内没有已删除词条")
                        .font(.ui(.title, weight: .medium))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Constants.VisualStyle.tintSubtle)
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(viewModel.recentSoftDeletedEntries) { item in
                            deletedItemRow(item)
                        }
                    }
                    .padding(2)
                }
                .frame(minHeight: 240, maxHeight: 340)
            }

            HStack(spacing: 10) {
                if !viewModel.recentSoftDeletedEntries.isEmpty {
                    PPActionButton(
                        allSelected ? "取消全选" : "全选",
                        variant: .secondary,
                        size: .compact
                    ) {
                        if allSelected {
                            selectedIds.removeAll()
                        } else {
                            selectedIds = Set(viewModel.recentSoftDeletedEntries.map(\.id))
                        }
                    }

                    Text("已选 \(selectedIds.count) 项")
                        .font(.ui(.caption, mono: true))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                }

                Spacer(minLength: 0)

                PPActionButton(
                    selectedIds.isEmpty ? "恢复所选" : "恢复所选 (\(selectedIds.count))",
                    systemImage: "arrow.uturn.backward",
                    variant: .primary,
                    size: .regular
                ) {
                    let ids = Array(selectedIds)
                    viewModel.restoreSoftDeletedEntries(ids: ids)
                    selectedIds.subtract(ids)
                }
                .disabled(selectedIds.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 580)
        .background(Constants.VisualStyle.surfaceRaised)
        .onAppear {
            viewModel.refreshRecentSoftDeletedEntries()
        }
        .onChange(of: viewModel.recentSoftDeletedEntries) { _, items in
            let validIds = Set(items.map(\.id))
            selectedIds = selectedIds.intersection(validIds)
        }
    }

    private func deletedItemRow(_ item: SoftDeletedEntryItem) -> some View {
        let isSelected = selectedIds.contains(item.id)
        return HStack(alignment: .center, spacing: 10) {
            Button {
                if isSelected {
                    selectedIds.remove(item.id)
                } else {
                    selectedIds.insert(item.id)
                }
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.icon(.base))
                    .foregroundStyle(isSelected ? Constants.VisualStyle.accent : Constants.VisualStyle.textTertiary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.projectName)
                        .font(.ui(.micro, weight: .medium))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Constants.VisualStyle.tintMedium)
                        )
                    Text(item.title.isEmpty ? "无标题词条" : item.title)
                        .font(.ui(.body, weight: .semibold))
                        .foregroundStyle(Constants.VisualStyle.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("删于 \(PPRelativeTimeFormatter.relativeString(from: item.deletedAt))")
                        .font(.ui(.micro, mono: true))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                }

                if !item.previewLine.isEmpty {
                    Text(item.previewLine)
                        .font(.ui(.caption))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            PPActionButton("恢复", variant: .secondary, size: .compact) {
                viewModel.restoreSoftDeletedEntries(ids: [item.id])
                selectedIds.remove(item.id)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Constants.VisualStyle.accentDim : Constants.VisualStyle.tintSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isSelected ? Constants.VisualStyle.accentBorder : Constants.VisualStyle.border,
                    lineWidth: Constants.Layout.hairline
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedIds.remove(item.id)
            } else {
                selectedIds.insert(item.id)
            }
        }
    }
}

private struct MobilePairingQRSheet: View {
    @ObservedObject var viewModel: MainWindowViewModel
    @Environment(\.dismiss) private var dismiss

    private var payloadJSON: String {
        viewModel.makeMobileSyncBundleJSON(pretty: false) ?? ""
    }

    private var qrImage: NSImage? {
        guard !payloadJSON.isEmpty else { return nil }
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payloadJSON.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.icon(.small, weight: .semibold))
                        .foregroundStyle(Constants.VisualStyle.accent)
                    Text("手机扫码配对云端同步")
                        .font(.ui(.title, weight: .semibold))
                        .foregroundStyle(Constants.VisualStyle.text)
                }
                Spacer()
                PPActionButton("关闭", variant: .ghost, size: .compact) {
                    dismiss()
                }
            }

            if let warning = viewModel.mobileSyncEndpointWarning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.icon(.small))
                        .foregroundStyle(Constants.VisualStyle.warn)
                    Text(warning)
                        .font(.ui(.caption))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Constants.VisualStyle.warnDim)
                )
            }

            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 196, height: 196)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                        )

                    if let qrImage {
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 172, height: 172)
                    } else {
                        Text("未配置同步地址")
                            .font(.ui(.caption))
                            .foregroundStyle(Constants.VisualStyle.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("手机端导入步骤：")
                        .font(.ui(.body, weight: .semibold))
                        .foregroundStyle(Constants.VisualStyle.text)

                    Text("1. 打开手机端底栏「设置 → 云端同步」，点击「扫码读取配对图」直接拍摄此二维码；\n2. 或使用系统相机/微信扫码复制文本后，在手机端点击「粘贴剪贴板配置」一键填入并自动开启同步。")
                        .font(.ui(.caption))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("当前同步地址")
                            .font(.ui(.micro))
                            .foregroundStyle(Constants.VisualStyle.textTertiary)
                        Text(viewModel.cloudSyncEndpoint)
                            .font(.ui(.caption, mono: true))
                            .foregroundStyle(Constants.VisualStyle.text)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Constants.VisualStyle.inputFill)
                    )

                    HStack(spacing: 8) {
                        PPActionButton("复制配对配置", systemImage: "doc.on.doc", variant: .primary, size: .compact, fillsAvailableWidth: true) {
                            viewModel.copyMobileSyncBundleToClipboard()
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 500)
        .background(Constants.VisualStyle.surfaceRaised)
    }
}
