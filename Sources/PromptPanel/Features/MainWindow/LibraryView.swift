import AppKit
import SwiftUI

struct LibraryView: View {
    @ObservedObject var viewModel: MainWindowViewModel
    @FocusState private var isEntrySearchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            projectsColumn
                .frame(width: 196)
                .background(Constants.VisualStyle.sidebar)

            verticalDivider

            entriesColumn
                .frame(width: 312)
                .background(Constants.VisualStyle.surface)

            verticalDivider

            PreviewPane(viewModel: viewModel, inlineSession: viewModel.inlineSession)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Constants.VisualStyle.surfaceRaised)
        }
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Constants.VisualStyle.divider)
            .frame(width: Constants.Layout.hairline)
    }

    private var horizontalDivider: some View {
        Rectangle()
            .fill(Constants.VisualStyle.divider)
            .frame(height: Constants.Layout.hairline)
    }

    // MARK: - Column 1: Native macOS Sidebar (Inbox / Categories / Projects / Archived)

    private var projectsColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Section 1: 全部与速记
                VStack(alignment: .leading, spacing: 2) {
                    SidebarGroupRow(
                        title: "全部内容",
                        systemImage: "tray.2",
                        count: viewModel.totalEntryCount,
                        isSelected: viewModel.selectedProjectId == MainWindowViewModel.allProjectsSelection,
                        isCurrentContext: false,
                        badgeText: nil
                    ) {
                        viewModel.selectedProjectId = MainWindowViewModel.allProjectsSelection
                    }

                    if let inbox = viewModel.inboxProject {
                        SidebarGroupRow(
                            title: inbox.name,
                            systemImage: "checklist",
                            count: viewModel.entryCount(forProjectId: inbox.id),
                            isSelected: viewModel.selectedProjectId == inbox.id,
                            isCurrentContext: inbox.id == viewModel.currentProjectId,
                            badgeText: nil,
                            onSetCurrentContext: {
                                viewModel.setCurrentProject(inbox.id)
                            },
                            onDropEntryIds: { ids in
                                viewModel.moveEntries(withIds: ids, toProjectId: inbox.id) > 0
                            }
                        ) {
                            viewModel.selectedProjectId = inbox.id
                        }
                        .contextMenu {
                            Button("设为快捷面板当前上下文") {
                                viewModel.selectedProjectId = inbox.id
                                viewModel.setCurrentProjectToSelected()
                            }
                            Button("新建待办或笔记") {
                                viewModel.selectedProjectId = inbox.id
                                viewModel.startCreateEntry()
                            }
                        }
                    }
                }

                // Section 2: 常用类型 (Reusable Categories)
                VStack(alignment: .leading, spacing: 2) {
                    SidebarSectionHeader(title: "常用类型") {
                        viewModel.startCreateProject(kind: .category)
                    }

                    ForEach(viewModel.categoryProjects) { category in
                        SidebarGroupRow(
                            title: category.name,
                            systemImage: category.effectiveIconName,
                            count: viewModel.entryCount(forProjectId: category.id),
                            isSelected: viewModel.selectedProjectId == category.id,
                            isCurrentContext: category.id == viewModel.currentProjectId,
                            badgeText: nil,
                            onSetCurrentContext: {
                                viewModel.setCurrentProject(category.id)
                            },
                            onDropEntryIds: { ids in
                                viewModel.moveEntries(withIds: ids, toProjectId: category.id) > 0
                            }
                        ) {
                            viewModel.selectedProjectId = category.id
                        }
                        .contextMenu {
                            projectContextMenu(for: category)
                        }
                    }
                }

                // Section 3: 项目 (Active Projects)
                VStack(alignment: .leading, spacing: 2) {
                    SidebarSectionHeader(title: "项目") {
                        viewModel.startCreateProject(kind: .project)
                    }

                    if viewModel.activeProjects.isEmpty {
                        Text("暂无项目")
                            .font(.ui(.caption))
                            .foregroundStyle(Constants.VisualStyle.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(viewModel.activeProjects) { project in
                            SidebarGroupRow(
                                title: project.name,
                                systemImage: project.effectiveIconName,
                                count: viewModel.entryCount(forProjectId: project.id),
                                isSelected: viewModel.selectedProjectId == project.id,
                                isCurrentContext: project.id == viewModel.currentProjectId,
                                badgeText: nil,
                                onSetCurrentContext: {
                                    viewModel.setCurrentProject(project.id)
                                },
                                onDropEntryIds: { ids in
                                    viewModel.moveEntries(withIds: ids, toProjectId: project.id) > 0
                                }
                            ) {
                                viewModel.selectedProjectId = project.id
                            }
                            .contextMenu {
                                projectContextMenu(for: project)
                            }
                        }
                    }
                }

                // Section 4: 已归档 (Archived Projects)
                if !viewModel.archivedProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.isArchivedSectionExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("已归档 (\(viewModel.archivedProjects.count))")
                                    .font(.ui(.caption, weight: .semibold))
                                    .foregroundStyle(Constants.VisualStyle.textTertiary)
                                Spacer()
                                Image(systemName: viewModel.isArchivedSectionExpanded ? "chevron.down" : "chevron.right")
                                    .font(.icon(.micro, weight: .semibold))
                                    .foregroundStyle(Constants.VisualStyle.textTertiary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if viewModel.isArchivedSectionExpanded {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(viewModel.archivedProjects) { archived in
                                    SidebarGroupRow(
                                        title: archived.name,
                                        systemImage: "archivebox",
                                        count: viewModel.entryCount(forProjectId: archived.id),
                                        isSelected: viewModel.selectedProjectId == archived.id,
                                        isCurrentContext: false,
                                        badgeText: nil
                                    ) {
                                        viewModel.selectedProjectId = archived.id
                                    }
                                    .contextMenu {
                                        projectContextMenu(for: archived)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func projectContextMenu(for project: Project) -> some View {
        if !project.isArchived {
            Button("设为快捷面板当前上下文") {
                viewModel.selectedProjectId = project.id
                viewModel.setCurrentProjectToSelected()
            }
            .disabled(project.id == viewModel.currentProjectId)
        }

        Button("打开参考窗口 (⌘⇧N)") {
            viewModel.selectedProjectId = project.id
            viewModel.openReferenceWindow()
        }

        Divider()

        Button("重命名…") {
            viewModel.selectedProjectId = project.id
            viewModel.startRenameSelectedProject()
        }

        if !project.isSystemProtected {
            if project.groupKind == .project {
                Button("转为「常用类型」") {
                    viewModel.setProjectGroupKind(project, kind: .category)
                }
                Button(project.isArchived ? "取消归档" : "归档项目") {
                    viewModel.toggleArchiveProject(project)
                }
            } else if project.groupKind == .category {
                Button("转为「项目」") {
                    viewModel.setProjectGroupKind(project, kind: .project)
                }
            }

            Divider()

            Button("删除…", role: .destructive) {
                viewModel.selectedProjectId = project.id
                viewModel.requestDeleteSelectedProject()
            }
        }
    }

    // MARK: - Column 2: Entries List

    private var entriesColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                searchBar
                quickJotBar
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            horizontalDivider

            if hasFilterChips {
                filterChipsRow
                horizontalDivider
            }

            countSortRow
            horizontalDivider

            entriesList
        }
    }

    private var quickJotBar: some View {
        let isJotEmpty = viewModel.quickCaptureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let canToggleInboxRouting: Bool = {
            guard viewModel.selectedProjectId != MainWindowViewModel.allProjectsSelection,
                  let selected = viewModel.selectedProject,
                  !selected.isArchived,
                  selected.id != viewModel.inboxProject?.id else {
                return false
            }
            return true
        }()

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.icon(.micro, weight: .semibold))
                    .foregroundStyle(Constants.VisualStyle.accent)

                ZStack(alignment: .leading) {
                    if viewModel.quickCaptureText.isEmpty {
                        Text("随手记便签，回车即存（支持 #标签，⇧↩ 存待办）…")
                            .font(.ui(.caption))
                            .foregroundStyle(Constants.VisualStyle.textTertiary)
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }

                    QuickJotInputField(
                        text: $viewModel.quickCaptureText,
                        onSubmitNote: {
                            _ = viewModel.submitQuickCapture(type: .note)
                        },
                        onSubmitTodo: {
                            _ = viewModel.submitQuickCapture(type: .todo)
                        }
                    )
                    .frame(height: 18)
                }
            }

            HStack(spacing: 6) {
                if canToggleInboxRouting {
                    Button {
                        viewModel.quickCapturePreferInbox.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Text("→ \(viewModel.quickCaptureDestinationName)")
                                .font(.ui(.micro, weight: .medium))
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.icon(.nano))
                        }
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Constants.VisualStyle.tintSubtle)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("点击切换速记落盘位置（当前分组 / 速记与待办）")
                } else {
                    Text("→ \(viewModel.quickCaptureDestinationName)")
                        .font(.ui(.micro, weight: .medium))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isJotEmpty {
                    Button {
                        _ = viewModel.quickJotFromClipboard(type: .note)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.icon(.micro, weight: .medium))
                            Text("剪贴板速记")
                                .font(.ui(.micro, weight: .medium))
                        }
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                        .padding(.horizontal, 6)
                        .frame(height: 19)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Constants.VisualStyle.tintSubtle)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("将系统剪贴板文本一键存为便签")
                } else {
                    Button {
                        _ = viewModel.submitQuickCapture(type: .todo)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "checklist")
                                .font(.icon(.micro, weight: .semibold))
                            Text("待办 ⇧↩")
                                .font(.ui(.micro, weight: .medium))
                        }
                        .foregroundStyle(Constants.VisualStyle.warn)
                        .padding(.horizontal, 6)
                        .frame(height: 19)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Constants.VisualStyle.warnDim)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("存为待办事项 (⇧Enter)")

                    Button {
                        _ = viewModel.submitQuickCapture(type: .note)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "note.text")
                                .font(.icon(.micro, weight: .semibold))
                            Text("存便签 ↩")
                                .font(.ui(.micro, weight: .semibold))
                        }
                        .foregroundStyle(Constants.VisualStyle.accent)
                        .padding(.horizontal, 6)
                        .frame(height: 19)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Constants.VisualStyle.accentDim)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("存为便签记录 (Enter)")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Constants.VisualStyle.inputFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isJotEmpty ? Constants.VisualStyle.border : Constants.VisualStyle.accentBorder,
                    lineWidth: Constants.Layout.hairline
                )
        )
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.icon(.small))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
            TextField("搜索标题、内容或 #标签", text: $viewModel.entrySearchText)
                .textFieldStyle(.plain)
                .font(.ui(.body))
                .foregroundStyle(Constants.VisualStyle.text)
                .focused($isEntrySearchFocused)
            if viewModel.entrySearchText.isEmpty {
                KbdLabel(text: "⌘F")
            } else {
                Button {
                    viewModel.entrySearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.icon(.small))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Constants.VisualStyle.inputFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
        )
        .onChange(of: viewModel.searchFocusToken) { _, _ in
            isEntrySearchFocused = true
        }
    }

    private var hasFilterChips: Bool {
        viewModel.availableEntryKinds.isEmpty == false || viewModel.topTags.isEmpty == false
    }

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                FilterChip(
                    label: "全部",
                    count: viewModel.entries.count,
                    isActive: viewModel.entryKindFilter == nil && viewModel.entryTagFilter == nil
                ) {
                    viewModel.clearEntryFilters()
                }
                if viewModel.availableEntryKinds.isEmpty == false {
                    Rectangle()
                        .fill(Constants.VisualStyle.divider)
                        .frame(width: Constants.Layout.hairline, height: 12)
                        .padding(.horizontal, 2)
                    ForEach(viewModel.availableEntryKinds, id: \.rawValue) { kind in
                        FilterChip(
                            label: kind.displayName,
                            systemImage: kind.symbolName,
                            count: viewModel.entryCount(forKind: kind),
                            isActive: viewModel.entryKindFilter == kind.rawValue
                        ) {
                            viewModel.toggleEntryKindFilter(kind)
                        }
                    }
                }
                if viewModel.topTags.isEmpty == false {
                    Rectangle()
                        .fill(Constants.VisualStyle.divider)
                        .frame(width: Constants.Layout.hairline, height: 12)
                        .padding(.horizontal, 2)
                    ForEach(viewModel.topTags) { facet in
                        FilterChip(
                            label: "#\(facet.tag)",
                            count: facet.count,
                            isActive: viewModel.entryTagFilter == facet.tag
                        ) {
                            viewModel.toggleEntryTagFilter(facet.tag)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private var showsCompletedControls: Bool {
        viewModel.completedEntryCount > 0 || viewModel.selectedProjectId == viewModel.inboxProject?.id
    }

    private var countSortRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("\(viewModel.displayedEntries.count) 条")
                    .font(.ui(.caption, weight: .medium, mono: true))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.icon(.micro, weight: .medium))
                    Text(viewModel.entrySortMode.title)
                        .font(.ui(.caption, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.icon(.micro))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                }
                .foregroundStyle(Constants.VisualStyle.textSecondary)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Constants.VisualStyle.tintSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                )
                .overlay {
                    Menu {
                        ForEach(MainWindowViewModel.EntrySortMode.allCases) { mode in
                            Button(mode.title) {
                                viewModel.entrySortMode = mode
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

                HStack(spacing: 4) {
                    Button {
                        viewModel.startCreateEntry()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.icon(.micro, weight: .bold))
                            Text("新建")
                                .font(.ui(.caption, weight: .medium))
                        }
                        .foregroundStyle(Constants.VisualStyle.accent)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Constants.VisualStyle.accentDim)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Constants.VisualStyle.accent.opacity(0.32), lineWidth: Constants.Layout.hairline)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("新建词条 (⌘N)")

                    Image(systemName: "doc.on.clipboard")
                        .font(.icon(.micro, weight: .medium))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                        .frame(width: 24, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Constants.VisualStyle.tintSubtle)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                        )
                        .overlay {
                            Menu {
                                Button {
                                    viewModel.startCreateEntry()
                                } label: {
                                    Label("新建词条 (⌘N)", systemImage: "square.and.pencil")
                                }

                                let targetId = viewModel.selectedProjectId == MainWindowViewModel.allProjectsSelection
                                    ? viewModel.currentProjectId
                                    : viewModel.selectedProjectId

                                Button {
                                    viewModel.createQuickEntryFromClipboard(intoProjectId: targetId, type: .prompt)
                                } label: {
                                    Label("从剪贴板直接存为提示词", systemImage: "doc.on.clipboard")
                                }

                                if let inbox = viewModel.inboxProject {
                                    Divider()
                                    Button {
                                        viewModel.createQuickEntryFromClipboard(intoProjectId: inbox.id, type: .todo)
                                    } label: {
                                        Label("从剪贴板存为待办事项", systemImage: "checklist")
                                    }
                                    Button {
                                        viewModel.createQuickEntryFromClipboard(intoProjectId: inbox.id, type: .note)
                                    } label: {
                                        Label("从剪贴板存为临时记录", systemImage: "note.text")
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
                        .help("从系统剪贴板快速新建词条或待办")
                }
            }

            if showsCompletedControls {
                HStack(spacing: 6) {
                    Button {
                        viewModel.hideCompletedEntries.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.hideCompletedEntries ? "eye.slash.fill" : "eye")
                                .font(.icon(.micro, weight: .medium))
                            Text("隐藏已完成 (\(viewModel.completedEntryCount))")
                                .font(.ui(.micro, weight: .medium))
                        }
                        .foregroundStyle(
                            viewModel.hideCompletedEntries
                                ? Constants.VisualStyle.accent
                                : Constants.VisualStyle.textSecondary
                        )
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(
                                    viewModel.hideCompletedEntries
                                        ? Constants.VisualStyle.accentDim
                                        : Constants.VisualStyle.tintSubtle
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(
                                    viewModel.hideCompletedEntries
                                        ? Constants.VisualStyle.accentBorder
                                        : Constants.VisualStyle.border,
                                    lineWidth: Constants.Layout.hairline
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.hideCompletedEntries ? "点击重新显示已完成项" : "仅展示未完成的待办与记录")

                    Spacer(minLength: 4)

                    if viewModel.completedEntryCount > 0 {
                        Button {
                            _ = viewModel.clearCompletedEntriesInVisibleScope()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "sparkles")
                                    .font(.icon(.micro))
                                Text("清理已完成")
                                    .font(.ui(.micro, weight: .medium))
                            }
                            .foregroundStyle(Constants.VisualStyle.textTertiary)
                            .padding(.horizontal, 6)
                            .frame(height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Constants.VisualStyle.tintSubtle)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("清理当前范围内已勾选完成的记录")
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var entriesList: some View {
        let selectedEntryId = viewModel.selectedEntry?.id
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if viewModel.displayedEntries.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.displayedEntries) { entry in
                            EntryListRow(
                                entry: entry,
                                isSelected: entry.id == selectedEntryId,
                                projectName: viewModel.selectedProjectId == MainWindowViewModel.allProjectsSelection
                                    ? viewModel.projectName(forEntry: entry)
                                    : nil,
                                isInboxContext: entry.projectId == viewModel.inboxProject?.id,
                                onTap: {
                                    viewModel.selectedEntryId = entry.id
                                },
                                onToggleComplete: {
                                    viewModel.toggleEntryCompleted(entry)
                                },
                                onCopy: {
                                    viewModel.selectedEntryId = entry.id
                                    viewModel.copyEntryContent(entry)
                                },
                                onTogglePin: {
                                    viewModel.togglePin(entry)
                                }
                            )
                            .contextMenu {
                                Button("复制内容 (⇧⌘C)") {
                                    viewModel.selectedEntryId = entry.id
                                    viewModel.copyEntryContent(entry)
                                }
                                Button("编辑词条 (⌘E)") {
                                    viewModel.selectedEntryId = entry.id
                                    viewModel.startEditEntry(entry)
                                }
                                Button(entry.isCompleted ? "标记为未完成" : "标记为已完成") {
                                    viewModel.toggleEntryCompleted(entry)
                                }
                                Button(entry.isPinned ? "取消置顶" : "置顶") {
                                    viewModel.togglePin(entry)
                                }
                                Menu("移动到项目…") {
                                    ForEach(viewModel.projects.filter { $0.id != entry.projectId && !$0.isArchived }) { target in
                                        Button(target.name) {
                                            viewModel.updateEntryProject(entry, toProjectId: target.id)
                                        }
                                    }
                                }
                                Menu("克隆到…") {
                                    ForEach(viewModel.projects.filter { $0.id != entry.projectId && !$0.isArchived }) { target in
                                        Button(target.name) {
                                            viewModel.cloneEntry(entry, toProjectId: target.id)
                                        }
                                    }
                                }
                                Divider()
                                Button("删除词条", role: .destructive) {
                                    viewModel.requestDeleteEntry(entry)
                                }
                            }
                            .id(entry.id)

                            Rectangle()
                                .fill(Constants.VisualStyle.divider)
                                .frame(height: Constants.Layout.hairline)
                                .padding(.leading, 34)
                        }
                    }
                }
            }
            .onChange(of: viewModel.programmaticScrollRevision) { _, _ in
                guard let id = viewModel.selectedEntry?.id else { return }
                proxy.scrollTo(id, anchor: viewModel.programmaticScrollAnchor)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.icon(.large, weight: .light))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
            Text(viewModel.entrySearchText.isEmpty ? "当前分组暂无内容" : "无匹配内容")
                .font(.ui(.body))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(20)
    }
}

// MARK: - Sidebar Subviews

private struct SidebarSectionHeader: View {
    let title: String
    let onAdd: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.ui(.caption, weight: .semibold))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
            Spacer()
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.icon(.micro, weight: .bold))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Constants.VisualStyle.tintSubtle)
                        )
                }
                .buttonStyle(.plain)
                .help("新建\(title)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }
}

private struct SidebarGroupRow: View {
    let title: String
    let systemImage: String
    let count: Int
    let isSelected: Bool
    let isCurrentContext: Bool
    let badgeText: String?
    var onSetCurrentContext: (() -> Void)? = nil
    var onDropEntryIds: (([String]) -> Bool)? = nil
    let action: () -> Void

    private var isHoveredState = SwiftUI.State<Bool>(initialValue: false)
    private var isDropTargetedState = SwiftUI.State<Bool>(initialValue: false)

    private var isHovered: Bool {
        get { isHoveredState.wrappedValue }
        nonmutating set { isHoveredState.wrappedValue = newValue }
    }

    private var isDropTargeted: Bool {
        get { isDropTargetedState.wrappedValue }
        nonmutating set { isDropTargetedState.wrappedValue = newValue }
    }

    private var showsSetContextButton: Bool {
        isHovered && !isCurrentContext && onSetCurrentContext != nil
    }

    private var rowBackgroundFill: Color {
        if isDropTargeted {
            return Constants.VisualStyle.accentDim
        }
        if isSelected {
            return Constants.VisualStyle.accentDim
        }
        if isHovered {
            return Constants.VisualStyle.surfaceHover
        }
        return Color.clear
    }

    private var rowBorderColor: Color {
        if isDropTargeted {
            return Constants.VisualStyle.accent
        }
        if isSelected {
            return Constants.VisualStyle.accent.opacity(0.28)
        }
        return Color.clear
    }

    var body: some View {
        let baseRow = Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.icon(.base))
                    .foregroundStyle(isSelected ? Constants.VisualStyle.accent : Constants.VisualStyle.textSecondary)
                    .frame(width: 16)

                Text(title)
                    .font(.ui(.body, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Constants.VisualStyle.text)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isCurrentContext {
                    Text("当前")
                        .font(.ui(.micro, weight: .medium))
                        .foregroundStyle(Constants.VisualStyle.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Constants.VisualStyle.accentDim)
                        )
                } else if let badgeText {
                    Text(badgeText)
                        .font(.ui(.micro))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Constants.VisualStyle.tintSubtle)
                        )
                        .opacity(showsSetContextButton ? 0 : 1)
                }

                Text("\(count)")
                    .font(.ui(.caption, mono: true))
                    .foregroundStyle(isSelected ? Constants.VisualStyle.accent : Constants.VisualStyle.textTertiary)
                    .frame(minWidth: 18, alignment: .trailing)
                    .opacity(showsSetContextButton ? 0 : 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowBackgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(rowBorderColor, lineWidth: isDropTargeted ? 1 : Constants.Layout.hairline)
        )
        .overlay(alignment: .trailing) {
            if showsSetContextButton, let onSetCurrentContext {
                Button(action: onSetCurrentContext) {
                    Image(systemName: "scope")
                        .font(.icon(.micro, weight: .semibold))
                        .foregroundStyle(Constants.VisualStyle.accent)
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Constants.VisualStyle.accentDim)
                        )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .help("设为快捷面板当前分组")
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
            }
        }

        if let onDropEntryIds {
            baseRow.dropDestination(for: String.self) { items, _ in
                onDropEntryIds(items)
            } isTargeted: { targeted in
                if isDropTargeted != targeted {
                    isDropTargeted = targeted
                }
            }
        } else {
            baseRow
        }
    }
}

private struct QuickJotInputField: NSViewRepresentable {
    @Binding var text: String
    let onSubmitNote: () -> Void
    let onSubmitTodo: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: PPDesign.TextSize.body.rawValue)
        field.textColor = .labelColor
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.onSubmitNote = onSubmitNote
        context.coordinator.onSubmitTodo = onSubmitTodo
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmitNote: onSubmitNote, onSubmitTodo: onSubmitTodo)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onSubmitNote: () -> Void
        var onSubmitTodo: () -> Void

        init(text: Binding<String>, onSubmitNote: @escaping () -> Void, onSubmitTodo: @escaping () -> Void) {
            self._text = text
            self.onSubmitNote = onSubmitNote
            self.onSubmitTodo = onSubmitTodo
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if textView.hasMarkedText() {
                return false
            }
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                let isShift = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
                if isShift {
                    onSubmitTodo()
                } else {
                    onSubmitNote()
                }
                return true
            case #selector(NSResponder.insertLineBreak(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                onSubmitTodo()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                if !text.isEmpty {
                    text = ""
                    control.stringValue = ""
                } else {
                    control.window?.makeFirstResponder(nil)
                }
                return true
            default:
                return false
            }
        }
    }
}

// MARK: - Date Formatting Helpers (Explicit Time Display)

enum EntryDateFormat {
    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let fullDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func lastUsed(_ date: Date?) -> String {
        guard let date else {
            return "未使用"
        }
        return relative.localizedString(for: date, relativeTo: Date())
    }

    static func shortDay(_ date: Date) -> String {
        shortDate.string(from: date)
    }

    static func full(_ date: Date) -> String {
        fullDateTime.string(from: date)
    }
}

// MARK: - Native Entry List Row

private struct EntryListRow: View {
    let entry: Entry
    let isSelected: Bool
    let projectName: String?
    let isInboxContext: Bool
    let onTap: () -> Void
    let onToggleComplete: () -> Void
    let onCopy: () -> Void
    let onTogglePin: () -> Void

    private var isHoveredState = SwiftUI.State<Bool>(initialValue: false)

    private var isHovered: Bool {
        get { isHoveredState.wrappedValue }
        nonmutating set { isHoveredState.wrappedValue = newValue }
    }

    private var showsCheckbox: Bool {
        isInboxContext || entry.type == Constants.EntryType.todo.rawValue || entry.type == Constants.EntryType.note.rawValue
    }

    private var rowBackgroundColor: Color {
        if isSelected {
            return Constants.VisualStyle.accentDim
        }
        if isHovered {
            return Constants.VisualStyle.surfaceHover
        }
        return Color.clear
    }

    var body: some View {
        let type = Constants.EntryType.resolve(entry.type)
        let level = Constants.EntryLevel.resolve(useCount: entry.useCount)
        HStack(alignment: .top, spacing: 8) {
            if showsCheckbox {
                Button(action: onToggleComplete) {
                    Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.icon(.base))
                        .foregroundStyle(entry.isCompleted ? Constants.VisualStyle.accent : Constants.VisualStyle.textTertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .help(entry.isCompleted ? "标记为未完成" : "完成并划掉")
            } else {
                Image(systemName: type.symbolName)
                    .font(.icon(.base))
                    .foregroundStyle(type.accentColor)
                    .frame(width: 18, height: 18)
                    .padding(.top, 2)
            }

            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(entry.title)
                            .font(.ui(.title, weight: .medium))
                            .foregroundStyle(entry.isCompleted ? Constants.VisualStyle.textTertiary : Constants.VisualStyle.text)
                            .strikethrough(entry.isCompleted)
                            .lineLimit(1)

                        if entry.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.icon(.micro))
                                .foregroundStyle(Constants.VisualStyle.warn)
                        }

                        Spacer(minLength: 4)

                        HStack(spacing: 6) {
                            if entry.useCount > 0 {
                                Text("\(entry.useCount)次")
                                    .font(.ui(.micro, weight: .medium, mono: true))
                                    .foregroundStyle(level.color)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(level.fillColor)
                                    )
                                    .fixedSize()
                            }

                            Text(type.displayName)
                                .font(.ui(.micro))
                                .foregroundStyle(Constants.VisualStyle.textSecondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(Constants.VisualStyle.tintSubtle)
                                )
                                .fixedSize()
                        }
                        .frame(minWidth: 44, alignment: .trailing)
                        .opacity(isHovered ? 0 : 1)
                    }

                    Text(entry.previewLine)
                        .font(.ui(.body))
                        .foregroundStyle(entry.isCompleted ? Constants.VisualStyle.textTertiary : Constants.VisualStyle.textSecondary)
                        .strikethrough(entry.isCompleted)
                        .lineLimit(1)

                    // Explicit Time & Usage Row
                    HStack(spacing: 4) {
                        Text(entry.lastUsedAt != nil ? EntryDateFormat.lastUsed(entry.lastUsedAt) : "未使用")
                            .fixedSize()

                        Text("·")
                            .fixedSize()

                        if let projectName {
                            Text(projectName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            Text(EntryDateFormat.shortDay(entry.createdAt))
                                .monospacedDigit()
                                .fixedSize()
                        }

                        Spacer(minLength: 4)

                        if !entry.tags.isEmpty {
                            TagChipsInline(tags: entry.tags, max: 2)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .lineLimit(1)
                    .font(.ui(.micro))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackgroundColor)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(Constants.VisualStyle.accent)
                    .frame(width: 2.5)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isHovered {
                HStack(spacing: 4) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.icon(.micro, weight: .semibold))
                            .foregroundStyle(Constants.VisualStyle.textSecondary)
                            .frame(width: 20, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Constants.VisualStyle.surfaceRaised)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("复制内容")

                    Button(action: onTogglePin) {
                        Image(systemName: entry.isPinned ? "pin.slash" : "pin")
                            .font(.icon(.micro, weight: .semibold))
                            .foregroundStyle(entry.isPinned ? Constants.VisualStyle.warn : Constants.VisualStyle.textSecondary)
                            .frame(width: 20, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(entry.isPinned ? Constants.VisualStyle.warnDim : Constants.VisualStyle.surfaceRaised)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(
                                        entry.isPinned ? Constants.VisualStyle.warn.opacity(0.35) : Constants.VisualStyle.border,
                                        lineWidth: Constants.Layout.hairline
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(entry.isPinned ? "取消置顶" : "置顶")
                }
                .padding(.top, 7)
                .padding(.trailing, 10)
            }
        }
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Column 3: Native Detail, Explicit Time Bar, Direct Inline Editor & Version History

private struct PreviewPane: View {
    @ObservedObject var viewModel: MainWindowViewModel
    @ObservedObject var inlineSession: InlineEditorSession

    var body: some View {
        if let entry = viewModel.selectedEntry {
            detailContent(for: entry)
                .onAppear {
                    viewModel.syncInlineDraft(with: entry)
                }
                .onChange(of: entry) { _, newValue in
                    let isSameEntry = inlineSession.entryId == newValue.id
                    let shouldForceSync = !isSameEntry || !viewModel.hasUnsavedInlineChanges(for: newValue)
                    viewModel.syncInlineDraft(
                        with: newValue,
                        force: shouldForceSync,
                        preserveSavedState: isSameEntry
                    )
                }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.icon(.hero, weight: .light))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
            Text("选择一条内容查看或编辑")
                .font(.ui(.title))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detailContent(for entry: Entry) -> some View {
        let isDirty = viewModel.hasUnsavedInlineChanges(for: entry)
        let latestVersionNumber = viewModel.selectedEntryVersions.first?.versionNumber ?? 1
        let currentKind = Constants.EntryType.resolve(inlineSession.type)

        return VStack(alignment: .leading, spacing: 0) {
            // Top Native Action & Metadata Toolbar
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    // Group / Category Pill Menu
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.icon(.micro, weight: .semibold))
                            .foregroundStyle(Constants.VisualStyle.accent)
                        Text(viewModel.projectName(for: inlineSession.projectId))
                            .font(.ui(.caption, weight: .medium))
                            .foregroundStyle(Constants.VisualStyle.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .font(.icon(.micro))
                            .foregroundStyle(Constants.VisualStyle.textTertiary)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .fixedSize()
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Constants.VisualStyle.surfaceRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                    )
                    .overlay {
                        Menu {
                            ForEach(viewModel.projects.filter { !$0.isArchived || $0.id == inlineSession.projectId }) { project in
                                Button {
                                    viewModel.updateEntryProject(entry, toProjectId: project.id)
                                } label: {
                                    Label(project.name, systemImage: project.effectiveIconName)
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
                    .help("归属分组")

                    // Entry Type Pill Menu
                    HStack(spacing: 4) {
                        Image(systemName: currentKind.symbolName)
                            .font(.icon(.micro, weight: .semibold))
                            .foregroundStyle(currentKind.accentColor)
                        Text(currentKind.displayName)
                            .font(.ui(.caption, weight: .medium))
                            .foregroundStyle(Constants.VisualStyle.text)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.icon(.micro))
                            .foregroundStyle(Constants.VisualStyle.textTertiary)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .fixedSize()
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Constants.VisualStyle.surfaceRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                    )
                    .overlay {
                        Menu {
                            ForEach(Constants.EntryType.allCases, id: \.rawValue) { kind in
                                Button {
                                    viewModel.updateEntryType(entry, toType: kind.rawValue)
                                } label: {
                                    Label(kind.displayName, systemImage: kind.symbolName)
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
                    .help("词条类型")

                    // Completed Pill Toggle
                    Button {
                        viewModel.toggleEntryCompleted(entry)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: inlineSession.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.icon(.micro, weight: .semibold))
                                .foregroundStyle(inlineSession.isCompleted ? Constants.VisualStyle.success : Constants.VisualStyle.textTertiary)
                            Text("完成")
                                .font(.ui(.caption, weight: .medium))
                                .foregroundStyle(inlineSession.isCompleted ? Constants.VisualStyle.text : Constants.VisualStyle.textSecondary)
                        }
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(inlineSession.isCompleted ? Constants.VisualStyle.successDim : Constants.VisualStyle.surfaceRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    inlineSession.isCompleted ? Constants.VisualStyle.success.opacity(0.35) : Constants.VisualStyle.border,
                                    lineWidth: Constants.Layout.hairline
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("标记为已完成")

                    // Pin Pill Toggle
                    Button {
                        viewModel.togglePin(entry)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: inlineSession.isPinned ? "pin.fill" : "pin")
                                .font(.icon(.micro, weight: .semibold))
                                .foregroundStyle(inlineSession.isPinned ? Constants.VisualStyle.warn : Constants.VisualStyle.textTertiary)
                            Text("置顶")
                                .font(.ui(.caption, weight: .medium))
                                .foregroundStyle(inlineSession.isPinned ? Constants.VisualStyle.text : Constants.VisualStyle.textSecondary)
                        }
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(inlineSession.isPinned ? Constants.VisualStyle.warnDim : Constants.VisualStyle.surfaceRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    inlineSession.isPinned ? Constants.VisualStyle.warn.opacity(0.35) : Constants.VisualStyle.border,
                                    lineWidth: Constants.Layout.hairline
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("置顶此词条")

                    Spacer(minLength: 2)

                    // Version History Popover Button
                    SettingsPillButton("v\(latestVersionNumber)", systemImage: "clock.arrow.circlepath") {
                        viewModel.isShowingVersionPopover.toggle()
                    }
                    .fixedSize()
                    .help("版本历史（共 \(max(viewModel.selectedEntryVersions.count, 1)) 个版本）")
                    .popover(isPresented: $viewModel.isShowingVersionPopover, arrowEdge: .bottom) {
                        VersionHistoryPopover(
                            versions: viewModel.selectedEntryVersions,
                            currentContent: entry.content,
                            onCopyVersion: { version in
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(version.content, forType: .string)
                                viewModel.bannerMessage = "已复制 v\(version.versionNumber) 内容"
                            },
                            onRestoreVersion: { version in
                                viewModel.restoreEntryVersion(version)
                                viewModel.isShowingVersionPopover = false
                            }
                        )
                    }

                    // Clone to another project menu
                    HStack(spacing: 4) {
                        Image(systemName: "plus.square.on.square")
                            .font(.icon(.micro, weight: .semibold))
                            .foregroundStyle(Constants.VisualStyle.textSecondary)
                        Text("克隆")
                            .font(.ui(.caption, weight: .medium))
                            .foregroundStyle(Constants.VisualStyle.text)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .fixedSize()
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Constants.VisualStyle.surfaceRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                    )
                    .overlay {
                        Menu {
                            Section("项目") {
                                ForEach(viewModel.activeProjects.filter { $0.id != entry.projectId }) { target in
                                    Button(target.name) {
                                        viewModel.cloneEntry(entry, toProjectId: target.id)
                                    }
                                }
                            }
                            Section("常用类型") {
                                ForEach(viewModel.categoryProjects.filter { $0.id != entry.projectId }) { target in
                                    Button(target.name) {
                                        viewModel.cloneEntry(entry, toProjectId: target.id)
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
                    .help("克隆到其他分组")

                    Button {
                        viewModel.copyEntryContent(entry)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.icon(.micro, weight: .semibold))
                            Text("复制")
                                .font(.ui(.caption, weight: .semibold))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Constants.VisualStyle.accent)
                        )
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("复制词条内容 (⇧⌘C)")

                    Button {
                        viewModel.requestDeleteEntry(entry)
                    } label: {
                        Image(systemName: "trash")
                            .font(.icon(.micro, weight: .semibold))
                            .foregroundStyle(Constants.VisualStyle.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Constants.VisualStyle.surfaceRaised)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                            )
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("删除此词条")
                }

                // Inline Metadata Line + Calm Auto-Save Status
                HStack(spacing: 6) {
                    Text("创建 \(EntryDateFormat.shortDay(entry.createdAt))")
                    Text("·")
                    Text("修改 \(EntryDateFormat.shortDay(entry.updatedAt))")
                    Text("·")
                    Text(
                        entry.lastUsedAt != nil
                            ? "使用 \(EntryDateFormat.lastUsed(entry.lastUsedAt)) (\(entry.useCount)次)"
                            : "未使用"
                    )
                    if let sourceId = entry.sourceEntryId, !sourceId.isEmpty {
                        Text("·")
                        Text("来自常用类型")
                    }
                    Spacer(minLength: 6)

                    autoSaveStatusView(for: entry, isDirty: isDirty)
                }
                .font(.ui(.caption, mono: true))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Constants.VisualStyle.surface)

            Rectangle()
                .fill(Constants.VisualStyle.divider)
                .frame(height: Constants.Layout.hairline)

            // Inline Editable Title & Tags
            VStack(alignment: .leading, spacing: 8) {
                TextField("输入标题（留空自动取首行）…", text: $inlineSession.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Constants.VisualStyle.text)

                HStack(spacing: 6) {
                    Image(systemName: "tag")
                        .font(.icon(.small))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                    TextField("标签（逗号分隔，单标签不超过 10 字）", text: $inlineSession.tagsText)
                        .textFieldStyle(.plain)
                        .font(.ui(.caption))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                    Spacer()
                    Text("\(inlineSession.content.count) 字")
                        .font(.ui(.caption, mono: true))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Constants.VisualStyle.surfaceRaised)

            Rectangle()
                .fill(Constants.VisualStyle.divider)
                .frame(height: Constants.Layout.hairline)

            // Inline Editable Content Area
            TextEditor(text: $inlineSession.content)
                .font(.system(size: 13.5))
                .foregroundStyle(Constants.VisualStyle.text)
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Constants.VisualStyle.surfaceRaised)
                .background(
                    Button("") {
                        _ = viewModel.commitInlineChanges(for: entry)
                    }
                    .keyboardShortcut("s", modifiers: [.command])
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                )
        }
    }

    @ViewBuilder
    private func autoSaveStatusView(for entry: Entry, isDirty: Bool) -> some View {
        switch inlineSession.saveState {
        case .saving:
            HStack(spacing: 4) {
                Circle()
                    .fill(Constants.VisualStyle.accent)
                    .frame(width: 5, height: 5)
                Text("正在保存…")
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
            }
        case .pending:
            Button {
                _ = viewModel.commitInlineChanges(for: entry)
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Constants.VisualStyle.accent)
                        .frame(width: 5, height: 5)
                    Text("正在保存…")
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .help("正在自动保存，点击或按 ⌘S 立即保存")
        case .invalid:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle")
                    .font(.icon(.micro))
                Text("内容不能为空")
            }
            .foregroundStyle(Constants.VisualStyle.warn)
        case .saved:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .font(.icon(.micro))
                Text("已自动保存")
            }
            .foregroundStyle(Constants.VisualStyle.textTertiary)
        case .idle:
            if isDirty {
                Button {
                    _ = viewModel.commitInlineChanges(for: entry)
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Constants.VisualStyle.accent)
                            .frame(width: 5, height: 5)
                        Text("正在保存…")
                            .foregroundStyle(Constants.VisualStyle.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .help("按 ⌘S 立即保存")
            }
        }
    }
}

// MARK: - Version History Popover

private struct VersionHistoryPopover: View {
    let versions: [EntryVersion]
    let currentContent: String
    let onCopyVersion: (EntryVersion) -> Void
    let onRestoreVersion: (EntryVersion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("版本历史", systemImage: "clock.arrow.circlepath")
                    .font(.ui(.title, weight: .semibold))
                    .foregroundStyle(Constants.VisualStyle.text)
                Spacer()
                Text("\(versions.count) 个版本")
                    .font(.ui(.caption, mono: true))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
            }
            .padding(12)

            Rectangle()
                .fill(Constants.VisualStyle.divider)
                .frame(height: Constants.Layout.hairline)

            if versions.isEmpty {
                Text("暂无历史版本")
                    .font(.ui(.body))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(versions) { version in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("v\(version.versionNumber)")
                                        .font(.ui(.body, weight: .bold, mono: true))
                                        .foregroundStyle(Constants.VisualStyle.accent)
                                    Text(EntryDateFormat.full(version.createdAt))
                                        .font(.ui(.caption, mono: true))
                                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                                    if let note = version.changeNote, !note.isEmpty {
                                        Text("· \(note)")
                                            .font(.ui(.caption))
                                            .foregroundStyle(Constants.VisualStyle.textSecondary)
                                    }
                                    Spacer()
                                    Text("\(version.content.count) 字")
                                        .font(.ui(.micro, mono: true))
                                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                                }

                                Text(version.title)
                                    .font(.ui(.body, weight: .medium))
                                    .foregroundStyle(Constants.VisualStyle.text)
                                    .lineLimit(1)

                                Text(version.content)
                                    .font(.ui(.caption))
                                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(Constants.VisualStyle.inputFill)
                                    )

                                HStack {
                                    Spacer()
                                    SettingsPillButton("复制") {
                                        onCopyVersion(version)
                                    }

                                    if version.content != currentContent {
                                        SettingsPillButton("恢复此版本", tone: .primary) {
                                            onRestoreVersion(version)
                                        }
                                    } else {
                                        Text("当前版本")
                                            .font(.ui(.micro))
                                            .foregroundStyle(Constants.VisualStyle.textTertiary)
                                    }
                                }
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Constants.VisualStyle.surfaceRaised)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
                            )
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(width: 420, height: 380)
        .background(Constants.VisualStyle.surface)
    }
}

struct TagChipsInline: View {
    let tags: [String]
    let max: Int

    var body: some View {
        let visible = Array(tags.prefix(max))
        let overflow = tags.count - visible.count
        HStack(spacing: 3) {
            ForEach(visible, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.ui(.micro, weight: .medium))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Constants.VisualStyle.tintSubtle)
                    )
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.ui(.micro, mono: true))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct MetaInline: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.ui(.caption))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
            Text(value)
                .font(.ui(.body, weight: .medium))
                .foregroundStyle(Constants.VisualStyle.text)
                .lineLimit(1)
        }
    }
}
