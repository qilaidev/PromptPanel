# Changelog

All notable changes to PromptPanel are tracked here.

The format is based on Keep a Changelog, and this project uses Conventional Commits for commit messages.

## [1.8.0] - 2026-11-21

PromptPanel 全新基线版本（`1.8.0+18`）：围绕**多设备智能双向同步与清晰可观测 UI**、**`Ctrl+C` 与快捷键全局/局部防护**、**词条与分类逻辑一致性重构**、**`entry_tags` 索引与全链路性能优化**，以及 **macOS 原生视觉与毛玻璃/自适应 HUD 精修**完成系统性升级。

### Added & Improved

- **多设备智能双向同步、乐观锁并发防护与清晰同步 UI（`CloudSyncService` / `AppSettings` / `server/promptpanel_sync_server.py` / `mobile/android/assets/index.html` / `MainWindowView` / `SettingsView`）。**
  - **智能双向同步与显式模式**：默认「立即双向同步」与自动同步严格执行 `Pull → 确定性 Merge → 条件 Push`（仅当 `local_mutation_seq` 推进或本地存在未上云变更时才发起 `POST`，本地无新增修改时不盲推覆盖）；新增显式 `.pullOnly`（「仅从云端拉取合并」）与二次确认的 `.forcePushLocal`（「强制以本机覆盖云端」），本地文件/iCloud 同步引入 `NSFileCoordinator` 与 `SHA256` 写前并发校验。
  - **服务端乐观锁与墓碑防复活**：服务端 `GET /v1/sync` 返回 `ETag`、`serverRevision` 与 `serverTime`；`POST /v1/sync` 支持 `expectedRevision` / `If-Match` 与 `strictConflict` 冲突检测（`409 Conflict` 自动触发客户端 `Pull → Merge → Retry` 重试闭环，同时向后兼容旧客户端并返回 `rebased: true`）；修复孤儿活跃词条自动复活已软删非内置分组的缺陷（改为安全迁移至默认活跃分组并统计 `orphansMigrated`）；统一熔断统计排除 `isCompleted` 待办，支持用户主动批量删除确认标记；本地纯使用计数变更（`usage_dirty`）不再推高 `local_mutation_seq` 触发全量重传，彻底消除异步同步飞行途中并发编辑漏传的 TOCTOU 漏洞。
  - **全端同步可观测 UI 与 30 天回收站**：主窗口顶栏新增实时同步状态胶囊与详情 Popover（支持一键双向同步及查看模式、云端版本 `r<rev>`、上次方向与分项计数）；设置页右上角接入 `SyncStatusBadge`、多行「同步状态与遥测概览」卡片、配置未保存提示、401/403 自动暂停鉴权提示条，以及折叠「高级操作」菜单中的「最近 30 天已删除（按条恢复）」回收站弹窗（取代全历史一键复活）；Android 端修复三处 `ep` 未定义 `ReferenceError`、持久化同步运行时游标、遇 `401/403` 自动暂停轮询并对齐同步卡片与「仅拉取云端合并」按钮。

- **`Ctrl+C` 与快捷键全局及局部安全防护（`HotkeyService` / `HotkeyRecorderField` / `KeyAwareSearchField` / `QuickPanelViewModel` / `MainWindowViewModel` / `PanelService` / `ExecuteService` / `ClipboardService` / `PasteService` / `AppDelegate`）。**
  - **高危终端/系统保留键隔离**：`HotkeyService` 与 `HotkeyRecorderField` 明确拦截 `Ctrl+C`、`Ctrl+D`、`Ctrl+Z`、`Ctrl+\` 与系统/菜单保留键（`Cmd+C`/`V`/`X`/`A`/`Z`/`Q`/`W`/`H`/`M` 等），启动时自动清理历史误存的危险全局绑定；引入 `HotkeyRecordingCoordinator` 单点协调多录制芯片的全局热键暂停与恢复竞态。
  - **精确硬件 `keyCode` 映射与局部按键防护**：`QuickPanelViewModel.panelKeyCommand` 与 `MainWindowViewModel.mainWindowKeyCommand` 优先基于硬件 `keyCode` + 精确修饰键集合判断（兼容非拉丁/中文输入法，严防 `Ctrl+C` 误触发复制）；修复 `KeyAwareSearchField` 与 `QuickJotInputField` 在 `Ctrl+Enter` / `Cmd+Enter` 下误提交、`⌥↩` 与 `⇧↩` 行为不一致的问题；移除内容库隐形 `⌘S` 按钮，无未保存改动时不再空写库或生成冗余历史版本；弹窗打开时屏蔽主窗口快捷键，为参考窗口补齐 `Esc` / `⌘W` / `⌘,` 拦截；`PanelService.hasActiveTextSelection` 覆盖预览浮层划选，避免划选文本按 `⌘C` 误复制整条；`QuickPanelViewModel.copySelectionOnly` 统一经 `ExecuteService.resolveAndCopyEntry` 展开动态占位符并尊重 `isPanelPinned` 固定面板状态。
  - **剪贴板快照、物理修饰键等待与终端护栏增强**：`PasteService` 发送模拟粘贴前等待物理修饰键释放（带超时保护）；`ClipboardService` 与 `ExecuteService` 在原剪贴板为空或超大时同样使用 `TransientType` 标记并修复连续快速执行时的恢复竞态；终端识别扩展覆盖 VS Code、Cursor、Windsurf、JetBrains、Tabby、WezTerm、Alacritty、Rio 等，规范换行并剥离末尾换行符。

- **词条管理与分类逻辑一致性重构（`EntryRepository` / `ProjectRepository` / `LibraryTransferService` / `MainWindowViewModel` / `QuickPanelViewModel` / `LibraryView` / `MainWindowView` / `ReferenceLibraryWindowView`）。**
  - **「全部内容」与活跃目标项目统一**：主窗口「全部内容」、`totalEntryCount`、清理已完成、快捷面板及参考窗口统一排除已归档项目；`fetchActiveTargetProjects` 与编辑/迁移/克隆目标列表包含 `速记与待办`（`inboxProject`）且严格禁止迁入已归档项目。
  - **原子字段级编辑与组合筛选**：`EntryRepository.updateEditableFields` 在写事务内重读最新行，仅更新编辑字段而不覆盖并发 `useCount`/`lastUsedAt`，遇到已软删词条返回 `.deletedOrMissing` 绝不复活；解除 `entryKindFilter` 与 `entryTagFilter` 互斥，支持「类型 + 标签」组合筛选并在切组/搜索变化时自动清理失效过滤器；取消主窗口搜索硬编码 `LIMIT 100` 截断；修复恢复历史版本前未取消防抖保存、空正文切换分组选区回滚错位及空白/重名项目与系统分组重命名防护。

- **数据库 `entry_tags` 索引与全链路性能优化（`Migrations` V9 / `DatabaseManager` / `EntryRepository` / `EntryRanking` / `QuickPanelViewModel` / `MainWindowViewModel` / `DesignComponents` / `UpdaterService`）。**
  - **SQLite V9 `entry_tags` 索引表与一次注册函数**：新增 `v9_entry_tags_index_table` 迁移及 `idx_entry_tags_tag_lower` 索引，标签筛选淘汰逐行 `NSLock + JSONDecoder` 解码改走索引查询；`pp_icontains` 在 `DatabaseManager.prepareDatabase` 一次性注册；`EntryRanking` 增加零使用短路与时间戳数值快速路径；`.entryUsageDidChange` 与内容写入解耦，使用词条不再触发 2 秒全量云同步。
  - **防抖、缓存与内存收敛**：面板搜索防抖调整为 `40ms`，参考库与版本历史分别接入 `150ms` / `80ms` 防抖；`QuickPanelViewModel` 缓存 `entryIndexById`，列表行采用时间桶缓存的 `PPRelativeTimeFormatter`，`lastInlineVersionSnapshotAtByEntryId` 限制最近 200 条 LRU 裁剪，`UpdaterService` 补齐 `deinit` 定时器清理。

- **全界面 macOS 原生视觉与毛玻璃/自适应 HUD 精修（`Constants` / `AppTheme` / `DesignComponents` / `QuickPanelView` / `MainWindowView` / `LibraryView` / `SettingsView` / `ReferenceLibraryWindowView` / `ToastService` / `TrayManager` / `AppDelegate`）。**
  - **表面材质、对比度与设计原语**：拉开 Light 模式 `bg` / `surface` / `surfaceRaised` 层级与辅助文字对比度，收敛 `EntryLevel` 彩虹染色；`QuickPanelView` 接入 `.hudWindow` 毛玻璃、`LibraryView` 侧栏接入 `.sidebar` 毛玻璃并支持左右分栏拖拽调宽；主窗口与参考窗口启用透明一体化标题栏消除色差断层；统一 `PPActionButton`、`PPInteractiveButtonStyle`、`.focusableInputSurface` 与分主题 `.themedShadow`。
  - **组件降噪与细节打磨**：清理 `LibraryView` 中 5 处透明 `Menu` 遮罩 Hack 并补齐行拖拽 `.draggable(entry.id)`、修复 hover 操作条文字遮挡及待保存状态文案；`QuickPanelView` 仅在指针悬停时显示行快捷操作（保留键盘选中行元信息）、放宽行高至 `28pt / 32pt`、修复预览标签溢出与底栏提示；`ToastService` 改为顶部居中自适应尺寸毛玻璃 HUD（带淡入淡出动画）；`TrayManager` 补充 SF Symbol 兼容回退。

[1.8.0]: https://github.com/qilaidev/PromptPanel/releases/tag/v1.8.0
