import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/sync_models.dart';
import 'services/mobile_sync_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final syncClient = MobileSyncClient();
  await syncClient.initialize();
  runApp(PromptPanelMobileApp(syncClient: syncClient));
}

class PromptPanelPalette {
  final bool isDark;
  const PromptPanelPalette(this.isDark);

  Color get bg => isDark ? const Color(0xFF111215) : const Color(0xFFF3F4F7);
  Color get surface => isDark ? const Color(0xFF17181C) : const Color(0xFFFFFFFF);
  Color get surfaceRaised => isDark ? const Color(0xFF1E2025) : const Color(0xFFFFFFFF);
  Color get sidebar => isDark ? const Color(0xFF141518) : const Color(0xFFF3F4F7);
  Color get inputFill => isDark ? const Color(0xFF141519) : const Color(0xFFF5F6F9);
  Color get border => isDark ? const Color(0x14FFFFFF) : const Color(0x17000000);
  Color get divider => isDark ? const Color(0x0FFFFFFF) : const Color(0x12000000);

  Color get text => isDark ? const Color(0xFFECEEF2) : const Color(0xFF16181D);
  Color get textSecondary => isDark ? const Color(0xFFB2B8C4) : const Color(0xFF464B55);
  Color get textTertiary => isDark ? const Color(0xFF8A919E) : const Color(0xFF646B78);

  Color get accent => isDark ? const Color(0xFF7C8CF8) : const Color(0xFF4F5FE8);
  Color get accentDim => isDark ? const Color(0x267C8CF8) : const Color(0x1C4F5FE8);
  Color get warn => isDark ? const Color(0xFFD4A35A) : const Color(0xFF9A6510);
  Color get tintSubtle => isDark ? const Color(0x0BFFFFFF) : const Color(0x0A000000);
}

class PromptPanelMobileApp extends StatelessWidget {
  final MobileSyncClient syncClient;
  const PromptPanelMobileApp({super.key, required this.syncClient});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PromptPanel',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _buildTheme(false),
      darkTheme: _buildTheme(true),
      home: MobileHomeScreen(syncClient: syncClient),
    );
  }

  ThemeData _buildTheme(bool isDark) {
    final p = PromptPanelPalette(isDark);
    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: p.surface,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: p.accent,
        onPrimary: Colors.white,
        secondary: p.accent,
        onSecondary: Colors.white,
        error: isDark ? const Color(0xFFD97373) : const Color(0xFFBF2C2C),
        onError: Colors.white,
        surface: p.surface,
        onSurface: p.text,
      ),
      dividerColor: p.divider,
      useMaterial3: true,
    );
  }
}

class MobileHomeScreen extends StatefulWidget {
  final MobileSyncClient syncClient;
  const MobileHomeScreen({super.key, required this.syncClient});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  int _selectedTabIndex = 0; // 0: 速记与待办, 1: 常用类型, 2: 项目
  String? _selectedGroupId;
  bool _showArchivedProjects = false;
  String _searchQuery = '';

  MobileSyncClient get _client => widget.syncClient;

  List<EntryModel> get _activeEntries =>
      _client.entries.where((e) => e.deletedAt == null).toList();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = PromptPanelPalette(isDark);

    return Scaffold(
      backgroundColor: p.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(p),
            _buildSearchBar(p),
            Expanded(child: _buildCurrentTabBody(p)),
            _buildBottomBar(p),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(PromptPanelPalette p) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: p.tintSubtle,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: p.border, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.adjust, size: 13, color: p.accent),
                const SizedBox(width: 6),
                Text(
                  '当前面板：$_tabTitle',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: p.text),
                ),
              ],
            ),
          ),
          const Spacer(),
          _quietButton(
            p: p,
            icon: Icons.sync,
            label: '同步',
            onTap: _triggerCloudSync,
          ),
          const SizedBox(width: 6),
          _quietButton(
            p: p,
            icon: Icons.tune,
            onTap: _openSyncSettingsSheet,
          ),
        ],
      ),
    );
  }

  Widget _quietButton({
    required PromptPanelPalette p,
    required IconData icon,
    String? label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 28,
        padding: EdgeInsets.symmetric(horizontal: label == null ? 8 : 10),
        decoration: BoxDecoration(
          color: p.tintSubtle,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: p.border, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: p.textSecondary),
            if (label != null) ...[
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: p.text),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(PromptPanelPalette p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.divider, width: 0.5)),
      ),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: p.inputFill,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: p.border, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 14, color: p.textTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                style: TextStyle(fontSize: 12, color: p.text),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '搜索标题、内容或 #标签',
                  hintStyle: TextStyle(fontSize: 12, color: p.textTertiary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _tabTitle {
    switch (_selectedTabIndex) {
      case 0:
        return '速记与待办';
      case 1:
        return '常用类型';
      default:
        return '项目';
    }
  }

  Widget _buildCurrentTabBody(PromptPanelPalette p) {
    List<EntryModel> entries;
    Widget? chipRow;

    if (_selectedTabIndex == 0) {
      entries = _activeEntries
          .where((e) =>
              e.projectId == ProjectModel.builtinInboxId ||
              e.type == 'todo' ||
              e.type == 'note')
          .toList();
    } else {
      final targetKind =
          _selectedTabIndex == 1 ? GroupKind.category : GroupKind.project;
      final groups = _client.projects
          .where((proj) =>
              proj.deletedAt == null &&
              proj.groupKind == targetKind &&
              (_showArchivedProjects || !proj.isArchived))
          .toList();

      final currentGroupId =
          _selectedGroupId ?? (groups.isEmpty ? null : groups.first.id);
      entries = currentGroupId == null
          ? <EntryModel>[]
          : _activeEntries.where((e) => e.projectId == currentGroupId).toList();

      chipRow = Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: p.surface,
          border: Border(bottom: BorderSide(color: p.divider, width: 0.5)),
        ),
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final group in groups)
              Padding(
                padding: const EdgeInsets.only(right: 4, top: 6, bottom: 6),
                child: InkWell(
                  onTap: () => setState(() => _selectedGroupId = group.id),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: group.id == currentGroupId ? p.accentDim : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      group.isArchived ? '${group.name} (已归档)' : group.name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: group.id == currentGroupId ? p.accent : p.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    if (_searchQuery.isNotEmpty) {
      final rawQuery = _searchQuery.trim().toLowerCase();
      final tagQuery = rawQuery.startsWith('#') ? rawQuery.substring(1) : rawQuery;
      bool matchesEntry(EntryModel e) {
        if (rawQuery.startsWith('#')) {
          return tagQuery.isEmpty ||
              e.tags.any((t) => t.toLowerCase().contains(tagQuery));
        }
        return e.title.toLowerCase().contains(rawQuery) ||
            e.content.toLowerCase().contains(rawQuery) ||
            e.tags.any((t) => t.toLowerCase().contains(tagQuery));
      }

      var scopedMatches = entries.where(matchesEntry).toList();
      if (scopedMatches.isEmpty) {
        scopedMatches = _activeEntries.where(matchesEntry).toList();
      }
      entries = scopedMatches;
    }

    return Column(
      children: [
        if (chipRow != null) chipRow,
        _buildCountToolbar(p, entries.length),
        Expanded(
          child: _buildEntryList(
            p,
            entries,
            allowCheckbox: _selectedTabIndex == 0,
          ),
        ),
      ],
    );
  }

  Widget _buildCountToolbar(PromptPanelPalette p, int count) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Text(
            '$count 条',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: p.textSecondary,
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: _openQuickCreateSheet,
            borderRadius: BorderRadius.circular(5),
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: p.accentDim,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 12, color: p.accent),
                  const SizedBox(width: 4),
                  Text(
                    '新建',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: p.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryList(
    PromptPanelPalette p,
    List<EntryModel> items, {
    required bool allowCheckbox,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          '当前分组暂无内容',
          style: TextStyle(fontSize: 12, color: p.textSecondary),
        ),
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(height: 0.5, thickness: 0.5, indent: 38, color: p.divider),
      itemBuilder: (context, index) {
        final item = items[index];
        final isTodo = allowCheckbox || item.type == 'todo' || item.type == 'note';
        return InkWell(
          onTap: () => _openEntryDetailSheet(item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isTodo)
                  GestureDetector(
                    onTap: () async {
                      final updated = item.copyWith(
                        isCompleted: !item.isCompleted,
                        updatedAt: DateTime.now().toUtc(),
                      );
                      await _client.addOrUpdateEntry(updated, changeNote: '切换完成状态');
                      setState(() {});
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2, right: 8),
                      child: Icon(
                        item.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 16,
                        color: item.isCompleted ? p.accent : p.textTertiary,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 8),
                    child: Icon(Icons.chat_bubble_outline, size: 15, color: p.accent),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: item.isCompleted ? p.textTertiary : p.text,
                                decoration: item.isCompleted ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ),
                          if (item.useCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: p.accentDim,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '${item.useCount}次',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                  color: p.accent,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.content.replaceAll('\n', ' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.createdAt.toLocal().toString().substring(0, 10),
                        style: TextStyle(
                          fontSize: 10,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: p.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _copyEntryAndRecordUse(item),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: p.tintSubtle,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: p.border, width: 0.5),
                    ),
                    child: Icon(Icons.copy_rounded, size: 13, color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(PromptPanelPalette p) {
    const items = [
      (Icons.checklist_rtl, '速记与待办'),
      (Icons.grid_view_outlined, '常用类型'),
      (Icons.folder_outlined, '项目'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: p.sidebar,
        border: Border(top: BorderSide(color: p.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                child: InkWell(
                  onTap: () => setState(() {
                    _selectedTabIndex = i;
                    _selectedGroupId = null;
                  }),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: _selectedTabIndex == i ? p.accentDim : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          items[i].$1,
                          size: 15,
                          color: _selectedTabIndex == i ? p.accent : p.textTertiary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          items[i].$2,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _selectedTabIndex == i ? FontWeight.w600 : FontWeight.w400,
                            color: _selectedTabIndex == i ? p.text : p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _triggerCloudSync() async {
    try {
      final msg = await _client.syncNow();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('同步失败: $e')),
      );
    }
  }

  Future<void> _copyEntryAndRecordUse(EntryModel item) async {
    await Clipboard.setData(ClipboardData(text: item.content));
    final now = DateTime.now().toUtc();
    final updated = item.copyWith(
      useCount: item.useCount + 1,
      lastUsedAt: now,
      updatedAt: now,
    );
    await _client.addOrUpdateEntry(updated);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制：${item.title}')),
    );
  }

  void _openEntryDetailSheet(EntryModel item) {
    final titleCtrl = TextEditingController(text: item.title);
    final contentCtrl = TextEditingController(text: item.content);
    final tagsCtrl = TextEditingController(text: item.tags.join(', '));
    bool isPinned = item.isPinned;
    bool isCompleted = item.isCompleted;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '词条详情与编辑',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: '复制内容',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _copyEntryAndRecordUse(item);
                    },
                  ),
                  IconButton(
                    tooltip: '删除词条',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () async {
                      final now = DateTime.now().toUtc();
                      await _client.addOrUpdateEntry(
                        item.copyWith(deletedAt: now, updatedAt: now),
                        changeNote: '手机端删除',
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      setState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('置顶'),
                    selected: isPinned,
                    onSelected: (val) => setSheetState(() => isPinned = val),
                  ),
                  if (item.type == 'todo' || item.type == 'note')
                    FilterChip(
                      label: Text(isCompleted ? '已完成' : '待办中'),
                      selected: isCompleted,
                      onSelected: (val) => setSheetState(() => isCompleted = val),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: '标题',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '内容',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tagsCtrl,
                decoration: const InputDecoration(
                  labelText: '标签（逗号分隔）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  final text = contentCtrl.text.trim();
                  if (text.isEmpty) return;
                  final rawTitle = titleCtrl.text.trim();
                  final title = rawTitle.isEmpty
                      ? text.split('\n').first.substring(
                            0,
                            text.split('\n').first.length.clamp(0, 28),
                          )
                      : rawTitle;
                  final parsedTags = tagsCtrl.text
                      .split(RegExp(r'[,，、]'))
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toList();
                  final now = DateTime.now().toUtc();
                  final updated = item.copyWith(
                    title: title,
                    content: text,
                    isPinned: isPinned,
                    isCompleted: isCompleted,
                    tags: parsedTags,
                    updatedAt: now,
                  );
                  await _client.addOrUpdateEntry(updated, changeNote: '手机端编辑保存');
                  if (ctx.mounted) Navigator.pop(ctx);
                  setState(() {});
                },
                child: const Text('保存修改'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openQuickCreateSheet() {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final String selectedType = _selectedTabIndex == 0 ? 'todo' : 'prompt';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('新建词条', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: '标题（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentCtrl,
              maxLines: 5,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '内容',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final text = contentCtrl.text.trim();
                if (text.isEmpty) return;
                final rawTitle = titleCtrl.text.trim();
                final title = rawTitle.isEmpty
                    ? text.split('\n').first.substring(0, text.split('\n').first.length.clamp(0, 28))
                    : rawTitle;
                final now = DateTime.now().toUtc();
                final entry = EntryModel(
                  id: 'mob-${now.millisecondsSinceEpoch}',
                  projectId: _selectedGroupId ?? ProjectModel.builtinInboxId,
                  title: title,
                  content: text,
                  type: selectedType,
                  createdAt: now,
                  updatedAt: now,
                );
                await _client.addOrUpdateEntry(entry);
                if (ctx.mounted) Navigator.pop(ctx);
                setState(() {});
              },
              child: const Text('保存修改'),
            ),
          ],
        ),
      ),
    );
  }

  void _openSyncSettingsSheet() {
    final endpointCtrl = TextEditingController(text: _client.endpoint);
    final keyCtrl = TextEditingController(text: _client.apiKey);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('设置与云端同步', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: endpointCtrl,
              decoration: const InputDecoration(
                labelText: '同步地址',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '访问令牌 (Token)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                await _client.saveSettings(
                  newEndpoint: endpointCtrl.text,
                  newApiKey: keyCtrl.text,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('保存同步配置'),
            ),
          ],
        ),
      ),
    );
  }
}
