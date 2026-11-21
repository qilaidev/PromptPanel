import AppKit
import SwiftUI

struct ReferenceLibraryWindowView: View {
    @ObservedObject var viewModel: MainWindowViewModel
    @FocusState private var isSearchFocused: Bool

    private var activeTargetProjects: [Project] {
        viewModel.targetProjects(excluding: "")
    }

    private var effectiveTargetProjectId: String {
        if !viewModel.referenceTargetProjectId.isEmpty,
           activeTargetProjects.contains(where: { $0.id == viewModel.referenceTargetProjectId }) {
            return viewModel.referenceTargetProjectId
        }
        if viewModel.selectedProjectId != MainWindowViewModel.allProjectsSelection,
           activeTargetProjects.contains(where: { $0.id == viewModel.selectedProjectId }) {
            return viewModel.selectedProjectId
        }
        if activeTargetProjects.contains(where: { $0.id == viewModel.currentProjectId }) {
            return viewModel.currentProjectId
        }
        return activeTargetProjects.first?.id ?? viewModel.currentProjectId
    }

    private var sourceFilterLabel: String {
        if viewModel.referenceSourceProjectId == MainWindowViewModel.allProjectsSelection {
            return "全部来源"
        }
        let name = viewModel.projectName(for: viewModel.referenceSourceProjectId)
        return name.isEmpty ? "全部来源" : name
    }

    private var targetProjectLabel: String {
        let name = viewModel.projectName(for: effectiveTargetProjectId)
        return name.isEmpty ? "选择目标" : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerToolbar

            Rectangle()
                .fill(Constants.VisualStyle.divider)
                .frame(height: Constants.Layout.hairline)

            clipboardQuickImportStrip

            Rectangle()
                .fill(Constants.VisualStyle.divider)
                .frame(height: Constants.Layout.hairline)

            referenceEntriesList
        }
        .frame(minWidth: 540, minHeight: 560)
        .background(Constants.VisualStyle.surfaceRaised)
        .tint(Constants.VisualStyle.accent)
        .preferredColorScheme(viewModel.appTheme.preferredColorScheme)
        .onAppear {
            if viewModel.referenceTargetProjectId.isEmpty
                || !activeTargetProjects.contains(where: { $0.id == viewModel.referenceTargetProjectId }) {
                viewModel.referenceTargetProjectId = effectiveTargetProjectId
            }
            if viewModel.referenceSourceProjectId != MainWindowViewModel.allProjectsSelection
                && !activeTargetProjects.contains(where: { $0.id == viewModel.referenceSourceProjectId }) {
                viewModel.referenceSourceProjectId = MainWindowViewModel.allProjectsSelection
            }
            viewModel.refreshClipboardPreview()
            viewModel.refreshReferenceEntries(immediate: true)
        }
        .onChange(of: viewModel.referenceSourceProjectId) { _, _ in
            viewModel.refreshReferenceEntries()
        }
        .onChange(of: viewModel.referenceSearchText) { _, _ in
            viewModel.refreshReferenceEntries()
        }
        .onChange(of: viewModel.projects) { _, _ in
            if !activeTargetProjects.contains(where: { $0.id == viewModel.referenceTargetProjectId }) {
                viewModel.referenceTargetProjectId = effectiveTargetProjectId
            }
            if viewModel.referenceSourceProjectId != MainWindowViewModel.allProjectsSelection
                && !activeTargetProjects.contains(where: { $0.id == viewModel.referenceSourceProjectId }) {
                viewModel.referenceSourceProjectId = MainWindowViewModel.allProjectsSelection
            }
        }
    }

    // MARK: - Top Toolbar (Source Filter, Search & Target Project)

    private var headerToolbar: some View {
        HStack(spacing: 8) {
            sourceFilterMenu

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.icon(.small))
                    .foregroundStyle(isSearchFocused ? Constants.VisualStyle.accent : Constants.VisualStyle.textTertiary)
                TextField("搜索标题、内容或标签…", text: $viewModel.referenceSearchText)
                    .textFieldStyle(.plain)
                    .font(.ui(.body))
                    .foregroundStyle(Constants.VisualStyle.text)
                    .focused($isSearchFocused)
                if !viewModel.referenceSearchText.isEmpty {
                    Button {
                        viewModel.referenceSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.icon(.small))
                            .foregroundStyle(Constants.VisualStyle.textTertiary)
                            .frame(width: 18, height: 18)
                            .hoverHighlight(cornerRadius: 4)
                    }
                    .buttonStyle(PPInteractiveButtonStyle(cornerRadius: 4))
                    .help("清空搜索")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Constants.Layout.regularControlHeight)
            .focusableInputSurface(isFocused: isSearchFocused, cornerRadius: 6)

            targetProjectMenu
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Constants.VisualStyle.surface)
    }

    private var sourceFilterMenu: some View {
        Menu {
            Button {
                viewModel.referenceSourceProjectId = MainWindowViewModel.allProjectsSelection
            } label: {
                menuItemLabel("全部来源", isSelected: viewModel.referenceSourceProjectId == MainWindowViewModel.allProjectsSelection)
            }

            if let inbox = viewModel.inboxProject, !inbox.isArchived {
                Divider()
                Section("速记与待办") {
                    Button {
                        viewModel.referenceSourceProjectId = inbox.id
                    } label: {
                        menuItemLabel(inbox.name, isSelected: viewModel.referenceSourceProjectId == inbox.id)
                    }
                }
            }

            if !viewModel.categoryProjects.isEmpty {
                Divider()
                Section("常用类型") {
                    ForEach(viewModel.categoryProjects) { category in
                        Button {
                            viewModel.referenceSourceProjectId = category.id
                        } label: {
                            menuItemLabel(category.name, isSelected: viewModel.referenceSourceProjectId == category.id)
                        }
                    }
                }
            }

            if !viewModel.activeProjects.isEmpty {
                Divider()
                Section("项目") {
                    ForEach(viewModel.activeProjects) { project in
                        Button {
                            viewModel.referenceSourceProjectId = project.id
                        } label: {
                            menuItemLabel(project.name, isSelected: viewModel.referenceSourceProjectId == project.id)
                        }
                    }
                }
            }
        } label: {
            toolbarMenuPill(prefix: "来源", title: sourceFilterLabel, maxWidth: 146)
        }
        .menuStyle(.borderlessButton)
        .help("筛选来源分组：\(sourceFilterLabel)")
    }

    private var targetProjectMenu: some View {
        Menu {
            if !viewModel.activeProjects.isEmpty {
                Section("项目") {
                    ForEach(viewModel.activeProjects) { project in
                        Button {
                            viewModel.referenceTargetProjectId = project.id
                        } label: {
                            menuItemLabel(project.name, isSelected: effectiveTargetProjectId == project.id)
                        }
                    }
                }
            }

            if !viewModel.categoryProjects.isEmpty {
                Section("常用类型") {
                    ForEach(viewModel.categoryProjects) { category in
                        Button {
                            viewModel.referenceTargetProjectId = category.id
                        } label: {
                            menuItemLabel(category.name, isSelected: effectiveTargetProjectId == category.id)
                        }
                    }
                }
            }

            if let inbox = viewModel.inboxProject, !inbox.isArchived {
                Section("速记与待办") {
                    Button {
                        viewModel.referenceTargetProjectId = inbox.id
                    } label: {
                        menuItemLabel(inbox.name, isSelected: effectiveTargetProjectId == inbox.id)
                    }
                }
            }
        } label: {
            toolbarMenuPill(prefix: "目标", title: targetProjectLabel, maxWidth: 152)
        }
        .menuStyle(.borderlessButton)
        .help("目标存入与克隆分组：\(targetProjectLabel)")
    }

    private func toolbarMenuPill(prefix: String, title: String, maxWidth: CGFloat) -> some View {
        HStack(spacing: 5) {
            Text(prefix)
                .font(.ui(.caption, weight: .medium))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
            Text(title)
                .font(.ui(.body, weight: .medium))
                .foregroundStyle(Constants.VisualStyle.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 2)
            Image(systemName: "chevron.up.chevron.down")
                .font(.icon(.nano, weight: .semibold))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
        }
        .padding(.horizontal, 9)
        .frame(minWidth: 112, maxWidth: maxWidth)
        .frame(height: Constants.Layout.regularControlHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Constants.VisualStyle.inputFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
        )
        .hoverHighlight(cornerRadius: 6)
    }

    @ViewBuilder
    private func menuItemLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    // MARK: - System Clipboard Strip

    private var clipboardQuickImportStrip: some View {
        let fullTargetName = viewModel.projectName(for: effectiveTargetProjectId)
        let compactTargetName = Self.compactProjectLabel(fullTargetName)

        return HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.icon(.small, weight: .semibold))
                .foregroundStyle(Constants.VisualStyle.accent)
            Text("剪贴板")
                .font(.ui(.caption, weight: .semibold))
                .foregroundStyle(Constants.VisualStyle.text)

            Text(
                viewModel.clipboardPreviewText.isEmpty
                    ? "剪贴板为空"
                    : viewModel.clipboardPreviewText.replacingOccurrences(of: "\n", with: " ")
            )
            .font(.ui(.caption, mono: true))
            .foregroundStyle(viewModel.clipboardPreviewText.isEmpty ? Constants.VisualStyle.textTertiary : Constants.VisualStyle.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Constants.VisualStyle.inputFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
            )

            QuietIconButton(systemImage: "arrow.clockwise", help: "刷新剪贴板内容") {
                viewModel.refreshClipboardPreview()
            }

            if !viewModel.clipboardPreviewText.isEmpty {
                if let inbox = viewModel.inboxProject, !inbox.isArchived {
                    PPActionButton("记入待办", systemImage: "checklist", variant: .secondary, size: .compact) {
                        viewModel.createQuickEntryFromClipboard(intoProjectId: inbox.id, type: .todo)
                        viewModel.refreshReferenceEntries()
                    }
                }

                PPActionButton(
                    "存入「\(compactTargetName)」",
                    systemImage: "plus",
                    variant: .primary,
                    size: .compact
                ) {
                    viewModel.createQuickEntryFromClipboard(
                        intoProjectId: effectiveTargetProjectId,
                        type: .prompt
                    )
                    viewModel.refreshReferenceEntries()
                }
                .frame(maxWidth: 168)
                .help("将剪贴板内容存入「\(fullTargetName)」")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Constants.VisualStyle.surface)
    }

    // MARK: - Reference Entries List

    private var referenceEntriesList: some View {
        Group {
            if viewModel.referenceEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.icon(.hero, weight: .light))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                    Text("没有匹配的参考词条")
                        .font(.ui(.title, weight: .semibold))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                    if !viewModel.referenceSearchText.isEmpty
                        || viewModel.referenceSourceProjectId != MainWindowViewModel.allProjectsSelection {
                        PPActionButton("重置筛选条件", variant: .secondary, size: .compact) {
                            viewModel.referenceSearchText = ""
                            viewModel.referenceSourceProjectId = MainWindowViewModel.allProjectsSelection
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.referenceEntries) { entry in
                            ReferenceEntryRow(
                                entry: entry,
                                sourceName: viewModel.projectName(for: entry.projectId),
                                targetName: viewModel.projectName(for: effectiveTargetProjectId),
                                isAlreadyInTarget: entry.projectId == effectiveTargetProjectId,
                                onCloneToTarget: {
                                    _ = viewModel.cloneEntry(entry, toProjectId: effectiveTargetProjectId)
                                    viewModel.refreshReferenceEntries()
                                },
                                onCopy: {
                                    viewModel.copyEntryContent(entry)
                                    viewModel.refreshClipboardPreview()
                                }
                            )
                            Rectangle()
                                .fill(Constants.VisualStyle.divider)
                                .frame(height: Constants.Layout.hairline)
                        }
                    }
                }
                .background(Constants.VisualStyle.surfaceRaised)
            }
        }
    }

    static func compactProjectLabel(_ name: String, maxCharacters: Int = 8) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }
        return String(trimmed.prefix(maxCharacters)) + "…"
    }
}

private struct ReferenceEntryRow: View {
    let entry: Entry
    let sourceName: String
    let targetName: String
    let isAlreadyInTarget: Bool
    let onCloneToTarget: () -> Void
    let onCopy: () -> Void

    var body: some View {
        let compactTarget = ReferenceLibraryWindowView.compactProjectLabel(targetName)
        let cloneTitle = isAlreadyInTarget ? "再次克隆" : "克隆到「\(compactTarget)」"
        let cloneHelp = isAlreadyInTarget ? "再次克隆到「\(targetName)」" : "克隆到「\(targetName)」"

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(ReferenceLibraryWindowView.compactProjectLabel(sourceName, maxCharacters: 10))
                        .font(.ui(.micro, weight: .medium))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Constants.VisualStyle.tintMedium)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                        )
                        .help(sourceName)

                    Text(entry.title)
                        .font(.ui(.body, weight: .semibold))
                        .foregroundStyle(Constants.VisualStyle.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    Text("\(entry.useCount)次 · \(EntryDateFormat.shortDay(entry.createdAt))")
                        .font(.ui(.micro, mono: true))
                        .monospacedDigit()
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Text(entry.content)
                    .font(.ui(.caption))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            HStack(spacing: 6) {
                PPActionButton("复制", variant: .secondary, size: .compact, action: onCopy)

                PPActionButton(
                    cloneTitle,
                    systemImage: "plus.square.on.square",
                    variant: .primary,
                    size: .compact,
                    action: onCloneToTarget
                )
                .frame(maxWidth: 164)
                .disabled(targetName.isEmpty)
                .help(cloneHelp)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .hoverHighlight(cornerRadius: 0)
    }
}
