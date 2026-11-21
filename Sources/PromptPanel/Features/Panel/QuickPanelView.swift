import AppKit
import Foundation
import SwiftUI

struct QuickPanelView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: QuickPanelViewModel

    private var isContentInteractionBlocked: Bool {
        viewModel.isScopeDropdownOpen || viewModel.isPreviewPresented
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .overlay(dividerBottom, alignment: .bottom)

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    if viewModel.quickCaptureDraft == nil {
                        kindFilterStrip
                            .overlay(dividerBottom, alignment: .bottom)
                            .allowsHitTesting(!isContentInteractionBlocked)
                    }

                    if let statusMessage = viewModel.statusMessage {
                        statusBanner(statusMessage, tone: viewModel.statusTone)
                            .overlay(dividerBottom, alignment: .bottom)
                    }

                    ZStack {
                        if let draft = viewModel.quickCaptureDraft {
                            quickCapturePreviewBody(draft)
                        } else {
                            resultsList
                                .allowsHitTesting(!isContentInteractionBlocked)
                        }

                        if viewModel.isPreviewPresented,
                           viewModel.quickCaptureDraft == nil,
                           let previewEntry = viewModel.selectedEntry {
                            entryPreviewOverlay(previewEntry)
                                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if appState.panelShowFooter {
                        footerHints
                            .overlay(dividerTop, alignment: .top)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if viewModel.isScopeDropdownOpen {
                    Color.black.opacity(0.001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeScopeDropdownImmediately()
                        }
                        .zIndex(15)

                    scopeDropdownCard
                        .padding(.leading, Design.Space.lg)
                        .padding(.top, Design.Space.xs)
                        .zIndex(20)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelSurface)
        .preferredColorScheme(appState.appTheme.preferredColorScheme)
        .animation(.easeOut(duration: 0.14), value: viewModel.isScopeDropdownOpen)
        .animation(.easeOut(duration: 0.14), value: viewModel.isPreviewPresented)
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
        HStack(alignment: .center, spacing: Design.Space.sm) {
            projectScopePill

            Rectangle()
                .fill(Constants.VisualStyle.divider)
                .frame(width: Constants.Layout.hairline, height: 14)

            if let draft = viewModel.quickCaptureDraft {
                quickCaptureModeBadge(draft)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.icon(.base))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
            }

            KeyAwareSearchField(
                text: Binding(
                    get: { viewModel.query },
                    set: { viewModel.query = $0 }
                ),
                placeholder: searchPlaceholder,
                focusToken: viewModel.focusToken,
                onMoveSelection: viewModel.moveSelection,
                onSubmit: { viewModel.executeSelection(triggerSource: .keyboardSubmit) },
                onQuickCreateNote: { viewModel.quickCreateEntryFromPanel(type: .note) },
                onQuickCreateTodo: { viewModel.quickCreateEntryFromPanel(type: .todo) },
                onCycleScope: viewModel.cycleScope,
                onEscape: viewModel.handleEscape,
                onFocusResolved: viewModel.handleSearchFieldFocus
            )
            .frame(minWidth: 132, maxWidth: .infinity)

            headerQuickCaptureControls

            pinButton
            settingsButton
            closeButton
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.sm)
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if viewModel.isScopeDropdownOpen {
                        closeScopeDropdownImmediately()
                    }
                }
        )
    }

    @ViewBuilder
    private var headerQuickCaptureControls: some View {
        if viewModel.query.isEmpty {
            HeaderGhostButton(systemImage: "square.and.pencil", title: "写便签") {
                viewModel.startQuickCapture(type: .note)
            }
            .help("进入便签输入模式，打字回车即存（也可输入 ; 开头）")

            if viewModel.hasClipboardText {
                HeaderGhostButton(systemImage: "doc.on.clipboard", title: nil) {
                    viewModel.quickCreateNoteFromClipboard()
                }
                .help("把剪贴板内容存为便签")
            }
        } else {
            if viewModel.quickCaptureDraft == nil {
                HeaderGhostButton(systemImage: "note.text", title: nil, shortcut: "⇧↩") {
                    viewModel.quickCreateEntryFromPanel(type: .note)
                }
                .help("把当前输入存为便签（⇧Enter）")

                HeaderGhostButton(systemImage: "checklist", title: nil, shortcut: "⌥↩") {
                    viewModel.quickCreateEntryFromPanel(type: .todo)
                }
                .help("把当前输入存为待办（⌥Enter）")
            }

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
            .help("清除输入")
        }
    }

    private func quickCaptureModeBadge(_ draft: QuickPanelViewModel.QuickCaptureDraft) -> some View {
        let isTodo = draft.type == .todo
        return HStack(spacing: 4) {
            Image(systemName: isTodo ? "checklist" : "note.text")
                .font(.icon(.small, weight: .semibold))
            Text(draft.modeBadgeText)
                .font(.ui(.caption, weight: .semibold))
        }
            .foregroundStyle(isTodo ? Constants.VisualStyle.warn : Constants.VisualStyle.accent)
            .padding(.horizontal, 8)
            .frame(height: Constants.Layout.compactControlHeight - 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isTodo ? Constants.VisualStyle.warnDim : Constants.VisualStyle.accentDim)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(
                        isTodo ? Constants.VisualStyle.warn.opacity(0.32) : Constants.VisualStyle.accentBorder,
                        lineWidth: Constants.Layout.hairline
                    )
            )
            .fixedSize()
    }

    private var searchPlaceholder: String {
        let name = currentScopeDisplayName
        return "搜索 \(name) 或 #标签"
    }

    private var currentProject: Project? {
        viewModel.projects.first(where: { $0.id == viewModel.currentProjectId })
    }

    private var currentScopeDisplayName: String {
        if viewModel.isAllProjectsScope {
            return QuickPanelViewModel.allProjectsScopeName
        }
        return currentProject?.name ?? "当前项目"
    }

    private var currentScopeIconName: String {
        if viewModel.isAllProjectsScope {
            return "square.stack.3d.up.fill"
        }
        return currentProject?.effectiveIconName ?? "folder.fill"
    }

    // MARK: - Scope Switcher (Click-to-Open + Click-to-Select + Tab-to-Cycle)

    private var projectScopePill: some View {
        Button {
            toggleScopeDropdownImmediately()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: currentScopeIconName)
                    .font(.icon(.micro))
                    .foregroundStyle(Constants.VisualStyle.accent)
                Text(currentScopeDisplayName)
                    .font(.ui(.body, weight: .medium))
                    .foregroundStyle(Constants.VisualStyle.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 88, alignment: .leading)
                Image(systemName: viewModel.isScopeDropdownOpen ? "chevron.up" : "chevron.down")
                    .font(.icon(.micro, weight: .semibold))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: Constants.Layout.compactControlHeight)
            .background(
                RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous)
                    .fill(
                        viewModel.isScopeDropdownOpen
                            ? Constants.VisualStyle.surfaceHover
                            : Constants.VisualStyle.tintSubtle
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous)
                    .strokeBorder(
                        viewModel.isScopeDropdownOpen ? Constants.VisualStyle.accentBorder : Constants.VisualStyle.border,
                        lineWidth: Constants.Layout.hairline
                    )
            )
            .hoverHighlight(cornerRadius: Design.rowCornerRadius, isEnabled: !viewModel.isScopeDropdownOpen)
            .roundedHitTarget(cornerRadius: Design.rowCornerRadius)
        }
        .buttonStyle(PPInteractiveButtonStyle(cornerRadius: Design.rowCornerRadius))
        .fixedSize()
        .help("点击切换分组 · Tab 键快速轮换")
    }

    private var scopeDropdownCard: some View {
        let inboxProjects = viewModel.projects.filter { $0.groupKind == .inbox }
        let categoryProjects = viewModel.projects.filter { $0.groupKind == .category }
        let activeProjects = viewModel.projects.filter { $0.groupKind == .project }

        return VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    scopeDropdownItem(
                        id: QuickPanelViewModel.allProjectsScopeId,
                        name: QuickPanelViewModel.allProjectsScopeName,
                        iconName: "square.stack.3d.up.fill"
                    )

                    if !inboxProjects.isEmpty {
                        scopeDropdownSectionHeader("速记与待办")
                        ForEach(inboxProjects) { project in
                            scopeDropdownItem(
                                id: project.id,
                                name: project.name,
                                iconName: project.effectiveIconName
                            )
                        }
                    }

                    if !categoryProjects.isEmpty {
                        scopeDropdownSectionHeader("常用类型")
                        ForEach(categoryProjects) { project in
                            scopeDropdownItem(
                                id: project.id,
                                name: project.name,
                                iconName: project.effectiveIconName
                            )
                        }
                    }

                    if !activeProjects.isEmpty {
                        scopeDropdownSectionHeader("项目")
                        ForEach(activeProjects) { project in
                            scopeDropdownItem(
                                id: project.id,
                                name: project.name,
                                iconName: project.effectiveIconName
                            )
                        }
                    }
                }
                .padding(Design.Space.sm)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 332)
            .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(Constants.VisualStyle.divider)
                .frame(height: Constants.Layout.hairline)

            HStack(spacing: 4) {
                Image(systemName: "hand.point.up.left")
                    .font(.icon(.micro))
                Text("点击切换分组 · Tab 键快速轮换")
                    .font(.ui(.micro))
            }
            .foregroundStyle(Constants.VisualStyle.textTertiary)
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, 6)
        }
        .frame(width: 224)
        .background(
            RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                .fill(Constants.VisualStyle.surfaceRaised)
        )
        .themedShadow(.popover, cornerRadius: Design.cardCornerRadius)
    }

    private func scopeDropdownSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.ui(.micro, weight: .semibold))
            .foregroundStyle(Constants.VisualStyle.textTertiary)
            .padding(.horizontal, Design.Space.sm)
            .padding(.top, Design.Space.xs)
            .padding(.bottom, 1)
    }

    private func scopeDropdownItem(id: String, name: String, iconName: String) -> some View {
        ScopeDropdownItemRow(
            name: name,
            iconName: iconName,
            isActive: viewModel.currentProjectId == id
        ) {
            viewModel.activateScope(id)
            closeScopeDropdownImmediately()
        }
    }

    private func toggleScopeDropdownImmediately() {
        viewModel.isScopeDropdownOpen.toggle()
    }

    private func closeScopeDropdownImmediately() {
        viewModel.isScopeDropdownOpen = false
    }

    // MARK: - Kind Filter Bar

    private var kindFilterStrip: some View {
        HStack(spacing: Design.Space.xs) {
            ForEach(QuickPanelViewModel.KindFilter.barItems) { filter in
                KindFilterChipButton(
                    filter: filter,
                    isActive: viewModel.activeKindFilter == filter,
                    isHoverEnabled: !isContentInteractionBlocked,
                    count: viewModel.countForFilter(filter)
                ) {
                    guard !isContentInteractionBlocked else { return }
                    viewModel.activeKindFilter = filter
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                KbdLabel(text: "Tab")
                Text("切分组")
                    .font(.ui(.caption))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
                    .lineLimit(1)
            }
            .fixedSize()
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, 5)
    }

    // MARK: - Window Controls

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
                .hoverHighlight(cornerRadius: 5)
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
                .hoverHighlight(cornerRadius: 5)
                .roundedHitTarget(cornerRadius: 5)
        }
        .buttonStyle(.plain)
        .help("打开词库与设置")
    }

    // MARK: - Quick Capture Live Preview Card

    private func quickCapturePreviewBody(_ draft: QuickPanelViewModel.QuickCaptureDraft) -> some View {
        let isTodo = draft.type == .todo
        let accentColor = isTodo ? Constants.VisualStyle.warn : Constants.VisualStyle.accent
        let accentFill = isTodo ? Constants.VisualStyle.warnDim : Constants.VisualStyle.accentDim

        return ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.md) {
                HStack(spacing: Design.Space.sm) {
                    Image(systemName: isTodo ? "checklist" : "note.text")
                        .font(.icon(.base, weight: .semibold))
                        .foregroundStyle(accentColor)

                    Text(isTodo ? "待办速记预览" : "便签速记预览")
                        .font(.ui(.body, weight: .semibold))
                        .foregroundStyle(Constants.VisualStyle.text)

                    Text("→ 速记与待办")
                        .font(.ui(.micro, weight: .medium))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(accentFill)
                        )

                    Spacer(minLength: 0)

                    Button {
                        viewModel.startQuickCapture(type: isTodo ? .note : .todo)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.icon(.nano, weight: .semibold))
                            Text(isTodo ? "切换为便签" : "切换为待办")
                                .font(.ui(.caption, weight: .medium))
                        }
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: Constants.Layout.regularControlHeight)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Constants.VisualStyle.tintSubtle)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                        )
                        .hoverHighlight(cornerRadius: 6)
                        .roundedHitTarget(cornerRadius: 6)
                    }
                    .buttonStyle(.plain)
                    .help(isTodo ? "切换为便签输入模式" : "切换为待办输入模式")

                    PrimaryActionButton(
                        title: "保存 ⏎",
                        systemImage: nil,
                        shortcut: nil
                    ) {
                        viewModel.executeSelection(force: true, triggerSource: .pointerClick)
                    }
                    .disabled(!draft.hasContent)
                    .opacity(draft.hasContent ? 1 : 0.5)
                    .help(isTodo ? "保存待办（Enter）" : "保存便签（Enter）")
                }

                Divider()
                    .overlay(Constants.VisualStyle.divider)

                if draft.hasContent {
                    VStack(alignment: .leading, spacing: Design.Space.xs) {
                        Text(draft.title)
                            .font(.ui(.heading, weight: .semibold))
                            .foregroundStyle(Constants.VisualStyle.text)
                            .lineLimit(2)

                        Text(draft.cleanedContent)
                            .font(.ui(.title))
                            .foregroundStyle(Constants.VisualStyle.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text(isTodo
                         ? "继续输入待办内容，按 Enter 直接存入「速记与待办」（支持 #标签 自动归类）…"
                         : "继续输入便签内容，按 Enter 直接存入「速记与待办」（支持 #标签 自动归类）…")
                        .font(.ui(.body))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                        .padding(.vertical, Design.Space.sm)
                }

                HStack(spacing: Design.Space.xs) {
                    if !draft.tags.isEmpty {
                        ForEach(draft.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.ui(.micro, weight: .medium))
                                .foregroundStyle(Constants.VisualStyle.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Constants.VisualStyle.accentDim)
                                )
                        }
                    } else {
                        Text("提示：在文本中加入 #标签 可自动提取标签")
                            .font(.ui(.micro))
                            .foregroundStyle(Constants.VisualStyle.textTertiary)
                    }

                    Spacer(minLength: 0)

                    if draft.hasContent {
                        Button {
                            viewModel.quickCreateEntryFromPanel(type: isTodo ? .note : .todo)
                        } label: {
                            Text(isTodo ? "改存为便签 (⇧↩)" : "改存为待办 (⌥↩)")
                                .font(.ui(.caption, weight: .medium))
                                .foregroundStyle(Constants.VisualStyle.textSecondary)
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Constants.VisualStyle.tintSubtle)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Design.Space.xl)
            .background(
                RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                    .fill(Constants.VisualStyle.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                    .strokeBorder(Constants.VisualStyle.borderStrong, lineWidth: Constants.Layout.hairline)
            )
            .padding(Design.Space.lg)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Results

    /// Rows adapt to the panel width, but the width is a property of the *list*,
    /// not of each row. One `GeometryReader` here replaces one per visible row:
    /// nesting a GeometryReader inside a LazyVStack cell forces a second layout
    /// pass for every row on every scroll and every keystroke.
    private var resultsList: some View {
        let hoverEnabled = !isContentInteractionBlocked
        return GeometryReader { listGeometry in
            let rowWidth = max(listGeometry.size.width - Design.Space.xs * 2, 0)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if viewModel.entries.isEmpty, viewModel.isLoadingEntries {
                            loadingState
                        } else if viewModel.entries.isEmpty {
                            emptyState
                        } else {
                            if viewModel.isShowingGlobalFallback {
                                globalFallbackHeader
                            }
                            let selectedEntryId = viewModel.selectedEntry?.id
                            ForEach(viewModel.entries) { entry in
                                let index = viewModel.displayIndex(forEntryId: entry.id) ?? 0
                                PanelRow(
                                    entry: entry,
                                    index: index,
                                    isSelected: entry.id == selectedEntryId,
                                    isHoverEnabled: hoverEnabled,
                                    showNumber: showsShortcutNumbers,
                                    scopeBadgeText: scopeBadgeText(for: entry),
                                    isCompact: appState.panelCompactRows,
                                    availableWidth: rowWidth,
                                    onTap: {
                                        guard !isContentInteractionBlocked else { return }
                                        viewModel.executeEntry(at: index, triggerSource: .pointerClick)
                                    },
                                    onCopy: {
                                        guard !isContentInteractionBlocked else { return }
                                        viewModel.copyEntry(at: index)
                                    },
                                    onPreview: {
                                        guard !isContentInteractionBlocked else { return }
                                        viewModel.openPreview(at: index)
                                    },
                                    onToggleComplete: {
                                        guard !isContentInteractionBlocked else { return }
                                        viewModel.toggleEntryCompleted(entry)
                                    },
                                    onTogglePin: {
                                        guard !isContentInteractionBlocked else { return }
                                        viewModel.toggleEntryPinned(entry)
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
                .onChange(of: viewModel.scrollSelectionRevision) { _, _ in
                    guard let selectedEntry = viewModel.selectedEntry else { return }
                    if viewModel.selectedIndex == 0 {
                        proxy.scrollTo(selectedEntry.id, anchor: .top)
                    } else {
                        proxy.scrollTo(selectedEntry.id)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Inline Full-Text Preview Overlay (⌘Y)

    private func entryPreviewOverlay(_ entry: Entry) -> some View {
        let resolvedType = Constants.EntryType.resolve(entry.type)
        let projectLabel = viewModel.projectName(for: entry.projectId) ?? "通用"
        let supportsCompletion = resolvedType == .todo || resolvedType == .note || entry.isCompleted

        return ZStack {
            Color.black.opacity(0.28)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.dismissPreview()
                }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Design.Space.sm) {
                    HStack(spacing: 4) {
                        Image(systemName: resolvedType.symbolName)
                            .font(.icon(.small))
                        Text(resolvedType.displayName)
                            .font(.ui(.caption, weight: .semibold))
                    }
                    .foregroundStyle(resolvedType.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Constants.VisualStyle.tintMedium)
                    )

                    Text(projectLabel)
                        .font(.ui(.caption, weight: .medium))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Constants.VisualStyle.tintSubtle)
                        )

                    if entry.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.icon(.micro, weight: .semibold))
                            .foregroundStyle(Constants.VisualStyle.warn)
                    }

                    Spacer(minLength: 0)

                    Button {
                        viewModel.dismissPreview()
                    } label: {
                        HStack(spacing: 4) {
                            Text("关闭预览")
                                .font(.ui(.caption, weight: .medium))
                            KbdLabel(text: "Esc")
                        }
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                        .padding(.horizontal, 6)
                        .frame(height: 22)
                        .hoverHighlight(cornerRadius: 5)
                        .roundedHitTarget(cornerRadius: 5)
                    }
                    .buttonStyle(PPInteractiveButtonStyle(cornerRadius: 5))
                }
                .padding(.horizontal, Design.Space.xl)
                .padding(.vertical, Design.Space.md)
                .overlay(dividerBottom, alignment: .bottom)

                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Space.md) {
                        Text(entry.title)
                            .font(.ui(.heading, weight: .semibold))
                            .foregroundStyle(entry.isCompleted ? Constants.VisualStyle.textTertiary : Constants.VisualStyle.text)
                            .strikethrough(entry.isCompleted, color: Constants.VisualStyle.textTertiary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if !entry.tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Design.Space.xs) {
                                    ForEach(entry.tags, id: \.self) { tag in
                                        Text("#\(tag)")
                                            .font(.ui(.micro, weight: .medium))
                                            .foregroundStyle(Constants.VisualStyle.accent)
                                            .fixedSize()
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                    .fill(Constants.VisualStyle.accentDim)
                                            )
                                    }
                                }
                            }
                        }

                        Text(entry.content)
                            .font(.ui(.title, mono: resolvedType == .code))
                            .foregroundStyle(Constants.VisualStyle.text)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(Design.Space.xl)
                }

                HStack(spacing: Design.Space.sm) {
                    if supportsCompletion {
                        GhostActionButton(
                            title: entry.isCompleted ? "标记未完成" : "标记已完成",
                            systemImage: entry.isCompleted ? "checkmark.circle.fill" : "circle"
                        ) {
                            viewModel.toggleEntryCompleted(entry)
                        }
                    }

                    Spacer(minLength: 0)

                    GhostActionButton(
                        title: "复制",
                        systemImage: "doc.on.doc",
                        shortcut: "⌘C"
                    ) {
                        viewModel.copySelectionOnly()
                    }

                    PrimaryActionButton(
                        title: "执行",
                        systemImage: "return",
                        shortcut: "Enter"
                    ) {
                        viewModel.executeSelection(force: true, triggerSource: .pointerClick)
                    }
                }
                .padding(.horizontal, Design.Space.xl)
                .padding(.vertical, Design.Space.md)
                .overlay(dividerTop, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                    .fill(Constants.VisualStyle.surfaceRaised)
            )
            .themedShadow(.modal, cornerRadius: Design.cardCornerRadius)
            .padding(Design.Space.md)
        }
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

    private var globalFallbackHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.icon(.micro, weight: .semibold))
                .foregroundStyle(Constants.VisualStyle.accent)
            Text("当前分组无匹配，已自动扩展至全词库搜索")
                .font(.ui(.caption, weight: .medium))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.vertical, Design.Space.xs)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Constants.VisualStyle.accentDim)
        )
        .padding(.horizontal, Design.Space.xs)
        .padding(.bottom, Design.Space.xs)
    }

    private var emptyState: some View {
        VStack(spacing: Design.Space.md) {
            Text(emptyStateTitle)
                .font(.ui(.title))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: Design.Space.sm) {
                if !viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        viewModel.quickCreateEntryFromPanel(type: .note)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "note.text.badge.plus")
                                .font(.icon(.small))
                            Text("存为便签 (⇧↩)")
                                .font(.ui(.caption, weight: .medium))
                        }
                        .foregroundStyle(Constants.VisualStyle.accent)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Constants.VisualStyle.accentDim)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.quickCreateEntryFromPanel(type: .todo)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checklist")
                                .font(.icon(.small))
                            Text("存为待办 (⌥↩)")
                                .font(.ui(.caption, weight: .medium))
                        }
                        .foregroundStyle(Constants.VisualStyle.warn)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Constants.VisualStyle.warnDim)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.quickCreateEntryFromPanel(type: viewModel.defaultQuickCreateType)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.icon(.small))
                            Text("以搜索词直接新建 (⌘N)")
                                .font(.ui(.caption, weight: .medium))
                        }
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Constants.VisualStyle.tintSubtle)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    if viewModel.activeKindFilter != .all {
                        Button {
                            viewModel.activeKindFilter = .all
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .font(.icon(.small))
                                Text("查看全部类型")
                                    .font(.ui(.caption, weight: .medium))
                            }
                            .foregroundStyle(Constants.VisualStyle.accent)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Constants.VisualStyle.accentDim)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        viewModel.startQuickCapture(type: .note)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.pencil")
                                .font(.icon(.small))
                            Text("写便签")
                                .font(.ui(.caption, weight: .semibold))
                        }
                        .foregroundStyle(Constants.VisualStyle.accent)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Constants.VisualStyle.accentDim)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Constants.VisualStyle.accentBorder, lineWidth: Constants.Layout.hairline)
                        )
                        .hoverHighlight(cornerRadius: 6)
                        .roundedHitTarget(cornerRadius: 6)
                    }
                    .buttonStyle(.plain)

                    if viewModel.hasClipboardText {
                        Button {
                            viewModel.quickCreateNoteFromClipboard()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.icon(.small))
                                Text("剪贴板存便签")
                                    .font(.ui(.caption, weight: .medium))
                            }
                            .foregroundStyle(Constants.VisualStyle.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Constants.VisualStyle.tintSubtle)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                            )
                            .hoverHighlight(cornerRadius: 6)
                            .roundedHitTarget(cornerRadius: 6)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        viewModel.openSettings()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.pencil")
                                .font(.icon(.small))
                            Text("打开内容库")
                                .font(.ui(.caption, weight: .medium))
                        }
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Constants.VisualStyle.tintSubtle)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .padding(.vertical, Design.Space.xl)
    }

    private var emptyStateTitle: String {
        if !viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "全词库无匹配词条，按 ⇧Enter 存为便签或 ⌥Enter 存为待办"
        }
        if viewModel.activeKindFilter != .all {
            return "当前筛选「\(viewModel.activeKindFilter.displayName)」暂无词条"
        }
        return "当前分组暂无词条"
    }

    private func scopeBadgeText(for entry: Entry) -> String? {
        guard entry.projectId != viewModel.currentProjectId else {
            return nil
        }
        if entry.projectId == appState.defaultProjectId {
            return "通用"
        }
        return viewModel.projectName(for: entry.projectId)
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Design.Space.md) {
                hint(keys: "↑↓", label: "选择")
                hint(keys: "Enter", label: "执行")
                hint(keys: showsShortcutNumbers ? "⌘1-9" : "⇧↩", label: showsShortcutNumbers ? "直达" : "记便签")
                hint(keys: "⌘Y", label: "预览")
                hint(keys: "⌘P", label: appState.isPanelPinned ? "取消固定" : "固定")
                Spacer(minLength: 0)
                footerCountLabel
            }

            HStack(spacing: Design.Space.sm) {
                hint(keys: "Enter", label: "执行")
                hint(keys: showsShortcutNumbers ? "⌘1-9" : "⇧↩", label: showsShortcutNumbers ? "直达" : "记便签")
                hint(keys: "⌘Y", label: "预览")
                hint(keys: "⌘P", label: appState.isPanelPinned ? "取消固定" : "固定")
                Spacer(minLength: 0)
                footerCountLabel
            }
        }
        .padding(.horizontal, Design.Space.lg)
        .frame(height: Constants.Layout.footerHeight)
        .background(Constants.VisualStyle.scrim)
    }

    private var footerCountLabel: some View {
        Text("\(viewModel.entries.count) 条")
            .font(.ui(.caption, mono: true))
            .foregroundStyle(Constants.VisualStyle.textTertiary)
    }

    private func hint(keys: String, label: String) -> some View {
        HStack(spacing: 4) {
            KbdLabel(text: keys)
            Text(label)
                .font(.ui(.caption))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
                .lineLimit(1)
        }
        .fixedSize()
    }

    private var panelSurface: some View {
        Color.clear
            .materialSurface(
                material: .hudWindow,
                blendingMode: .behindWindow,
                state: .active,
                tint: Constants.VisualStyle.surface.opacity(0.76),
                cornerRadius: Design.windowCornerRadius,
                borderColor: Constants.VisualStyle.borderStrong
            )
    }
}

// MARK: - Panel Row

private struct PanelRow: View {
    let entry: Entry
    let index: Int
    let isSelected: Bool
    let isHoverEnabled: Bool
    let showNumber: Bool
    let scopeBadgeText: String?
    let isCompact: Bool
    /// Supplied by the list rather than measured per row; see `resultsList`.
    let availableWidth: CGFloat
    let onTap: () -> Void
    let onCopy: () -> Void
    let onPreview: () -> Void
    let onToggleComplete: () -> Void
    let onTogglePin: () -> Void

    private var _isHovered = SwiftUI.State(initialValue: false)

    init(
        entry: Entry,
        index: Int,
        isSelected: Bool,
        isHoverEnabled: Bool,
        showNumber: Bool,
        scopeBadgeText: String?,
        isCompact: Bool,
        availableWidth: CGFloat,
        onTap: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onPreview: @escaping () -> Void,
        onToggleComplete: @escaping () -> Void,
        onTogglePin: @escaping () -> Void
    ) {
        self.entry = entry
        self.index = index
        self.isSelected = isSelected
        self.isHoverEnabled = isHoverEnabled
        self.showNumber = showNumber
        self.scopeBadgeText = scopeBadgeText
        self.isCompact = isCompact
        self.availableWidth = availableWidth
        self.onTap = onTap
        self.onCopy = onCopy
        self.onPreview = onPreview
        self.onToggleComplete = onToggleComplete
        self.onTogglePin = onTogglePin
    }

    private var isHovered: Bool {
        get { _isHovered.wrappedValue }
        nonmutating set { _isHovered.wrappedValue = newValue }
    }

    private var isInteractiveTodo: Bool {
        entry.type == Constants.EntryType.todo.rawValue || entry.type == Constants.EntryType.note.rawValue
    }

    private var effectiveHovered: Bool {
        isHoverEnabled && isHovered
    }

    private var showsQuickActions: Bool {
        effectiveHovered
    }

    var body: some View {
        let type = Constants.EntryType.resolve(entry.type)
        let level = Constants.EntryLevel.resolve(useCount: entry.useCount)
        let rowHeight: CGFloat = isCompact ? 28 : 32
        let metrics = RowMetrics(totalWidth: availableWidth)

        // Fixed leading columns — number, then one 16pt glyph slot — so titles line
        // up whether the slot holds a type icon or a todo checkbox. The checkbox
        // used to sit in front of the number and shove the whole row 4pt right.
        HStack(spacing: Design.Space.md) {
            if showNumber {
                Group {
                    if index < 9 {
                        Text("\(index + 1)")
                            .font(.ui(.micro, weight: isSelected ? .semibold : .medium, mono: true))
                            .foregroundStyle(isSelected ? Constants.VisualStyle.accent : Constants.VisualStyle.textTertiary)
                            .frame(width: 18, height: 18)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isSelected ? Constants.VisualStyle.accentDim : Constants.VisualStyle.tintSubtle)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? Constants.VisualStyle.accentBorder : Constants.VisualStyle.border,
                                        lineWidth: Constants.Layout.hairline
                                    )
                            )
                    } else {
                        Text("\(index + 1)")
                            .font(.ui(.micro, weight: .medium, mono: true))
                            .foregroundStyle(isSelected ? Constants.VisualStyle.accent : Constants.VisualStyle.textQuaternary)
                            .frame(width: 18, height: 18, alignment: .center)
                    }
                }
                .frame(width: 18, height: rowHeight, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
            }

            if isInteractiveTodo {
                Button(action: onToggleComplete) {
                    Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.icon(.base))
                        .foregroundStyle(entry.isCompleted ? Constants.VisualStyle.success : Constants.VisualStyle.textTertiary)
                        .frame(width: 16, height: rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(entry.isCompleted ? "标记为未完成" : "完成并划掉")
            } else {
                Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : type.symbolName)
                    .font(.icon(.base))
                    .foregroundStyle(
                        entry.isCompleted
                            ? Constants.VisualStyle.success
                            : (isSelected ? Constants.VisualStyle.accent : Constants.VisualStyle.textSecondary)
                    )
                    .frame(width: 16, height: rowHeight)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)
            }

            Button(action: onTap) {
                HStack(spacing: Design.Space.md) {
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

                    HStack(spacing: Design.Space.xs) {
                        if entry.useCount > 0 {
                            Text("\(entry.useCount)次")
                                .font(.ui(.micro, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(entry.useCount >= 25 ? level.color : Constants.VisualStyle.textTertiary)
                        }
                        if let scopeBadgeText {
                            Text(scopeBadgeText)
                                .font(.ui(.micro, weight: .medium))
                                .foregroundStyle(Constants.VisualStyle.textTertiary)
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: Constants.Layout.badgeCornerRadius, style: .continuous)
                                        .fill(Constants.VisualStyle.tintSubtle)
                                )
                        }
                        if metrics.showsRecency {
                            Text(recencyLabel)
                                .font(.ui(.micro, weight: .medium, mono: true))
                                .foregroundStyle(isSelected ? Constants.VisualStyle.textSecondary : Constants.VisualStyle.textTertiary)
                        }
                    }
                    .layoutPriority(2)
                    .fixedSize(horizontal: true, vertical: false)
                    // The action strip overlays this corner; fading the meta out (rather
                    // than removing it) keeps the row layout identical on hover, and
                    // stops a half-covered "18 次" chip peeking out from under it.
                    .opacity(showsQuickActions ? 0 : 1)
                }
                .padding(.trailing, Design.Space.lg)
                .frame(maxWidth: .infinity)
                .frame(height: rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .padding(.leading, Design.Space.sm)
        .roundedHitTarget(cornerRadius: Design.rowCornerRadius)
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Constants.VisualStyle.accent)
                    .frame(width: 2.5, height: isCompact ? 14 : 16)
            }
        }
        .overlay(alignment: .trailing) {
            if showsQuickActions {
                quickActionStrip
                    .padding(.trailing, Design.Space.sm)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous)
                .fill(
                    isSelected
                        ? Constants.VisualStyle.accentDim
                        : (effectiveHovered ? Constants.VisualStyle.surfaceHover : Color.clear)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous))
        .onHover { hovering in
            guard isHoverEnabled else {
                if isHovered {
                    isHovered = false
                }
                return
            }
            if isHovered != hovering {
                isHovered = hovering
            }
        }
        .onChange(of: isHoverEnabled) { _, enabled in
            if !enabled, isHovered {
                isHovered = false
            }
        }
        .contextMenu {
            Button("执行词条 (Enter)") { onTap() }
            Button("仅复制内容 (⌘C)") { onCopy() }
            Button("预览全文 (⌘Y)") { onPreview() }
            Divider()
            Button(entry.isCompleted ? "标记为未完成" : "标记为已完成") { onToggleComplete() }
            Button(entry.isPinned ? "取消置顶" : "置顶词条") { onTogglePin() }
        }
    }

    private var quickActionStrip: some View {
        HStack(spacing: 2) {
            rowQuickActionButton(
                systemImage: "doc.on.doc",
                tint: Constants.VisualStyle.textSecondary,
                help: "仅复制内容 (⌘C)",
                action: onCopy
            )
            rowQuickActionButton(
                systemImage: "eye",
                tint: Constants.VisualStyle.textSecondary,
                help: "预览全文 (⌘Y)",
                action: onPreview
            )
            rowQuickActionButton(
                systemImage: entry.isPinned ? "pin.fill" : "pin",
                tint: entry.isPinned ? Constants.VisualStyle.warn : Constants.VisualStyle.textTertiary,
                help: entry.isPinned ? "取消置顶" : "置顶词条",
                action: onTogglePin
            )
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Constants.VisualStyle.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
        )
        .fixedSize()
    }

    private func rowQuickActionButton(
        systemImage: String,
        tint: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.icon(.small))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Constants.VisualStyle.tintSubtle)
                )
                .roundedHitTarget(cornerRadius: 4)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var titleLabel: some View {
        HStack(spacing: Design.Space.xs) {
            Text(entry.title)
                .font(.ui(.title, weight: .medium))
                .foregroundStyle(entry.isCompleted ? Constants.VisualStyle.textTertiary : Constants.VisualStyle.text)
                .strikethrough(entry.isCompleted, color: Constants.VisualStyle.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.icon(.micro, weight: .semibold))
                    .foregroundStyle(Constants.VisualStyle.warn.opacity(0.85))
            }
        }
    }

    /// How a row spends the width it is given. Kept strictly invariant with respect to
    /// hover and selection state so crossing rows never triggers text re-measurement.
    private struct RowMetrics {
        let titleWidth: CGFloat?
        let showsPreview: Bool
        let showsRecency: Bool

        init(totalWidth: CGFloat) {
            let effectiveWidth = max(totalWidth, 0)
            showsPreview = effectiveWidth >= 460
            showsRecency = effectiveWidth >= 400
            titleWidth = showsPreview ? min(max(effectiveWidth * 0.28, 145), 250) : nil
        }
    }

    private var recencyLabel: String {
        PPRelativeTimeFormatter.compactRecency(from: entry.lastUsedAt)
    }
}

// MARK: - Lightweight Click Controls (Local Hover Feedback Only)

private struct ScopeDropdownItemRow: View {
    let name: String
    let iconName: String
    let isActive: Bool
    let action: () -> Void

    private var _isHovered = SwiftUI.State(initialValue: false)

    init(name: String, iconName: String, isActive: Bool, action: @escaping () -> Void) {
        self.name = name
        self.iconName = iconName
        self.isActive = isActive
        self.action = action
    }

    private var isHovered: Bool {
        get { _isHovered.wrappedValue }
        nonmutating set { _isHovered.wrappedValue = newValue }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Space.sm) {
                Image(systemName: iconName)
                    .font(.icon(.small))
                    .foregroundStyle(isActive ? Constants.VisualStyle.accent : Constants.VisualStyle.textSecondary)
                    .frame(width: 15, alignment: .center)

                Text(name)
                    .font(.ui(.body, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Constants.VisualStyle.accent : Constants.VisualStyle.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.icon(.micro, weight: .bold))
                        .foregroundStyle(Constants.VisualStyle.accent)
                }
            }
            .padding(.horizontal, Design.Space.sm)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isActive
                            ? Constants.VisualStyle.accentDim
                            : (isHovered ? Constants.VisualStyle.surfaceHover : Color.clear)
                    )
            )
            .roundedHitTarget(cornerRadius: 6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
            }
        }
    }
}

private struct KindFilterChipButton: View {
    let filter: QuickPanelViewModel.KindFilter
    let isActive: Bool
    let isHoverEnabled: Bool
    let count: Int
    let action: () -> Void

    private var _isHovered = SwiftUI.State(initialValue: false)

    init(
        filter: QuickPanelViewModel.KindFilter,
        isActive: Bool,
        isHoverEnabled: Bool,
        count: Int,
        action: @escaping () -> Void
    ) {
        self.filter = filter
        self.isActive = isActive
        self.isHoverEnabled = isHoverEnabled
        self.count = count
        self.action = action
    }

    private var isHovered: Bool {
        get { _isHovered.wrappedValue }
        nonmutating set { _isHovered.wrappedValue = newValue }
    }

    private var effectiveHovered: Bool {
        isHoverEnabled && isHovered
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol = filter.symbolName {
                    Image(systemName: symbol)
                        .font(.icon(.micro))
                }
                Text(filter.displayName)
                    .font(.ui(.caption, weight: isActive ? .semibold : .medium))
                if count > 0, filter != .all {
                    Text("\(count)")
                        .font(.ui(.micro, weight: .medium, mono: true))
                        .opacity(0.75)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .foregroundStyle(
                isActive
                    ? Constants.VisualStyle.accent
                    : (effectiveHovered ? Constants.VisualStyle.text : Constants.VisualStyle.textTertiary)
            )
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        isActive
                            ? Constants.VisualStyle.accentDim
                            : (effectiveHovered ? Constants.VisualStyle.surfaceHover : Color.clear)
                    )
            )
            .roundedHitTarget(cornerRadius: 5)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            guard isHoverEnabled else {
                if isHovered {
                    isHovered = false
                }
                return
            }
            if isHovered != hovering {
                isHovered = hovering
            }
        }
        .onChange(of: isHoverEnabled) { _, enabled in
            if !enabled, isHovered {
                isHovered = false
            }
        }
    }
}


/// Quiet header action: neutral line icon, optional label and keycap. The panel
/// header used to mix emoji and three accent colours here; the accent now stays
/// reserved for the selected row so the eye lands on results, not chrome.
private struct HeaderGhostButton: View {
    let systemImage: String
    let title: String?
    var shortcut: String? = nil
    let action: () -> Void

    init(systemImage: String, title: String?, shortcut: String? = nil, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.icon(.small))
                if let title {
                    Text(title)
                        .font(.ui(.caption, weight: .medium))
                }
                if let shortcut {
                    Text(shortcut)
                        .font(.ui(.micro, weight: .medium, mono: true))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                }
            }
            .foregroundStyle(Constants.VisualStyle.textSecondary)
            .padding(.horizontal, title == nil ? 0 : 7)
            .frame(
                minWidth: Constants.Layout.compactControlHeight - 2,
                minHeight: Constants.Layout.compactControlHeight - 2
            )
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Constants.VisualStyle.tintSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
            )
            .hoverHighlight(cornerRadius: 5)
            .roundedHitTarget(cornerRadius: 5)
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}
