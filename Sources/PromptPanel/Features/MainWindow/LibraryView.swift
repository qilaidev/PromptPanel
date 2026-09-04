import SwiftUI

struct LibraryView: View {
    @ObservedObject var viewModel: MainWindowViewModel
    @FocusState private var isEntrySearchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            projectsColumn
                .frame(width: 200)
                .background(Constants.VisualStyle.surfaceRaised)

            verticalDivider

            entriesColumn
                .frame(width: 360)
                .background(Constants.VisualStyle.surface)

            verticalDivider

            PreviewPane(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Constants.VisualStyle.surface)
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

    // MARK: Projects column

    private var projectsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Design.Space.sm) {
                SectionHeading(text: "项目")
                Spacer(minLength: 0)
                Button {
                    viewModel.startCreateProject()
                } label: {
                    Image(systemName: "plus")
                        .font(.icon(.small, weight: .semibold))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                        .frame(width: 22, height: 22)
                        .roundedHitTarget(cornerRadius: 5)
                }
                .buttonStyle(.plain)
                .help("新建项目")
            }
            .padding(.horizontal, Design.Space.lg)
            .padding(.top, Design.Space.lg)
            .padding(.bottom, Design.Space.sm)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ProjectRow(
                        title: "全部项目",
                        systemImage: "tray.full",
                        count: viewModel.totalEntryCount,
                        isActive: viewModel.selectedProjectId == MainWindowViewModel.allProjectsSelection,
                        isCurrent: false
                    ) {
                        viewModel.selectedProjectId = MainWindowViewModel.allProjectsSelection
                    }
                    .contextMenu {
                        Button("新建项目") { viewModel.startCreateProject() }
                    }

                    ForEach(viewModel.projectOptions) { project in
                        ProjectRow(
                            title: project.name,
                            systemImage: nil,
                            count: viewModel.entryCount(forProjectId: project.id),
                            isActive: viewModel.selectedProjectId == project.id,
                            isCurrent: project.id == viewModel.currentProjectId
                        ) {
                            viewModel.selectedProjectId = project.id
                        }
                        .contextMenu {
                            Button("设为当前执行项目") {
                                viewModel.selectedProjectId = project.id
                                viewModel.setCurrentProjectToSelected()
                            }
                            .disabled(project.id == viewModel.currentProjectId)
                            Button("重命名") {
                                viewModel.selectedProjectId = project.id
                                viewModel.startRenameSelectedProject()
                            }
                            Divider()
                            Button("删除", role: .destructive) {
                                viewModel.selectedProjectId = project.id
                                viewModel.requestDeleteSelectedProject()
                            }
                            .disabled(project.isDefault)
                        }
                    }
                }
                .padding(.horizontal, Design.Space.sm)
            }
            .scrollIndicators(.hidden)

            horizontalDivider

            VStack(alignment: .leading, spacing: Design.Space.sm) {
                Button {
                    viewModel.setCurrentProjectToSelected()
                } label: {
                    HStack(spacing: Design.Space.sm) {
                        Image(systemName: "scope")
                            .font(.icon(.small))
                        Text(canMarkAsCurrent ? "设为当前项目" : selectedProjectFootnoteTitle)
                            .font(.ui(.body, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(canMarkAsCurrent ? Constants.VisualStyle.textSecondary : Constants.VisualStyle.textQuaternary)
                    .padding(.horizontal, 8)
                    .frame(height: Constants.Layout.regularControlHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Constants.VisualStyle.tintSubtle)
                    )
                    .roundedHitTarget(cornerRadius: 6)
                }
                .buttonStyle(.plain)
                .disabled(!canMarkAsCurrent)

                Text(selectedProjectFootnote)
                    .font(.ui(.caption))
                    .foregroundStyle(Constants.VisualStyle.textQuaternary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Design.Space.lg)
            .padding(.vertical, Design.Space.md)
        }
    }

    private var canMarkAsCurrent: Bool {
        guard let selected = viewModel.selectedProject else {
            return false
        }
        return selected.id != viewModel.currentProjectId
            && viewModel.selectedProjectId != MainWindowViewModel.allProjectsSelection
    }

    private var selectedProjectFootnoteTitle: String {
        if viewModel.selectedProjectId == MainWindowViewModel.allProjectsSelection {
            return "请选择具体项目"
        }
        return "已是当前项目"
    }

    private var selectedProjectFootnote: String {
        if viewModel.selectedProjectId == MainWindowViewModel.allProjectsSelection {
            return "右键具体项目可重命名或删除。"
        }
        return "重命名和删除继续放在项目右键菜单里。"
    }

    // MARK: Entries column

    private var entriesColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
                .padding(.horizontal, Design.Space.lg)
                .padding(.vertical, Design.Space.md)

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
        HStack(spacing: Design.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.icon(.small))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
            TextField("搜索标题或内容", text: $viewModel.entrySearchText)
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
                        .frame(width: 22, height: 22)
                        .roundedHitTarget(cornerRadius: 5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Design.Space.md)
        .frame(height: Constants.Layout.regularControlHeight)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Constants.VisualStyle.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
        )
        .roundedHitTarget(cornerRadius: 7)
        .onTapGesture {
            isEntrySearchFocused = true
        }
        .onChange(of: viewModel.searchFocusToken) { _, _ in
            isEntrySearchFocused = true
        }
    }

    private var hasFilterChips: Bool {
        viewModel.availableEntryKinds.isEmpty == false || viewModel.topTags.isEmpty == false
    }

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Space.xxs) {
                FilterChip(
                    label: "全部",
                    count: viewModel.entries.count,
                    isActive: viewModel.entryKindFilter == nil && viewModel.entryTagFilter == nil
                ) {
                    viewModel.clearEntryFilters()
                }
                if viewModel.availableEntryKinds.isEmpty == false {
                    chipDivider
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
                    chipDivider
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
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, 3)
        }
    }

    private var chipDivider: some View {
        Rectangle()
            .fill(Constants.VisualStyle.divider)
            .frame(width: Constants.Layout.hairline, height: 12)
            .padding(.horizontal, Design.Space.xs)
    }

    private var countSortRow: some View {
        HStack(spacing: 0) {
            Text("\(viewModel.displayedEntries.count) 条")
                .font(.ui(.caption, weight: .medium, mono: true))
                .tracking(0.8)
                .foregroundStyle(Constants.VisualStyle.textQuaternary)

            Spacer(minLength: 0)

            Menu {
                ForEach(MainWindowViewModel.EntrySortMode.allCases) { mode in
                    Button(mode.title) {
                        viewModel.entrySortMode = mode
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(viewModel.entrySortMode.title)
                        .font(.ui(.caption))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                    Image(systemName: "chevron.down")
                        .font(.icon(.micro, weight: .semibold))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button {
                viewModel.startCreateEntry()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.icon(.small))
                    Text("新建")
                        .font(.ui(.caption, weight: .medium))
                }
                .foregroundStyle(Constants.VisualStyle.textSecondary)
                .padding(.horizontal, 8)
                .frame(height: Constants.Layout.compactControlHeight)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Constants.VisualStyle.tintSubtle)
                )
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.xs)
    }

    private var entriesList: some View {
        // Resolved once per pass, not once per row: `selectedEntry` scans
        // `displayedEntries`, so reading it inside the `ForEach` made selection
        // rendering O(n²) in the number of visible entries.
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
                                projectName: projectName(for: entry)
                            ) {
                                viewModel.selectedEntryId = entry.id
                            }
                            .id(entry.id)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: viewModel.selectedEntry?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Design.Space.sm) {
            Image(systemName: "tray")
                .font(.icon(.large, weight: .light))
                .foregroundStyle(Constants.VisualStyle.textQuaternary)
            Text(emptyStateTitle)
                .font(.ui(.body))
                .foregroundStyle(Constants.VisualStyle.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(.vertical, 20)
    }

    private var emptyStateTitle: String {
        if viewModel.entrySearchText.isEmpty {
            return "当前还没有词条\n点击右上 + 开始添加"
        }
        return "没有匹配的词条\n换个关键词试试"
    }

    private func projectName(for entry: Entry) -> String? {
        viewModel.projectName(forEntry: entry)
    }
}

private struct ProjectRow: View {
    let title: String
    let systemImage: String?
    let count: Int?
    let isActive: Bool
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Space.sm) {
                Image(systemName: systemImage ?? (isCurrent ? "folder.fill" : "folder"))
                    .font(.icon(.base))
                    .foregroundStyle(isActive ? Constants.VisualStyle.textSecondary : Constants.VisualStyle.textTertiary)
                    .frame(width: 13)
                Text(title)
                    .font(.ui(.title, weight: .medium))
                    .foregroundStyle(isActive ? Constants.VisualStyle.text : Constants.VisualStyle.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if isCurrent {
                    Text("当前")
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
                if let count {
                    Text("\(count)")
                        .font(.ui(.caption, mono: true))
                        .foregroundStyle(Constants.VisualStyle.textQuaternary)
                }
            }
            .padding(.horizontal, Design.Space.md)
            .frame(height: Constants.Layout.regularRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Constants.VisualStyle.tintSubtle : Color.clear)
            )
            .roundedHitTarget(cornerRadius: 6)
        }
        .buttonStyle(.plain)
    }
}

/// Date formatters are expensive to build. The entry list rebuilds every
/// visible row on each keystroke, so the formatter is created once and reused.
private enum EntryDateFormat {
    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func lastUsed(_ date: Date?) -> String {
        guard let date else {
            return "未使用"
        }
        return relative.localizedString(for: date, relativeTo: Date())
    }
}

private struct EntryListRow: View {
    let entry: Entry
    let isSelected: Bool
    let projectName: String?
    let onTap: () -> Void

    var body: some View {
        let type = Constants.EntryType.resolve(entry.type)
        let level = Constants.EntryLevel.resolve(useCount: entry.useCount)
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Design.Space.md) {
                Image(systemName: type.symbolName)
                    .font(.icon(.base))
                    .foregroundStyle(level.color)
                    .frame(width: 16, height: 16)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Design.Space.sm) {
                        Text(entry.title)
                            .font(.ui(.title, weight: .medium))
                            .foregroundStyle(Constants.VisualStyle.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if entry.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.icon(.micro, weight: .semibold))
                                .foregroundStyle(Constants.VisualStyle.warn)
                        }
                        Spacer(minLength: 0)
                    }
                    Text(entry.previewLine)
                        .font(.ui(.body))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: Design.Space.xs) {
                        Text("\(entry.useCount) 次")
                            .font(.ui(.micro, weight: .medium, mono: true))
                            .foregroundStyle(level.color)
                        Text("·")
                            .opacity(0.5)
                        Text(lastUsedText)
                            .font(.ui(.micro))
                        if let projectName {
                            Text("·")
                                .opacity(0.5)
                            Text(projectName)
                                .font(.ui(.micro))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        if entry.tags.isEmpty == false {
                            TagChipsInline(tags: entry.tags, max: 2)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Constants.VisualStyle.textQuaternary)
                }
            }
            .padding(.vertical, Design.Space.sm)
            .padding(.leading, Design.Space.lg)
            .padding(.trailing, Design.Space.lg)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isSelected ? Constants.VisualStyle.accent : Color.clear)
                    .frame(width: 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Constants.VisualStyle.tintSubtle : Color.clear)
            .fullHitTarget()
        }
        .buttonStyle(.plain)
    }

    private var lastUsedText: String {
        EntryDateFormat.lastUsed(entry.lastUsedAt)
    }
}

private struct PreviewPane: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        if let entry = viewModel.selectedEntry {
            content(for: entry)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: Design.Space.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.icon(.hero, weight: .light))
                .foregroundStyle(Constants.VisualStyle.textQuaternary)
            Text("选择一条词条查看")
                .font(.ui(.title))
                .foregroundStyle(Constants.VisualStyle.textQuaternary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(for entry: Entry) -> some View {
        let type = Constants.EntryType.resolve(entry.type)
        return VStack(alignment: .leading, spacing: 0) {
            header(for: entry, type: type)
                .padding(.horizontal, 16)
                .padding(.vertical, Design.Space.lg)
                .background(
                    VStack(spacing: 0) {
                        Spacer()
                        Rectangle()
                            .fill(Constants.VisualStyle.divider)
                            .frame(height: Constants.Layout.hairline)
                    }
                )

            ScrollView {
                Text(entry.content)
                    .font(.ui(.title))
                    .foregroundStyle(Constants.VisualStyle.text)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, Design.Space.lg)
            }
            .scrollIndicators(.hidden)

            footer(for: entry)
                .padding(.horizontal, 16)
                .padding(.vertical, Design.Space.md)
                .background(
                    Rectangle()
                        .fill(Constants.VisualStyle.divider)
                        .frame(height: Constants.Layout.hairline),
                    alignment: .top
                )
        }
    }

    private func header(for entry: Entry, type: Constants.EntryType) -> some View {
        let level = Constants.EntryLevel.resolve(useCount: entry.useCount)
        return VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack(spacing: Design.Space.sm) {
                HStack(spacing: Design.Space.xs) {
                    Image(systemName: type.symbolName)
                        .font(.icon(.micro))
                    Text(type.displayName)
                        .font(.ui(.caption, weight: .medium))
                }
                .foregroundStyle(Constants.VisualStyle.textTertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: Constants.Layout.badgeCornerRadius, style: .continuous)
                        .fill(Constants.VisualStyle.tintSubtle)
                )

                Text(level.displayName)
                    .font(.ui(.caption, weight: .semibold))
                    .foregroundStyle(level.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: Constants.Layout.badgeCornerRadius, style: .continuous)
                            .fill(level.fillColor)
                    )

                if entry.isPinned {
                    HStack(spacing: 3) {
                        Image(systemName: "pin.fill")
                            .font(.icon(.micro))
                        Text("已置顶")
                            .font(.ui(.caption, weight: .medium))
                    }
                    .foregroundStyle(Constants.VisualStyle.warn)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: Constants.Layout.badgeCornerRadius, style: .continuous)
                            .fill(Constants.VisualStyle.warnDim)
                    )
                }

                HStack(spacing: 4) {
                    Text("· \(entry.useCount) 次使用")
                        .foregroundStyle(level.color)
                    Text("· \(lastUsedText(entry))")
                        .foregroundStyle(Constants.VisualStyle.textQuaternary)
                }
                .font(.ui(.caption))

                Spacer(minLength: 0)

                Menu {
                    Button("复制内容") { viewModel.copyEntryContent(entry) }
                    Button("编辑词条") { viewModel.startEditEntry(entry) }
                    Button(entry.isPinned ? "取消置顶" : "置顶") { viewModel.togglePin(entry) }
                    Divider()
                    Button("删除", role: .destructive) { viewModel.requestDeleteEntry(entry) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.icon(.base))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                        .frame(width: Constants.Layout.compactControlHeight, height: Constants.Layout.compactControlHeight)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            Text(entry.title)
                .font(.ui(.display, weight: .semibold))
                .foregroundStyle(Constants.VisualStyle.text)
                .lineLimit(2)
                .truncationMode(.tail)

            HStack(spacing: Design.Space.sm) {
                PrimaryActionButton(title: "复制", systemImage: "doc.on.doc", shortcut: "⇧⌘C") {
                    viewModel.copyEntryContent(entry)
                }
                GhostActionButton(title: "编辑", systemImage: "pencil", shortcut: "⌘E") {
                    viewModel.startEditEntry(entry)
                }
                Spacer(minLength: 0)
                QuietIconButton(
                    systemImage: entry.isPinned ? "pin.slash" : "pin",
                    tint: entry.isPinned ? Constants.VisualStyle.warn : nil,
                    help: entry.isPinned ? "取消置顶" : "置顶"
                ) {
                    viewModel.togglePin(entry)
                }
                QuietIconButton(systemImage: "trash", help: "删除") {
                    viewModel.requestDeleteEntry(entry)
                }
            }
        }
    }

    private func footer(for entry: Entry) -> some View {
        HStack(spacing: Design.Space.xl) {
            MetaInline(label: "项目", value: projectName(for: entry) ?? "未归属")
            footerSeparator
            HStack(spacing: Design.Space.sm) {
                Text("标签")
                    .font(.ui(.caption))
                    .foregroundStyle(Constants.VisualStyle.textQuaternary)
                if entry.tags.isEmpty {
                    Text("无")
                        .font(.ui(.body))
                        .foregroundStyle(Constants.VisualStyle.textQuaternary)
                } else {
                    HStack(spacing: 4) {
                        ForEach(entry.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.ui(.caption, weight: .medium))
                                .foregroundStyle(Constants.VisualStyle.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: Constants.Layout.badgeCornerRadius, style: .continuous)
                                        .fill(Constants.VisualStyle.tintSubtle)
                                )
                        }
                    }
                }
            }
            footerSeparator
            MetaInline(label: "更新时间", value: formattedUpdatedAt(entry))
            Spacer(minLength: 0)
        }
    }

    private var footerSeparator: some View {
        Rectangle()
            .fill(Constants.VisualStyle.divider)
            .frame(width: Constants.Layout.hairline, height: 14)
    }

    private func projectName(for entry: Entry) -> String? {
        viewModel.projectName(forEntry: entry)
    }

    private func lastUsedText(_ entry: Entry) -> String {
        EntryDateFormat.lastUsed(entry.lastUsedAt)
    }

    private func formattedUpdatedAt(_ entry: Entry) -> String {
        entry.updatedAt.formatted(date: .abbreviated, time: .shortened)
    }
}

struct TagChipsInline: View {
    let tags: [String]
    let max: Int

    init(tags: [String], max: Int = 2) {
        self.tags = tags
        self.max = max
    }

    var body: some View {
        let shown = Array(tags.prefix(max))
        let rest = tags.count - shown.count
        HStack(spacing: 4) {
            ForEach(shown, id: \.self) { tag in
                Text(tag)
                    .font(.ui(.micro, weight: .medium))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: Constants.Layout.badgeCornerRadius, style: .continuous)
                            .fill(Constants.VisualStyle.tintSubtle)
                    )
            }
            if rest > 0 {
                Text("+\(rest)")
                    .font(.ui(.micro, weight: .medium, mono: true))
                    .foregroundStyle(Constants.VisualStyle.textQuaternary)
            }
        }
    }
}

private struct MetaInline: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: Design.Space.sm) {
            Text(label)
                .font(.ui(.caption))
                .foregroundStyle(Constants.VisualStyle.textQuaternary)
            Text(value)
                .font(.ui(.body))
                .foregroundStyle(Constants.VisualStyle.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
