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
                }

                SettingsColumn {
                    PermissionSection(viewModel: viewModel)
                    CloudSyncSection(viewModel: viewModel)
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
            .roundedHitTarget(cornerRadius: 6)
        }
        .buttonStyle(.plain)
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
                SettingsSectionHeader(title: title)
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
        Text(title)
            .font(.ui(.caption, weight: .semibold))
            .tracking(0.2)
            .foregroundStyle(Constants.VisualStyle.textTertiary)
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
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.icon(.small))
                }
                Text(title)
                    .font(.ui(.body, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(maxWidth: fillsAvailableWidth ? .infinity : nil)
            .frame(height: Constants.Layout.compactControlHeight)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: Constants.Layout.hairline)
            )
            .roundedHitTarget(cornerRadius: 6)
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch tone {
        case .primary: return .white
        case .neutral: return Constants.VisualStyle.text
        case .danger: return Constants.VisualStyle.danger
        }
    }

    private var fillColor: Color {
        switch tone {
        case .primary: return Constants.VisualStyle.accent
        case .neutral: return Constants.VisualStyle.tintMedium
        case .danger: return Color.clear
        }
    }

    private var borderColor: Color {
        switch tone {
        case .primary: return .clear
        case .neutral: return Constants.VisualStyle.border
        case .danger: return Constants.VisualStyle.danger.opacity(0.3)
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
            SettingsRow(label: "呼出快捷键") {
                HotkeyRecorderField(name: .togglePanel)
            }
            SettingsRow(label: "登录时启动", showsDivider: false) {
                Toggle("", isOn: Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { viewModel.setLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
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
            .roundedHitTarget(cornerRadius: 5)
        }
        .buttonStyle(.plain)
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
                .roundedHitTarget(cornerRadius: 5)
        }
        .buttonStyle(.plain)
    }
}

private struct PanelBehaviorSection: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        SettingsCard("快捷面板") {
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
            Button {
                viewModel.resetPanelContentSize()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.icon(.small))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                    .frame(width: Constants.Layout.compactControlHeight, height: Constants.Layout.compactControlHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Constants.VisualStyle.tintMedium)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                    )
            }
            .buttonStyle(.plain)
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
                    SettingsPillButton("请求授权", systemImage: "hand.raised", tone: .primary, fillsAvailableWidth: true) {
                        viewModel.requestAccessibilityPermission()
                    }
                    SettingsPillButton("系统设置", systemImage: "arrow.up.forward", fillsAvailableWidth: true) {
                        viewModel.openAccessibilitySettings()
                    }
                    SettingsPillButton("重新检测", systemImage: "arrow.clockwise", fillsAvailableWidth: true) {
                        viewModel.refreshPermissionState()
                    }
                    SettingsPillButton("重置授权", systemImage: "arrow.counterclockwise", fillsAvailableWidth: true) {
                        viewModel.resetAccessibilityApproval()
                    }
                }
            } else {
                HStack(spacing: Design.Space.xs) {
                    SettingsPillButton("系统设置", systemImage: "arrow.up.forward", fillsAvailableWidth: true) {
                        viewModel.openAccessibilitySettings()
                    }
                    SettingsPillButton("重新检测", systemImage: "arrow.clockwise", fillsAvailableWidth: true) {
                        viewModel.refreshPermissionState()
                    }
                    SettingsPillButton("重置授权", systemImage: "arrow.counterclockwise", fillsAvailableWidth: true) {
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
            Button {
                viewModel.refreshOperationalStatus()
                viewModel.refreshUpdaterStatus()
                viewModel.refreshLogs()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.icon(.small))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
                    .frame(width: 20, height: 20)
                    .roundedHitTarget(cornerRadius: 5)
            }
            .buttonStyle(.plain)
            .help("刷新运行状态")
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
                VStack(alignment: .leading, spacing: Design.Space.sm) {
                    Text("近 7 天执行")
                        .font(.ui(.caption))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                    HStack(spacing: 6) {
                        summaryPill(title: "总计", value: "\(summary.totalCount)", tone: .neutral)
                        summaryPill(title: "成功", value: "\(summary.successCount)", tone: .success)
                        summaryPill(title: "仅复制", value: "\(summary.clipboardOnlyCount)", tone: .warn)
                        summaryPill(title: "失败", value: "\(summary.failedCount)", tone: .danger)
                    }
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

    private enum PillTone {
        case neutral, success, warn, danger
    }

    private func summaryPill(title: String, value: String, tone: PillTone) -> some View {
        let color: Color = {
            switch tone {
            case .neutral: return Constants.VisualStyle.accent
            case .success: return Constants.VisualStyle.success
            case .warn: return Constants.VisualStyle.warn
            case .danger: return Constants.VisualStyle.danger
            }
        }()
        return VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.ui(.micro))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
            Text(value)
                .font(.ui(.title, weight: .semibold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.Space.md)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(color.opacity(0.18), lineWidth: Constants.Layout.hairline)
        )
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
                SettingsPillButton("立即备份", systemImage: "plus", tone: .primary, fillsAvailableWidth: true) {
                    viewModel.createBackupNow()
                }
                SettingsPillButton("数据目录", systemImage: "folder", fillsAvailableWidth: true) {
                    viewModel.openDataDirectory()
                }
                SettingsPillButton("备份目录", systemImage: "tray.full", fillsAvailableWidth: true) {
                    viewModel.openBackupDirectory()
                }
            }

            actionGroup(title: "导入与导出", columns: 2) {
                SettingsPillButton("导出 JSON", systemImage: "square.and.arrow.up", fillsAvailableWidth: true) {
                    viewModel.exportLibraryAsJSON()
                }
                SettingsPillButton("导出 MD", systemImage: "doc.text", fillsAvailableWidth: true) {
                    viewModel.exportLibraryAsMarkdown()
                }
                SettingsPillButton("导入 JSON", systemImage: "square.and.arrow.down", fillsAvailableWidth: true) {
                    viewModel.importLibraryFromJSON()
                }
                SettingsPillButton("导入 MD", systemImage: "doc.text.fill", fillsAvailableWidth: true) {
                    viewModel.importLibraryFromMarkdown()
                }
            }

            actionGroup(title: "诊断与清理", columns: 3) {
                SettingsPillButton("检查更新", systemImage: "arrow.down.circle", fillsAvailableWidth: true) {
                    viewModel.checkForUpdates()
                }
                SettingsPillButton("导出诊断", systemImage: "doc.zipper", fillsAvailableWidth: true) {
                    viewModel.exportDiagnosticsBundle()
                }
                SettingsPillButton("清理日志", systemImage: "trash", tone: .danger, fillsAvailableWidth: true) {
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
            Button {
                copyPath(value)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.icon(.small))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
                    .frame(width: 24, height: 24)
                    .roundedHitTarget(cornerRadius: 5)
            }
            .buttonStyle(.plain)
            .help("复制路径")
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
            HStack(spacing: Design.Space.sm) {
                infoPill(title: "目标应用", value: log.frontAppBundleId ?? "未知")
                if let durationText {
                    infoPill(title: "耗时", value: durationText)
                }
                infoPill(title: "权限", value: log.hasAccessibility ? "已授权" : "未授权")
                infoPill(title: "自动粘贴", value: log.pasteAttempted ? (log.pasteSuccess ? "成功" : "失败") : "未尝试")
                Spacer(minLength: 0)
            }
            if let failureReasonTitle {
                infoPill(title: "失败原因", value: failureReasonTitle)
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

    private func infoPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.ui(.micro))
                .foregroundStyle(Constants.VisualStyle.textQuaternary)
            Text(value)
                .font(.ui(.caption))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Design.Space.sm)
        .padding(.vertical, Design.Space.xxs)
        .background(Capsule().fill(Constants.VisualStyle.tintSubtle))
    }
}

private struct CloudSyncSection: View {
    @ObservedObject var viewModel: MainWindowViewModel

    private var isBusy: Bool {
        viewModel.activeMaintenanceTask != nil
    }

    private var isConfigured: Bool {
        !viewModel.cloudSyncEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        SettingsCard("云端同步") {
            syncStatusPill
        } content: {
            SettingsRow(label: "自动同步") {
                Toggle("", isOn: Binding(
                    get: { viewModel.cloudSyncEnabled },
                    set: { viewModel.setCloudSyncEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

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
                    }
                    .buttonStyle(.plain)
                }

                TextField("https://... 或本地文件路径", text: $viewModel.cloudSyncEndpoint)
                    .textFieldStyle(.plain)
                    .font(.ui(.caption, mono: true))
                    .foregroundStyle(Constants.VisualStyle.text)
                    .padding(.horizontal, Design.Space.md)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Constants.VisualStyle.inputFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                    )
                    .onSubmit {
                        viewModel.saveCloudSyncSettings()
                    }

                HStack(alignment: .center) {
                    Text("访问令牌 (Token)")
                        .font(.ui(.caption, weight: .medium))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                    Spacer()
                    Button {
                        viewModel.generateNewCloudSyncToken()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "key")
                                .font(.icon(.micro))
                            Text("生成 Token")
                                .font(.ui(.caption, weight: .medium))
                        }
                        .foregroundStyle(Constants.VisualStyle.accent)
                    }
                    .buttonStyle(.plain)
                }

                SecureField("不少于 12 位字符（本地文件同步可留空）", text: $viewModel.cloudSyncApiKey)
                    .textFieldStyle(.plain)
                    .font(.ui(.caption, mono: true))
                    .foregroundStyle(Constants.VisualStyle.text)
                    .padding(.horizontal, Design.Space.md)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Constants.VisualStyle.inputFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                    )
                    .onSubmit {
                        viewModel.saveCloudSyncSettings()
                    }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Design.Space.xs),
                        GridItem(.flexible(), spacing: Design.Space.xs)
                    ],
                    alignment: .leading,
                    spacing: Design.Space.xs
                ) {
                    SettingsPillButton("立即同步", systemImage: "arrow.triangle.2.circlepath", tone: .primary, fillsAvailableWidth: true) {
                        viewModel.syncCloudNow()
                    }
                    SettingsPillButton("测试连接", systemImage: "bolt.horizontal.circle", fillsAvailableWidth: true) {
                        viewModel.testCloudSyncConnection()
                    }
                    SettingsPillButton("扫码配对手机", systemImage: "qrcode", fillsAvailableWidth: true) {
                        viewModel.openMobilePairingQRSheet()
                    }
                    SettingsPillButton("复制手机配置", systemImage: "iphone.and.arrow.forward", fillsAvailableWidth: true) {
                        viewModel.copyMobileSyncBundleToClipboard()
                    }
                }
                .padding(.top, 2)
                .disabled(isBusy)

                HStack(spacing: Design.Space.xs) {
                    SettingsPillButton("复制部署命令", systemImage: "terminal", fillsAvailableWidth: true) {
                        viewModel.copyOpenSourceDeployCommand()
                    }
                    SettingsPillButton("恢复误删并回推", systemImage: "arrow.uturn.backward.circle", fillsAvailableWidth: true) {
                        viewModel.recoverDeletedAndPushToCloud()
                    }
                }
                .disabled(isBusy)

                if isConfigured || viewModel.cloudSyncLastStatus != "尚未执行云端同步" {
                    HStack(spacing: 6) {
                        Text(viewModel.cloudSyncConnectionStatus)
                            .font(.ui(.caption, weight: .medium))
                            .foregroundStyle(Constants.VisualStyle.textSecondary)
                            .lineLimit(1)
                        Text("·")
                            .font(.ui(.caption))
                            .foregroundStyle(Constants.VisualStyle.textQuaternary)
                        Text(viewModel.cloudSyncLastStatus)
                            .font(.ui(.caption))
                            .foregroundStyle(Constants.VisualStyle.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.top, Design.Space.sm)
        }
        .sheet(isPresented: $viewModel.isShowingMobilePairingQR) {
            MobilePairingQRSheet(viewModel: viewModel)
        }
    }

    private var syncStatusPill: some View {
        let isHealthy = viewModel.cloudSyncConnectionHealthy == true
        let color: Color = {
            if !isConfigured { return Constants.VisualStyle.textTertiary }
            if viewModel.cloudSyncConnectionHealthy == false { return Constants.VisualStyle.danger }
            return isHealthy || viewModel.cloudSyncEnabled ? Constants.VisualStyle.success : Constants.VisualStyle.accent
        }()
        let dim: Color = {
            if !isConfigured { return Constants.VisualStyle.tintSubtle }
            if viewModel.cloudSyncConnectionHealthy == false { return Constants.VisualStyle.dangerDim }
            return isHealthy || viewModel.cloudSyncEnabled ? Constants.VisualStyle.successDim : Constants.VisualStyle.accentDim
        }()
        let labelText: String = {
            if !isConfigured { return "未配置" }
            if viewModel.cloudSyncConnectionHealthy == false { return "连接异常" }
            if isHealthy { return "已连通" }
            return viewModel.cloudSyncEnabled ? "已启用" : "待启用"
        }()

        return HStack(spacing: 4) {
            Image(systemName: isConfigured ? "cloud.fill" : "cloud")
                .font(.icon(.micro, weight: .semibold))
            Text(labelText)
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
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.ui(.caption, weight: .medium))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
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
                        SettingsPillButton("复制配对配置", systemImage: "doc.on.doc", tone: .primary, fillsAvailableWidth: true) {
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
