import 'dart:convert';

enum GroupKind {
  inbox('inbox', '速记与待办'),
  category('category', '常用类型'),
  project('project', '具体项目');

  final String rawValue;
  final String displayName;
  const GroupKind(this.rawValue, this.displayName);

  static GroupKind fromRaw(String? raw) {
    return GroupKind.values.firstWhere(
      (k) => k.rawValue == raw,
      orElse: () => GroupKind.project,
    );
  }
}

class ProjectModel {
  static const String builtinInboxId = 'builtin-inbox';

  final String id;
  final String name;
  final bool isDefault;
  final GroupKind groupKind;
  final bool isArchived;
  final String? iconName;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const ProjectModel({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.groupKind,
    required this.isArchived,
    this.iconName,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory ProjectModel.fromJson(Map<String, dynamic> json) {
    final isDef = json['isDefault'] == true || json['is_default'] == true;
    final rawKind = (json['groupKindRaw'] ?? json['group_kind'] ?? json['groupKind']) as String?;
    final rawCreatedAt = (json['createdAt'] ?? json['created_at']) as String;
    final rawUpdatedAt = (json['updatedAt'] ?? json['updated_at']) as String;
    final rawDeletedAt = (json['deletedAt'] ?? json['deleted_at']) as String?;
    return ProjectModel(
      id: json['id'] as String,
      name: json['name'] as String,
      isDefault: isDef,
      groupKind: rawKind != null
          ? GroupKind.fromRaw(rawKind)
          : (isDef ? GroupKind.category : GroupKind.project),
      isArchived: json['isArchived'] == true || json['is_archived'] == true,
      iconName: (json['iconName'] ?? json['icon_name']) as String?,
      sortOrder: (json['sortOrder'] ?? json['sort_order'] ?? 0) as int,
      createdAt: DateTime.parse(rawCreatedAt).toUtc(),
      updatedAt: DateTime.parse(rawUpdatedAt).toUtc(),
      deletedAt: rawDeletedAt != null
          ? DateTime.parse(rawDeletedAt).toUtc()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isDefault': isDefault,
        'groupKindRaw': groupKind.rawValue,
        'isArchived': isArchived,
        'iconName': iconName,
        'sortOrder': sortOrder,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };
}

class EntryModel {
  final String id;
  final String projectId;
  final String title;
  final String content;
  final String type; // prompt | code | todo | note | reply
  final bool isPinned;
  final bool isCompleted;
  final int sortOrder;
  final int useCount;
  final DateTime? lastUsedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? sourceEntryId;
  final List<String> tags;

  const EntryModel({
    required this.id,
    required this.projectId,
    required this.title,
    required this.content,
    required this.type,
    this.isPinned = false,
    this.isCompleted = false,
    this.sortOrder = 0,
    this.useCount = 0,
    this.lastUsedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.sourceEntryId,
    this.tags = const [],
  });

  EntryModel copyWith({
    String? projectId,
    String? title,
    String? content,
    String? type,
    bool? isPinned,
    bool? isCompleted,
    int? useCount,
    DateTime? lastUsedAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    List<String>? tags,
  }) {
    return EntryModel(
      id: id,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      content: content ?? this.content,
      type: type ?? this.type,
      isPinned: isPinned ?? this.isPinned,
      isCompleted: isCompleted ?? this.isCompleted,
      sortOrder: sortOrder,
      useCount: useCount ?? this.useCount,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      sourceEntryId: sourceEntryId,
      tags: tags ?? this.tags,
    );
  }

  factory EntryModel.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    List<String> parsedTags = const [];
    if (rawTags is List) {
      parsedTags = rawTags.map((e) => e.toString()).toList();
    } else if (rawTags is String && rawTags.isNotEmpty) {
      final decoded = jsonDecode(rawTags);
      if (decoded is List) {
        parsedTags = decoded.map((e) => e.toString()).toList();
      }
    }
    final rawLastUsedAt = (json['lastUsedAt'] ?? json['last_used_at']) as String?;
    final rawCreatedAt = (json['createdAt'] ?? json['created_at']) as String;
    final rawUpdatedAt = (json['updatedAt'] ?? json['updated_at']) as String;
    final rawDeletedAt = (json['deletedAt'] ?? json['deleted_at']) as String?;
    return EntryModel(
      id: json['id'] as String,
      projectId: (json['projectId'] ?? json['project_id']) as String,
      title: json['title'] as String,
      content: json['content'] as String,
      type: (json['type'] ?? 'prompt') as String,
      isPinned: json['isPinned'] == true || json['is_pinned'] == true,
      isCompleted: json['isCompleted'] == true || json['is_completed'] == true,
      sortOrder: (json['sortOrder'] ?? json['sort_order'] ?? 0) as int,
      useCount: (json['useCount'] ?? json['use_count'] ?? 0) as int,
      lastUsedAt: rawLastUsedAt != null
          ? DateTime.parse(rawLastUsedAt).toUtc()
          : null,
      createdAt: DateTime.parse(rawCreatedAt).toUtc(),
      updatedAt: DateTime.parse(rawUpdatedAt).toUtc(),
      deletedAt: rawDeletedAt != null
          ? DateTime.parse(rawDeletedAt).toUtc()
          : null,
      sourceEntryId: (json['sourceEntryId'] ?? json['source_entry_id']) as String?,
      tags: parsedTags,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'title': title,
        'content': content,
        'type': type,
        'isPinned': isPinned,
        'isCompleted': isCompleted,
        'sortOrder': sortOrder,
        'useCount': useCount,
        'lastUsedAt': lastUsedAt?.toUtc().toIso8601String(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
        'sourceEntryId': sourceEntryId,
        'tags': tags,
      };
}

class EntryVersionModel {
  final String id;
  final String entryId;
  final int versionNumber;
  final String title;
  final String content;
  final String? changeNote;
  final DateTime createdAt;

  const EntryVersionModel({
    required this.id,
    required this.entryId,
    required this.versionNumber,
    required this.title,
    required this.content,
    this.changeNote,
    required this.createdAt,
  });

  factory EntryVersionModel.fromJson(Map<String, dynamic> json) {
    final rawCreatedAt = (json['createdAt'] ?? json['created_at']) as String;
    return EntryVersionModel(
      id: json['id'] as String,
      entryId: (json['entryId'] ?? json['entry_id']) as String,
      versionNumber: (json['versionNumber'] ?? json['version_number'] ?? 1) as int,
      title: (json['title'] ?? '') as String,
      content: (json['content'] ?? '') as String,
      changeNote: (json['changeNote'] ?? json['change_note']) as String?,
      createdAt: DateTime.parse(rawCreatedAt).toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'entryId': entryId,
        'versionNumber': versionNumber,
        'title': title,
        'content': content,
        'changeNote': changeNote,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}

class CloudSyncEnvelope {
  final int schemaVersion;
  final String deviceId;
  final DateTime exportedAt;
  final List<ProjectModel> projects;
  final List<EntryModel> entries;
  final List<EntryVersionModel> versions;

  const CloudSyncEnvelope({
    this.schemaVersion = 2,
    required this.deviceId,
    required this.exportedAt,
    required this.projects,
    required this.entries,
    required this.versions,
  });

  factory CloudSyncEnvelope.fromJson(Map<String, dynamic> json) {
    final rawExportedAt = (json['exportedAt'] ?? json['exported_at']) as String;
    return CloudSyncEnvelope(
      schemaVersion: (json['schemaVersion'] ?? json['schema_version'] ?? 2) as int,
      deviceId: (json['deviceId'] ?? json['device_id'] ?? 'unknown') as String,
      exportedAt: DateTime.parse(rawExportedAt).toUtc(),
      projects: ((json['projects'] as List?) ?? const [])
          .map((item) => ProjectModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      entries: ((json['entries'] as List?) ?? const [])
          .map((item) => EntryModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      versions: ((json['versions'] as List?) ?? const [])
          .map((item) => EntryVersionModel.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'deviceId': deviceId,
        'exportedAt': exportedAt.toUtc().toIso8601String(),
        'projects': projects.map((p) => p.toJson()).toList(),
        'entries': entries.map((e) => e.toJson()).toList(),
        'versions': versions.map((v) => v.toJson()).toList(),
      };
}
