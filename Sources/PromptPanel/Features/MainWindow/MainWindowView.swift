import AppKit
import Foundation
import SwiftUI

struct MainWindowView: View {
    @ObservedObject var viewModel: MainWindowViewModel
    private var _isSyncPopoverOpen = SwiftUI.State(initialValue: false)

    init(viewModel: MainWindowViewModel) {
        self.viewModel = viewModel
    }

    private var isContextDropdownOpen: Bool {
        get { viewModel.isContextDropdownOpen }
        nonmutating set { viewModel.isContextDropdownOpen = newValue }
    }

    private var isSyncPopoverOpen: Bool {
        get { _isSyncPopoverOpen.wrappedValue }
        nonmutating set { _isSyncPopoverOpen.wrappedValue = newValue }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Constants.VisualStyle.surface
                .ignoresSafeArea()

            VStack(spacing: 0) {
                windowHeader

                VStack(spacing: 0) {
                    if let bannerMessage = viewModel.bannerMessage {
                        SettingsBanner(
                            message: bannerMessage,
                            isBusy: viewModel.activeMaintenanceTask != nil,
                            onDismiss: { viewModel.bannerMessage = nil }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, Design.Space.md)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Group {
                        switch viewModel.selectedTab {
                        case .library:
                            LibraryView(viewModel: viewModel)
                        case .settings:
                            SettingsView(viewModel: viewModel)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transaction { $0.animation = nil }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(!isContextDropdownOpen)
            }

            if isContextDropdownOpen {
                Button("") {
                    closeContextDropdownImmediately()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)

                Color.black.opacity(0.001)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .padding(.top, Constants.Layout.headerHeight)
                    .onTapGesture {
                        closeContextDropdownImmediately()
                    }
                    .zIndex(10)

                contextSwitcherDropdown
                    .padding(.leading, Design.Space.lg)
                    .padding(.top, Constants.Layout.headerHeight + 4)
                    .zIndex(20)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
            }
        }
        .preferredColorScheme(viewModel.appTheme.preferredColorScheme)
        .tint(Constants.VisualStyle.accent)
        .frame(
            minWidth: Constants.MainWindowLayout.minContentSize.width,
            minHeight: Constants.MainWindowLayout.minContentSize.height
        )
        .animation(.easeOut(duration: 0.14), value: isContextDropdownOpen)
        .animation(.easeOut(duration: 0.14), value: viewModel.bannerMessage != nil)
        .onChange(of: viewModel.selectedTab) { _, _ in
            if isContextDropdownOpen {
                closeContextDropdownImmediately()
            }
            if isSyncPopoverOpen {
                isSyncPopoverOpen = false
            }
        }
        .onDisappear {
            if isContextDropdownOpen {
                closeContextDropdownImmediately()
            }
            if isSyncPopoverOpen {
                isSyncPopoverOpen = false
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.projectDraft != nil },
            set: { if !$0 { viewModel.projectDraft = nil } }
        )) {
            if let draftBinding = projectDraftBinding {
                ProjectEditorSheet(
                    draft: draftBinding,
                    onSave: viewModel.saveProjectDraft
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.entryDraft != nil },
            set: { if !$0 { viewModel.entryDraft = nil } }
        )) {
            if let draftBinding = entryDraftBinding {
                EntryEditorSheet(
                    draft: draftBinding,
                    projects: viewModel.targetProjects(excluding: ""),
                    onSave: viewModel.saveEntryDraft
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.deleteProjectState != nil },
            set: { if !$0 { viewModel.deleteProjectState = nil } }
        )) {
            if let deletionBinding = deleteProjectBinding {
                ProjectMigrationSheet(
                    state: deletionBinding,
                    targets: viewModel.targetProjects(excluding: deletionBinding.wrappedValue.project.id),
                    onConfirm: viewModel.confirmDeleteProject
                )
            }
        }
        .alert(
            "删除词条？",
            isPresented: Binding(
                get: { viewModel.entryPendingDeletion != nil },
                set: { if !$0 { viewModel.entryPendingDeletion = nil } }
            ),
            presenting: viewModel.entryPendingDeletion
        ) { _ in
            Button("删除", role: .destructive) {
                viewModel.confirmDeleteEntry()
            }
            Button("取消", role: .cancel) {
                viewModel.entryPendingDeletion = nil
            }
        } message: { entry in
            Text("“\(entry.title)” 删除后可在「设置 → 云端同步 → 高级操作 → 最近 30 天已删除」中按条恢复。")
        }
    }

    // MARK: - Header & Floating Context Switcher

    private var windowHeader: some View {
        ZStack {
            segmentedControl

            HStack(alignment: .center, spacing: 8) {
                contextSwitcherPill

                Spacer(minLength: 0)

                headerSyncCapsule

                PPActionButton("参考窗口", systemImage: "rectangle.split.2x1", variant: .secondary, size: .compact) {
                    if isContextDropdownOpen {
                        closeContextDropdownImmediately()
                    }
                    viewModel.openReferenceWindow()
                }
                .help("打开参考窗口 (⌘⇧N)")
            }
        }
        .padding(.horizontal, Design.Space.lg)
        .frame(height: Constants.Layout.headerHeight)
        .background(
            Rectangle()
                .fill(Constants.VisualStyle.surface)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isContextDropdownOpen {
                        closeContextDropdownImmediately()
                    }
                }
                .overlay(
                    Rectangle()
                        .fill(Constants.VisualStyle.divider)
                        .frame(height: Constants.Layout.hairline),
                    alignment: .bottom
                )
        )
    }

    private var headerSyncCapsule: some View {
        HStack(spacing: 1) {
            Button {
                if isContextDropdownOpen {
                    closeContextDropdownImmediately()
                }
                if viewModel.syncBadgeState == .unconfigured {
                    viewModel.selectedTab = .settings
                    viewModel.selectedSettingsArea = .preferences
                } else {
                    viewModel.syncCloudNow()
                }
            } label: {
                SyncStatusBadge(state: viewModel.syncBadgeState, compact: true)
            }
            .buttonStyle(PPInteractiveButtonStyle(cornerRadius: 6))
            .help(
                viewModel.syncBadgeState == .unconfigured
                    ? "前往设置配置多设备云端同步"
                    : "点击立即执行智能双向同步（先拉取云端合并，再推送本地变更）"
            )
            .contextMenu {
                if viewModel.syncBadgeState != .unconfigured {
                    Button("立即双向同步") {
                        viewModel.syncCloudNow()
                    }
                    Button("仅拉取云端合并到本地") {
                        viewModel.pullCloudOnly()
                    }
                    Divider()
                }
                Button("打开同步设置") {
                    viewModel.selectedTab = .settings
                    viewModel.selectedSettingsArea = .preferences
                }
            }

            if viewModel.syncBadgeState != .unconfigured {
                Button {
                    if isContextDropdownOpen {
                        closeContextDropdownImmediately()
                    }
                    isSyncPopoverOpen.toggle()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.icon(.nano, weight: .semibold))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                        .frame(width: 18, height: 22)
                        .hoverHighlight(cornerRadius: 5)
                        .roundedHitTarget(cornerRadius: 5)
                }
                .buttonStyle(PPInteractiveButtonStyle(cornerRadius: 5))
                .help("查看同步详情与模式")
                .popover(isPresented: Binding(
                    get: { isSyncPopoverOpen },
                    set: { isSyncPopoverOpen = $0 }
                ), arrowEdge: .bottom) {
                    headerSyncPopover
                }
            }
        }
    }

    private var headerSyncPopover: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack(spacing: Design.Space.sm) {
                SyncStatusBadge(state: viewModel.syncBadgeState, compact: false)
                Spacer(minLength: 8)
                Text(viewModel.cloudSyncEnabled ? "自动双向同步" : "手动同步")
                    .font(.ui(.caption, weight: .medium))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
            }

            Rectangle()
                .fill(Constants.VisualStyle.divider)
                .frame(height: Constants.Layout.hairline)

            if let report = viewModel.lastSyncReport {
                VStack(alignment: .leading, spacing: 4) {
                    syncPopoverRow(label: "上次同步", value: EntryDateFormat.full(report.syncedAt))
                    syncPopoverRow(label: "执行方向", value: report.direction.displayName)
                    if let rev = report.remoteRevision ?? viewModel.cloudRemoteRevision {
                        syncPopoverRow(label: "云端版本", value: "r\(rev)")
                    }
                    syncPopoverRow(
                        label: "拉取统计",
                        value: "分组 +\(report.pulledProjectsCreated)/更\(report.pulledProjectsUpdated) · 词条 +\(report.pulledEntriesCreated)/更\(report.pulledEntriesUpdated)/删\(report.pulledDeletionsCount)"
                    )
                    syncPopoverRow(
                        label: "推送统计",
                        value: report.pushedChangesCount > 0 ? "已推送 \(report.pushedChangesCount) 项" : (report.skippedPushReason ?? "本地无新变更")
                    )
                    if report.conflictsPreserved > 0 {
                        syncPopoverRow(label: "冲突留存", value: "\(report.conflictsPreserved) 处（已存历史版本）")
                    }
                    if let error = report.errorMessage, !error.isEmpty {
                        Text(error)
                            .font(.ui(.caption))
                            .foregroundStyle(Constants.VisualStyle.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text(viewModel.cloudSyncLastStatus)
                    .font(.ui(.caption))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Design.Space.sm) {
                PPActionButton("立即同步", systemImage: "arrow.triangle.2.circlepath", variant: .primary, size: .compact) {
                    isSyncPopoverOpen = false
                    viewModel.syncCloudNow()
                }
                PPActionButton("打开设置", systemImage: "slider.horizontal.3", variant: .secondary, size: .compact) {
                    isSyncPopoverOpen = false
                    viewModel.selectedTab = .settings
                    viewModel.selectedSettingsArea = .preferences
                }
            }
        }
        .padding(Design.Space.xl)
        .frame(width: 310)
        .background(Constants.VisualStyle.surfaceRaised)
    }

    private func syncPopoverRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.sm) {
            Text(label)
                .font(.ui(.caption))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.ui(.caption, weight: .medium))
                .foregroundStyle(Constants.VisualStyle.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var contextSwitcherPill: some View {
        Button {
            isContextDropdownOpen.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "scope")
                    .font(.icon(.micro, weight: .semibold))
                    .foregroundStyle(Constants.VisualStyle.accent)
                Text("当前面板：\(viewModel.projectName(for: viewModel.currentProjectId))")
                    .font(.ui(.caption, weight: .medium))
                    .foregroundStyle(isContextDropdownOpen ? Constants.VisualStyle.text : Constants.VisualStyle.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 168, alignment: .leading)
                Image(systemName: isContextDropdownOpen ? "chevron.up" : "chevron.down")
                    .font(.icon(.micro, weight: .semibold))
                    .foregroundStyle(isContextDropdownOpen ? Constants.VisualStyle.accent : Constants.VisualStyle.textTertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isContextDropdownOpen ? Constants.VisualStyle.surfaceHover : Constants.VisualStyle.tintSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isContextDropdownOpen ? Constants.VisualStyle.accentBorder : Constants.VisualStyle.border,
                        lineWidth: Constants.Layout.hairline
                    )
            )
            .hoverHighlight(cornerRadius: 6, isEnabled: !isContextDropdownOpen)
            .roundedHitTarget(cornerRadius: 6)
        }
        .buttonStyle(PPInteractiveButtonStyle(cornerRadius: 6))
        .help("点击切换当前快捷面板分组")
    }

    private var contextSwitcherDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let inbox = viewModel.inboxProject {
                        VStack(alignment: .leading, spacing: 2) {
                            dropdownSectionTitle("速记与待办")
                            contextDropdownRow(for: inbox, iconName: "checklist")
                        }
                    }

                    if !viewModel.categoryProjects.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            dropdownSectionTitle("常用类型")
                            ForEach(viewModel.categoryProjects) { category in
                                contextDropdownRow(for: category, iconName: category.effectiveIconName)
                            }
                        }
                    }

                    if !viewModel.activeProjects.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            dropdownSectionTitle("具体项目")
                            ForEach(viewModel.activeProjects) { project in
                                contextDropdownRow(for: project, iconName: project.effectiveIconName)
                            }
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 320)
            .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(Constants.VisualStyle.divider)
                .frame(height: Constants.Layout.hairline)

            HStack(spacing: 4) {
                Image(systemName: "hand.point.up.left")
                    .font(.icon(.micro))
                Text("点击切换当前快捷面板分组")
                    .font(.ui(.micro))
            }
            .foregroundStyle(Constants.VisualStyle.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(width: 244)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Constants.VisualStyle.surfaceRaised)
        )
        .themedShadow(.popover, cornerRadius: 9)
    }

    private func dropdownSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.ui(.micro, weight: .semibold))
            .foregroundStyle(Constants.VisualStyle.textTertiary)
            .padding(.horizontal, 6)
            .padding(.top, 2)
    }

    private func contextDropdownRow(for project: Project, iconName: String) -> some View {
        ContextDropdownRow(
            name: project.name,
            iconName: iconName,
            entryCount: viewModel.entryCount(forProjectId: project.id),
            isActive: project.id == viewModel.currentProjectId
        ) {
            viewModel.setCurrentProject(project.id)
            closeContextDropdownImmediately()
        }
    }

    private func closeContextDropdownImmediately() {
        isContextDropdownOpen = false
    }

    private var segmentedControl: some View {
        HStack(spacing: 2) {
            ForEach(segments, id: \.tab) { segment in
                segmentButton(title: segment.title, tab: segment.tab)
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

    private var segments: [(tab: MainWindowViewModel.Tab, title: String)] {
        [
            (.library, "内容库"),
            (.settings, "设置")
        ]
    }

    private func segmentButton(title: String, tab: MainWindowViewModel.Tab) -> some View {
        let isActive = viewModel.selectedTab == tab
        return Button {
            if isContextDropdownOpen {
                closeContextDropdownImmediately()
            }
            viewModel.selectedTab = tab
        } label: {
            Text(title)
                .font(.ui(.body, weight: .medium))
                .foregroundStyle(isActive ? Constants.VisualStyle.text : Constants.VisualStyle.textTertiary)
                .padding(.horizontal, 14)
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

    // MARK: - Binding helpers

    private var projectDraftBinding: Binding<MainWindowViewModel.ProjectDraft>? {
        guard viewModel.projectDraft != nil else { return nil }
        return Binding(
            get: { viewModel.projectDraft ?? MainWindowViewModel.ProjectDraft(existingProject: nil) },
            set: { viewModel.projectDraft = $0 }
        )
    }

    private var entryDraftBinding: Binding<MainWindowViewModel.EntryDraft>? {
        guard viewModel.entryDraft != nil else { return nil }
        return Binding(
            get: { viewModel.entryDraft ?? MainWindowViewModel.EntryDraft(existingEntry: nil, defaultProjectId: viewModel.currentProjectId) },
            set: { viewModel.entryDraft = $0 }
        )
    }

    private var deleteProjectBinding: Binding<MainWindowViewModel.ProjectDeletionState>? {
        guard viewModel.deleteProjectState != nil else { return nil }
        return Binding(
            get: {
                viewModel.deleteProjectState ?? MainWindowViewModel.ProjectDeletionState(
                    project: Project(name: ""),
                    entryCount: 0,
                    targetProjectId: ""
                )
            },
            set: { viewModel.deleteProjectState = $0 }
        )
    }
}

// MARK: - Sheets

private struct ProjectEditorSheet: View {
    @Binding var draft: MainWindowViewModel.ProjectDraft
    let onSave: () -> Bool
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: draft.existingProject == nil ? "新建分组" : "编辑分组")

            VStack(alignment: .leading, spacing: Design.Space.lg) {
                if draft.existingProject?.isSystemProtected != true {
                    SheetField(label: "分组类型") {
                        Picker("", selection: $draft.groupKind) {
                            Text("常用类型").tag(Project.GroupKind.category)
                            Text("项目").tag(Project.GroupKind.project)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }

                SheetField(label: "名称") {
                    TextField(draft.groupKind == .category ? "如：开发、写作" : "如：PromptPanel 2.0", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.ui(.title))
                        .focused($isNameFocused)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, Design.Space.xl)

            SheetActionFooter(
                primaryTitle: "保存",
                canSubmit: isProjectDraftValid,
                onCancel: { dismiss() },
                onPrimary: saveAndDismiss
            )
        }
        .frame(width: 420)
        .onAppear { isNameFocused = true }
    }

    private var isProjectDraftValid: Bool {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func saveAndDismiss() {
        guard isProjectDraftValid else { return }
        if onSave() {
            dismiss()
        }
    }
}

private struct EntryEditorSheet: View {
    @Binding var draft: MainWindowViewModel.EntryDraft
    let projects: [Project]
    let onSave: () -> Bool
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case title
        case content
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: draft.existingEntry == nil ? "新建词条" : "编辑词条")

            VStack(alignment: .leading, spacing: Design.Space.lg) {
                SheetField(label: "标题") {
                    TextField("输入标题（留空自动取首行）", text: $draft.title)
                        .textFieldStyle(.roundedBorder)
                        .font(.ui(.title))
                        .focused($focusedField, equals: .title)
                }

                HStack(alignment: .bottom, spacing: Design.Space.lg) {
                    SheetField(label: "所属项目") {
                        Picker("", selection: $draft.projectId) {
                            ForEach(projects) { project in
                                Text(project.name).tag(project.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 176, alignment: .leading)
                        .fixedSize()
                    }

                    SheetField(label: "类型") {
                        Picker("", selection: $draft.type) {
                            ForEach(Constants.EntryType.allCases, id: \.rawValue) { type in
                                Text(type.displayName).tag(type.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 132, alignment: .leading)
                        .fixedSize()
                    }

                    Toggle(isOn: $draft.isPinned) {
                        Text("置顶")
                            .font(.ui(.title, weight: .medium))
                    }
                    .toggleStyle(.checkbox)
                    .frame(height: 22, alignment: .center)

                    Spacer(minLength: 0)
                }

                SheetField(label: "标签") {
                    TextField("多个标签用逗号分隔（单标签不超过 10 字）", text: $draft.tagsText)
                        .textFieldStyle(.roundedBorder)
                        .font(.ui(.title))
                }

                contentEditor
            }
            .padding(.horizontal, 18)
            .padding(.vertical, Design.Space.xl)

            SheetActionFooter(
                primaryTitle: "保存",
                canSubmit: isEntryDraftValid,
                onCancel: { dismiss() },
                onPrimary: saveAndDismiss
            )
        }
        .frame(width: 620)
        .onAppear {
            focusedField = .content
        }
    }

    private var contentEditor: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Design.Space.sm) {
                SheetFieldLabel(text: "内容")
                Spacer(minLength: 0)
                Text("\(draft.content.count) 字")
                    .font(.ui(.caption, weight: .medium, mono: true))
                    .foregroundStyle(Constants.VisualStyle.textQuaternary)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft.content)
                    .font(.ui(.title))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .background(Constants.VisualStyle.surface)
                    .focused($focusedField, equals: .content)

                if draft.content.isEmpty {
                    Text("粘贴或输入要记录/执行的内容")
                        .font(.ui(.title))
                        .foregroundStyle(Constants.VisualStyle.textQuaternary)
                        // NSTextView adds 5pt default lineFragmentPadding inside TextEditor.
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            // The tighter chrome around it buys the editor extra rows, which is
            // where the height actually matters.
            .frame(height: 264)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Constants.VisualStyle.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(contentBorderColor, lineWidth: focusedField == .content ? 1 : 0.5)
            )
        }
    }

    private var contentBorderColor: Color {
        focusedField == .content ? Constants.VisualStyle.accentBorder : Constants.VisualStyle.borderStrong
    }

    private var isEntryDraftValid: Bool {
        draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func saveAndDismiss() {
        guard isEntryDraftValid else { return }
        if onSave() {
            dismiss()
        }
    }
}

private struct ProjectMigrationSheet: View {
    @Binding var state: MainWindowViewModel.ProjectDeletionState
    let targets: [Project]
    let onConfirm: () -> Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "删除前先迁移词条")

            VStack(alignment: .leading, spacing: Design.Space.lg) {
                Text("项目 “\(state.project.name)” 下还有 \(state.entryCount) 条词条，必须先迁移到其他项目。")
                    .font(.ui(.title))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                SheetField(label: "迁移到") {
                    Picker("", selection: $state.targetProjectId) {
                        ForEach(targets) { project in
                            Text(project.name).tag(project.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, Design.Space.xl)

            SheetActionFooter(
                primaryTitle: "迁移并删除",
                primaryRole: .destructive,
                canSubmit: state.targetProjectId.isEmpty == false,
                onCancel: { dismiss() },
                onPrimary: confirmAndDismiss
            )
        }
        .frame(width: 460)
    }

    private func confirmAndDismiss() {
        guard state.targetProjectId.isEmpty == false else { return }
        if onConfirm() {
            dismiss()
        }
    }
}

private struct SheetHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.ui(.heading, weight: .semibold))
            .foregroundStyle(Constants.VisualStyle.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, Design.Space.xl)
            .padding(.bottom, Design.Space.lg)
            .background(Constants.VisualStyle.surfaceRaised)
            .overlay(
                Rectangle()
                    .fill(Constants.VisualStyle.divider)
                    .frame(height: Constants.Layout.hairline),
                alignment: .bottom
            )
    }
}

private struct SheetField<Content: View>: View {
    let label: String
    let footer: String?
    let content: () -> Content

    init(label: String, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            SheetFieldLabel(text: label)
            content()
            if let footer {
                Text(footer)
                    .font(.ui(.caption))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SheetFieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.ui(.title, weight: .semibold))
            .foregroundStyle(Constants.VisualStyle.text)
    }
}

private struct SheetActionFooter: View {
    let primaryTitle: String
    var primaryRole: ButtonRole?
    let canSubmit: Bool
    var message: String?
    let onCancel: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        HStack(spacing: Design.Space.md) {
            if let message {
                Text(message)
                    .font(.ui(.body))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button("取消", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .frame(minWidth: 72)

            Button(role: primaryRole, action: onPrimary) {
                Text(primaryTitle)
                    .frame(minWidth: 72)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
        }
        .controlSize(.regular)
        .padding(.horizontal, 18)
        .padding(.vertical, Design.Space.lg)
        .background(Constants.VisualStyle.surfaceRaised)
        .overlay(
            Rectangle()
                .fill(Constants.VisualStyle.divider)
                .frame(height: Constants.Layout.hairline),
            alignment: .top
        )
    }
}

private struct ContextDropdownRow: View {
    let name: String
    let iconName: String
    let entryCount: Int
    let isActive: Bool
    let action: () -> Void

    private var _isHovered = SwiftUI.State(initialValue: false)

    init(
        name: String,
        iconName: String,
        entryCount: Int,
        isActive: Bool,
        action: @escaping () -> Void
    ) {
        self.name = name
        self.iconName = iconName
        self.entryCount = entryCount
        self.isActive = isActive
        self.action = action
    }

    private var isHovered: Bool {
        get { _isHovered.wrappedValue }
        nonmutating set { _isHovered.wrappedValue = newValue }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: iconName)
                    .font(.icon(.small, weight: .medium))
                    .foregroundStyle(isActive ? Constants.VisualStyle.accent : Constants.VisualStyle.textSecondary)
                    .frame(width: 15)

                Text(name)
                    .font(.ui(.body, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(Constants.VisualStyle.text)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(entryCount)")
                    .font(.ui(.micro, mono: true))
                    .foregroundStyle(isActive ? Constants.VisualStyle.accent : Constants.VisualStyle.textTertiary)

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.icon(.micro, weight: .bold))
                        .foregroundStyle(Constants.VisualStyle.accent)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isActive
                            ? Constants.VisualStyle.accentDim
                            : (isHovered ? Constants.VisualStyle.surfaceHover : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isActive ? Constants.VisualStyle.accent.opacity(0.3) : Color.clear,
                        lineWidth: Constants.Layout.hairline
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
