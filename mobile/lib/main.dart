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

class PromptPanelMobileApp extends StatelessWidget {
  final MobileSyncClient syncClient;
  const PromptPanelMobileApp({super.key, required this.syncClient});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PromptPanel 手机快贴',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: MobileHomeScreen(syncClient: syncClient),
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
  int _selectedTabIndex = 0; // 0: 速记与待办, 1: 常用类型, 2: 项目管理
  String? _selectedGroupId;
  bool _showArchivedProjects = false;

  MobileSyncClient get _client => widget.syncClient;

  List<EntryModel> get _activeEntries =>
      _client.entries.where((e) => e.deletedAt == null).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tabTitle),
        actions: [
          IconButton(
            tooltip: '立即云端同步',
            icon: const Icon(Icons.sync),
            onPressed: _triggerCloudSync,
          ),
          IconButton(
            tooltip: '同步设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSyncSettingsSheet,
          ),
        ],
      ),
      body: _buildCurrentTabBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openQuickCreateSheet,
        icon: const Icon(Icons.add),
        label: Text(_selectedTabIndex == 0 ? '新建待办' : '新建词条'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (idx) {
          setState(() {
            _selectedTabIndex = idx;
            _selectedGroupId = null;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checklist_rtl_outlined),
            selectedIcon: Icon(Icons.checklist_rtl),
            label: '速记与待办',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: '常用类型',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: '项目',
          ),
        ],
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

  Widget _buildCurrentTabBody() {
    if (_selectedTabIndex == 0) {
      final inboxEntries = _activeEntries
          .where((e) =>
              e.projectId == ProjectModel.builtinInboxId ||
              e.type == 'todo' ||
              e.type == 'note')
          .toList();
      return _buildEntryList(inboxEntries, allowCheckbox: true);
    }

    final targetKind =
        _selectedTabIndex == 1 ? GroupKind.category : GroupKind.project;
    final groups = _client.projects
        .where((p) =>
            p.deletedAt == null &&
            p.groupKind == targetKind &&
            (_showArchivedProjects || !p.isArchived))
        .toList();

    final currentGroupId = _selectedGroupId ?? (groups.isEmpty ? null : groups.first.id);
    final entries = currentGroupId == null
        ? <EntryModel>[]
        : _activeEntries.where((e) => e.projectId == currentGroupId).toList();

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              for (final group in groups)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(group.isArchived ? '${group.name} (已归档)' : group.name),
                    selected: group.id == currentGroupId,
                    onSelected: (_) => setState(() => _selectedGroupId = group.id),
                  ),
                ),
              if (_selectedTabIndex == 2)
                FilterChip(
                  label: const Text('显示已归档'),
                  selected: _showArchivedProjects,
                  onSelected: (v) => setState(() => _showArchivedProjects = v),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildEntryList(entries, allowCheckbox: false)),
      ],
    );
  }

  Widget _buildEntryList(List<EntryModel> items, {required bool allowCheckbox}) {
    if (items.isEmpty) {
      return const Center(
        child: Text('暂无内容'),
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        final versions = _client.versionsForEntry(item.id);
        return ListTile(
          leading: allowCheckbox || item.type == 'todo'
              ? Checkbox(
                  value: item.isCompleted,
                  onChanged: (checked) async {
                    final updated = item.copyWith(
                      isCompleted: checked ?? false,
                      updatedAt: DateTime.now().toUtc(),
                    );
                    await _client.addOrUpdateEntry(updated, changeNote: '切换完成状态');
                    setState(() {});
                  },
                )
              : const Icon(Icons.chat_bubble_outline, size: 20),
          title: Text(
            item.title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              decoration: item.isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.content, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(
                '创建: ${item.createdAt.toLocal().toString().substring(0, 16)} · '
                '用 ${item.useCount} 次 · v${versions.isEmpty ? 1 : versions.first.versionNumber}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          trailing: IconButton(
            tooltip: '一键复制',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: item.content));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已复制：${item.title}')),
              );
            },
          ),
        );
      },
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

  void _openQuickCreateSheet() {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    String selectedType = _selectedTabIndex == 0 ? 'todo' : 'prompt';

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
              child: const Text('保存'),
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
            Text('云端同步', style: Theme.of(ctx).textTheme.titleMedium),
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
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
