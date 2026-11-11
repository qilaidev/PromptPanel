import AppKit
import Foundation
import SwiftUI

@MainActor
private final class PanelInteractionCoordinator: ObservableObject {
    @Published var isHoveringScopePill = false
    @Published var isHoveringScopeDropdown = false
    @Published var hoveredScopeItemId: String?
    @Published var hoveredKindFilter: QuickPanelViewModel.KindFilter?
    var hasPointerMovedInSession = false

    var scopeOpenWorkItem: DispatchWorkItem?
    var scopeCloseWorkItem: DispatchWorkItem?
    var scopeSelectWorkItem: DispatchWorkItem?
    var filterDwellWorkItem: DispatchWorkItem?

    deinit {
        scopeOpenWorkItem?.cancel()
        scopeCloseWorkItem?.cancel()
        scopeSelectWorkItem?.cancel()
        filterDwellWorkItem?.cancel()
    }

    func resetScopeDropdownHoverState() {
        scopeOpenWorkItem?.cancel()
        scopeOpenWorkItem = nil
        scopeCloseWorkItem?.cancel()
        scopeCloseWorkItem = nil
        scopeSelectWorkItem?.cancel()
        scopeSelectWorkItem = nil
        isHoveringScopeDropdown = false
        hoveredScopeItemId = nil
    }

    func cancelAllTimers() {
        resetScopeDropdownHoverState()
        filterDwellWorkItem?.cancel()
        filterDwellWorkItem = nil
        isHoveringScopePill = false
        hoveredKindFilter = nil
    }
}

@MainActor
private final class PanelRowHoverBox: ObservableObject {
    @Published var isHovered = false
}

struct QuickPanelView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: QuickPanelViewModel
    @StateObject private var interaction = PanelInteractionCoordinator()

    private static let scopeHoverOpenDelayMs = 45
    private static let scopeHoverCloseDelayMs = 170
    private static let scopeHoverSelectDelayMs = 55
    private static let filterHoverDwellDelayMs = 65

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                header
                    .overlay(dividerBottom, alignment: .bottom)

                if viewModel.quickCaptureDraft == nil {
                    kindFilterStrip
                        .overlay(dividerBottom, alignment: .bottom)
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
                    }

                    if viewModel.isPreviewPresented,
                       viewModel.quickCaptureDraft == nil,
                       let previewEntry = viewModel.selectedEntry {
                        entryPreviewOverlay(previewEntry)
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
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closeScopeDropdownImmediately()
                    }
                    .zIndex(15)

                scopeDropdownCard
                    .padding(.leading, Design.Space.lg)
                    .padding(.top, 38)
                    .zIndex(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            PanelPointerActivityCatcher {
                if !interaction.hasPointerMovedInSession {
                    interaction.hasPointerMovedInSession = true
                }
                viewModel.notifyPointerMoved()
            }
        )
        .background(panelSurface)
        .preferredColorScheme(appState.appTheme.preferredColorScheme)
        .transaction { $0.animation = nil }
        .onChange(of: viewModel.focusToken) { _, _ in
            interaction.hasPointerMovedInSession = false
            interaction.cancelAllTimers()
        }
        .onChange(of: viewModel.isScopeDropdownOpen) { _, isOpen in
            if !isOpen {
                interaction.resetScopeDropdownHoverState()
            }
        }
        .onDisappear {
            interaction.cancelAllTimers()
        }
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

            ZStack(alignment: .leading) {
                if viewModel.query.isEmpty {
                    Text(searchPlaceholder)
                        .font(.ui(.title))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, 6)
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
                    onQuickCreateNote: { viewModel.quickCreateEntryFromPanel(type: .note) },
                    onQuickCreateTodo: { viewModel.quickCreateEntryFromPanel(type: .todo) },
                    onCycleScope: viewModel.cycleScope,
                    onEscape: viewModel.handleEscape,
                    onFocusResolved: viewModel.handleSearchFieldFocus
                )
            }
            .frame(minWidth: 72, maxWidth: .infinity)

            headerQuickCaptureControls

            pinButton
            settingsButton
            closeButton
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.sm)
    }

    @ViewBuilder
    private var headerQuickCaptureControls: some View {
        if viewModel.query.isEmpty {
            Button {
                viewModel.startQuickCapture(type: .note)
            } label: {
                HStack(spacing: 3) {
                    Text("✏️")
                        .font(.ui(.micro))
                    Text("写便签")
                        .font(.ui(.caption, weight: .semibold))
                }
                .foregroundStyle(Constants.VisualStyle.accent)
                .padding(.horizontal, 8)
                .frame(height: Constants.Layout.compactControlHeight - 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Constants.VisualStyle.accentDim)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Constants.VisualStyle.accentBorder, lineWidth: Constants.Layout.hairline)
                )
                .hoverHighlight(cornerRadius: 5)
                .roundedHitTarget(cornerRadius: 5)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("一键进入便签输入模式，直接打字回车即存")

            if viewModel.hasClipboardText {
                Button {
                    viewModel.quickCreateNoteFromClipboard()
                } label: {
                    Text("📋")
                        .font(.ui(.micro))
                        .frame(width: Constants.Layout.compactControlHeight - 2, height: Constants.Layout.compactControlHeight - 2)
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
                .help("将剪贴板内容一键存为便签")
            }
        } else {
            if viewModel.quickCaptureDraft == nil {
                Button {
                    viewModel.quickCreateEntryFromPanel(type: .note)
                } label: {
                    HStack(spacing: 3) {
                        Text("📝")
                            .font(.ui(.micro))
                        Text("记便签")
                            .font(.ui(.caption, weight: .medium))
                        Text("⇧↩")
                            .font(.ui(.micro, weight: .medium, mono: true))
                            .opacity(0.8)
                    }
                    .foregroundStyle(Constants.VisualStyle.accent)
                    .padding(.horizontal, 7)
                    .frame(height: Constants.Layout.compactControlHeight - 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Constants.VisualStyle.accentDim)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Constants.VisualStyle.accentBorder, lineWidth: Constants.Layout.hairline)
                    )
                    .roundedHitTarget(cornerRadius: 5)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("将当前输入一键存为便签（⇧Enter）")

                Button {
                    viewModel.quickCreateEntryFromPanel(type: .todo)
                } label: {
                    HStack(spacing: 3) {
                        Text("☑️")
                            .font(.ui(.micro))
                        Text("待办")
                            .font(.ui(.caption, weight: .medium))
                        Text("⌥↩")
                            .font(.ui(.micro, weight: .medium, mono: true))
                            .opacity(0.8)
                    }
                    .foregroundStyle(Constants.VisualStyle.warn)
                    .padding(.horizontal, 6)
                    .frame(height: Constants.Layout.compactControlHeight - 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Constants.VisualStyle.warnDim)
                    )
                    .roundedHitTarget(cornerRadius: 5)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("将当前输入一键存为待办（⌥Enter）")
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
        return Text(draft.modeBadgeText)
            .font(.ui(.caption, weight: .semibold))
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
        return "搜索 \(name)、#标签，或输入 ; 记便签 / t 记待办"
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

    // MARK: - Non-Focus-Stealing Scope Switcher (Hover-to-Open + Hover-to-Select + Scroll-to-Cycle)

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
                    .frame(maxWidth: 96, alignment: .leading)
                Image(systemName: viewModel.isScopeDropdownOpen ? "chevron.up" : "chevron.down")
                    .font(.icon(.micro, weight: .semibold))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: Constants.Layout.compactControlHeight)
            .background(
                RoundedRectangle(cornerRadius: Design.pillCornerRadius, style: .continuous)
                    .fill(
                        viewModel.isScopeDropdownOpen || interaction.isHoveringScopePill
                            ? Constants.VisualStyle.surfaceHover
                            : Constants.VisualStyle.tintSubtle
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.pillCornerRadius, style: .continuous)
                    .strokeBorder(
                        viewModel.isScopeDropdownOpen ? Constants.VisualStyle.accentBorder : Constants.VisualStyle.border,
                        lineWidth: Constants.Layout.hairline
                    )
            )
            .roundedHitTarget(cornerRadius: Design.pillCornerRadius)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onVerticalScrollStep { step in
            viewModel.cycleScope(step)
        }
        .onAlwaysHover { hovering in
            handleScopePillHoverChanged(hovering)
        }
        .help("悬停展开切换 · 滚轮或 Tab 快速切换分组")
    }

    private var scopeDropdownCard: some View {
        let inboxProjects = viewModel.projects.filter { $0.groupKind == .inbox }
        let categoryProjects = viewModel.projects.filter { $0.groupKind == .category }
        let activeProjects = viewModel.projects.filter { $0.groupKind == .project }

        return ScrollView {
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
        .frame(width: 224)
        .frame(maxHeight: 332)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                .fill(Constants.VisualStyle.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                .strokeBorder(Constants.VisualStyle.borderStrong, lineWidth: Constants.Layout.hairline)
        )
        .shadow(color: Color.black.opacity(0.26), radius: 16, x: 0, y: 8)
        .onAlwaysHover { hovering in
            handleScopeDropdownHoverChanged(hovering)
        }
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
        let isActive = viewModel.currentProjectId == id
        let isHovered = interaction.hoveredScopeItemId == id

        return Button {
            interaction.scopeSelectWorkItem?.cancel()
            interaction.scopeSelectWorkItem = nil
            viewModel.activateScope(id)
            closeScopeDropdownImmediately()
        } label: {
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
        .onAlwaysHover { hovering in
            handleScopeItemHover(id: id, hovering: hovering)
        }
    }

    private func toggleScopeDropdownImmediately() {
        if viewModel.isScopeDropdownOpen {
            closeScopeDropdownImmediately()
        } else {
            interaction.scopeOpenWorkItem?.cancel()
            interaction.scopeOpenWorkItem = nil
            interaction.scopeCloseWorkItem?.cancel()
            interaction.scopeCloseWorkItem = nil
            interaction.scopeSelectWorkItem?.cancel()
            interaction.scopeSelectWorkItem = nil
            viewModel.isScopeDropdownOpen = true
        }
    }

    private func closeScopeDropdownImmediately() {
        interaction.resetScopeDropdownHoverState()
        viewModel.isScopeDropdownOpen = false
    }

    private func handleScopePillHoverChanged(_ hovering: Bool) {
        interaction.isHoveringScopePill = hovering
        if hovering {
            interaction.scopeCloseWorkItem?.cancel()
            interaction.scopeCloseWorkItem = nil
            guard !viewModel.isScopeDropdownOpen else { return }
            interaction.scopeOpenWorkItem?.cancel()
            let interaction = self.interaction
            let viewModel = self.viewModel
            let workItem = DispatchWorkItem {
                guard interaction.isHoveringScopePill else { return }
                viewModel.isScopeDropdownOpen = true
            }
            interaction.scopeOpenWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(Self.scopeHoverOpenDelayMs),
                execute: workItem
            )
        } else {
            interaction.scopeOpenWorkItem?.cancel()
            interaction.scopeOpenWorkItem = nil
            scheduleScopeDropdownCloseIfNeeded()
        }
    }

    private func handleScopeDropdownHoverChanged(_ hovering: Bool) {
        interaction.isHoveringScopeDropdown = hovering
        if hovering {
            interaction.scopeCloseWorkItem?.cancel()
            interaction.scopeCloseWorkItem = nil
        } else {
            interaction.hoveredScopeItemId = nil
            interaction.scopeSelectWorkItem?.cancel()
            interaction.scopeSelectWorkItem = nil
            scheduleScopeDropdownCloseIfNeeded()
        }
    }

    private func scheduleScopeDropdownCloseIfNeeded() {
        guard !interaction.isHoveringScopePill, !interaction.isHoveringScopeDropdown, viewModel.isScopeDropdownOpen else {
            return
        }
        interaction.scopeCloseWorkItem?.cancel()
        let interaction = self.interaction
        let viewModel = self.viewModel
        let workItem = DispatchWorkItem {
            guard !interaction.isHoveringScopePill, !interaction.isHoveringScopeDropdown else { return }
            interaction.hoveredScopeItemId = nil
            viewModel.isScopeDropdownOpen = false
        }
        interaction.scopeCloseWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Self.scopeHoverCloseDelayMs),
            execute: workItem
        )
    }

    private func handleScopeItemHover(id: String, hovering: Bool) {
        if hovering {
            interaction.hoveredScopeItemId = id
            interaction.scopeSelectWorkItem?.cancel()
            let interaction = self.interaction
            let viewModel = self.viewModel
            let workItem = DispatchWorkItem {
                guard interaction.hoveredScopeItemId == id, viewModel.isScopeDropdownOpen else { return }
                viewModel.activateScope(id)
            }
            interaction.scopeSelectWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(Self.scopeHoverSelectDelayMs),
                execute: workItem
            )
        } else if interaction.hoveredScopeItemId == id {
            interaction.hoveredScopeItemId = nil
            interaction.scopeSelectWorkItem?.cancel()
            interaction.scopeSelectWorkItem = nil
        }
    }

    // MARK: - Kind Filter Bar

    private var kindFilterStrip: some View {
        HStack(spacing: Design.Space.xs) {
            ForEach(QuickPanelViewModel.KindFilter.barItems) { filter in
                kindFilterChip(filter)
            }

            Spacer(minLength: 0)

            Text("Tab 切分组")
                .font(.ui(.micro, mono: true))
                .foregroundStyle(Constants.VisualStyle.textQuaternary)
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, 5)
    }

    private func kindFilterChip(_ filter: QuickPanelViewModel.KindFilter) -> some View {
        let isActive = viewModel.activeKindFilter == filter
        let isHovered = interaction.hoveredKindFilter == filter
        let count = viewModel.countForFilter(filter)

        return Button {
            interaction.filterDwellWorkItem?.cancel()
            interaction.filterDwellWorkItem = nil
            viewModel.activeKindFilter = filter
        } label: {
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
                    : (isHovered ? Constants.VisualStyle.text : Constants.VisualStyle.textTertiary)
            )
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        isActive
                            ? Constants.VisualStyle.accentDim
                            : (isHovered ? Constants.VisualStyle.surfaceHover : Color.clear)
                    )
            )
            .roundedHitTarget(cornerRadius: 5)
        }
        .buttonStyle(.plain)
        .onAlwaysHover { hovering in
            handleKindFilterHover(filter: filter, hovering: hovering)
        }
    }

    private func handleKindFilterHover(filter: QuickPanelViewModel.KindFilter, hovering: Bool) {
        if hovering {
            interaction.hoveredKindFilter = filter
            interaction.filterDwellWorkItem?.cancel()
            let interaction = self.interaction
            let viewModel = self.viewModel
            let workItem = DispatchWorkItem {
                guard interaction.hoveredKindFilter == filter else { return }
                viewModel.activeKindFilter = filter
            }
            interaction.filterDwellWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(Self.filterHoverDwellDelayMs),
                execute: workItem
            )
        } else if interaction.hoveredKindFilter == filter {
            interaction.hoveredKindFilter = nil
            interaction.filterDwellWorkItem?.cancel()
            interaction.filterDwellWorkItem = nil
        }
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
                            if viewModel.isShowingGlobalFallback {
                                globalFallbackHeader
                            }
                            ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                                PanelRow(
                                    entry: entry,
                                    index: index,
                                    isSelected: index == viewModel.selectedIndex,
                                    showNumber: showsShortcutNumbers,
                                    scopeBadgeText: scopeBadgeText(for: entry),
                                    isCompact: appState.panelCompactRows,
                                    availableWidth: rowWidth,
                                    onHoverSelect: {
                                        guard interaction.hasPointerMovedInSession else { return }
                                        viewModel.selectEntryByHover(at: index)
                                    },
                                    onTap: {
                                        viewModel.executeEntry(at: index, triggerSource: .pointerClick)
                                    },
                                    onCopy: {
                                        viewModel.copyEntry(at: index)
                                    },
                                    onPreview: {
                                        viewModel.openPreview(at: index)
                                    },
                                    onToggleComplete: {
                                        viewModel.toggleEntryCompleted(entry)
                                    },
                                    onTogglePin: {
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
                .onChange(of: viewModel.lastSelectionScrollToken) { _, _ in
                    guard let selectedEntry = viewModel.selectedEntry else { return }
                    proxy.scrollTo(selectedEntry.id, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Inline Full-Text Preview Overlay (⌘Y)

    private func entryPreviewOverlay(_ entry: Entry) -> some View {
        let resolvedType = Constants.EntryType.resolve(entry.type)
        let projectLabel = viewModel.projectName(for: entry.projectId) ?? "通用"

        return ZStack {
            Color.black.opacity(0.18)
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
                        .roundedHitTarget(cornerRadius: 5)
                    }
                    .buttonStyle(.plain)
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
                            HStack(spacing: Design.Space.xs) {
                                ForEach(entry.tags, id: \.self) { tag in
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
                    GhostActionButton(
                        title: entry.isCompleted ? "标记未完成" : "标记已完成",
                        systemImage: entry.isCompleted ? "checkmark.circle.fill" : "circle"
                    ) {
                        viewModel.toggleEntryCompleted(entry)
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
            .overlay(
                RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                    .strokeBorder(Constants.VisualStyle.borderStrong, lineWidth: Constants.Layout.hairline)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 8)
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
                            Text("✏️")
                                .font(.ui(.micro))
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
            return "全词库无匹配词条，按 ⇧Enter 可直接存为便签"
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
                hint(keys: "⇧↩", label: "记便签")
                hint(keys: "Tab", label: "切分组")
                hint(keys: "⌘Y", label: "预览")
                hint(keys: "⌘C", label: "复制")
                Spacer(minLength: 0)
                footerCountLabel
            }

            HStack(spacing: Design.Space.sm) {
                hint(keys: "↑↓", label: "选择")
                hint(keys: "Enter", label: "执行")
                hint(keys: "⇧↩", label: "记便签")
                hint(keys: "Tab", label: "分组")
                hint(keys: "⌘Y", label: "预览")
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
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Constants.VisualStyle.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Constants.VisualStyle.borderStrong, lineWidth: Constants.Layout.hairline)
            )
    }
}

// MARK: - Panel Row

private struct PanelRow: View {
    let entry: Entry
    let index: Int
    let isSelected: Bool
    let showNumber: Bool
    let scopeBadgeText: String?
    let isCompact: Bool
    /// Supplied by the list rather than measured per row; see `resultsList`.
    let availableWidth: CGFloat
    let onHoverSelect: () -> Void
    let onTap: () -> Void
    let onCopy: () -> Void
    let onPreview: () -> Void
    let onToggleComplete: () -> Void
    let onTogglePin: () -> Void

    @StateObject private var hoverBox = PanelRowHoverBox()

    private var isInteractiveTodo: Bool {
        entry.type == Constants.EntryType.todo.rawValue || entry.type == Constants.EntryType.note.rawValue
    }

    private var showsQuickActions: Bool {
        hoverBox.isHovered || isSelected
    }

    var body: some View {
        let type = Constants.EntryType.resolve(entry.type)
        let level = Constants.EntryLevel.resolve(useCount: entry.useCount)
        let rowHeight = isCompact ? Constants.Layout.compactRowHeight : Constants.Layout.regularRowHeight
        let metrics = RowMetrics(totalWidth: availableWidth, reservingQuickActions: showsQuickActions)

        HStack(spacing: 0) {
            if isInteractiveTodo {
                Button(action: onToggleComplete) {
                    Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.icon(.base))
                        .foregroundStyle(entry.isCompleted ? Constants.VisualStyle.success : Constants.VisualStyle.textTertiary)
                        .frame(width: 22, height: rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, Design.Space.sm)
                .help(entry.isCompleted ? "标记为未完成" : "完成并划掉")
            }

            Button(action: onTap) {
                HStack(spacing: Design.Space.md) {
                    if showNumber {
                        Text("\(index + 1)")
                            .font(.ui(.micro, weight: .medium, mono: true))
                            .foregroundStyle(isSelected ? Constants.VisualStyle.accent : Constants.VisualStyle.textQuaternary)
                            .frame(width: 18, alignment: .center)
                    }

                    if !isInteractiveTodo {
                        Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : type.symbolName)
                            .font(.icon(.base))
                            .foregroundStyle(entry.isCompleted ? Constants.VisualStyle.success : level.color)
                            .frame(width: 16, height: 16)
                    }

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
                        if !showsQuickActions || availableWidth >= 480 {
                            Text("\(entry.useCount) 次")
                                .font(.ui(.micro, weight: .medium, mono: true))
                                .foregroundStyle(level.color)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: Constants.Layout.badgeCornerRadius, style: .continuous)
                                        .fill(level.fillColor)
                                )
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
                        if metrics.showsRecency, !showsQuickActions {
                            Text(recencyLabel)
                                .font(.ui(.micro, weight: .medium, mono: true))
                                .foregroundStyle(isSelected ? Constants.VisualStyle.textSecondary : Constants.VisualStyle.textTertiary)
                        }
                    }
                    .layoutPriority(2)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.leading, isInteractiveTodo ? Design.Space.xs : Design.Space.sm)
                .padding(.trailing, showsQuickActions ? Design.Space.xs : Design.Space.lg)
                .frame(maxWidth: .infinity)
                .frame(height: rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            if showsQuickActions {
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
                .padding(.trailing, Design.Space.sm)
                .fixedSize()
            }
        }
        .roundedHitTarget(cornerRadius: Design.rowCornerRadius)
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Constants.VisualStyle.accent)
                    .frame(width: 2.5, height: isCompact ? 14 : 16)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous)
                .fill(
                    isSelected
                        ? Constants.VisualStyle.tintMedium
                        : (hoverBox.isHovered ? Constants.VisualStyle.surfaceHover : Color.clear)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous))
        .onAlwaysHover { hovering in
            hoverBox.isHovered = hovering
            if hovering {
                onHoverSelect()
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

    /// How a row spends the width it is given. A portrait panel is narrow by
    /// design, so the secondary columns drop out in order of importance —
    /// content preview first, then the recency label — instead of squeezing the
    /// title down to an ellipsis.
    private struct RowMetrics {
        let titleWidth: CGFloat?
        let showsPreview: Bool
        let showsRecency: Bool

        init(totalWidth: CGFloat, reservingQuickActions: Bool) {
            let effectiveWidth = reservingQuickActions ? max(totalWidth - 64, 0) : totalWidth
            showsPreview = effectiveWidth >= 460
            showsRecency = effectiveWidth >= 400
            titleWidth = showsPreview ? min(max(effectiveWidth * 0.28, 145), 250) : nil
        }
    }

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

// MARK: - Non-Focus-Stealing AppKit Pointer Monitor

/// Detects genuine pointer movement inside the panel window so keyboard `↑/↓`
/// list scrolling never gets hijacked by a stationary mouse cursor.
private struct PanelPointerActivityCatcher: NSViewRepresentable {
    var onPointerMoved: () -> Void

    func makeNSView(context: Context) -> PanelPointerActivityNSView {
        let view = PanelPointerActivityNSView()
        view.onPointerMoved = onPointerMoved
        return view
    }

    func updateNSView(_ nsView: PanelPointerActivityNSView, context: Context) {
        nsView.onPointerMoved = onPointerMoved
    }
}

private final class PanelPointerActivityNSView: NSView {
    var onPointerMoved: (() -> Void)?
    private var monitor: Any?
    private var trackingArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var acceptsFirstResponder: Bool {
        false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        if abs(event.deltaX) > 0.15 || abs(event.deltaY) > 0.15 {
            onPointerMoved?()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMonitor()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeMonitor()
            if let trackingArea {
                removeTrackingArea(trackingArea)
                self.trackingArea = nil
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func updateMonitor() {
        removeMonitor()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self, let window = self.window, window.isVisible, event.window === window else {
                return event
            }
            if abs(event.deltaX) > 0.15 || abs(event.deltaY) > 0.15 {
                self.onPointerMoved?()
            }
            return event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
