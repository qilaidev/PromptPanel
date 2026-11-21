import Foundation
import GRDB

/// Key-value settings stored in the database.
struct AppSetting: Codable, Equatable {
    /// Setting key (primary key).
    var key: String
    /// Setting value.
    var value: String?
}

// MARK: - GRDB Conformance

extension AppSetting: FetchableRecord, PersistableRecord {
    static let databaseTableName = "app_settings"

    enum Columns: String, ColumnExpression {
        case key
        case value
    }
}

// MARK: - Sync Metadata Keys & Shared Sync State Types

enum SyncMetadataKey {
    static let deviceId = "device_id"
    static let localMutationSeq = "local_mutation_seq"
    static let lastSyncedMutationSeq = "last_synced_mutation_seq"
    static let lastSyncedRevision = "last_synced_revision"
    static let lastSyncedTargetKey = "last_synced_target_key"
    static let lastSyncedContentFingerprint = "last_synced_content_fingerprint"
    static let lastSyncedFingerprint = "last_synced_fingerprint"
    static let usageDirty = "usage_dirty"
    static let lastSyncSummary = "last_sync_summary"
    static let lastSyncReportJson = "last_sync_report_json"
    static let pendingAllowMassDelete = "pending_allow_mass_delete"
    static let highWaterActiveEntries = "high_water_active_entries"
    static let lastSyncedActiveEntries = "last_synced_active_entries"
    static let lastSyncedActiveProjects = "last_synced_active_projects"
}

enum CloudSyncActionMode: String, Codable, Equatable, Sendable, CaseIterable {
    case smartBidirectional = "smart_bidirectional"
    case pullOnly = "pull_only"
    case forcePushLocal = "force_push_local"

    var displayName: String {
        switch self {
        case .smartBidirectional: return "双向智能合并"
        case .pullOnly: return "仅拉取云端"
        case .forcePushLocal: return "强制以本机覆盖云端"
        }
    }
}

enum CloudSyncDirection: String, Codable, Equatable, Sendable {
    case bidirectional = "bidirectional"
    case pulledOnly = "pulled_only"
    case pushedOnly = "pushed_only"
    case alignedNoChange = "aligned_no_change"
    case forcedLocalOverwrite = "forced_local_overwrite"
    case failed = "failed"

    var displayName: String {
        switch self {
        case .bidirectional: return "双向合并"
        case .pulledOnly: return "仅拉取云端"
        case .pushedOnly: return "仅推送本地"
        case .alignedNoChange: return "已对齐·无变更"
        case .forcedLocalOverwrite: return "强制本机覆盖"
        case .failed: return "同步失败"
        }
    }
}

struct CloudSyncReport: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let isAutoSync: Bool
    let modeLabel: String
    let actionMode: CloudSyncActionMode
    let direction: CloudSyncDirection
    let channelKind: String
    let deviceId: String
    let remoteRevision: Int?
    let pulledProjectsCreated: Int
    let pulledProjectsUpdated: Int
    let pulledEntriesCreated: Int
    let pulledEntriesUpdated: Int
    let pulledDeletionsCount: Int
    let pushedChangesCount: Int
    let skippedPushReason: String?
    let conflictsPreserved: Int
    let orphansMigrated: Int
    let protectedEntriesCount: Int
    let protectedProjectsCount: Int
    let hasPendingLocalChanges: Bool
    let pendingLocalMutationDelta: Int
    let syncedAt: Date
    let errorMessage: String?
    let summaryText: String
}

struct SoftDeletedEntryItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let previewLine: String
    let projectId: String
    let projectName: String
    let type: String
    let deletedAt: Date
    let updatedAt: Date
}
