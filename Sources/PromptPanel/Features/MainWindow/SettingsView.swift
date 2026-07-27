import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: MainWindowViewModel
    @State private var selectedArea: SettingsArea = .preferences

    private let columnSpacing: CGFloat = 14

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.Layout.sectionSpacing) {
                if let bannerMessage = viewModel.bannerMessage {
                    SettingsBanner(message: bannerMessage)
                }

                SettingsHealthStrip(viewModel: viewModel)

                SettingsAreaPicker(selection: $selectedArea)

                selectedAreaContent
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(Constants.VisualStyle.surface)
    }

    @ViewBuilder
    private var selectedAreaContent: some View {
        switch selectedArea {
        case .preferences:
            HStack(alignment: .top, spacing: columnSpacing) {
                SettingsColumn {
                    AppearanceSection(viewModel: viewModel)
                    LibrarySection(viewModel: viewModel)
                }

                SettingsColumn {
                    HotkeySection(viewModel: viewModel)
                    PanelBehaviorSection(viewModel: viewModel)
                }
            }
        case .permissions:
            HStack(alignment: .top, spacing: columnSpacing) {
                SettingsColumn {
                    PermissionSection(viewModel: viewModel)
                }

                SettingsColumn {
                    OperationOverviewSection(viewModel: viewModel)
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

private enum SettingsArea: String, CaseIterable, Identifiable {
    case preferences
    case permissions
    case maintenance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preferences: return "偏好"
        case .permissions: return "权限"
        case .maintenance: return "维护"
        }
    }

    var systemImage: String {
        switch self {
        case .preferences: return "slider.horizontal.3"
        case .permissions: return "hand.raised"
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
                .fill(Constants.VisualStyle.tintSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Constants.VisualStyle.border, lineWidth: 0.5)
        )
    }

    private func option(for area: SettingsArea) -> some View {
        let isActive = selection == area
        return Button {
            selection = area
        } label: {
            HStack(spacing: 6) {
                Image(systemName: area.systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(area.title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(isActive ? Constants.VisualStyle.text : Constants.VisualStyle.textTertiary)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Constants.VisualStyle.tintStrong : Color.clear)
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

struct SettingsCard<Content: View>: View {
    let title: String
    let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: title)
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
                .strokeBorder(Constants.VisualStyle.border, lineWidth: 0.5)
        )
    }
}

struct SettingsBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Constants.VisualStyle.accent)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.sectionCornerRadius, style: .continuous)
                .fill(Constants.VisualStyle.infoBannerFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Constants.Layout.sectionCornerRadius, style: .continuous)
                .strokeBorder(Constants.VisualStyle.infoBannerBorder, lineWidth: 0.5)
        )
    }
}

private struct SettingsHealthStrip: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        Group {
            if let issue = primaryIssue {
                HStack(spacing: 8) {
                    Image(systemName: issue.systemImage)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(issue.color)
                    Text(issue.message)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: Constants.Layout.sectionCornerRadius, style: .continuous)
                        .fill(issue.background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.sectionCornerRadius, style: .continuous)
                        .strokeBorder(issue.color.opacity(0.25), lineWidth: 0.5)
                )
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Constants.VisualStyle.success)
                        .frame(width: 6, height: 6)
                    Text(summaryText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                    Spacer(minLength: 0)
                    Text(versionText)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Constants.VisualStyle.textQuaternary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var summaryText: String {
        let backupText = viewModel.storageHealthSnapshot.map { "备份 \($0.backupCount)/\(Constants.automaticBackupRetentionCount)" } ?? "备份信息未加载"
        let recentText = viewModel.executionHealthSummary.map { $0.totalCount == 0 ? "近 7 天暂无执行" : "近 7 天执行 \($0.totalCount) 次" } ?? "执行信息未加载"
        return "运行正常 · \(backupText) · \(recentText)"
    }

    private var versionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知"
        return "v\(shortVersion) (\(buildVersion))"
    }

    private var primaryIssue: (message: String, systemImage: String, color: Color, background: Color)? {
        if viewModel.hasAccessibilityPermission == false {
            return (
                "辅助功能权限未开启，当前仍会退化为仅复制模式。",
                "exclamationmark.triangle.fill",
                Constants.VisualStyle.warn,
                Constants.VisualStyle.warnDim
            )
        }
        if let snapshot = viewModel.storageHealthSnapshot, snapshot.backupCount == 0 {
            return (
                "当前没有可用备份，建议先执行一次手动备份。",
                "externaldrive.badge.exclamationmark",
                Constants.VisualStyle.warn,
                Constants.VisualStyle.warnDim
            )
        }
        if let summary = viewModel.executionHealthSummary, summary.failedCount > 0 {
            return (
                "近 7 天有 \(summary.failedCount) 次执行失败，建议优先查看最近执行记录。",
                "exclamationmark.octagon.fill",
                Constants.VisualStyle.danger,
                Constants.VisualStyle.dangerDim
            )
        }
        return nil
    }
}

struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Constants.VisualStyle.textQuaternary)
            .textCase(.uppercase)
    }
}

struct SettingsRow<Control: View>: View {
    let label: String
    let hint: String?
    let control: Control
    let dense: Bool

    init(label: String, hint: String? = nil, dense: Bool = false, @ViewBuilder control: () -> Control) {
        self.label = label
        self.hint = hint
        self.dense = dense
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Constants.VisualStyle.text)
                if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            control
        }
        .padding(.vertical, dense ? 6 : 8)
        .overlay(
            Rectangle()
                .fill(Constants.VisualStyle.divider)
                .frame(height: 0.5),
            alignment: .bottom
        )
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
                        .font(.system(size: 11, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
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
                    .strokeBorder(borderColor, lineWidth: 0.5)
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

private struct AppearanceSection: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        SettingsCard("外观") {
            SettingsRow(
                label: "主题",
                hint: "跟随系统自动切换；也可固定为浅色或深色。"
            ) {
                ThemeSegmentedPicker(selection: Binding(
                    get: { viewModel.appTheme },
                    set: { viewModel.setAppTheme($0) }
                ))
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
                .fill(Constants.VisualStyle.tintSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Constants.VisualStyle.border, lineWidth: 0.5)
        )
    }

    private func option(for theme: AppTheme) -> some View {
        let isActive = selection == theme
        return Button {
            selection = theme
        } label: {
            HStack(spacing: 5) {
                Image(systemName: theme.systemImageName)
                    .font(.system(size: 11, weight: .medium))
                Text(theme.title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(isActive ? Constants.VisualStyle.text : Constants.VisualStyle.textTertiary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isActive ? Constants.VisualStyle.tintStrong : Color.clear)
            )
            .roundedHitTarget(cornerRadius: 5)
        }
        .buttonStyle(.plain)
    }
}

private struct LibrarySection: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        SettingsCard("词条排序") {
            SettingsRow(
                label: "默认排序",
                hint: "按使用＝严格按次数；按等级＝同档色块成组（rookie→master）。"
            ) {
                EntrySortSegmentedPicker(selection: Binding(
                    get: { viewModel.entrySortMode },
                    set: { viewModel.entrySortMode = $0 }
                ))
            }
        }
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
                .fill(Constants.VisualStyle.tintSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Constants.VisualStyle.border, lineWidth: 0.5)
        )
    }

    private func option(for mode: MainWindowViewModel.EntrySortMode) -> some View {
        let isActive = selection == mode
        return Button {
            selection = mode
        } label: {
            Text(mode.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isActive ? Constants.VisualStyle.text : Constants.VisualStyle.textTertiary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isActive ? Constants.VisualStyle.tintStrong : Color.clear)
                )
                .roundedHitTarget(cornerRadius: 5)
        }
        .buttonStyle(.plain)
    }
}

private struct HotkeySection: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        SettingsCard("快捷键") {
            SettingsRow(
                label: "呼出面板",
                hint: "这是呼出快捷面板的唯一入口。点击后按下组合键即可修改；如果新快捷键按下去没反应，说明已被其他应用或系统占用，换一个组合。"
            ) {
                HotkeyRecorderField(name: .togglePanel)
            }
        }
    }
}

private struct PanelBehaviorSection: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        SettingsCard("面板行为") {
            SettingsRow(
                label: "固定面板",
                hint: "关闭时失焦自动收起；开启后持续置顶，适合边看边选。"
            ) {
                Toggle("", isOn: Binding(
                    get: { viewModel.isPanelPinned },
                    set: { viewModel.setPanelPinned($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            SettingsRow(
                label: "显示键位提示栏",
                hint: "面板底部显示 Enter / Esc / ⌘C / ⌘1-9 等提示。"
            ) {
                Toggle("", isOn: Binding(
                    get: { viewModel.panelShowFooter },
                    set: { viewModel.setPanelShowFooter($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            SettingsRow(
                label: "紧凑行高",
                hint: "每屏显示更多词条，适合高频检索。"
            ) {
                Toggle("", isOn: Binding(
                    get: { viewModel.panelCompactRows },
                    set: { viewModel.setPanelCompactRows($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            SettingsRow(
                label: "面板尺寸",
                hint: "可拖拽面板边缘，也可在这里精确设置宽高。"
            ) {
                PanelSizeControls(viewModel: viewModel)
            }
        }
    }
}

private struct PanelSizeControls: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            HStack(spacing: 8) {
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
            }

            SettingsPillButton("恢复默认", systemImage: "arrow.counterclockwise") {
                viewModel.resetPanelContentSize()
            }
        }
    }

    private func dimensionStepper(label: String, value: Binding<Int>, bounds: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: bounds, step: 20) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
                Text("\(value.wrappedValue)")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Constants.VisualStyle.text)
                    .frame(width: 38, alignment: .trailing)
            }
        }
        .controlSize(.small)
        .fixedSize()
    }
}

private struct PermissionSection: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        SettingsCard("权限与启动") {
            SettingsRow(
                label: "辅助功能权限",
                hint: "用于监听快捷键和自动粘贴；若系统里同时出现两项，请开启 PromptPanel.app。"
            ) {
                permissionPill
            }
            SettingsRow(
                label: "授权操作",
                hint: "重新授权时以 PromptPanel.app 那一项为准。"
            ) {
                HStack(spacing: 6) {
                    SettingsPillButton("请求授权", systemImage: "hand.raised") {
                        viewModel.requestAccessibilityPermission()
                    }
                    SettingsPillButton("系统设置", systemImage: "arrow.up.forward") {
                        viewModel.openAccessibilitySettings()
                    }
                    SettingsPillButton("重新检测", systemImage: "arrow.clockwise") {
                        viewModel.refreshPermissionState()
                    }
                }
            }
            SettingsRow(
                label: "重置授权记录",
                hint: "更新或重装后，若系统里看似已授权但应用仍显示未授权，点这里清空旧记录后再去重新开启。"
            ) {
                SettingsPillButton("重置授权", systemImage: "arrow.counterclockwise") {
                    viewModel.resetAccessibilityApproval()
                }
            }
            SettingsRow(
                label: "登录时启动",
                hint: "系统启动后自动在后台运行。"
            ) {
                Toggle("", isOn: Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { viewModel.setLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
    }

    private var permissionPill: some View {
        let granted = viewModel.hasAccessibilityPermission
        let color: Color = granted ? Constants.VisualStyle.success : Constants.VisualStyle.warn
        let dim: Color = granted ? Constants.VisualStyle.successDim : Constants.VisualStyle.warnDim
        return HStack(spacing: 4) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(granted ? "已授权" : "未授权")
                .font(.system(size: 11.5, weight: .medium))
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

// MARK: - Right column sections

private struct OperationOverviewSection: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        SettingsCard("运行概况") {
            SettingsRow(label: "当前版本", dense: true) {
                valueText(appVersionText, monospaced: true)
            }
            SettingsRow(label: "更新状态", dense: true) {
                Text(viewModel.updaterStatusMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 240, alignment: .trailing)
            }

            if let snapshot = viewModel.storageHealthSnapshot {
                SettingsRow(label: "数据大小", dense: true) {
                    valueText(ByteCountFormatter.string(fromByteCount: snapshot.databaseSizeBytes, countStyle: .file))
                }
                SettingsRow(label: "备份文件", dense: true) {
                    valueText("\(snapshot.backupCount)")
                }
                SettingsRow(label: "启动备份保留", dense: true) {
                    valueText("最近 \(Constants.automaticBackupRetentionCount) 份")
                }
                SettingsRow(label: "最近备份", dense: true) {
                    valueText(latestBackupSummary(snapshot.latestBackupURL))
                }
            }

            if let summary = viewModel.executionHealthSummary {
                VStack(alignment: .leading, spacing: 8) {
                    Text("近 7 天执行")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                    HStack(spacing: 6) {
                        summaryPill(title: "执行", value: "\(summary.totalCount)", tone: .neutral)
                        summaryPill(title: "成功", value: "\(summary.successCount)", tone: .success)
                        summaryPill(title: "兜底", value: "\(summary.clipboardOnlyCount)", tone: .warn)
                        summaryPill(title: "失败", value: "\(summary.failedCount)", tone: .danger)
                    }
                }
                .padding(.vertical, 8)
                .overlay(
                    Rectangle()
                        .fill(Constants.VisualStyle.divider)
                        .frame(height: 0.5),
                    alignment: .bottom
                )

                SettingsRow(label: "最近执行", dense: true) {
                    valueText(format(date: summary.latestExecutionAt))
                }
                SettingsRow(label: "最近异常", dense: true) {
                    valueText(format(date: summary.latestFailureAt))
                }
            } else {
                Text("最近 7 天还没有执行记录。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
                    .padding(.vertical, 10)
            }
        }
    }

    private var appVersionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知"
        return "\(shortVersion) (\(buildVersion))"
    }

    private func valueText(_ value: String, monospaced: Bool = false) -> some View {
        Text(value)
            .font(.system(size: 11.5, weight: .medium, design: monospaced ? .monospaced : .default))
            .foregroundStyle(Constants.VisualStyle.textSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func latestBackupSummary(_ url: URL?) -> String {
        guard let url,
              let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return "暂无"
        }
        return modifiedAt.formatted(date: .abbreviated, time: .shortened)
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
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9.5))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(color.opacity(0.18), lineWidth: 0.5)
        )
    }
}

private struct MaintenanceSection: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        SettingsCard("维护操作") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ],
                alignment: .leading,
                spacing: 6
            ) {
                SettingsPillButton("刷新状态", systemImage: "arrow.clockwise", fillsAvailableWidth: true) {
                    viewModel.refreshOperationalStatus()
                    viewModel.refreshUpdaterStatus()
                }
                SettingsPillButton("检查更新", systemImage: "arrow.down.circle", fillsAvailableWidth: true) {
                    viewModel.checkForUpdates()
                }
                SettingsPillButton("立即备份", systemImage: "plus", tone: .primary, fillsAvailableWidth: true) {
                    viewModel.createBackupNow()
                }
                SettingsPillButton("数据目录", systemImage: "folder", fillsAvailableWidth: true) {
                    viewModel.openDataDirectory()
                }
                SettingsPillButton("备份目录", systemImage: "tray.full", fillsAvailableWidth: true) {
                    viewModel.openBackupDirectory()
                }
                SettingsPillButton("导出 JSON", systemImage: "square.and.arrow.up", fillsAvailableWidth: true) {
                    viewModel.exportLibraryAsJSON()
                }
                SettingsPillButton("导出 MD", systemImage: "doc.text", fillsAvailableWidth: true) {
                    viewModel.exportLibraryAsMarkdown()
                }
                SettingsPillButton("导入 JSON", systemImage: "square.and.arrow.down", tone: .primary, fillsAvailableWidth: true) {
                    viewModel.importLibraryFromJSON()
                }
                SettingsPillButton("导入 MD", systemImage: "doc.text.fill", fillsAvailableWidth: true) {
                    viewModel.importLibraryFromMarkdown()
                }
                SettingsPillButton("导出诊断", systemImage: "doc.zipper", fillsAvailableWidth: true) {
                    viewModel.exportDiagnosticsBundle()
                }
                SettingsPillButton("清理日志", systemImage: "trash", tone: .danger, fillsAvailableWidth: true) {
                    viewModel.cleanupLogs()
                }
            }
            .padding(.vertical, 4)

            Text("导入词库前会自动创建本地数据库备份；Sparkle 只在 feed 和公钥都配置完成后启用。")
                .font(.system(size: 11))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
                .padding(.top, 4)
        }
    }
}

// MARK: - Bottom full-width sections

private struct DataLocationSection: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        SettingsCard("数据位置") {
            if let snapshot = viewModel.storageHealthSnapshot {
                Text("落盘路径、备份和恢复隔离目录。复制路径可直接粘贴到终端。")
                    .font(.system(size: 11))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
                    .padding(.bottom, 6)

                VStack(alignment: .leading, spacing: 8) {
                    pathRow(title: "数据库", value: snapshot.databaseURL.path)
                    pathRow(title: "备份目录", value: snapshot.backupDirectoryURL.path)
                    pathRow(title: "恢复隔离", value: snapshot.recoveryDirectoryURL.path)
                    pathRow(title: "日志目录", value: snapshot.logsDirectoryURL.path)
                    if let url = snapshot.latestBackupURL {
                        pathRow(title: "最近备份路径", value: url.path)
                    }
                }
            } else {
                Text("尚未加载数据目录信息。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
            }
        }
    }

    private func pathRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10.5))
                .tracking(0.3)
                .foregroundStyle(Constants.VisualStyle.textQuaternary)
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                        .frame(width: 24, height: 24)
                        .roundedHitTarget(cornerRadius: 5)
                }
                .buttonStyle(.plain)
                .help("复制路径")
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
                HStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                    Text("当前还没有执行记录。按下全局快捷键选一条词条后，这里会立即出现。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(viewModel.recentExecutionLogs.prefix(6)) { log in
                        ExecutionLogRow(log: log, projectName: viewModel.projectName(for: log.projectId))
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

private struct ExecutionLogRow: View {
    let log: ExecutionLog
    let projectName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(resultTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(resultColor)
                Text(projectName)
                    .font(.system(size: 11))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                Spacer(minLength: 0)
                Text(log.createdAt.formatted(date: .abbreviated, time: .standard))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
            }
            HStack(spacing: 8) {
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
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Constants.VisualStyle.tintSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Constants.VisualStyle.border, lineWidth: 0.5)
        )
    }

    private var resultTitle: String {
        switch log.result {
        case Constants.ExecutionResult.success.rawValue: return "执行成功"
        case Constants.ExecutionResult.clipboardOnly.rawValue: return "复制兜底"
        default: return "执行失败"
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
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9.5))
                .foregroundStyle(Constants.VisualStyle.textQuaternary)
            Text(value)
                .font(.system(size: 10.5))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Constants.VisualStyle.tintSubtle))
    }
}
