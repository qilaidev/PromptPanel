import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sync_models.dart';

class MobileSyncClient {
  static const String _storageKey = 'promptpanel_mobile_store_v2';
  static const String _endpointKey = 'promptpanel_cloud_endpoint';
  static const String _apiKeyKey = 'promptpanel_cloud_api_key';

  String deviceId = 'mobile-client';
  String endpoint = '';
  String apiKey = '';
  String lastSyncMessage = '尚未同步';

  List<ProjectModel> projects = [];
  List<EntryModel> entries = [];
  List<EntryVersionModel> versions = [];

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    endpoint = prefs.getString(_endpointKey) ?? '';
    apiKey = prefs.getString(_apiKeyKey) ?? '';
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final env = CloudSyncEnvelope.fromJson(decoded);
      deviceId = env.deviceId;
      projects = env.projects;
      entries = env.entries;
      versions = env.versions;
    } else {
      final now = DateTime.now().toUtc();
      projects = [
        ProjectModel(
          id: ProjectModel.builtinInboxId,
          name: '速记与待办',
          isDefault: false,
          groupKind: GroupKind.inbox,
          isArchived: false,
          iconName: 'checklist',
          sortOrder: -10,
          createdAt: now,
          updatedAt: now,
        ),
        ProjectModel(
          id: 'default-general',
          name: '通用项目',
          isDefault: true,
          groupKind: GroupKind.category,
          isArchived: false,
          iconName: 'square.grid.2x2',
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      ];
      await persistLocal();
    }
  }

  Future<void> saveSettings({
    required String newEndpoint,
    required String newApiKey,
  }) async {
    endpoint = newEndpoint.trim();
    apiKey = newApiKey.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_endpointKey, endpoint);
    await prefs.setString(_apiKeyKey, apiKey);
  }

  Future<void> persistLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final envelope = CloudSyncEnvelope(
      deviceId: deviceId,
      exportedAt: DateTime.now().toUtc(),
      projects: projects,
      entries: entries,
      versions: versions,
    );
    await prefs.setString(_storageKey, jsonEncode(envelope.toJson()));
  }

  List<EntryVersionModel> versionsForEntry(String entryId) {
    final matched = versions.where((v) => v.entryId == entryId).toList();
    matched.sort((a, b) => b.versionNumber.compareTo(a.versionNumber));
    return matched;
  }

  Future<void> addOrUpdateEntry(EntryModel entry, {String? changeNote}) async {
    final idx = entries.indexWhere((e) => e.id == entry.id);
    final existingVersions = versionsForEntry(entry.id);
    final nextVer = (existingVersions.isEmpty ? 0 : existingVersions.first.versionNumber) + 1;

    if (idx >= 0) {
      final previous = entries[idx];
      entries[idx] = entry;
      if (previous.content != entry.content || previous.title != entry.title) {
        versions.add(
          EntryVersionModel(
            id: '${entry.id}-v$nextVer',
            entryId: entry.id,
            versionNumber: nextVer,
            title: entry.title,
            content: entry.content,
            changeNote: changeNote ?? '手机端编辑保存',
            createdAt: entry.updatedAt,
          ),
        );
      }
    } else {
      entries.insert(0, entry);
      versions.add(
        EntryVersionModel(
          id: '${entry.id}-v1',
          entryId: entry.id,
          versionNumber: 1,
          title: entry.title,
          content: entry.content,
          changeNote: changeNote ?? '手机端创建',
          createdAt: entry.createdAt,
        ),
      );
    }
    await persistLocal();
  }

  /// Bidirectional HTTP sync with macOS CloudSyncService (Conflict-to-Version-History safe).
  Future<String> syncNow() async {
    if (endpoint.isEmpty) {
      throw Exception('请先配置云端同步 HTTPS 地址');
    }
    final uri = Uri.parse(endpoint);
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
    };

    final getResp = await http.get(uri, headers: headers);
    if (getResp.statusCode >= 200 && getResp.statusCode < 300 && getResp.body.isNotEmpty) {
      final remote = CloudSyncEnvelope.fromJson(
        jsonDecode(getResp.body) as Map<String, dynamic>,
      );
      _mergeRemoteEnvelope(remote);
    }

    final mergedEnvelope = CloudSyncEnvelope(
      deviceId: deviceId,
      exportedAt: DateTime.now().toUtc(),
      projects: projects,
      entries: entries,
      versions: versions,
    );
    final postResp = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(mergedEnvelope.toJson()),
    );
    if (postResp.statusCode < 200 || postResp.statusCode >= 300) {
      throw Exception('推送失败: HTTP ${postResp.statusCode}');
    }
    await persistLocal();
    lastSyncMessage = '同步成功 (${DateTime.now().toIso8601String().substring(0, 19)})';
    return lastSyncMessage;
  }

  void _mergeRemoteEnvelope(CloudSyncEnvelope remote) {
    for (final remoteProject in remote.projects) {
      final idx = projects.indexWhere((p) => p.id == remoteProject.id);
      if (idx >= 0) {
        if (remoteProject.updatedAt.isAfter(projects[idx].updatedAt)) {
          projects[idx] = remoteProject;
        }
      } else {
        projects.add(remoteProject);
      }
    }

    for (final remoteEntry in remote.entries) {
      final idx = entries.indexWhere((e) => e.id == remoteEntry.id);
      if (idx >= 0) {
        final local = entries[idx];
        if (remoteEntry.updatedAt.isAfter(local.updatedAt)) {
          if (local.content != remoteEntry.content || local.title != remoteEntry.title) {
            final currentMax = versionsForEntry(local.id).isEmpty
                ? 0
                : versionsForEntry(local.id).first.versionNumber;
            versions.add(
              EntryVersionModel(
                id: '${local.id}-conflict-${DateTime.now().millisecondsSinceEpoch}',
                entryId: local.id,
                versionNumber: currentMax + 1,
                title: local.title,
                content: local.content,
                changeNote: '云端同步前手机本地版本自动留存',
                createdAt: local.updatedAt,
              ),
            );
          }
          entries[idx] = remoteEntry;
        }
      } else {
        entries.add(remoteEntry);
      }
    }

    for (final remoteVersion in remote.versions) {
      final exists = versions.any(
        (v) =>
            v.id == remoteVersion.id ||
            (v.entryId == remoteVersion.entryId &&
                v.versionNumber == remoteVersion.versionNumber),
      );
      if (!exists) {
        versions.add(remoteVersion);
      }
    }
  }
}
