import AppKit
import Foundation
import SwiftUI

private final class ContextDropdownInteractionState: ObservableObject {
    @Published var isOpen: Bool = false
    @Published var isHoveringPill: Bool = false
    @Published var isHoveringDropdown: Bool = false
    @Published var hoveredProjectId: String?

    var pendingOpenWorkItem: DispatchWorkItem?
    var pendingCloseWorkItem: DispatchWorkItem?
    var pendingHoverSelectWorkItem: DispatchWorkItem?

    deinit {
        cancelAllTimers()
    }

    func cancelAllTimers() {
        pendingOpenWorkItem?.cancel()
        pendingOpenWorkItem = nil
        pendingCloseWorkItem?.cancel()
        pendingCloseWorkItem = nil
        pendingHoverSelectWorkItem?.cancel()
        pendingHoverSelectWorkItem = nil
    }

    func resetDropdownHoverState() {
        cancelAllTimers()
        isHoveringDropdown = false
        hoveredProjectId = nil
    }
}

struct MainWindowView: View {
    @ObservedObject var viewModel: MainWindowViewModel
    @StateObject private var dropdownState = ContextDropdownInteractionState()

    private static let hoverOpenDelayMs: Int = 110
    private static let hoverCloseDelayMs: Int = 170
    private static let hoverSelectDelayMs: Int = 70

    var body: some View {
        ZStack(alignment: .topLeading) {
            Constants.VisualStyle.surface
                .ignoresSafeArea()

            VStack(spacing: 0) {
                windowHeader

                if let bannerMessage = viewModel.bannerMessage {
                    SettingsBanner(
                        message: bannerMessage,
                        isBusy: viewModel.activeMaintenanceTask != nil,
                        onDismiss: { viewModel.bannerMessage = nil }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, Design.Space.md)
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
            }

            if dropdownState.isOpen {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeContextDropdownImmediately()
                    }
                    .zIndex(10)

                contextSwitcherDropdown
                    .padding(.leading, Design.Space.lg)
                    .padding(.top, Constants.Layout.headerHeight + 4)
                    .zIndex(20)
            }
        }
        .preferredColorScheme(viewModel.appTheme.preferredColorScheme)
        .tint(Constants.VisualStyle.accent)
        .frame(
            minWidth: Constants.MainWindowLayout.minContentSize.width,
            minHeight: Constants.MainWindowLayout.minContentSize.height
        )
        .transaction { $0.animation = nil }
        .onChange(of: dropdownState.isOpen) { _, isOpen in
            if !isOpen {
                dropdownState.resetDropdownHoverState()
            }
        }
        .onDisappear {
            dropdownState.resetDropdownHoverState()
            dropdownState.isHoveringPill = false
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
                    projects: viewModel.projectOptions,
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
                    targets: viewModel.projectOptions.filter { $0.id != deletionBinding.wrappedValue.project.id },
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
            Text("“\(entry.title)” 删除后无法恢复。")
        }
    }

    // MARK: - Header & Floating Context Switcher

    private var windowHeader: some View {
        ZStack {
            segmentedControl

            HStack(alignment: .center, spacing: 8) {
                contextSwitcherPill

                Spacer(minLength: 0)

                SettingsPillButton("参考窗口", systemImage: "rectangle.split.2x1") {
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
                .overlay(
                    Rectangle()
                        .fill(Constants.VisualStyle.divider)
                        .frame(height: Constants.Layout.hairline),
                    alignment: .bottom
                )
        )
    }

    private var contextSwitcherPill: some View {
        let isHighlighted = dropdownState.isOpen || dropdownState.isHoveringPill
        return Button {
            if dropdownState.isOpen {
                closeContextDropdownImmediately()
            } else {
                dropdownState.pendingOpenWorkItem?.cancel()
                dropdownState.pendingOpenWorkItem = nil
                dropdownState.pendingCloseWorkItem?.cancel()
                dropdownState.pendingCloseWorkItem = nil
                dropdownState.isOpen = true
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "scope")
                    .font(.icon(.micro, weight: .semibold))
                    .foregroundStyle(Constants.VisualStyle.accent)
                Text("当前面板：\(viewModel.projectName(for: viewModel.currentProjectId))")
                    .font(.ui(.caption, weight: .medium))
                    .foregroundStyle(isHighlighted ? Constants.VisualStyle.text : Constants.VisualStyle.textSecondary)
                    .lineLimit(1)
                Image(systemName: dropdownState.isOpen ? "chevron.up" : "chevron.down")
                    .font(.icon(.micro, weight: .semibold))
                    .foregroundStyle(isHighlighted ? Constants.VisualStyle.accent : Constants.VisualStyle.textTertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHighlighted ? Constants.VisualStyle.surfaceHover : Constants.VisualStyle.tintSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        dropdownState.isOpen ? Constants.VisualStyle.accentBorder : Constants.VisualStyle.border,
                        lineWidth: Constants.Layout.hairline
                    )
            )
            .roundedHitTarget(cornerRadius: 6)
        }
        .buttonStyle(.plain)
        .onVerticalScrollStep { step in
            viewModel.cycleCurrentProject(step: step)
        }
        .onHover { hovering in
            dropdownState.isHoveringPill = hovering
            if hovering {
                dropdownState.pendingCloseWorkItem?.cancel()
                dropdownState.pendingCloseWorkItem = nil
                if !dropdownState.isOpen {
                    scheduleContextDropdownOpen()
                }
            } else {
                dropdownState.pendingOpenWorkItem?.cancel()
                dropdownState.pendingOpenWorkItem = nil
                scheduleContextDropdownCloseIfOutside()
            }
        }
        .help("悬停展开并滑过即切 · 滚轮上下轮换当前快捷面板分组")
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
                Image(systemName: "cursorarrow.motionlines")
                    .font(.icon(.micro))
                Text("滑过即切 · 点击收起 · 顶部滚轮轮换")
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
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Constants.VisualStyle.borderStrong, lineWidth: Constants.Layout.hairline)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 8)
        .onHover { hovering in
            dropdownState.isHoveringDropdown = hovering
            if hovering {
                dropdownState.pendingCloseWorkItem?.cancel()
                dropdownState.pendingCloseWorkItem = nil
            } else {
                dropdownState.hoveredProjectId = nil
                dropdownState.pendingHoverSelectWorkItem?.cancel()
                dropdownState.pendingHoverSelectWorkItem = nil
                scheduleContextDropdownCloseIfOutside()
            }
        }
    }

    private func dropdownSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.ui(.micro, weight: .semibold))
            .foregroundStyle(Constants.VisualStyle.textTertiary)
            .padding(.horizontal, 6)
            .padding(.top, 2)
    }

    private func contextDropdownRow(for project: Project, iconName: String) -> some View {
        let isActive = project.id == viewModel.currentProjectId
        let isHovered = dropdownState.hoveredProjectId == project.id
        return Button {
            dropdownState.pendingHoverSelectWorkItem?.cancel()
            dropdownState.pendingHoverSelectWorkItem = nil
            if viewModel.currentProjectId != project.id {
                viewModel.setCurrentProject(project.id)
            }
            closeContextDropdownImmediately()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: iconName)
                    .font(.icon(.small, weight: .medium))
                    .foregroundStyle(isActive ? Constants.VisualStyle.accent : Constants.VisualStyle.textSecondary)
                    .frame(width: 15)

                Text(project.name)
                    .font(.ui(.body, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(Constants.VisualStyle.text)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(viewModel.entryCount(forProjectId: project.id))")
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
            if hovering {
                dropdownState.hoveredProjectId = project.id
                scheduleHoverSelectProject(project.id)
            } else if dropdownState.hoveredProjectId == project.id {
                dropdownState.hoveredProjectId = nil
                dropdownState.pendingHoverSelectWorkItem?.cancel()
                dropdownState.pendingHoverSelectWorkItem = nil
            }
        }
    }

    private func scheduleContextDropdownOpen() {
        dropdownState.pendingOpenWorkItem?.cancel()
        let state = dropdownState
        let workItem = DispatchWorkItem { [weak state] in
            guard let state, state.isHoveringPill else { return }
            state.isOpen = true
        }
        dropdownState.pendingOpenWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Self.hoverOpenDelayMs),
            execute: workItem
        )
    }

    private func scheduleContextDropdownCloseIfOutside() {
        dropdownState.pendingCloseWorkItem?.cancel()
        let state = dropdownState
        let workItem = DispatchWorkItem { [weak state] in
            guard let state, !state.isHoveringPill && !state.isHoveringDropdown else { return }
            state.isOpen = false
            state.hoveredProjectId = nil
        }
        dropdownState.pendingCloseWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Self.hoverCloseDelayMs),
            execute: workItem
        )
    }

    private func scheduleHoverSelectProject(_ projectId: String) {
        dropdownState.pendingHoverSelectWorkItem?.cancel()
        guard viewModel.currentProjectId != projectId else { return }
        let state = dropdownState
        let viewModel = self.viewModel
        let workItem = DispatchWorkItem { [weak state, weak viewModel] in
            guard let state, let viewModel,
                  state.hoveredProjectId == projectId,
                  state.isOpen else { return }
            if viewModel.currentProjectId != projectId {
                viewModel.setCurrentProject(projectId)
            }
        }
        dropdownState.pendingHoverSelectWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Self.hoverSelectDelayMs),
            execute: workItem
        )
    }

    private func closeContextDropdownImmediately() {
        dropdownState.resetDropdownHoverState()
        dropdownState.isOpen = false
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

                HStack(alignment: .top, spacing: Design.Space.lg) {
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
                    // Sits level with the pickers, below their field labels.
                    .padding(.top, 21)

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
                    .padding(.horizontal, Design.Space.xs)
                    .padding(.vertical, 3)
                    .background(Constants.VisualStyle.surface)
                    .focused($focusedField, equals: .content)

                if draft.content.isEmpty {
                    Text("粘贴或输入要记录/执行的内容")
                        .font(.ui(.title))
                        .foregroundStyle(Constants.VisualStyle.textQuaternary)
                        .padding(.horizontal, Design.Space.md)
                        .padding(.vertical, Design.Space.sm)
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
