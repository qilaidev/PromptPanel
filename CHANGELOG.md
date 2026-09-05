# Changelog

All notable changes to PromptPanel are tracked here.

The format is based on Keep a Changelog, and this project uses Conventional Commits for commit messages.

## [Unreleased]

## [1.5.0] - 2026-09-06

性能与稳定性版本。设置页里每个维护动作——备份、导出、导入、诊断包——原来都跑在主线程上，
点下去窗口就不再重绘、不再响应点击，看起来像卡死；列表渲染和存储健康刷新也有几处每帧重算
的热点。这一版把这些工作全部挪下主线程，删掉了只有测试在用的仓储写入口，并把设置页从三个
半空的分区收成两个排满的分区。日常使用方式没有变化。

### Fixed

- **点「导出」后窗口长时间无响应。** `NSSavePanel.runModal()` 在主线程上开了一个嵌套 modal 循环，选完路径之后，导出本身又同步跑在主 actor 上：整库 JSON 编码、SQLite 备份、诊断包里的 `OSLogStore.getEntries` 加一个 `ditto` 子进程。窗口在这段时间既不重绘也不接受点击，最后确实导出成功了，但过程读起来就是「卡住了」。现在保存/打开面板以 sheet 形式挂在主窗口上（不再阻塞），实际的 IO 跑在专用串行队列上，顶部横幅在整个过程里显示为进度行，同时暂时停用其余维护按钮以免两个动作抢同一个 SQLite 文件。
- **`Constants.applicationSupportDirectory` 每次读取都在做文件系统调用。** 它是个计算属性，每次求值都会 `createDirectory` + `chmod`；而 `databaseURL`、`backupDirectory(for:)`、`recoveryDirectory(for:)` 全部经过它，这些又被 SwiftUI 的 `body` 和每次存储健康刷新读取。一次设置页重绘因此产生几十次主线程 syscall。现在整个进程只解析一次。
- **存储健康刷新在主线程上做文件 IO 和数据库查询。** `refreshOperationalStatus()` 会枚举备份目录并 stat 每个文件，它在打开窗口、每次维护动作之后、以及**每一次执行日志变化**时都会跑——也就是每粘贴一次词条就卡一下。它和 `refreshLogs()` / `refreshProjectEntryCounts()` 现在都在后台队列上完成，回主线程只做赋值。另外 `healthSnapshot()` 不再顺手创建和 chmod 四个目录，它现在是只读的。
- **`SMAppService.mainApp.status` 挂在权限刷新的主路径上。** 这是一次同步的守护进程往返，而 `refreshPermissionState()` 会在每次 `applicationDidBecomeActive` 时调用——包括保存面板关闭时触发的那一次，正好落在导出交互中间。登录项状态现在异步读取，开关本身也改成先乐观翻转、再用守护进程的真实结果校正。
- **列表行每帧都在处理整条词条正文。** 面板行和词条库行的预览文本对**完整** `content` 做两次 `replacingOccurrences`，再 `components(separatedBy:)` + `joined`。几 KB 的提示词乘以可见行数，就是每次按键几 MB 的字符串搬运，而行本身只显示一行、超出即截断。现在只扫描前 240 个字符，一趟归一化空白。
- **筛选芯片的统计每帧全量重算。** `availableEntryKinds` 和 `topTags()` 都是从 `body` 直接调用的计算属性，各自遍历全部已加载词条，`topTags()` 一帧调三次，`kindCount(for:)` 每个芯片调一次。现在在 `entries` 变化时一趟算完并发布；项目名也改成用 id→name 字典查，不再每行线性扫描项目列表。
- **面板每一行内嵌一个 `GeometryReader`。** 行宽是列表的属性而不是行的属性，把 GeometryReader 放进 `LazyVStack` 的每个 cell 里，等于每次滚动、每次按键都为每行多做一次布局。现在整个列表只测量一次，宽度传给行。
- **面板在「数据变了」时也会把结果清空重建。** `scheduleEntriesRefresh` 无条件 `entries = []`，包括执行完一条词条后仅仅是使用次数变了触发的那次刷新——列表被整个拆掉重建，闪一下再回来。现在按刷新原因区分：查询词或项目范围变化仍然立即清空（这是安全属性，不是闪烁：留着旧结果意味着防抖窗口内按 Enter 或 ⌘1-9 会把用户已经看不到的词条粘进文档，`testQuickPanelClearsResultsWhileAsyncSearchIsPending` 钉住这条）；只有查询和范围都没变、单纯是底层行变了的刷新才保留当前结果并把高亮留在同一条词条上。
- **每次导入词库都会永久留下一份完整数据库副本。** 导入前的安全快照走的是 `createManualBackup()`，于是继承了「手动备份永不自动清理」这条策略——而那条策略是为用户点「立即备份」显式创建的存档准备的，不是为机器自动生成的快照。安全快照现在有自己的 `createImportSafetyBackup()` 和保留数（5 份）；用户手动创建的备份仍然永不自动删除（`testStorageMaintenanceKeepsManualBackupsBeyondAutomaticRetention` 钉住这条）。
- **内容库里发出的状态提示全部被丢弃。** `bannerMessage` 只画在设置页里，所以「已复制到剪贴板」「词条已删除」「保存词条失败」这些在内容库触发的消息，用户一条都看不到。横幅现在由 `MainWindowView` 承载，两个 Tab 共用，可手动关闭，并在 8 秒后自动消失（维护任务进行中除外）。
- **窗口标题栏右侧的「PromptPanel」在 72pt 里折成两行。** 这个标签和系统标题栏本来就重复，直接删掉，只留占位保证分段控件居中。
- **「授权操作」的三个按钮全部被截断成「请…」「系统…」「重新…」。** 带图标的文字胶囊塞不进设置分栏里标签旁边剩下的宽度。授权相关动作现在整宽两列排列。
- **拖动面板边缘时，每一帧都在主线程写一次 SQLite。** `windowDidResize` 在拖拽期间持续到达，`onPanelContentSizeChanged` 直接落盘，完全没有防抖——正好卡在窗口最需要主线程跟手的时候。位置和尺寸现在都走同一个 `SettleWriter`：停止拖动 250ms 后合并成一次写入，写入在后台队列上。
- **「退出前不丢最后一次面板位置」这句注释一直是假的。** `flushPendingPanelOriginPersistence()` 先 `cancel()` 再 `perform()` 同一个 `DispatchWorkItem`，而被取消的 work item 的块**永远不会执行**（已实测确认）——所以终止前的 flush 什么都没写。待写值现在保存在 `SettleWriter` 自身而不是捕获在闭包里，`flush()` 直接写。
- **导入词库后，快捷面板的项目菜单还停在导入前的列表。** `importLibrary` 只刷新了自己，没有广播 `.projectsDidChange` / `.entriesDidChange`，而快捷面板持有独立的项目和词条副本。
- **内容库的选中态渲染是 O(n²)。** `isSelected:` 里读 `viewModel.selectedEntry?.id`，而这个属性会扫描整个 `displayedEntries`——每行扫一遍全表。现在每次重绘只解析一次。
- 关闭主窗口时立刻切回 `.accessory` 会在 AppKit 还没收完窗口时把应用踢出前台，表现为一次卡顿和下一个应用的焦点闪烁；现在延后一个 runloop。
- 设置卡片里最后一行的分隔线原来悬在卡片内边距上，成了一条没有下文的游离细线。
- 版本号字符串在设置页两张卡片里各自从 `Info.plist` 现算一遍、格式还不一致；收敛成 `Constants.appVersionDisplay`。
- `AppDelegate` 里 `schedulePanelOriginPersistence` 的文档注释在某次重构里漂到了 `handlePanelKeyEvent` 头上，两段 `///` 粘在一起。

### Changed

- **设置页从三个分区收成两个。** 八张短卡片摊在 `偏好 / 权限 / 维护` 三个 Tab 上，前两个在 1040×760 里都填不满一半窗口，而 `权限` 的右列直接复用了 `维护` 的「运行概况」——同一组数字画两遍。权限本来就是「设一次」的东西，现已并入 `偏好`；右列换成一张真正的「授权排查」分步指引（原来这些信息散在四行的 `hint:` 文案里）。`设置 → 偏好 → …` 这类已有路径不受影响。
- **维护操作按功能分组。** 十一个同款胶囊挤在一个三列网格里像一堵墙，看不出哪些会动用户数据，最后一行还总是缺口。现在分成「备份与数据」「词库导入导出」「诊断与清理」三组，每组行数取整；「刷新状态」移到「运行概况」卡片标题栏的图标按钮上。
- **新增 `Core/Utils/SettleWriter.swift`。** 把「连续事件 → 合并 → 后台落盘 → 终止前同步 flush」抽成一个原语，面板位置和面板尺寸共用，`DispatchWorkItem` 那个取消陷阱也只需要在一处讲清楚。
- **`docs/开发规范.md` 新增「3.1 主线程规则」。** 给出判断边界（按触发方式而不是耗时估计分类），并把这一轮踩到的具体坑逐条列出：`body` 里不做 I/O 和 O(n) 聚合、`ForEach` 里不读 O(n) 属性、面板用 `beginSheetModal` 不用 `runModal`、跨进程调用一律按不可控工作量处理、连续事件落盘走 `SettleWriter`。
- **日志降噪。** 每次按键一条搜索日志、每次激活一条权限日志、每次写库一条仓储日志，把真正重要的告警埋了。这些降到 `debug`，权限只在状态真正变化时才记 `info`；GRDB 的语句级 trace 从「所有 DEBUG 构建默认开」改为 `PROMPTPANEL_TRACE_SQL=1` 显式开启（一次词库加载会产生每行一条日志）。

### Removed

- **`EntryRepository.updateSortOrder` / `togglePin(id:)` / `moveToProject`。** 三个都只有测试在调用：`sort_order` 在 v6 迁移里已经退役，置顶走 `MainWindowViewModel.togglePin(_:)` → `update`，移动项目只发生在项目删除迁移的事务里。
- `ClipboardService.readText()`、`MainWindowViewModel.loadEntries()` / `openSettingsTab()`，以及面板状态栏里那个所有分支都返回入参的 `displayStatusMessage`。

### Documentation

- **面向读者的版本号从 1.1.2 同步到当前版本。** Info.plist、codemeta.json 和 JSON-LD 一直是对的，因为 `check-docs.sh` 只校验了这两个机器可读出口；八个 README 的 Release 徽章、llms.txt 的「Current release」与 answer-engine 摘要、FAQ 的版本问答、配置说明里的 Info.plist 表全部停在 1.1.2。校验范围已扩到全部读者出口，Info.plist 仍是唯一权威。
- **排序规则的描述改正为 frecency。** 八个 README 都还写着「置顶 → 手动排序 → 最近使用 → 使用次数」，那是 v1.3.0 之前的规则。现在写的是实际生效的 `置顶 → use_count × 2^(-闲置天数 / 90) → 最近使用 → 使用次数`，README 与 FAQ 另加「词条顺序为什么会自己变？」，llms.txt / llms-full.txt / codemeta / JSON-LD 同步补上排序事实。
- **八个 README 补上界面截图与键盘快捷键速查表。** `docs/ui-qa/latest/` 下的截图此前从未被引用，而 README 里已经写着提供 screenshots；快捷键表覆盖面板与主窗口，内容取自 `QuickPanelViewModel.panelKeyCommand` 与 `MainWindowViewModel`（含主窗口复制是 ⇧⌘C 而非 ⌘C）。
- **仓库链接改用规范地址 `qilaidev/PromptPanel`。** 账号改名后旧地址只是重定向。Sparkle feed（`SUFeedURL`，已烧进已发布二进制）、`© 2026 tytsxai` 署名与 CHANGELOG 正文按原样保留。


## [1.4.0] - 2026-09-02

### Changed

- **frecency 换成连续的半衰期衰减，排序不再有台阶。** 1.3.0 用的是按 4 / 14 / 31 / 90 / 180 天分档的整数权重，实测有两个毛病：档位之间是悬崖——一条词条在夜里跨过 31 天那条线，名次会毫无征兆地跳一截；而且 100 → 30 的落差太陡，时效轻易压过 3 倍的频次差，出现「用了 6 次的排在用了 19 次的上面」。现在是 `使用次数 × 2^(-闲置天数 / 90)`：每闲置 90 天权重减半，只有一个参数、一个含义，曲线连续没有跳变。频次重新占主导，而两年没碰过的旧热词依然会沉下去。
- **SQL 侧不再重写公式。** `EntryRanking.databaseFunction` 把 Swift 的打分函数注册成 SQLite 标量函数 `pp_frecency`，仓储层的 `ORDER BY` 和面板内存排序调的是同一份代码。此前是「同一张权重表生成两套实现」，仍留有写歪的余地——而两边一旦不一致，⌘1-9 的编号就会指向错的词条。顺带也不再依赖 SQLite 是否编进了可选数学扩展。

### Fixed

- **快捷面板的行里显示「最近使用」，替掉了「Prompt」标签。** 排序由「使用次数 × 时效」决定，但行里只显示了使用次数——另一半是隐形的，所以「6 次」排在「19 次」上面看起来像坏了。现在显示「今天 / 3天 / 5周 / 7月」这种紧凑相对时间。被替掉的类型标签在词条库里几乎每行都是同一个词，信息量为零，而且行首图标已经在表达类型了。

## [1.3.0] - 2026-09-02

### Changed

- **常用词条现在会自己浮到前面。** 排序改为 frecency：`使用次数 × 最近使用时间的权重`（4 / 14 / 31 / 90 / 180 天分档取 100 / 70 / 50 / 30 / 10，更旧取 1）。此前的规则是 `置顶 → 手动排序值 → 最近使用时间 → 使用次数`，其中**「使用次数」永远不会生效**：它排在 `last_used_at` 后面，而那是个精确到秒的时间戳，两条词条几乎不可能相同，所以频次对顺序毫无影响。实际效果是一条用了 3 次的词条能压在用了 595 次的上面。现在高频词条排在前面，而半年没碰过的旧热词会自己沉下去，不会靠历史总量永久占位。

### Removed

- **退役了 `sort_order`（手动排序值）。** 它的优先级仅次于置顶，却没有任何界面能修改——`updateSortOrder` 全仓库只有测试在调用。从导入档案带进来的值会把词条永久钉在列表顶部，用户既没设过也清不掉。排序不再读这个字段，v6 迁移会把历史值清零；列本身保留，因为 `LibraryTransferService` 的导入导出格式里有 `Sort Order:` 行，删掉会破坏与 1.x 归档的往返兼容。置顶请用词条右键菜单里已有的「置顶」（`is_pinned`）。

## [1.2.0] - 2026-09-02

窗口与交互可靠性版本。快捷面板从横版改为竖版，尺寸与落点按屏幕自适应；⌘1-9 / ⌘C / ⌘P
等面板快捷键此前走的是一条 AppKit 永远不会到达的代码路径，现在真正生效；自动粘贴不再
可能打回 PromptPanel 自己并被记成成功。日常使用方式没有变化。

### Fixed

- **Auto-paste could fire into PromptPanel itself and be logged as a success.** ⌘V is posted to the HID event tap, so it lands wherever focus happens to be. When no target app had been recorded — the panel opened from the tray, or while PromptPanel was already frontmost — `waitForTargetApplicationRestore` returned instantly with no wait and no settle delay, and the mismatch check treated an unknown target as "no mismatch". The keystroke went out microseconds after `orderOut`, usually back into PromptPanel, and the execution log recorded `success` / `pasteSuccess: true`. The wait now also covers the no-known-target case (it waits for focus to leave PromptPanel), and a paste is refused outright whenever the frontmost app is PromptPanel, falling back to clipboard-only with the existing "请手动粘贴" toast.
- **A second PromptPanel instance would silently steal the global hotkey** from the installed app. Two processes can both register the same Carbon shortcut and which one answers is a coin flip — and the one that answers during a QA capture run has a throwaway library and no Accessibility grant, so nothing pastes. Instances started with `PROMPTPANEL_ALLOW_EXISTING_INSTANCE=1` no longer register the hotkey at all; the QA harness opens the panel directly and loses nothing.
- **⌘F, ⌘C and ⌘E were drawn in the library but never implemented.** The search field showed a `⌘F` keycap, and the preview pane's 复制 / 编辑 buttons showed `⌘C` / `⌘E`; ⌘C fell through to the Edit menu's generic Copy and the other two did nothing. ⌘F and ⌘E are now resolved by a key monitor scoped to the main window. Copy-entry moved to **⇧⌘C**: the preview pane's content is selectable, so claiming plain ⌘C would mean a user who highlights part of a prompt and copies it silently gets the whole entry instead.
- **The quick panel had no pointer-driven way to close.** Its titlebar buttons are hidden, click-outside is suppressed while the panel is pinned, and Esc was handled only by the search field — so once focus moved off that field (a background click, a dismissed menu) the panel could not be dismissed at all. There is now an ✕ button in the panel header, and Esc is handled by the panel itself, independent of what holds focus.
- **A failed execution could permanently disable the panel.** `ExecuteService`'s in-flight guard, which stops a double-click from pasting twice, was a plain boolean: had any run failed to clear it, every later click and Enter would have been dropped for the rest of the session with only a log line to show for it. The guard is now bounded by the target-app restore timeout plus slack, so the worst case is a sub-second debounce.
- **⌘1-9 direct execution in the quick panel never fired** ([#2](https://github.com/qilaidev/PromptPanel/issues/2)). The handler lived in `PromptSearchField.keyDown(with:)`, which AppKit never reaches for a ⌘-combination: while the search field is being edited the field editor is first responder, and ⌘-events are resolved through key-equivalent dispatch (the main menu included, which owns ⌘C) before any `keyDown:` runs. The panel's shortcuts now come from a local `NSEvent` monitor installed by `PanelService`, which runs inside `NSApplication.sendEvent(_:)` ahead of all of that; ⌘C and ⌘P went through the same dead path and are fixed with it. ⌘C still copies highlighted text when the search field has a selection, and ⌘4 with three results falls through instead of being swallowed.

### Changed

- **The quick panel is portrait now — 560 × 700 instead of 780 × 440.** The panel is a single-column scanner: search field, result list, footer. Width only has to hold one row; height is what decides how many candidates you can see without scrolling. The old landscape default spent its pixels on the wrong axis and showed about 13 rows — the same area, turned upright (4:5), shows roughly 22. The main window keeps its landscape shape on purpose: its library is a three-column master/detail surface (projects → entries → preview) that cannot be stacked vertically without losing the preview, so it was only tightened from 1100 × 740 to 1040 × 760, and its minimum came down from 1020 × 680 to 920 × 620 so it fits on a 1280 × 800 display. Existing installs keep the panel size they already have; **恢复默认** in settings adopts the new one.
- **The panel opens where a launcher should.** The first-run position was the screen centre offset 12% left and 8% down, which put a tall panel low and off-axis; it is now horizontally centred and anchored in the upper third. Both windows also shrink to fit the display they open on, so a 700pt panel or a 760pt window no longer hangs off the bottom of a small screen — and that fit-to-screen shrink is presentation-only, so opening on a laptop does not overwrite the size and position you chose on a large monitor.
- **Panel rows degrade by column instead of by ellipsis.** A narrow panel used to squeeze the title down while keeping the content preview and the type label; below 470pt the preview column now drops out and the title takes the full width, and below 400pt the type label goes too.
- **Front-end density and typography pass.** Thirteen ad-hoc font sizes (8 → 24pt, half-points included) collapse into a six-step type scale plus a five-step icon scale (`Design.TextSize` / `Design.IconSize`, applied via `Font.ui(_:)` / `Font.icon(_:)`). The smallest labels move up — 8/9/9.5pt text is now 10pt — while padding drops roughly a third across the panel, library, settings and sheets, so information density rises without shrinking text. Row heights, section spacing and card insets are driven from `Constants.Layout`; every divider and border now uses one `Constants.Layout.hairline` (0.5pt) weight, replacing the mixed 0.5pt/1pt rules and the three SwiftUI `Divider()`s in the library column that drew their own heavier separator color.
- The quick panel no longer reserves the ⌘1-9 number gutter while searching, where the numbers are hidden anyway.
- The entry editor's content box grew to 264pt — the tighter chrome around it is spent where the content actually is.

### Fixed (front-end)

- The quick-panel search field rendered typed text at 14pt over a 12.5pt placeholder, so text jumped a point on the first keystroke. Both are the type scale's 13pt step now.
- The library entry list built a `RelativeDateTimeFormatter` per row per render; it is now created once.
- The execution toast used ad-hoc system fonts and a 16pt radius; it now draws from the same type, spacing and hairline tokens as the rest of the app.
- `capture-ui-qa.sh` now probes for Screen Recording permission before it builds or launches anything, and tracks every instance it starts by pid. It previously relied on `pkill -f "$APP_PATH"`, which matches nothing when the repo path contains non-ASCII characters — a QA instance survived its own cleanup trap and kept running against the user's installed app.

## [1.1.2] - 2026-07-28

Distribution-correctness release. Nothing changes in how the app is used day to day; what changes is that a downloaded build is now actually installable and updatable. Two defects that would have surfaced on the first public binary are fixed (invalid code signature, arm64-only "universal" build), the Sparkle update channel is finalized end to end, and the public positioning surfaces now state only what the evidence supports.

### Fixed

- **The packaged `.app` had an invalid code signature.** `build-app.sh` added three app-root symlinks to `Contents/Resources/*.bundle` after signing, to satisfy the SwiftPM `Bundle.module` accessor. Content at the bundle root cannot be sealed, so `codesign --verify` exited 1 (`unsealed contents present in the bundle root`) — not a warning: a quarantined download would be blocked by Gatekeeper on first launch and Sparkle would refuse to install the update. The symlinks are gone and `release-readiness.sh` now verifies signatures with no exemptions, so the failure cannot silently return.
- **The release archive was arm64-only** while the README and FAQ promised a universal binary — an Intel download would simply not run, and the defect was invisible on an Apple Silicon build machine. Release builds now produce `arm64 + x86_64` (native build + cross build + `lipo -create`; `--debug` stays single-arch, overridable with `--arch native|universal`), and the release gate fails if either slice is missing.
- **The seeded `release/appcast.xml` was not well-formed XML**: its explanatory comment contained a double hyphen, so Sparkle's parser rejected the whole feed. Update checks would have failed silently forever — HTTP 200, plausible-looking file, no updates ever offered. The comment is fixed and both `generate-appcast.sh` and the publish workflow now validate the feed before writing or deploying it.
- **The appcast XML check broke the publish workflow**: `xmllint` is no longer preinstalled on `ubuntu-latest`, so the guard itself failed with exit 127. Validation now uses the preinstalled `python3` (expat), with the same fallback in `generate-appcast.sh`.

### Added

- **Sparkle update channel finalized.** The feed URL is pinned to `https://tytsxai.github.io/PromptPanel/appcast.xml`, published from `release/appcast.xml` by `.github/workflows/publish-appcast.yml`; installers ship as GitHub Release assets. `SUFeedURL`/`SUPublicEDKey` are baked into each installed app and cannot be corrected afterwards, so `release-readiness.sh --public-distribution` now fills in the canonical feed URL, requires an EdDSA public key, and asserts both keys are present in the packaged `Info.plist`. `generate-appcast.sh` gained `--tag` (download-URL prefix derived from the remote), `--feed-file` seed merging, a guard against rewriting already-published enclosure URLs when an older archive lingers in the staging directory, and a hard failure when no signing key is available.
- **`HotkeyRecorderField`**, a self-drawn shortcut recorder built only on the public non-UI API of `KeyboardShortcuts`, replacing `KeyboardShortcuts.Recorder` — this is what removed the last runtime dependency on `Bundle.module`. Existing hotkeys are temporarily disabled while recording so the Carbon-registered shortcut cannot swallow the keystroke; Esc cancels and Delete clears as before. Trade-off: the library's "this shortcut is already taken" popup is gone (it used internal API); the Settings hint and FAQ cover the workaround.
- Seven unit tests for the recorder's decision function, plus regression coverage around the signing path.

### Changed

- **`Package.resolved` is now version-controlled.** With `Sparkle from: "2.9.1"` and a GRDB version range, release builds were not reproducible: different machines could ship dependency versions that were never QA'd, invisibly. Locked at GRDB 7.8.0 / KeyboardShortcuts 1.10.0 / Sparkle 2.9.4.
- **README architecture claims now state build facts only.** All eight READMEs previously said Apple Silicon and Intel were both tested; the x86_64 slice has only been exercised through Rosetta, so the claim is now that the release is built as a universal binary that runs natively on both.
- **The Simplified-Chinese-only app interface is disclosed** across all eight READMEs, FAQ, `llms.txt`, `llms-full.txt`, the discoverability doc, `codemeta.json`, and the Schema.org JSON-LD — the docs ship in eight languages and readers (and answer engines) would otherwise assume the UI does too. `check-docs.sh` asserts the disclosure as long as `CFBundleDevelopmentRegion` is `zh-Hans`.
- Simplified the framework-signing helper in `build-app.sh`: collapsed a redundant `case` branch in `sign_framework_contents` whose two arms ran the identical `codesign_path "$helper_path" runtime` command. Signing output is unchanged.
- README search-latency figure corrected to `<80 ms`, matching `Constants.searchLatencyTargetMs`.

### Removed

- **10 UI-QA and draft screenshots (~5.9 MiB) deleted from the repository.** They are regenerable output of `capture-ui-qa.sh` and are now git-ignored; referencing docs and the Schema.org `screenshot` array were updated accordingly.

## [1.1.1] - 2026-07-14

Reliability, security-hardening, and documentation release. No end-user feature changes and no new default network paths: the app stays local-first, and the auto-update channel added here remains dormant unless a feed URL and signing key are configured at build time.

### Added

- **Auto-update release channel wired up**: `scripts/generate-appcast.sh` now generates and EdDSA-signs an `appcast.xml` from a directory of notarized release archives, completing the Sparkle update path (`build-app.sh` already injected the feed URL and public key, but nothing produced the feed clients poll). Daily automatic update checks are enabled (`SUEnableAutomaticChecks`, 24 h interval) while installs still prompt first — no silent install. The channel stays inert in default and source builds because no `SUFeedURL`/`SUPublicEDKey` is baked in unless passed to `build-app.sh` at package time.
- **Localized READMEs** for Japanese, Korean, Traditional Chinese, Spanish, French, and German (in addition to English and Simplified Chinese).

### Security

- **Hardened-runtime library validation kept enabled**: removed `com.apple.security.cs.disable-library-validation` from the shipped entitlements. `build-app.sh` now re-signs `Sparkle.framework` and every embedded helper (Installer.xpc / Downloader.xpc / Autoupdate / Updater.app and nested dylibs) with the hardened runtime and the app's identity, so all loaded code shares one Team ID and passes library validation without the entitlement — closing an unnecessary dylib-injection surface. `release-readiness.sh` now asserts the entitlement is absent and verifies the bundle signature.
- **HTTPS-only Sparkle feed** enforced in both `build-app.sh` and `release-readiness.sh`.
- **Data directory permissions tightened**: the app-support and logs directories are now created with `0700`, so no other local account can read PromptPanel storage — matching the contract already enforced in `DatabaseManager` / `StorageMaintenanceService`.

### Fixed

- **Diagnostics export could hang** when `ditto` emitted a large amount of stderr while packaging the diagnostics bundle: the process was awaited before its error pipe was drained, so a full pipe buffer (~64 KB) would deadlock `waitUntilExit()`. The pipe is now drained before waiting.
- **Accessibility reset could hang** for the same reason: `PermissionService.resetAccessibilityApproval()` (the `tccutil reset` helper) now drains the process output before awaiting exit.
- **Hardened two force-unwraps** that could crash the app: the FTS search statement arguments in `EntryRepository.search` are now built with typed `StatementArguments` instead of a force-unwrapped `[Any]` conversion, and `LogRepository.cleanup` no longer force-unwraps the retention cutoff date.
- **Keyboard-shortcut recorder no longer crashes on first use**: app-root symlinks to `Contents/Resources/*.bundle` are added after signing so the Swift 6 `Bundle.module` accessor resolves resources.

## [1.1.0] - 2026-06-11

First stable feature release after 1.0. Focus areas: lossless library migration, on-device diagnostics, and storage self-maintenance — all still local-first with no new network paths.

### Added

- **Library import/export** (`Settings → Maintenance`): `Export JSON` for lossless full-library transfer, `Export MD` for human-reviewable sharing, `Import JSON` / `Import MD` for migration from another PromptPanel install or a Markdown prompt collection. Every import automatically creates a local database backup first, and all import writes run inside a single SQLite transaction — a failed import rolls back completely instead of leaving a half-written library.
- **Diagnostics export**: one click produces a local diagnostics bundle (app/system info, settings snapshot, recent logs, database health) for troubleshooting and bug reports. Nothing is uploaded; the bundle is a local file you choose to share.
- **Recovery pruning**: automatic cleanup of stale recovery/backup artifacts via the storage maintenance service, keeping the data directory bounded.
- Regression coverage for import rollback and quick-panel manual ordering.

### Changed

- Quick-panel window origin persistence is now debounced, reducing redundant settings writes while dragging the panel.
- Settings window polish: clearer maintenance section layout and runtime-health presentation.
- Hardened distribution path: entitlements aligned for release signing, update messaging consistent with the actually-disabled Sparkle state.

### Fixed

- Library import is now atomic — a mid-import failure no longer leaves partially imported projects or entries (single-transaction rollback).
- Quick-panel local ranking now matches repository ordering for manual `sortOrder`, so the panel and library show the same order.
- Repository consistency edge cases in entry and settings persistence.

### Documentation

- OpenSpec baseline established: `openspec/specs/project-documentation/spec.md` is the documentation-system spec, with reliability contracts recorded.
- Library transfer workflow, consistency safeguards, and bilingual discoverability docs added.
- Star History chart, `项目快贴` alias, and Chinese long-tail keywords surfaced in the READMEs for search and answer engines.

### Security

- No new network paths. Import/export and diagnostics export operate purely on local files; Sparkle remains bundled but disabled (no feed configured, no update probe dispatched).

## [1.0.1] - 2026-05-19

### Added

- **README — Workflow examples section** capturing concrete "how do I..." use cases (fresh ChatGPT/Claude role prompt, Cursor project-context paste, code-review checklists, terminal command snippets, meeting-notes templates, Slack/email replies, project-isolated prompt sets). These double as long-tail SEO/GEO surfaces.

### Changed

- README structure now leads from the comparison table into concrete workflow examples for stronger generative-engine answers.

### Notes

Documentation-only release. No app behavior, hotkey, paste path, or storage format changes since 1.0.0.

## [1.0.0] - 2026-05-17

First public release. Aligns the `Info.plist`, `codemeta.json`, and `docs/search-metadata.schema.jsonld` version surfaces with the shipped artifact.

### Added

- Entry use-count tiers with visible tier colors in the library and quick panel.
- "By level" library sort mode, persisted across launches.
- Quick-panel pin controls, including a header button and `Command-P` handling while the search field is focused.
- Persisted quick-panel window origin and settings controls for panel content size.
- Public project documentation: README files, contribution guide, FAQ, security policy, changelog, license, and issue templates.
- Open-source documentation pages for project introduction, API/feature contracts, development standards, usage examples, roadmap/contribution flow, AI search discoverability, CodeMeta, and Schema.org metadata.
- High-frequency AI interaction pain-point sections in `README.md` and `README.zh-CN.md` to make the product's job-to-be-done explicit.
- Generative-engine optimization (GEO) surfaces: an answer-engine summary in `llms.txt`, an FAQ-style block in `docs/ai-search/llms-full.txt`, and a Schema.org `FAQPage` graph node in `docs/search-metadata.schema.jsonld`.
- `scripts/check-docs.sh` as the documentation, SEO, LLM-index, and structured-metadata gate used by release readiness and CI.

### Changed

- Tighter quick-panel row density and improved title/preview truncation.
- Pointer clicks now execute visible quick-panel rows immediately.
- Sheet layouts improved for project, entry, and project-migration flows.
- Paste is delayed briefly after the target app regains focus to reduce focus-race failures.
- Frontend draft updated to match the denser quick-panel layout.
- README badges and roadmap renamed from `v0.1` to `v1.0` to match the shipped version.

### Fixed

- Use tracked app icon assets from the README instead of ignored local icon-generation artifacts.

### Security

- No remote authentication, telemetry, or cloud sync paths are introduced. Prompt content remains local in SQLite; the only network traffic is the optional Sparkle update check.

[Unreleased]: https://github.com/qilaidev/PromptPanel/compare/v1.5.0...HEAD
[1.5.0]: https://github.com/qilaidev/PromptPanel/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/qilaidev/PromptPanel/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/qilaidev/PromptPanel/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/qilaidev/PromptPanel/compare/v1.1.2...v1.2.0
[1.1.2]: https://github.com/qilaidev/PromptPanel/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/qilaidev/PromptPanel/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/qilaidev/PromptPanel/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/qilaidev/PromptPanel/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/qilaidev/PromptPanel/releases/tag/v1.0.0
