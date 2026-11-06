import Foundation
import GRDB

/// All database schema migrations, registered in order.
enum Migrations {

    /// Register all migrations with the migrator.
    static func registerAll(_ migrator: inout DatabaseMigrator) {
        registerV1(migrator: &migrator)
        registerV2ExecutionLogDiagnostics(migrator: &migrator)
        registerV3ExecutionLogInteractionDiagnostics(migrator: &migrator)
        registerV4EntryTags(migrator: &migrator)
        registerV5DropUnusedEntryTagsIndex(migrator: &migrator)
        registerV6RetireEntrySortOrder(migrator: &migrator)
        registerV7WorkspaceVersionsAndSync(migrator: &migrator)
    }

    // MARK: - V1: Initial Schema

    private static func registerV1(migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_create_tables") { db in
            PPLogger.database.info("Running migration: v1_create_tables")

            // ----- projects -----
            try db.create(table: "projects") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("name", .text).notNull()
                t.column("is_default", .boolean).notNull().defaults(to: false)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            // ----- entries -----
            try db.create(table: "entries") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("project_id", .text).notNull()
                    .references("projects", onDelete: .restrict)
                t.column("title", .text).notNull()
                t.column("content", .text).notNull()
                t.column("type", .text).notNull().defaults(to: "prompt")
                t.column("is_pinned", .boolean).notNull().defaults(to: false)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("use_count", .integer).notNull().defaults(to: 0)
                t.column("last_used_at", .datetime)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(indexOn: "entries", columns: ["project_id"])

            // ----- entries_fts (FTS5 for full-text search) -----
            try db.execute(sql: """
                CREATE VIRTUAL TABLE entries_fts USING fts5(
                    title,
                    content,
                    content='entries',
                    content_rowid='rowid'
                )
                """)

            // FTS sync triggers: keep entries_fts in sync with entries
            try db.execute(sql: """
                CREATE TRIGGER entries_ai AFTER INSERT ON entries BEGIN
                    INSERT INTO entries_fts(rowid, title, content)
                    VALUES (new.rowid, new.title, new.content);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER entries_ad AFTER DELETE ON entries BEGIN
                    INSERT INTO entries_fts(entries_fts, rowid, title, content)
                    VALUES ('delete', old.rowid, old.title, old.content);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER entries_au AFTER UPDATE ON entries BEGIN
                    INSERT INTO entries_fts(entries_fts, rowid, title, content)
                    VALUES ('delete', old.rowid, old.title, old.content);
                    INSERT INTO entries_fts(rowid, title, content)
                    VALUES (new.rowid, new.title, new.content);
                END
                """)

            // ----- app_settings -----
            try db.create(table: "app_settings") { t in
                t.column("key", .text).notNull().primaryKey()
                t.column("value", .text)
            }

            // ----- execution_logs -----
            try db.create(table: "execution_logs") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("entry_id", .text).notNull()
                t.column("project_id", .text).notNull()
                t.column("front_app_bundle_id", .text)
                t.column("has_accessibility", .boolean).notNull()
                t.column("clipboard_success", .boolean).notNull()
                t.column("paste_attempted", .boolean).notNull()
                t.column("paste_success", .boolean).notNull()
                t.column("result", .text).notNull()
                t.column("created_at", .datetime).notNull()
            }
            try db.create(indexOn: "execution_logs", columns: ["created_at"])

            // ----- Seed: Create the default project ("通用项目") using V1 columns -----
            let now = Date()
            let defaultProjectId = UUID().uuidString
            try db.execute(
                sql: """
                    INSERT INTO projects (id, name, is_default, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [defaultProjectId, Constants.defaultProjectName, true, now, now]
            )
            PPLogger.database.info("Default project created with ID: \(defaultProjectId)")

            // Persist the default project as current project
            try AppSetting(key: Constants.SettingsKey.currentProjectId, value: defaultProjectId).insert(db)
        }
    }

    private static func registerV2ExecutionLogDiagnostics(migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v2_execution_log_diagnostics") { db in
            PPLogger.database.info("Running migration: v2_execution_log_diagnostics")

            try db.alter(table: "execution_logs") { t in
                t.add(column: "observed_app_bundle_id", .text)
                t.add(column: "failure_reason", .text)
                t.add(column: "total_duration_ms", .integer)
            }
        }
    }

    private static func registerV3ExecutionLogInteractionDiagnostics(migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v3_execution_log_interaction_diagnostics") { db in
            PPLogger.database.info("Running migration: v3_execution_log_interaction_diagnostics")

            try db.alter(table: "execution_logs") { t in
                t.add(column: "trigger_source", .text)
                t.add(column: "target_app_restore_duration_ms", .integer)
            }
        }
    }

    private static func registerV4EntryTags(migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v4_entry_tags") { db in
            PPLogger.database.info("Running migration: v4_entry_tags")

            try db.alter(table: "entries") { t in
                t.add(column: "tags", .text).notNull().defaults(to: "[]")
            }
        }
    }

    private static func registerV5DropUnusedEntryTagsIndex(migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v5_drop_unused_entry_tags_index") { db in
            PPLogger.database.info("Running migration: v5_drop_unused_entry_tags_index")
            try db.execute(sql: "DROP INDEX IF EXISTS index_entries_on_tags")
        }
    }

    // MARK: - V6: Retire entries.sort_order

    private static func registerV6RetireEntrySortOrder(migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v6_retire_entry_sort_order") { db in
            PPLogger.database.info("Running migration: v6_retire_entry_sort_order")
            let cleared = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE sort_order <> 0") ?? 0
            try db.execute(sql: "UPDATE entries SET sort_order = 0 WHERE sort_order <> 0")
            PPLogger.database.info("Cleared stale sort_order on \(cleared) entries")
        }
    }

    // MARK: - V7: Workspace Group Kinds, Archive, Todo Completion, Entry Versions & Cloud Sync Support

    private static func registerV7WorkspaceVersionsAndSync(migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v7_workspace_versions_and_sync") { db in
            PPLogger.database.info("Running migration: v7_workspace_versions_and_sync")

            try db.alter(table: "projects") { t in
                t.add(column: "group_kind", .text).notNull().defaults(to: "project")
                t.add(column: "is_archived", .boolean).notNull().defaults(to: false)
                t.add(column: "icon_name", .text)
                t.add(column: "deleted_at", .datetime)
            }

            // Default project ("通用项目") acts as the primary built-in reusable category
            try db.execute(sql: "UPDATE projects SET group_kind = 'category' WHERE is_default = 1")

            // Seed the built-in Inbox ("速记与待办") if not already present
            let existingInboxCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM projects WHERE group_kind = 'inbox' OR id = ?",
                arguments: [Constants.inboxProjectId]
            ) ?? 0
            if existingInboxCount == 0 {
                let now = Date()
                let inboxProject = Project(
                    id: Constants.inboxProjectId,
                    name: Constants.inboxProjectName,
                    isDefault: false,
                    groupKind: .inbox,
                    isArchived: false,
                    iconName: "tray.fill",
                    createdAt: now,
                    updatedAt: now
                )
                try inboxProject.insert(db)
            }

            try db.alter(table: "entries") { t in
                t.add(column: "is_completed", .boolean).notNull().defaults(to: false)
                t.add(column: "source_entry_id", .text)
                t.add(column: "deleted_at", .datetime)
            }

            try db.create(table: "entry_versions") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("entry_id", .text).notNull()
                    .references("entries", onDelete: .cascade)
                t.column("version_number", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("content", .text).notNull()
                t.column("change_note", .text)
                t.column("created_at", .datetime).notNull()
            }
            try db.create(indexOn: "entry_versions", columns: ["entry_id", "version_number"])

            // Backfill initial v1 version snapshots for existing entries
            let existingRows = try Row.fetchAll(
                db,
                sql: "SELECT id, title, content, updated_at FROM entries"
            )
            for row in existingRows {
                let entryId: String = row["id"]
                let title: String = row["title"]
                let content: String = row["content"]
                let updatedAt: Date = row["updated_at"]
                let version = EntryVersion(
                    entryId: entryId,
                    versionNumber: 1,
                    title: title,
                    content: content,
                    changeNote: "初始版本",
                    createdAt: updatedAt
                )
                try version.insert(db)
            }

            try db.create(table: "sync_metadata") { t in
                t.column("key", .text).notNull().primaryKey()
                t.column("value", .text)
                t.column("updated_at", .datetime).notNull()
            }
        }
    }
}
