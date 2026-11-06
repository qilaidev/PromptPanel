# PromptPanel API 与功能说明

更新时间：`2026-11-06`

PromptPanel 桌面端本身是一个纯本地优先的原生应用（不暴露本地后台监听端口）；同时仓库提供可选的开源自托管同步服务端（`server/`）供有跨设备协同需求的用户自行部署。这里的“API”主要指项目对维护者和贡献者暴露的稳定契约：用户功能契约、内部服务接口、数据库结构、脚本入口、环境变量和搜索行为。

## 1. 用户功能契约

| 功能 | 用户可见行为 | 维护约束 |
| --- | --- | --- |
| 快捷面板 | 全局快捷键唤出面板，搜索框自动聚焦。 | 面板打开后必须尽快可输入；任何改动都要保留键盘优先路径。 |
| 搜索 | 输入标题、正文或标签关键词实时过滤（FTS5 前缀 + `INSTR` 子串兜底）。 | 空查询是浏览模式；非空查询结合 FTS5 与子串匹配；结果上限 100 条。 |
| 三层工作区与项目隔离 | 侧边栏分为 `速记与待办`（内置 Inbox）、`常用类型`（含默认 `通用项目`）、`项目管理`（可一键归档）。快捷面板展示当前项目词条 + `通用项目`。 | 内置系统分组（`通用项目` 与 `速记与待办`）不可删除；已归档项目在快捷面板切换器中自动隐藏。 |
| 双窗参考与剪贴板装配台 | 主窗口点击 `参考窗口` 打开伴侣窗，可边看常用类型模板或系统剪贴板，边一键克隆到目标项目。 | 克隆后词条记录 `source_entry_id`，在目标项目内修改不能反向污染源模板。 |
| 词条版本历史与回滚 | 词条每次修改标题或正文自动保存 `EntryVersion`（`v1`, `v2`, …），支持查看历史与一键恢复。 | 回滚前必须先将当前未归档状态存为新版本，保证历史链条单调递增且零丢失。 |
| 标签过滤 | 查询里第一个 `#tag` 作为标签过滤。 | 标签过滤下沉到 SQL `LIMIT 100` 截断前执行，不能因 100 条截断漏掉匹配标签的词条。 |
| 执行词条 | 回车或点击词条后，内容进入目标输入框。 | 剪贴板写入是硬保证；自动粘贴是尽力而为。 |
| 仅复制 | 快捷面板 `Command-C`（或右键菜单）可复制选中词条并关闭面板；主窗口内容库用 `Shift-Command-C` 复制选中词条。 | 不应触发自动粘贴，不应改变词条正文；主窗口普通 `Command-C` 留给预览区文本选区复制。 |
| 主窗口键盘导航 | 内容库支持 `Command-F` 聚焦搜索、`Command-N` 新建词条、`Command-E` 编辑选中词条、`↑`/`↓` 上下切换选中词条。 | 方向键导航在输入法组字（`hasMarkedText`）或存在文本选区时必须让位给输入框本身。 |
| 面板固定 | 图钉按钮或 `Command-P` 切换固定状态。 | 固定面板时目标 app 跟踪仍要可靠，避免粘贴回 PromptPanel。 |
| 词库导入导出 | 设置页维护区支持 JSON / Markdown 导入导出。 | JSON 用于无损迁移；Markdown 用于审阅和轻量迁移；导入写库前必须自动创建本地安全快照备份（`import` 类型）；写入阶段必须保持单事务，失败整体回滚。 |
| 可选多端同步 | 设置页偏好区支持配置本地网盘文件路径或自托管 `server/` 同步地址。 | 默认关闭且零网络调用；并发修改冲突时自动将被覆盖的本地版本转存进 `entry_versions` 历史记录。 |
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
| `LibraryTransferService` | `Sources/PromptPanel/Core/Services/LibraryTransferService.swift` | JSON / Markdown 词库导入导出；解析校验后、写库前调用 `createImportSafetyBackup()` 创建导入安全快照，导入写入必须在单个 SQLite 事务内完成。 |
| `CloudSyncService` | `Sources/PromptPanel/Core/Services/CloudSyncService.swift` | 可选的本地网盘文件或自托管 HTTP/HTTPS 同步信封（`CloudSyncEnvelope v2`）导入导出与冲突自动转存历史版本（`EntryVersion`）。 |
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
| `projects` | 工作区分组（速记与待办 / 常用类型 / 项目）。 | `id`, `name`, `is_default`, `group_kind`, `is_archived`, `icon_name`, `created_at`, `updated_at`, `deleted_at` |
| `entries` | Prompt / snippet / todo / note 词条。 | `project_id`, `title`, `content`, `type`, `is_pinned`, `is_completed`, `sort_order`, `use_count`, `last_used_at`, `source_entry_id`, `tags`, `deleted_at` |
| `entry_versions` | 词条历史版本快照。 | `id`, `entry_id`, `version_number`, `title`, `content`, `change_note`, `created_at` |
| `entries_fts` | FTS5 全文索引。 | `title`, `content` |
| `app_settings` | 本地设置键值。 | `key`, `value` |
| `sync_metadata` | 可选多端同步元数据。 | `key`, `value`, `updated_at` |
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
| v6 | `v6_retire_entry_sort_order` | 清零历史 `entries.sort_order`，排序全面改用 frecency（列保留仅兼容归档导入导出）。 |
| v7 | `v7_workspace_versions_and_sync` | 新增工作区三层角色（`group_kind`）、归档状态、内置 `速记与待办`、待办完成态、`entry_versions` 历史版本表及 `sync_metadata` 同步元数据表。 |

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
EntryRepository.searchAll(query:)
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

`frecency` 由注册进 SQLite 的 Swift 标量函数计算，SQL 里写作：

```sql
pp_frecency(entries.use_count, entries.last_used_at, ?)   -- 第三个参数是 now
```

公式为 `use_count × 2^(-闲置天数 / 90)`：每闲置 90 天权重减半，从未使用记 0，
未来时间戳按 0 天处理。实现见 `EntryRanking`；SQL 与内存排序调用同一份代码。

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
2. 调用 `StorageMaintenanceService.createImportSafetyBackup()` 创建导入前安全快照（`import` 类型备份，保留最近 5 份），作为后续写库风险的恢复边界。
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
| `PROMPTPANEL_TRACE_SQL` | 打开 GRDB 语句级 trace 日志。 | 只用于排查 SQL；开启后日志量与查询行数同量级。 |
| `PROMPTPANEL_QA_SNAPSHOT_PATH` | 在自动打开 QA 窗口后将窗口位图直接输出到指定 PNG 路径。 | 供 `capture-ui-qa.sh` 在无屏幕录制 TCC 权限时采集窗口级截图。 |

## 7. 对外没有的 API

为避免误解，当前没有以下能力：

- 没有 HTTP server。
- 没有云端同步 API。
- 没有团队空间 API。
- 没有浏览器扩展 API。
- 没有远程执行或 agent 编排 API。

导入/导出已经按本地文件契约实现，不提供远端服务。维护格式兼容性时优先保持 JSON 无损迁移，Markdown 保持可人工审阅。
