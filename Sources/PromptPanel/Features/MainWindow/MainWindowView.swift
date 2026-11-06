import AppKit
import Foundation
import SwiftUI

struct MainWindowView: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        ZStack {
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
        }
        .preferredColorScheme(viewModel.appTheme.preferredColorScheme)
        .tint(Constants.VisualStyle.accent)
        .frame(
            minWidth: Constants.MainWindowLayout.minContentSize.width,
            minHeight: Constants.MainWindowLayout.minContentSize.height
        )
        .transaction { $0.animation = nil }
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

    // MARK: - Header

    private var windowHeader: some View {
        ZStack {
            segmentedControl

            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "scope")
                        .font(.icon(.micro, weight: .semibold))
                        .foregroundStyle(Constants.VisualStyle.accent)
                    Text("当前面板：\(viewModel.projectName(for: viewModel.currentProjectId))")
                        .font(.ui(.caption, weight: .medium))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.icon(.micro, weight: .semibold))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Constants.VisualStyle.tintSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                )
                .overlay {
                    Menu {
                        ForEach(viewModel.activeProjects) { project in
                            Button {
                                viewModel.setCurrentProject(project.id)
                            } label: {
                                if project.id == viewModel.currentProjectId {
                                    Label(project.name, systemImage: "checkmark")
                                } else {
                                    Text(project.name)
                                }
                            }
                        }
                    } label: {
                        Color.clear
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .opacity(0.02)
                }
                .clipped()
                .help("切换快捷面板默认绑定的项目")

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
                    TextField("输入标题", text: $draft.title)
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
            focusedField = draft.title.isEmpty ? .title : .content
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
                    Text("粘贴或输入要执行的内容")
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
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
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
