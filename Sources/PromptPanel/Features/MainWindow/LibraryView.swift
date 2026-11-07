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

            PreviewPane(viewModel: viewModel)
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
                            badgeText: nil
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
                            badgeText: nil
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
                                badgeText: nil
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
            searchBar
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

    private var countSortRow: some View {
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
            .onChange(of: viewModel.selectedEntry?.id) { _, id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: .center)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
                }

                Text("\(count)")
                    .font(.ui(.caption, mono: true))
                    .foregroundStyle(isSelected ? Constants.VisualStyle.accent : Constants.VisualStyle.textTertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Constants.VisualStyle.accentDim : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isSelected ? Constants.VisualStyle.accent.opacity(0.28) : Color.clear,
                        lineWidth: Constants.Layout.hairline
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
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

    private var showsCheckbox: Bool {
        isInboxContext || entry.type == Constants.EntryType.todo.rawValue || entry.type == Constants.EntryType.note.rawValue
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
        .background(isSelected ? Constants.VisualStyle.accentDim : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(Constants.VisualStyle.accent)
                    .frame(width: 2.5)
            }
        }
    }
}

// MARK: - Column 3: Native Detail, Explicit Time Bar, Direct Inline Editor & Version History

private struct PreviewPane: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        if let entry = viewModel.selectedEntry {
            detailContent(for: entry)
                .onAppear {
                    viewModel.syncInlineDraft(with: entry)
                }
                .onChange(of: entry) { _, newValue in
                    let shouldForceSync = viewModel.inlineDraftEntryId != newValue.id
                        || !viewModel.hasUnsavedInlineChanges(for: newValue)
                    viewModel.syncInlineDraft(with: newValue, force: shouldForceSync)
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
        let currentKind = Constants.EntryType.resolve(viewModel.inlineDraftType)

        return VStack(alignment: .leading, spacing: 0) {
            // Top Native Action & Metadata Toolbar
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    // Group / Category Pill Menu
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.icon(.micro, weight: .semibold))
                            .foregroundStyle(Constants.VisualStyle.accent)
                        Text(viewModel.projectName(for: viewModel.inlineDraftProjectId))
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
                            ForEach(viewModel.projects.filter { !$0.isArchived || $0.id == viewModel.inlineDraftProjectId }) { project in
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
                            Image(systemName: viewModel.inlineDraftIsCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.icon(.micro, weight: .semibold))
                                .foregroundStyle(viewModel.inlineDraftIsCompleted ? Constants.VisualStyle.success : Constants.VisualStyle.textTertiary)
                            Text("完成")
                                .font(.ui(.caption, weight: .medium))
                                .foregroundStyle(viewModel.inlineDraftIsCompleted ? Constants.VisualStyle.text : Constants.VisualStyle.textSecondary)
                        }
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(viewModel.inlineDraftIsCompleted ? Constants.VisualStyle.successDim : Constants.VisualStyle.surfaceRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    viewModel.inlineDraftIsCompleted ? Constants.VisualStyle.success.opacity(0.35) : Constants.VisualStyle.border,
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
                            Image(systemName: viewModel.inlineDraftIsPinned ? "pin.fill" : "pin")
                                .font(.icon(.micro, weight: .semibold))
                                .foregroundStyle(viewModel.inlineDraftIsPinned ? Constants.VisualStyle.warn : Constants.VisualStyle.textTertiary)
                            Text("置顶")
                                .font(.ui(.caption, weight: .medium))
                                .foregroundStyle(viewModel.inlineDraftIsPinned ? Constants.VisualStyle.text : Constants.VisualStyle.textSecondary)
                        }
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(viewModel.inlineDraftIsPinned ? Constants.VisualStyle.warnDim : Constants.VisualStyle.surfaceRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    viewModel.inlineDraftIsPinned ? Constants.VisualStyle.warn.opacity(0.35) : Constants.VisualStyle.border,
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

                // Inline Metadata Line
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
                    Spacer(minLength: 0)
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
                TextField("输入标题…", text: $viewModel.inlineDraftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Constants.VisualStyle.text)

                HStack(spacing: 6) {
                    Image(systemName: "tag")
                        .font(.icon(.small))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                    TextField("标签（逗号分隔，单标签不超过 10 字）", text: $viewModel.inlineDraftTagsText)
                        .textFieldStyle(.plain)
                        .font(.ui(.caption))
                        .foregroundStyle(Constants.VisualStyle.textSecondary)
                    Spacer()
                    Text("\(viewModel.inlineDraftContent.count) 字")
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
            TextEditor(text: $viewModel.inlineDraftContent)
                .font(.system(size: 13.5))
                .foregroundStyle(Constants.VisualStyle.text)
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Constants.VisualStyle.surfaceRaised)

            // Save Bar when inline edits are present
            if isDirty {
                let willRecordNewVersion = viewModel.hasUnsavedInlineContentChanges(for: entry)
                Rectangle()
                    .fill(Constants.VisualStyle.divider)
                    .frame(height: Constants.Layout.hairline)
                HStack(spacing: 10) {
                    Circle()
                        .fill(Constants.VisualStyle.accent)
                        .frame(width: 6, height: 6)
                    Text(
                        willRecordNewVersion
                            ? "未保存修改 · 保存后生成 v\(latestVersionNumber + 1)"
                            : "未保存修改"
                    )
                    .font(.ui(.caption, weight: .medium))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                    Spacer()
                    SettingsPillButton("放弃") {
                        viewModel.syncInlineDraft(with: entry, force: true)
                    }

                    Button {
                        _ = viewModel.commitInlineChanges(for: entry)
                    } label: {
                        Text("保存 (⌘S)")
                            .font(.ui(.caption, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Constants.VisualStyle.accent)
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("s", modifiers: [.command])
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Constants.VisualStyle.surface)
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
