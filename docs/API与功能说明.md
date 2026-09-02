# PromptPanel API 与功能说明

更新时间：`2026-06-09`

PromptPanel 当前没有 HTTP API、云端 API 或公开 SDK。这里的“API”指项目对维护者和贡献者暴露的稳定契约：用户功能契约、内部服务接口、数据库结构、脚本入口、环境变量和搜索行为。

## 1. 用户功能契约

| 功能 | 用户可见行为 | 维护约束 |
| --- | --- | --- |
| 快捷面板 | 全局快捷键唤出面板，搜索框自动聚焦。 | 面板打开后必须尽快可输入；任何改动都要保留键盘优先路径。 |
| 搜索 | 输入标题或正文关键词实时过滤。 | 空查询是浏览模式；非空查询走 FTS5；结果上限保持可控。 |
| 项目隔离 | 当前项目词条 + `通用项目` 同时展示。 | 默认项目不可删除；跨项目排序不能让默认项目覆盖当前项目优先级。 |
| 标签过滤 | 查询里第一个 `#tag` 作为标签过滤。 | 标签过滤是 FTS 结果后的本地过滤，不能破坏普通关键词搜索。 |
| 执行词条 | 回车或点击词条后，内容进入目标输入框。 | 剪贴板写入是硬保证；自动粘贴是尽力而为。 |
| 仅复制 | `Command-C` 可复制选中词条并关闭面板。 | 不应触发自动粘贴，不应改变词条正文。 |
| 面板固定 | 图钉按钮或 `Command-P` 切换固定状态。 | 固定面板时目标 app 跟踪仍要可靠，避免粘贴回 PromptPanel。 |
| 词库导入导出 | 设置页维护区支持 JSON / Markdown 导入导出。 | JSON 用于无损迁移；Markdown 用于审阅和轻量迁移；导入写库前必须自动创建本地备份；写入阶段必须保持单事务，失败整体回滚。 |
| 运行健康 | 主窗口展示最近执行状态和运行诊断。 | 执行日志不能保存词条正文。 |
| 备份恢复 | 启动备份、恢复脚本和恢复演练保护本地 SQLite。 | migration 失败不能自动擦库；损坏库隔离和 migration 失败是不同事件。 |

## 2. 内部服务接口

PromptPanel 的核心分层是：

```text
AppDelegate / AppState
  -> Services
  -> Repositories
  -> SQLite / Integrations
  -> SwiftUI/AppKit Views
```

主要服务：

| 服务 | 路径 | 契约 |
| --- | --- | --- |
| `PanelService` | `Sources/PromptPanel/Core/Services/PanelService.swift` | 管理 `NSPanel` 生命周期、位置、尺寸、焦点、目标 app 跟踪。 |
| `EntrySearchService` | `Sources/PromptPanel/Core/Services/EntrySearchService.swift` | 包装词条搜索，负责当前项目 + 默认项目的作用域和搜索日志。 |
| `ExecuteService` | `Sources/PromptPanel/Core/Services/ExecuteService.swift` | 编排执行链路：剪贴板、关闭面板、恢复目标 app、权限检查、自动粘贴、日志。 |
| `PermissionService` | `Sources/PromptPanel/Core/Services/PermissionService.swift` | 读取并引导辅助功能权限。 |
| `StorageMaintenanceService` | `Sources/PromptPanel/Core/Services/StorageMaintenanceService.swift` | 启动备份、备份保留、日志保留、恢复入口辅助。 |
| `LibraryTransferService` | `Sources/PromptPanel/Core/Services/LibraryTransferService.swift` | JSON / Markdown 词库导入导出；解析校验后、写库前创建手动备份，导入写入必须在单个 SQLite 事务内完成。 |
| `QuickPanelViewModel` | `Sources/PromptPanel/Features/Panel/QuickPanelViewModel.swift` | 面板状态、搜索调度、项目切换、快捷键动作和执行入口。 |
| `MainWindowViewModel` | `Sources/PromptPanel/Features/MainWindow/MainWindowViewModel.swift` | 内容库、项目维护、词条编辑、设置和运行健康入口。 |

服务约束：

- View 不直接写数据库。
- ViewModel 不承担底层 AppKit 集成逻辑，除非是 UI 必须处理的输入事件。
- 系统 API 接入优先放在 `Integrations/`，业务编排放在 `Core/Services/`。
- 新增长期持久化设置必须进入 `Constants.SettingsKey`、`SettingsRepository`、配置文档和测试。

## 3. 数据模型与数据库契约

默认数据库路径：

```text
~/Library/Application Support/PromptPanel/promptpanel.db
```

主要表：

| 表 | 用途 | 关键字段 |
| --- | --- | --- |
| `projects` | 项目分组。 | `id`, `name`, `is_default`, `created_at`, `updated_at` |
| `entries` | Prompt / snippet / template 词条。 | `project_id`, `title`, `content`, `type`, `is_pinned`, `sort_order`, `use_count`, `last_used_at`, `tags` |
| `entries_fts` | FTS5 全文索引。 | `title`, `content` |
| `app_settings` | 本地设置键值。 | `key`, `value` |
| `execution_logs` | 执行诊断。 | `entry_id`, `project_id`, `front_app_bundle_id`, `observed_app_bundle_id`, `failure_reason`, `total_duration_ms` |
| `grdb_migrations` | GRDB migration 记录。 | `identifier` |

当前 migration 链：

| 版本 | 名称 | 说明 |
| --- | --- | --- |
| v1 | `v1_create_tables` | 初始表、FTS5、触发器、默认项目。 |
| v2 | `v2_execution_log_diagnostics` | 增加目标 app、失败原因和总耗时。 |
| v3 | `v3_execution_log_interaction_diagnostics` | 增加触发来源和目标 app 恢复耗时。 |
| v4 | `v4_entry_tags` | 给词条增加 JSON 字符串数组形式的 `tags` 字段。 |
| v5 | `v5_drop_unused_entry_tags_index` | 删除未使用的历史 tags 索引。 |

数据约束：

- `entries.tags` 存储为 JSON 字符串数组，解码失败时退为空数组，避免单条坏数据拖垮应用。
- 执行日志只保存诊断元数据，不保存 `entries.content`。
- SQLite 使用 WAL；数据库目录权限应保持 `0700`，数据库文件权限应保持 `0600`。
- `PROMPTPANEL_ERASE_ON_SCHEMA_CHANGE=1` 只允许用于明确的本地开发破坏性调试，不能作为发布或用户恢复方案。

## 4. 搜索契约

搜索入口：

```swift
EntrySearchService.search(query:currentProjectId:defaultProjectId:)
EntryRepository.search(query:projectIds:currentProjectId:)
```

排序优先级：

```text
is_pinned DESC
frecency DESC            -- use_count * recency weight, see EntryRanking
last_used_at DESC
use_count DESC
current project before default project when tied
updated_at DESC
id ASC
```

`frecency` 展开后是：

```sql
entries.use_count * (CASE
    WHEN entries.last_used_at IS NULL THEN 0
    WHEN age_days <   4 THEN 100
    WHEN age_days <  14 THEN  70
    WHEN age_days <  31 THEN  50
    WHEN age_days <  90 THEN  30
    WHEN age_days < 180 THEN  10
    ELSE 1
END)
-- age_days = CAST(julianday('now') - julianday(entries.last_used_at) AS INTEGER)
```

`sort_order` 自 v1.3.0 起不参与排序，列保留仅为兼容导入导出格式。

FTS 查询规则：

- 空查询返回当前项目和默认项目的浏览结果。
- 非空查询会拆分空白 token。
- 每个 token 会转换成 FTS5 prefix query，例如 `review bug` -> `"review"* "bug"*`。
- 查询中第一个 `#tag` 会从 FTS 查询中移除，并在结果上按 `Entry.tags` 二次过滤。
- 搜索结果限制为 100 条，防止面板一次加载过多结果。

## 4.1 词库导入契约

导入入口：

```swift
LibraryTransferService.importJSON(from:)
LibraryTransferService.importMarkdown(from:)
ProjectRepository.writeInTransaction(_:)
```

导入顺序：

1. 读取、解析并校验导入文件。
2. 创建手动备份，作为后续写库风险的恢复边界。
3. 在同一个 SQLite 写事务里映射项目、upsert 项目、upsert 词条。
4. 任一写入失败时回滚全部本次写入。
5. 返回导入摘要，由调用方刷新主窗口状态、计数和运行健康。

约束：

- 默认项目导入时映射到本机默认项目，不创建第二个默认项目。
- 词条标题和标签在写入前归一化。
- 写库前备份是恢复边界，不属于写事务。
- 不允许绕过 `LibraryTransferService` 直接在 UI 或 ViewModel 中逐条写入导入数据。

## 5. 脚本接口

| 脚本 | 用途 | 常用命令 |
| --- | --- | --- |
| `scripts/build-app.sh` | 构建 `.app` 和 zip。 | `./scripts/build-app.sh --output-dir /tmp/promptpanel-build` |
| `scripts/release-readiness.sh` | 发布就绪检查。 | `./scripts/release-readiness.sh --output-dir /tmp/promptpanel-ready-check` |
| `scripts/notarize-app.sh` | Developer ID 公证、staple、Gatekeeper 检查。 | 见 [部署说明](./部署说明.md)。 |
| `scripts/restore-backup.sh` | 从 SQLite 备份恢复到目标数据目录。 | `./scripts/restore-backup.sh --dry-run <backup.sqlite>` |
| `scripts/launch-computer-use.sh` | 面向 UI QA / Computer Use 的指定窗口启动。 | `./scripts/launch-computer-use.sh --surface panel` |
| `scripts/capture-ui-qa.sh` | 截取 UI QA 快照。 | `./scripts/capture-ui-qa.sh` |
| `scripts/check-docs.sh` | 文档、搜索索引和结构化元数据门禁。 | `./scripts/check-docs.sh` |

## 6. 环境变量

| 环境变量 | 用途 | 风险边界 |
| --- | --- | --- |
| `PROMPTPANEL_APP_SUPPORT_DIR` | 覆盖数据目录，用于 QA 或 release smoke。 | 不应写进用户长期启动配置。 |
| `PROMPTPANEL_LOGS_DIR` | 覆盖日志目录，用于隔离验证。 | 不应覆盖到公共目录。 |
| `PROMPTPANEL_ALLOW_EXISTING_INSTANCE` | 允许隔离 smoke 与已运行实例并存。 | 只用于测试；正式运行仍应单实例。 |
| `PROMPTPANEL_ERASE_ON_SCHEMA_CHANGE` | schema 变化时允许擦库重建。 | 破坏性，仅限本地开发。 |

## 7. 对外没有的 API

为避免误解，当前没有以下能力：

- 没有 HTTP server。
- 没有云端同步 API。
- 没有团队空间 API。
- 没有浏览器扩展 API。
- 没有远程执行或 agent 编排 API。

导入/导出已经按本地文件契约实现，不提供远端服务。维护格式兼容性时优先保持 JSON 无损迁移，Markdown 保持可人工审阅。
