# Changelog

All notable changes to PromptPanel are tracked here.

The format is based on Keep a Changelog, and this project uses Conventional Commits for commit messages.

## [Unreleased]

## [1.7.3] - 2026-11-13

macOS 空白设置窗口根治与原生菜单栏接管补丁版本（`1.7.3+14`）。彻底消除桌面端偶发或重开应用时弹出的空白「“项目快贴”设置」窗口。

### Fixed

- **彻底移除 SwiftUI 空壳 `Settings { EmptyView() }` 场景，根治空白「“项目快贴”设置」窗口弹出问题（`PromptPanelApp` / `AppDelegate` / `PanelService` / `QuickPanelViewModel`）。** 原应用入口通过 SwiftUI `App` 注册了占位的 `Settings { EmptyView() }` 场景，导致在快捷面板激活态按 `⌘,`、通过系统重开/唤醒实例（`open -a`）或触发 macOS 窗口状态恢复（`NSWindow Frame com_apple_SwiftUI_Settings_window` / `Saved Application State`）时，系统自动弹出 `900×450` 的空白「“项目快贴”设置」窗口。现已切换为纯原生 `NSApplication.shared` + `AppDelegate` 生命周期：启动时自动清理历史残留的空白窗口 Frame 与 `Saved Application State`，所有窗口与面板统一标记 `isRestorable = false` 并禁用系统窗口状态恢复；同时由 `AppDelegate.setupMainMenu()` 原生接管顶部菜单栏（完整保留文本框 `⌘Z / ⇧⌘Z / ⌘X / ⌘C / ⌘V / ⌘A` 响应链与窗口 `⌘W / ⌘M` 快捷键），将全局及快捷面板内的 `⌘,` 与应用重开请求统一路由至真实主界面的「设置」或「内容库」视图。

## [1.7.2] - 2026-11-13

跨端一键更新与后台自动更新版本（`1.7.2+13`）。打通 macOS 桌面端、Android 移动端与自托管同步服务端的双源（同步节点镜像优先 + GitHub Releases 兜底）SHA-256 校验更新闭环，告别手动翻找安装包与覆盖拖拽。

### Added

- **macOS 原生一键更新与后台静默升级（`UpdaterService` / `SettingsView` / `TrayManager` / `AppDelegate`）。** 在保留 Sparkle 企业签名源支持的同时，内置免配置发行版自更新引擎：支持在「设置 → 通用 → 软件版本」或菜单栏「检查更新…」一键检测、下载、校验 SHA-256 与 Bundle 代码签名（`codesign --verify --deep --strict`），升级前自动冲刷内联草稿并生成 `update` 安全数据库快照（`createUpdateSafetyBackup`），原子替换 `/Applications/PromptPanel.app`（失败自动回滚 `.old`）、剥离隔离属性并自动重启；开启「自动更新」后每 4 小时静默巡检并在后台空闲无窗口打开时无感完成升级。
- **Android 移动端应用内一键安装更新与后台预下载（`UpdateApkProvider` / `UpdateDownloadTask` / `MainActivity` / `assets/index.html`）。** 新增原生 `ContentProvider` 安装包分发与 `REQUEST_INSTALL_PACKAGES` 权限衔接（首次授权「允许安装未知应用」返回后自动续装）；「设置 → 偏好 → 版本与一键更新」支持开启「自动检查并预下载更新」、复制安装包直链及点击「检查并一键更新」，后台静默下载并完成 SHA-256 校验后在顶部横幅弹出「立即安装」一键原位覆盖升级，完整保留 SQLite 词库与 KeyStore 加密令牌。
- **自托管同步服务端发行包镜像中继与极速直链（`server/promptpanel_sync_server.py` `v2.2.0`）。** 新增 `GET /v1/update` 最新版本清单接口及 `/download/android`、`/download/macos`、`/download/dmg` 磁盘缓存流式下载接口（64KB 分块校验 SHA-256 并自动淘汰历史旧包），使国内或局域网设备无需直连 GitHub 即可满速完成一键更新。

## [1.7.1] - 2026-11-13

跨端同步稳定性根因修复、双端扫码/粘贴一键配对与移动端交互打磨补丁版本（`1.7.1+12`）。彻底解决手机端修改便签/待办无法同步回电脑、开启自动同步后缺少自动拉取以及电脑端复制配置在手机端无法导入的三项核心阻断问题，并同步落地手机端底部五栏导航（设置下沉）、列表左右滑动手势与双端一键新建待办体验。

### Fixed

- **修复手机端修改词条/勾选待办后无法同步至电脑端的字段覆盖缺陷（`Entry.swift` / `Project.swift` / `server/` / `mobile/`）。** 原 macOS 客户端序列化采用 `snake_case`（如 `updated_at`、`is_completed`、`deleted_at`），而 Android 端加载后仅更新 `camelCase` 字段（`updatedAt`、`isCompleted`、`deletedAt`），残留了旧的 `updated_at` 影子键；macOS 解码与服务端合并时优先读取了旧 `updated_at`，导致手机端全部改动在自动与手动同步中均被判定为旧版本丢弃。现已在 macOS 模型解码层、Python 自托管同步服务端与 Android 本地存储三端统一按较新时间戳选取字段并自动清理历史影子键，已有服务端库亦在首次同步时无感自愈。
- **补齐自动同步双向拉取闭环与开关即存即同步保护（`MainWindowViewModel` / `AppDelegate` / `mobile/`）。** 修复此前「自动同步」仅在本机发生写入后单向触发、不主动拉取对端新改动的问题：现已支持应用切回前台、唤出快捷面板及后台 45 秒静默轮询自动双向同步，并同步刷新快捷面板内存列表；同时修复开启自动同步开关或修改同步地址/Token 后未点「保存配置」导致配置未落盘的问题。

### Added

- **电脑端原生扫码配对弹窗与手机端一键导入配置（`SettingsView` / `MainWindowViewModel` / `mobile/`）。** macOS「设置 → 云端同步」新增「扫码配对手机」原生 `CoreImage` 二维码弹窗（自动检测并提示 `localhost` 或本机文件路径不可供手机直连）；Android 端新增「粘贴剪贴板配置」一键填入、「扫码读取配对图」文件/拍照识别（补齐 `WebChromeClient.onShowFileChooser` 原生桥接），并支持在输入框或 JSON 导入框中直接粘贴电脑端配对 JSON 自动识别拆解并触发首次同步。
- **双端零弹窗一键创建待办与移动端左右滑动手势。** macOS 主窗口顶部速记栏新增 `[便签 | 待办]` 一键切换胶囊与「剪贴板待办」快捷入口；Android 端内容库顶部新增内联速记输入栏（`+ 待办` / `+ 便签` 一键直存），词条列表新增**左滑删除（附顶部横幅一键撤销）**与**右滑切换待办完成状态**手势。

### Changed

- **Android 移动端移除顶部并列「设置」切换，统一收拢至底部五栏拇指导航。** 移除手机端顶部冗余的 `[内容库 | 设置]` 分段切换，在顶栏右侧提供带状态指示灯的一键「同步」快捷按钮，并将「设置」作为第 5 个一级 Tab（`全部 / 速记 / 类型 / 项目 / 设置`）放入底部导航栏；桌面端大改版与 SSE 实时推送同步等中长期优化项已评估排期并记录至 `docs/路线图与贡献指南.md`。

## [1.7.0] - 2026-11-13

快捷面板速记捕获、跨端同步防丢熔断与内联编辑性能隔离版本。围绕「高频随手记 + 零丢字同步 + 确定性跟手交互」三条主线，新增快捷面板前缀/快捷键/一键直写速记与待办、`__all_projects__` 全部项目作用域、全文预览与类型筛选，主窗口新增顶部行内速记栏、900ms 防抖自动保存与已完成项自动下沉清理；跨端同步在 macOS、自托管服务端与 Android 端全链路落地异常批量删除熔断器与软删除一键恢复；同时将内联编辑器抽离为独立会话并移除自定义鼠标/滚轮监听器，消除高频打字重绘与点击跳动。

### Added

- **跨端同步防丢数据熔断器、安全快照与软删除恢复（`CloudSyncService` + `server/` + `mobile/`）。** 当远端单次同步尝试软删除本地活跃词条达到阈值（`>= 3` 条且占比 `>= 25%`，或清空全部 `>= 2` 条活跃词条）时，自动触发高水位熔断拦截，保留本地活跃词条与所属分组并在回推时自动治愈远端信封；即便远端空白重置也会由本地词库自动反向重灌。同步删除前自动留存本地历史版本并按节流窗口写入同步安全快照（`createSyncGuardBackup`）；新增 `recoverDeletedAndSync`，支持一键恢复软删除记录并同步回云端。
- **快捷面板即时速记捕获与一键直写模式（`QuickPanelViewModel` / `QuickPanelView`）。** 搜索框输入 `; ` / `n `（便签）或 `t ` / `todo:`（待办）前缀即进入速记模式，自动解析 `#tag` 标签，`Enter` 直接存入内置 `速记与待办`（`builtin-inbox`）而不误执行旧词条且保持当前项目作用域不变；同时支持一键点击进入直写便签/待办模式（`startQuickCapture`，中途切换类型保留已输正文）、`⇧↩` 直存便签、`⌥↩` 直存待办，以及从快捷面板与菜单栏托盘一键将剪贴板存为速记便签。
- **快捷面板全部项目作用域、类型筛选与全文预览。** 新增 `__all_projects__` 作用域（浏览与检索时自动排除已归档项目，且不覆盖持久化的默认当前项目），支持悬停打开作用域切换菜单与 `Tab` / `⇧Tab` 循环切换；新增类型筛选芯片（全部 / Prompt / 代码 / 便签与待办）与 `⌘Y` 全文预览抽屉，并实现 `Esc` 分层关闭（先关全文预览 → 再关作用域下拉 → 最后收起面板）。
- **主窗口行内速记栏、空标题首行推导与批量管理增强。** 内容库顶部新增行内速记输入框（在「全部项目」下自动归入 `速记与待办` 并提取首行标题与 `#tag`）；新建词条或内联编辑留空标题时自动从正文首行生成标题；支持隐藏已完成项、一键清理当前范围或全局已完成项（`deleteCompleted`），以及跨分组拖拽移动词条（`moveEntries`）。

### Changed

- **已完成项自动下沉排序（SQL 与内存比较器双端对齐）。** `EntryRanking` 排序规则升级为 `未完成优先 (is_completed ASC) → 是否置顶 (is_pinned DESC) → frecency → 最近使用时间 → 使用次数`，勾选完成的待办或便签（即使曾置顶或刚更新）均自动下沉至未完成项下方；Android 移动端同步对齐该排序与防丢熔断逻辑。
- **中文输入法组字（`hasMarkedText`）快捷键让行保护。** `AppDelegate` 与 `KeyAwareSearchField` 在检测到拼音/中文输入法处于未上屏组字态时，自动让行 `Esc`、`Enter`、`⇧↩` 与 `⌥↩`，避免选词或取消拼音时误关面板或误提交速记。
- **900ms 防抖内联自动保存与零丢字切换保护。** 主窗口预览区内联编辑支持 900ms 防抖自动落盘（打字中途保留标题末尾空格与标签分隔符不被通知刷新冲掉）；在防抖窗口内点击置顶、改类型、克隆或切换选中词条时，均会先同步刷盘当前未保存修改，绝不因旧快照覆盖丢字。

### Performance & Fixed

- **内联编辑状态隔离与历史版本智能合并（`InlineEditorSession`）。** 将高频变化的标题、正文、标签草稿从 `MainWindowViewModel` 抽离到独立 `InlineEditorSession`，使每次按键触发 `0` 次主视图模型重绘广播；同一词条上的连续自动保存自动合并为单条 `EntryVersion` 快照（显式按 `⌘S` 手动保存仍独立留存新版本），消除版本列表膨胀。
- **移除自定义鼠标/滚轮监听器并分离键盘与指针滚动。** 移除易引发点击吞字与滚动冲突的自定义事件监听器，新增 `scrollSelectionRevision`（快捷面板）与 `programmaticScrollRevision`（主窗口）：仅键盘上下键导航触发列表自动滚动定位，鼠标悬停或点击选中保持视口绝对稳定不跳动；切换项目作用域时改为同步落盘后再广播 `.currentProjectDidChange`，彻底消除跨组件读取竞态。

## [1.6.0] - 2026-11-06

工作区三层分组、版本历史与双窗装配版本（V7）。在保持本地优先与单文件 SQLite 零云依赖默认行为的前提下，主窗口内容库升级为「速记与待办（Inbox）/ 常用类型（Categories）/ 项目管理（Projects）+ 项目归档」三层结构，新增「双窗对照与剪贴板装配台」（`参考窗口`）、词条每次修改自动生成不可变历史版本（`EntryVersion`）并支持一键回滚，以及可选的开源自托管云同步（`CloudSyncService` + `server/` + `mobile/`）。同时补齐 GitHub README 界面截图入库与全量文档同步。

### Added

- **三层工作区架构与项目归档（Migration V7）。** `projects` 新增 `group_kind`（`inbox` 速记与待办、`category` 常用类型、`project` 具体项目）、`is_archived` 与 `icon_name`；内置不可删除的 `速记与待办`（`builtin-inbox`）用于随手记待办（`todo` 类型，支持勾选完成 `is_completed`）与临时记录（`note`）；具体项目完成后可一键归档，自动从快捷面板项目切换器中隐藏并收拢至主窗口归档折叠区。
- **双窗对照与剪贴板装配台（`ReferenceLibraryWindowView`）。** 主窗口顶部与左下角新增 `参考窗口` 入口，支持边看「常用类型」通用模板或实时预览系统剪贴板，边一键克隆到目标项目（记录 `source_entry_id` 血缘），在项目内定制修改不会污染通用模板。
- **词条版本历史与无损回滚（`EntryVersion` / `entry_versions`）。** 每次修改词条标题或正文时自动留存版本号递增的历史快照（`v1`, `v2`, …）；预览区顶部可直接查看任意历史版本正文、复制历史版本或一键回滚（回滚前自动将当前状态存为新版本，绝不丢字）。
- **可选的开源自托管多端同步（`CloudSyncService` + `server/` + `mobile/`）。** 默认保持纯本地零网络请求；用户可在「设置 → 偏好 → 云端同步」中按需配置本地网盘/iCloud 同步文件路径，或接入仓库自带的零外部依赖 Python + SQLite WAL 自托管同步服务端（`server/`，按 Bearer Token SHA-256 哈希物理隔离数据库）与 Flutter 跨平台移动端（`mobile/`）。并发修改冲突时自动将被覆盖版本转存进 `entry_versions` 历史记录。
- **主窗口键盘导航与词条右键菜单。** 内容库支持 `⌘N` 新建词条，以及在未处于输入法组字（`hasMarkedText`）或文本选区状态下直接按 `↑` / `↓` 切换选中词条；内容库词条行新增右键菜单（复制内容 `⇧⌘C`、编辑词条 `⌘E`、克隆到项目、置顶/取消置顶、删除词条），快捷面板词条行也补齐右键菜单（执行词条 `Enter`、仅复制内容 `⌘C`）并在 `⌘C` 复制后弹出 Toast 提示。
- **跨全部项目 FTS 搜索与中文子串/标签召回增强。** `EntryRepository` 新增 `searchAll(query:tag:)`，主窗口与快捷面板统一支持 `#tag` 语法并在 `LIMIT 100` 截断前完成标签过滤；SQL 查询结合 FTS5 前缀匹配与 `INSTR` 大小写不敏感子串匹配，解决连续中文中段词（如在“并发安全”中搜“安全”）漏召回问题。

### Changed

- **macOS 原生视觉与高密度三栏细节打磨。** 快捷面板与主窗口侧边栏引入原生 `NSVisualEffectView` 毛玻璃材质与系统语义色；词条详情区支持所见即所得内联编辑，并直接展示精确到分的创建时间、最后修改时间与最近使用统计。
- **面板与搜索启动预热、去动画与低延迟预算收紧。** 启动时通过 `quickPanelViewModel.warmUp()` 与 `panelService.warmUp()` 预建 `NSPanel` 与宿主视图；`NSPanel`、`ToastService` 与主窗口/快捷面板根视图统一禁用冗余系统与隐式动画；`Entry.previewLine` 改为模型层缓存属性，列表滚动与 diff 时 O(1) 读取；搜索防抖收紧为面板 `0ms` / 主窗口 `16ms`，内部耗时预算收紧为搜索 `< 50ms`、执行 `< 180ms`。
- **作用域切换检索期间的安全执行门禁与衔接。** 当面板刚唤出或切换项目/查询词、后台检索尚未返回（`isScopeSearchInFlight`）时，自动拦截过期行的鼠标点击与 `⌘C`，并将用户按下的 `Enter` 或 `⌘1–9` 暂存到 `deferredExecutionRequest`（区分 `.selected` 与 `.index(Int)`），待新结果落地后精准衔接执行；`⌘C` 仅复制同步接入 `ClipboardService` 并记录词条使用统计以驱动 frecency 排序。
- **GitHub README 截图纳入版本控制并支持无 TCC 权限窗口级快照。** 移除 `.gitignore` 中对 `docs/ui-qa/latest/` 的忽略规则，使 GitHub 页面直接渲染最新四张高分截图；`capture-ui-qa.sh` 在终端缺少屏幕录制权限时自动回退到应用内 `NSWindow` 位图快照（`PROMPTPANEL_QA_SNAPSHOT_PATH`）。

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
- **仓库链接改用规范地址 `qilaidev/PromptPanel`。** 账号改名后旧地址只是重定向。Sparkle feed（`SUFeedURL`，已烧进已发布二进制）、`© 2026 qilaidev` 署名与 CHANGELOG 正文按原样保留。


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

> 1.1.2 及更早版本的条目已从本文件移除。这些版本的完整记录仍在 git 历史中
> （`git log -- CHANGELOG.md`），其中 v1.1.2 的 tag 也仍在仓库里。

[Unreleased]: https://github.com/qilaidev/PromptPanel/compare/v1.7.0...HEAD
[1.7.0]: https://github.com/qilaidev/PromptPanel/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/qilaidev/PromptPanel/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/qilaidev/PromptPanel/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/qilaidev/PromptPanel/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/qilaidev/PromptPanel/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/qilaidev/PromptPanel/compare/v1.1.2...v1.2.0
