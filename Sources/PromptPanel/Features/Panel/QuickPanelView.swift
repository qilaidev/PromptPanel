import AppKit
import Foundation
import SwiftUI

struct QuickPanelView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: QuickPanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .overlay(dividerBottom, alignment: .bottom)

            if let statusMessage = viewModel.statusMessage {
                statusBanner(statusMessage, tone: viewModel.statusTone)
                    .padding(.horizontal, Design.Space.sm)
                    .padding(.vertical, Design.Space.xs)
                    .overlay(dividerBottom, alignment: .bottom)
            }

            resultsList

            if appState.panelShowFooter {
                footerHints
                    .overlay(dividerTop, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelSurface)
        .preferredColorScheme(appState.appTheme.preferredColorScheme)
    }

    private var dividerBottom: some View {
        Rectangle()
            .fill(Constants.VisualStyle.divider)
            .frame(height: Constants.Layout.hairline)
    }

    private var dividerTop: some View {
        Rectangle()
            .fill(Constants.VisualStyle.divider)
            .frame(height: Constants.Layout.hairline)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: Design.Space.md) {
            projectScope

            Rectangle()
                .fill(Constants.VisualStyle.divider)
                .frame(width: Constants.Layout.hairline, height: 14)

            Image(systemName: "magnifyingglass")
                .font(.icon(.base))
                .foregroundStyle(Constants.VisualStyle.textTertiary)

            ZStack(alignment: .leading) {
                if viewModel.query.isEmpty {
                    Text(searchPlaceholder)
                        .font(.ui(.title, weight: .medium))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }

                KeyAwareSearchField(
                    text: Binding(
                        get: { viewModel.query },
                        set: { viewModel.query = $0 }
                    ),
                    placeholder: "",
                    focusToken: viewModel.focusToken,
                    onMoveSelection: viewModel.moveSelection,
                    onSubmit: { viewModel.executeSelection(triggerSource: .keyboardSubmit) },
                    onEscape: viewModel.closePanel,
                    onFocusResolved: viewModel.handleSearchFieldFocus
                )
                .id(viewModel.focusToken)
            }
            .frame(maxWidth: .infinity)

            if viewModel.query.isEmpty == false {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.icon(.small))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                        .frame(width: Constants.Layout.compactControlHeight, height: Constants.Layout.compactControlHeight)
                        .roundedHitTarget(cornerRadius: 5)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }

            pinButton
            settingsButton
            closeButton
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.sm)
    }

    private var searchPlaceholder: String {
        let name = currentProjectName
        return "搜索 \(name) · 输入 # 按标签筛选"
    }

    private var currentProjectName: String {
        viewModel.projects.first(where: { $0.id == viewModel.currentProjectId })?.name ?? "当前项目"
    }

    private var projectScope: some View {
        Menu {
            ForEach(viewModel.projects) { project in
                Button {
                    viewModel.activateProject(project.id)
                } label: {
                    HStack {
                        Text(project.name)
                        if project.id == appState.defaultProjectId {
                            Text("通用")
                                .font(.caption2)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder.fill")
                    .font(.icon(.micro))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
                Text(currentProjectName)
                    .font(.ui(.body, weight: .medium))
                    .foregroundStyle(Constants.VisualStyle.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if viewModel.currentProjectId == appState.defaultProjectId {
                    Text("通用")
                        .font(.ui(.micro, weight: .semibold))
                        .tracking(0.3)
                        .foregroundStyle(Constants.VisualStyle.accent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Constants.VisualStyle.accentDim)
                        )
                }
                Image(systemName: "chevron.down")
                    .font(.icon(.micro, weight: .semibold))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: Constants.Layout.compactControlHeight)
            .background(
                RoundedRectangle(cornerRadius: Design.pillCornerRadius, style: .continuous)
                    .fill(Constants.VisualStyle.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.pillCornerRadius, style: .continuous)
                    .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
            )
            .roundedHitTarget(cornerRadius: Design.pillCornerRadius)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var pinButton: some View {
        Button {
            viewModel.togglePanelPinned()
        } label: {
            Image(systemName: appState.isPanelPinned ? "pin.fill" : "pin")
                .font(.icon(.small))
                .foregroundStyle(appState.isPanelPinned ? Constants.VisualStyle.warn : Constants.VisualStyle.textTertiary)
                .frame(width: Constants.Layout.compactControlHeight, height: Constants.Layout.compactControlHeight)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(appState.isPanelPinned ? Constants.VisualStyle.warnDim : Color.clear)
                )
                .roundedHitTarget(cornerRadius: 5)
        }
        .buttonStyle(.plain)
        .help(appState.isPanelPinned ? "取消固定（⌘P）" : "固定面板（⌘P）")
    }

    /// The panel hides its titlebar buttons, and click-outside does not dismiss
    /// a pinned panel — without this there is no pointer-only way to close it.
    private var closeButton: some View {
        Button {
            viewModel.closePanel()
        } label: {
            Image(systemName: "xmark")
                .font(.icon(.small, weight: .semibold))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
                .frame(width: Constants.Layout.compactControlHeight, height: Constants.Layout.compactControlHeight)
                .roundedHitTarget(cornerRadius: 5)
        }
        .buttonStyle(.plain)
        .help("关闭面板（Esc）")
    }

    private var settingsButton: some View {
        Button {
            viewModel.openSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.icon(.small))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
                .frame(width: Constants.Layout.compactControlHeight, height: Constants.Layout.compactControlHeight)
                .roundedHitTarget(cornerRadius: 5)
        }
        .buttonStyle(.plain)
        .help("打开词库与设置")
    }

    // MARK: - Results

    /// Rows adapt to the panel width, but the width is a property of the *list*,
    /// not of each row. One `GeometryReader` here replaces one per visible row:
    /// nesting a GeometryReader inside a LazyVStack cell forces a second layout
    /// pass for every row on every scroll and every keystroke.
    private var resultsList: some View {
        GeometryReader { listGeometry in
            let rowWidth = max(listGeometry.size.width - Design.Space.xs * 2, 0)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if viewModel.entries.isEmpty, viewModel.isLoadingEntries {
                            loadingState
                        } else if viewModel.entries.isEmpty {
                            emptyState
                        } else {
                            ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                                PanelRow(
                                    entry: entry,
                                    index: index,
                                    isSelected: index == viewModel.selectedIndex,
                                    showNumber: showsShortcutNumbers,
                                    showDefaultBadge: shouldShowDefaultBadge(for: entry),
                                    isCompact: appState.panelCompactRows,
                                    availableWidth: rowWidth,
                                    onTap: {
                                        viewModel.executeEntry(at: index, triggerSource: .pointerClick)
                                    }
                                )
                                .id(entry.id)
                            }
                        }
                    }
                    .padding(.horizontal, Design.Space.xs)
                    .padding(.vertical, Design.Space.xs)
                }
                .scrollIndicators(.hidden)
                .onChange(of: viewModel.selectedIndex) { _, _ in
                    guard let selectedEntry = viewModel.selectedEntry else { return }
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(selectedEntry.id, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// ⌘1-9 only address the browse list; once a query narrows it the numbers
    /// would point at a different entry on every keystroke.
    private var showsShortcutNumbers: Bool {
        viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在刷新当前词条…")
                .font(.ui(.body))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .padding(.vertical, Design.Space.md)
    }

    private var emptyState: some View {
        VStack(spacing: Design.Space.xs) {
            Text(emptyStateTitle)
                .font(.ui(.title))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
            Text(emptyStateSubtitle)
                .font(.ui(.caption))
                .foregroundStyle(Constants.VisualStyle.textQuaternary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 60)
        .padding(.vertical, Design.Space.xl)
    }

    private var emptyStateTitle: String {
        viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "当前没有可执行词条"
            : "没有匹配的词条"
    }

    private var emptyStateSubtitle: String {
        viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "去主界面补充词条后，这里会立刻可搜可用。"
            : "换个关键词，或在主界面补充更容易命中的标题和内容。"
    }

    private func shouldShowDefaultBadge(for entry: Entry) -> Bool {
        entry.projectId == appState.defaultProjectId && entry.projectId != viewModel.currentProjectId
    }

    // MARK: - Status banner

    private func statusBanner(_ message: String, tone: QuickPanelViewModel.StatusTone) -> some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon(for: tone))
                .font(.icon(.small))
                .foregroundStyle(statusAccent(for: tone))
            Text(message)
                .font(.ui(.body))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if tone == .warning {
                Button("前往授权") {
                    viewModel.openAccessibilitySettings()
                }
                .buttonStyle(.plain)
                .font(.ui(.body, weight: .medium))
                .foregroundStyle(statusAccent(for: tone))
                .padding(.horizontal, 6)
                .frame(height: 22)
                .roundedHitTarget(cornerRadius: 5)
            }
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.xs)
        .background(
            Rectangle()
                .fill(statusBackground(for: tone))
        )
        .overlay(
            Rectangle()
                .fill(statusBorder(for: tone))
                .frame(height: Constants.Layout.hairline),
            alignment: .bottom
        )
    }

    private func statusIcon(for tone: QuickPanelViewModel.StatusTone) -> String {
        switch tone {
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "exclamationmark.octagon.fill"
        }
    }

    private func statusAccent(for tone: QuickPanelViewModel.StatusTone) -> Color {
        switch tone {
        case .info:
            return Constants.VisualStyle.accent
        case .warning:
            return Constants.VisualStyle.warn
        case .error:
            return Constants.VisualStyle.danger
        }
    }

    private func statusBackground(for tone: QuickPanelViewModel.StatusTone) -> Color {
        switch tone {
        case .info:
            return Constants.VisualStyle.accentDim
        case .warning:
            return Constants.VisualStyle.warnDim
        case .error:
            return Constants.VisualStyle.dangerDim
        }
    }

    private func statusBorder(for tone: QuickPanelViewModel.StatusTone) -> Color {
        statusAccent(for: tone).opacity(0.25)
    }

    // MARK: - Footer

    private var footerHints: some View {
        HStack(spacing: Design.Space.lg) {
            hint(keys: "↑↓", label: "选择")
            hint(keys: "Enter", label: "执行")
            hint(keys: "Esc", label: "关闭")
            hint(keys: "⌘C", label: "复制")
            hint(keys: "⌘1-9", label: "直达")
            hint(keys: "⌘P", label: appState.isPanelPinned ? "取消固定" : "固定")
            Spacer(minLength: 0)
            Text("\(viewModel.entries.count) 条")
                .font(.ui(.caption, mono: true))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
        }
        .padding(.horizontal, Design.Space.lg)
        .frame(height: Constants.Layout.footerHeight)
        .background(Constants.VisualStyle.scrim)
    }

    private func hint(keys: String, label: String) -> some View {
        HStack(spacing: 4) {
            KbdLabel(text: keys)
            Text(label)
                .font(.ui(.caption))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
        }
    }

    private var panelSurface: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Constants.VisualStyle.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Constants.VisualStyle.borderStrong, lineWidth: Constants.Layout.hairline)
            )
    }
}

private struct PanelRow: View {
    let entry: Entry
    let index: Int
    let isSelected: Bool
    let showNumber: Bool
    let showDefaultBadge: Bool
    let isCompact: Bool
    /// Supplied by the list rather than measured per row; see `resultsList`.
    let availableWidth: CGFloat
    let onTap: () -> Void

    var body: some View {
        let type = Constants.EntryType.resolve(entry.type)
        let level = Constants.EntryLevel.resolve(useCount: entry.useCount)
        let metrics = RowMetrics(totalWidth: availableWidth)
        Button(action: onTap) {
            HStack(spacing: Design.Space.md) {
                // Only reserve the ⌘1-9 gutter while the numbers are
                // actually shown; searching would otherwise leave a blank
                // column in every row.
                if showNumber {
                    Text("\(index + 1)")
                        .font(.ui(.micro, weight: .medium, mono: true))
                        .foregroundStyle(isSelected ? Constants.VisualStyle.accent : Constants.VisualStyle.textQuaternary)
                        .frame(width: 18, alignment: .center)
                }

                Image(systemName: type.symbolName)
                    .font(.icon(.base))
                    .foregroundStyle(level.color)
                    .frame(width: 16, height: 16)

                HStack(alignment: .firstTextBaseline, spacing: Design.Space.lg) {
                    if let titleWidth = metrics.titleWidth {
                        titleLabel
                            .frame(width: titleWidth, alignment: .leading)
                    } else {
                        titleLabel
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if metrics.showsPreview {
                        Text(entry.previewLine)
                            .font(.ui(.body))
                            .foregroundStyle(Constants.VisualStyle.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack(spacing: Design.Space.sm) {
                    Text("\(entry.useCount) 次")
                        .font(.ui(.micro, weight: .medium, mono: true))
                        .foregroundStyle(level.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: Constants.Layout.badgeCornerRadius, style: .continuous)
                                .fill(level.fillColor)
                        )
                    if showDefaultBadge {
                        Text("通用")
                            .font(.ui(.micro, weight: .medium))
                            .foregroundStyle(Constants.VisualStyle.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: Constants.Layout.badgeCornerRadius, style: .continuous)
                                    .fill(Constants.VisualStyle.tintSubtle)
                            )
                    }
                    // Recency, not the type name. Ranking is use count decayed by how
                    // long an entry has sat untouched, and the count was the only half
                    // of that the row showed — so "6 次" above "19 次" looked broken.
                    // The type name earned its slot even less: it is the same word on
                    // every row in a prompt library, and the leading icon already
                    // carries it.
                    if metrics.showsRecency {
                        Text(recencyLabel)
                            .font(.ui(.micro, weight: .medium, mono: true))
                            .foregroundStyle(isSelected ? Constants.VisualStyle.textSecondary : Constants.VisualStyle.textTertiary)
                    }
                }
                .layoutPriority(2)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.leading, Design.Space.sm)
            .padding(.trailing, Design.Space.lg)
            .frame(maxWidth: .infinity)
            .frame(height: isCompact ? Constants.Layout.compactRowHeight : Constants.Layout.regularRowHeight)
            .roundedHitTarget(cornerRadius: Design.rowCornerRadius)
            .background(
                RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous)
                    .fill(isSelected ? Constants.VisualStyle.tintSubtle : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous))
    }

    private var titleLabel: some View {
        HStack(spacing: Design.Space.xs) {
            Text(entry.title)
                .font(.ui(.title, weight: .medium))
                .foregroundStyle(Constants.VisualStyle.text)
                .lineLimit(1)
                .truncationMode(.tail)
            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.icon(.micro, weight: .semibold))
                    .foregroundStyle(Constants.VisualStyle.warn.opacity(0.85))
            }
        }
    }

    /// How a row spends the width it is given. A portrait panel is narrow by
    /// design, so the secondary columns drop out in order of importance —
    /// content preview first, then the type label — instead of squeezing the
    /// title down to an ellipsis.
    private struct RowMetrics {
        /// `nil` means the title takes the whole flexible column, which is what
        /// happens once the preview text is no longer shown.
        let titleWidth: CGFloat?
        let showsPreview: Bool
        let showsRecency: Bool

        init(totalWidth: CGFloat) {
            showsPreview = totalWidth >= 470
            showsRecency = totalWidth >= 400
            titleWidth = showsPreview ? min(max(totalWidth * 0.28, 150), 260) : nil
        }
    }

    /// Compact relative age for the recency column: "今天" / "3天" / "5周" / "7月".
    /// Deliberately not `RelativeDateTimeFormatter` — its output ("3 天前", "上个月") is too
    /// long and too variable for a column that has to stay the same width on every row.
    private var recencyLabel: String {
        guard let lastUsedAt = entry.lastUsedAt else {
            return "未用"
        }
        let days = Int(max(Date().timeIntervalSince(lastUsedAt), 0) / 86_400)
        switch days {
        case 0:
            return "今天"
        case 1:
            return "昨天"
        case 2..<7:
            return "\(days)天"
        case 7..<31:
            return "\(days / 7)周"
        case 31..<365:
            return "\(days / 30)月"
        default:
            return "\(days / 365)年"
        }
    }
}
