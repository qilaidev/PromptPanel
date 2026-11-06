import AppKit
import SwiftUI

struct ReferenceLibraryWindowView: View {
    @ObservedObject var viewModel: MainWindowViewModel

    private var effectiveTargetProjectId: String {
        if !viewModel.referenceTargetProjectId.isEmpty,
           viewModel.projects.contains(where: { $0.id == viewModel.referenceTargetProjectId }) {
            return viewModel.referenceTargetProjectId
        }
        if viewModel.selectedProjectId != MainWindowViewModel.allProjectsSelection,
           viewModel.projects.contains(where: { $0.id == viewModel.selectedProjectId }) {
            return viewModel.selectedProjectId
        }
        return viewModel.currentProjectId
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
        .frame(minWidth: 520, minHeight: 560)
        .background(Constants.VisualStyle.surfaceRaised)
        .tint(Constants.VisualStyle.accent)
        .preferredColorScheme(viewModel.appTheme.preferredColorScheme)
        .onAppear {
            if viewModel.referenceTargetProjectId.isEmpty {
                viewModel.referenceTargetProjectId = effectiveTargetProjectId
            }
            viewModel.refreshClipboardPreview()
            viewModel.refreshReferenceEntries()
        }
        .onChange(of: viewModel.referenceSourceProjectId) { _, _ in
            viewModel.refreshReferenceEntries()
        }
        .onChange(of: viewModel.referenceSearchText) { _, _ in
            viewModel.refreshReferenceEntries()
        }
    }

    // MARK: - Top Toolbar (Source Filter, Search & Target Project)

    private var headerToolbar: some View {
        HStack(spacing: 8) {
            Picker("来源", selection: $viewModel.referenceSourceProjectId) {
                Text("全部来源").tag(MainWindowViewModel.allProjectsSelection)
                Section("常用类型") {
                    ForEach(viewModel.categoryProjects) { category in
                        Text(category.name).tag(category.id)
                    }
                }
                Section("项目") {
                    ForEach(viewModel.activeProjects) { project in
                        Text(project.name).tag(project.id)
                    }
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 136)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.icon(.small))
                    .foregroundStyle(Constants.VisualStyle.textTertiary)
                TextField("搜索标题、内容或标签…", text: $viewModel.referenceSearchText)
                    .textFieldStyle(.plain)
                    .font(.ui(.body))
                    .foregroundStyle(Constants.VisualStyle.text)
                if !viewModel.referenceSearchText.isEmpty {
                    Button {
                        viewModel.referenceSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.icon(.small))
                            .foregroundStyle(Constants.VisualStyle.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Constants.VisualStyle.inputFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
            )

            HStack(spacing: 4) {
                Text("目标")
                    .font(.ui(.caption, weight: .medium))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)

                Picker("目标项目", selection: Binding(
                    get: { effectiveTargetProjectId },
                    set: { viewModel.referenceTargetProjectId = $0 }
                )) {
                    Section("项目") {
                        ForEach(viewModel.activeProjects) { project in
                            Text(project.name).tag(project.id)
                        }
                    }
                    Section("常用类型") {
                        ForEach(viewModel.categoryProjects) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                    if let inbox = viewModel.inboxProject {
                        Section("速记与待办") {
                            Text(inbox.name).tag(inbox.id)
                        }
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 140)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Constants.VisualStyle.surface)
    }

    // MARK: - System Clipboard Strip

    private var clipboardQuickImportStrip: some View {
        HStack(spacing: 8) {
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

            Button {
                viewModel.refreshClipboardPreview()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.icon(.small))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                    .frame(width: 24, height: 24)
                    .roundedHitTarget(cornerRadius: 5)
            }
            .buttonStyle(.plain)
            .help("刷新剪贴板内容")

            if !viewModel.clipboardPreviewText.isEmpty {
                if let inbox = viewModel.inboxProject {
                    SettingsPillButton("记入待办", systemImage: "checklist") {
                        viewModel.createQuickEntryFromClipboard(intoProjectId: inbox.id, type: .todo)
                        viewModel.refreshReferenceEntries()
                    }
                }

                SettingsPillButton(
                    "存入「\(viewModel.projectName(for: effectiveTargetProjectId))」",
                    systemImage: "plus",
                    tone: .primary
                ) {
                    viewModel.createQuickEntryFromClipboard(
                        intoProjectId: effectiveTargetProjectId,
                        type: .prompt
                    )
                    viewModel.refreshReferenceEntries()
                }
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
}

private struct ReferenceEntryRow: View {
    let entry: Entry
    let sourceName: String
    let targetName: String
    let isAlreadyInTarget: Bool
    let onCloneToTarget: () -> Void
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(sourceName)
                        .font(.ui(.micro, weight: .semibold))
                        .foregroundStyle(Constants.VisualStyle.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Constants.VisualStyle.accentDim)
                        )

                    Text(entry.title)
                        .font(.ui(.body, weight: .semibold))
                        .foregroundStyle(Constants.VisualStyle.text)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text("\(entry.useCount)次 · \(EntryDateFormat.shortDay(entry.createdAt))")
                        .font(.ui(.micro, mono: true))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                }

                Text(entry.content)
                    .font(.ui(.caption))
                    .foregroundStyle(Constants.VisualStyle.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                SettingsPillButton("复制", action: onCopy)

                SettingsPillButton(
                    isAlreadyInTarget ? "再次克隆" : "克隆到「\(targetName)」",
                    systemImage: "plus.square.on.square",
                    tone: .primary,
                    action: onCloneToTarget
                )
                .disabled(targetName.isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
