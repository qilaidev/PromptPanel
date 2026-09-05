# PromptPanel FAQ

## Quick facts / 快速事实

| Question / 问题 | Answer / 答案 |
| --- | --- |
| What is PromptPanel? / 它是什么？ | A native, local-first macOS prompt manager and snippet launcher. 它是 macOS 原生、本地优先的 Prompt 管理器 / 片段启动器。 |
| Who is it for? / 适合谁？ | AI power users, developers, prompt engineers, technical writers, PMs, consultants, and anyone reusing multiline prompts across apps. 适合高频复用 ChatGPT、Claude、Cursor、Copilot、终端命令和模板的人。 |
| How does it work? / 怎么用？ | Press a global hotkey, search the local library, press Enter, then PromptPanel writes to the clipboard and attempts automatic paste. 全局快捷键唤出面板，搜索，回车，先写剪贴板，再尝试自动粘贴。 |
| What is required? / 需要什么？ | macOS 14+, Xcode 15+ for source builds, and Accessibility permission only when you want automatic paste. 需要 macOS 14+；源码构建需要 Xcode 15+；自动粘贴需要辅助功能权限。 |
| What language is the UI? / 界面什么语言？ | **Simplified Chinese only** today (`CFBundleDevelopmentRegion = zh-Hans`, no localization resources). Stored prompt content can be in any language. **应用界面目前仅简体中文**；你存的 Prompt 内容本身不限语言。 |
| What are the limits? / 边界是什么？ | No cloud sync, no teams, no Windows/Linux build, no browser-extension-only mode, Simplified-Chinese-only UI, and no notarized binary release asset yet. 无云同步、无团队协作、无 Windows/Linux 版、界面仅简体中文，也暂无已公证二进制发布包。 |

## What problem does PromptPanel solve?

PromptPanel solves the most common high-frequency AI interaction pains for macOS users:

- Retyping the same role or system prompt into every new ChatGPT, Claude, Gemini, or Perplexity chat.
- Searching a Notes app or scratchpad for a reusable prompt mid-conversation.
- Pasting Cursor or Copilot project context blocks before every coding session.
- Auto-paste tools that silently fail when focus changes.
- Wanting a prompt library but not trusting NDA-bound or proprietary prompts to a cloud service.

It collapses the answer into one loop: press a global hotkey, type a few characters, press Enter. The selected entry is written to the clipboard, then pasted into the active text field when Accessibility permission is granted.

## Which apps can PromptPanel paste into?

Any focused text field on macOS. Common targets:

- Web: ChatGPT, Claude, Gemini, Perplexity, Poe, any chat UI in any browser.
- Coding: Cursor, VS Code, Xcode, JetBrains IDEs, Aider, GitHub Desktop, Sublime Text.
- Terminal: Terminal.app, iTerm2, Warp, Ghostty.
- Collaboration: Slack, Notion, Linear, GitHub, GitLab.
- Native macOS text fields anywhere.

## Is PromptPanel free?

Yes. PromptPanel is licensed under MIT. There is no account, paid tier, usage cap, or cloud service required for the core app.

## What language is the app interface in? / 应用界面是什么语言？

**Simplified Chinese only.** The bundle declares `CFBundleDevelopmentRegion = zh-Hans` and all UI strings are hard-coded in Swift — there are no `.lproj` localization resources and no in-app language switch. Documentation is bilingual and ships in eight languages, and `README.md` includes a Chinese→English UI label map. The prompt content you store is unaffected: entries can be in any language.

**应用界面目前只有简体中文**，暂无多语言资源和语言切换入口。文档是双语的，`README.md` 里有中英界面对照表。词条内容本身不限语言。

Adding an English or multi-language UI is not currently on the roadmap. If you want it, open an issue so the demand is visible.

## How do I search inside the quick panel? / 面板里怎么搜索？

Type in the search field; there is no submit step.

| Input | Behavior |
| --- | --- |
| `review` | SQLite FTS5 prefix match over entry title and content |
| `code rev` | Each whitespace-separated token is a prefix term, ANDed together |
| `#sql` | Filters to entries tagged `sql`; the `#tag` token is removed from the text query |
| `#sql migrate` | Tag filter `sql` **and** text match `migrate` |
| *(empty)* | Browses the current project plus the universal project |

Only the first `#tag` token is treated as a tag filter and it matches exactly and case-sensitively (`#SQL` will not match a `sql` tag). Results are capped at 100 rows, and text matching is prefix-based — a term taken from the middle of a word (or of an unspaced CJK run) will not match.

## Why do entries change position in the list? / 词条顺序为什么会变？

Ordering is **frecency**, not a fixed list. Pinned entries come first; everything else is ranked by

```text
score = use_count × 2 ^ (-days_since_last_use / 90)
```

so an entry counts for half as much after every 90 idle days. Frequently used prompts float to the top on their own, and a prompt you used heavily last year sinks instead of holding a slot forever. Ties fall through to last-used time, then raw use count, then update time. The same function runs in the SQL `ORDER BY` and in the panel's in-memory sort (`Sources/PromptPanel/Core/Utils/EntryRanking.swift`), so the panel's `⌘1`–`⌘9` numbers always address the rows you see.

Manual sort order (`sort_order`) was retired in v1.3.0 — no UI ever wrote it, and imported values pinned entries to the top permanently. Use **置顶** (pin) from an entry's context menu instead. The library window has its own display sort (`设置 → 偏好 → 词条排序`: 按使用 / 按等级 / 按最近 / 按字母), which affects only that list.

## Which keyboard shortcuts does PromptPanel have? / 有哪些快捷键？

| Key | Where | Action |
| --- | --- | --- |
| `⌥2` (default, rebindable) | anywhere | Toggle the quick panel |
| `↑` / `↓` | panel | Move the selection |
| `↵` | panel | Execute — clipboard write, then best-effort auto-paste |
| `⌘1`–`⌘9` | panel | Execute the Nth row (badges shown while the query is empty) |
| `⌘C` | panel | Copy without pasting |
| `⌘P` | panel | Pin the panel open |
| `Esc` / `✕` | panel | Dismiss |
| `⌘F` | main window | Focus the library search field |
| `⇧⌘C` | main window | Copy the selected entry |
| `⌘E` | main window | Edit the selected entry |

Copy in the main window is `⇧⌘C` rather than `⌘C` on purpose: the preview pane's text is selectable, so plain `⌘C` is left to normal text selection.

## How do I change the global hotkey? / 快捷键冲突怎么办？

Open `设置 → 偏好 → 快捷键 → 呼出面板` (Settings → Preferences → Hotkey → Toggle panel) and record a new combination. The default is `⌥2`. There is exactly one hotkey for the panel, and pressing it again while the panel is open dismisses it.

If a newly recorded shortcut does nothing, another running app or a macOS system shortcut is claiming it first — pick a different combination. Installs carried over from a pre-1.0 build are migrated to the current default exactly once, and only when the shortcut was still on its old built-in default; a shortcut you chose yourself is never overwritten.

## Auto-paste does not work in one specific app. What now? / 某个应用里粘贴不生效？

Work through this order:

1. Confirm Accessibility permission is granted in `设置 → 偏好 → 权限与启动` and in `System Settings → Privacy & Security → Accessibility`. After rebuilding the `.app`, macOS may treat it as a new binary and drop the grant — remove and re-add the entry.
2. Check the clipboard. If `⌘V` manually pastes the right content, the clipboard guarantee held and only the synthetic keystroke was blocked.
3. Read `设置 → 维护 → 最近执行记录` (recent execution log). Each failed execution records a reason.
4. Some apps refuse synthetic events on purpose (password fields, certain secure inputs, some remote-desktop and VM windows). That is a target-app policy, not a recoverable PromptPanel error.
5. If it reproduces in a common app, please file an issue with the app name, version, and the execution-log reason so it can be added to `docs/兼容性回归记录.md`.

## Does PromptPanel support variables or template placeholders? / 支持变量模板吗？

Not yet. Entry content is pasted verbatim. Variable templates (`{{name}}`-style) are listed in the roadmap as in-scope **only if** they can be added without slowing the main link. Today, keep placeholders in the text and edit after pasting.

## How do I uninstall PromptPanel and remove all of its data? / 怎么彻底卸载并清理数据？

Export first if you may want the library back (`设置 → 维护 → 导出 JSON`). Then quit from the menu bar, delete the `.app`, and remove the two directories PromptPanel owns:

```bash
rm -rf ~/Library/Application\ Support/PromptPanel   # promptpanel.db, Backups/, Recovery/
rm -rf ~/Library/Logs/PromptPanel                   # runtime logs
```

Also remove PromptPanel from `System Settings → Privacy & Security → Accessibility`, and from login items if launch-at-login was enabled. PromptPanel writes nothing outside these locations and the standard `UserDefaults` domain.

## Where is my data stored?

PromptPanel stores its primary SQLite database at:

```text
~/Library/Application Support/PromptPanel/promptpanel.db
```

Runtime logs are written under:

```text
~/Library/Logs/PromptPanel
```

Both locations can be isolated for QA with the environment variables documented in `docs/配置说明.md`.

## How do I import or export my prompt library?

Open `设置 → 维护 → 维护操作` (Settings → Maintenance). Use `导出 JSON` / `导入 JSON` (Export/Import JSON) for lossless PromptPanel-to-PromptPanel migration, or `导出 MD` / `导入 MD` (Export/Import MD) when you want a reviewable Markdown file. Every import creates a local database backup before writing projects or entries, and the writes run in a single transaction that rolls back completely on failure.

## Does PromptPanel upload prompt content?

No. Core prompt storage, search, execution, and logging are local. The current release also makes zero outbound calls — Sparkle is bundled but the appcast feed and signing key are not configured in this build, so no update probe happens at all.

## How do I upgrade PromptPanel?

The current release ships with the auto-update path intentionally disabled (no signed appcast is hosted yet). To upgrade:

1. Quit PromptPanel from the menu bar.
2. Build the latest source with `./scripts/build-app.sh`; current GitHub Releases do not attach notarized binary assets yet.
3. Replace `/Applications/PromptPanel.app` with the newly built bundle, or run `dist/PromptPanel.app` directly for local QA.
4. Reopen PromptPanel and confirm the version in `设置 → 维护 → 运行概况` (Settings → Maintenance → Runtime overview).

Your data lives in `~/Library/Application Support/PromptPanel` and is preserved across upgrades. The launch maintenance routine writes a backup automatically; you can also click `立即备份` (Back up now) in `设置 → 维护` before swapping the app.

## Is PromptPanel a ChatGPT prompt manager or Claude prompt library?

Yes. PromptPanel is designed for reusable prompts, snippets, templates, and project context blocks that you paste into ChatGPT, Claude, Cursor, Copilot, VS Code, Terminal, browsers, and ordinary macOS text fields. See `docs/使用示例.md` for concrete examples.

## Is PromptPanel a TextExpander, Espanso, or Raycast Snippets alternative?

It overlaps with those tools but is narrower: PromptPanel is a keyboard-first searchable panel for AI prompts and snippets. It is not a general text expansion engine, app launcher, or workflow automation platform.

## Why does PromptPanel need Accessibility permission?

Accessibility permission lets PromptPanel synthesize `Command-V` after it restores focus to the target app. Without it, PromptPanel still writes the selected entry to the clipboard and asks the user to paste manually.

## What happens if auto-paste fails?

The clipboard write happens first and is treated as the durable fallback. If paste cannot be dispatched or the target app does not regain focus, PromptPanel records the failure reason in the execution log and leaves the content on the clipboard.

## Can I sync prompts through the cloud or use teams?

No. Cloud sync, team collaboration, and complex workflow orchestration are permanent non-goals in `docs/项目快贴-PRD.md`. PromptPanel is intentionally single-user and local-first.

## Does PromptPanel have a public API?

No HTTP, cloud, GraphQL, plugin, or remote execution API exists today. The documented "API" surface is the local feature contract, Swift service boundaries, SQLite schema, script interfaces, and environment variables in `docs/API与功能说明.md`.

## How do I build from source?

Use SwiftPM for fast development builds:

```bash
swift build
```

For an app bundle:

```bash
./scripts/build-app.sh
open dist/PromptPanel.app
```

## Why does `swift test` sometimes only build tests locally?

On machines with only Command Line Tools, `xctest` may be unavailable. In that case `swift test` can prove compilation but cannot be counted as full XCTest execution. The release gate exposes this explicitly; use `./scripts/release-readiness.sh --allow-build-only-tests` only when accepting that downgrade.

## How should UI changes be made?

Update `frontend-draft/` first because it is the visual source of truth. Then align the SwiftUI/AppKit implementation and include the corresponding validation in the PR.

## Where is the roadmap?

The public roadmap and contribution scope are in `docs/路线图与贡献指南.md`. JSON/Markdown import/export is now built into `Settings → Maintenance`; repeat last entry, search/tag improvements, and compatibility samples remain in scope. Cloud sync, teams, and workflow orchestration are not.

## What version is current?

The current shipping version is `1.5.0`. `Sources/PromptPanel/Resources/Info.plist`, `codemeta.json`, and `docs/search-metadata.schema.jsonld` are the authoritative version surfaces. Release notes live in `CHANGELOG.md`.

## What macOS versions does PromptPanel support?

macOS 14 (Sonoma) and later, on both Apple Silicon (M1/M2/M3/M4) and Intel Macs. The release is built as a universal binary.

## Is there a Windows or Linux build?

No. PromptPanel is deliberately macOS-only because the main link (global hotkey timing, focus restoration, synthetic Command-V) is built on macOS system APIs. A cross-platform port is not on the roadmap.

## How does PromptPanel compare to TextExpander, Espanso, Raycast Snippets, and Alfred Snippets?

PromptPanel is narrower and AI-shaped:

- TextExpander: powerful general expander but commercial and increasingly cloud-oriented.
- Espanso: open-source typed-trigger expander, no search panel, not AI-shaped.
- Raycast Snippets: good panel UX but tied to a Raycast account and Powerpack tier for some features.
- Alfred Snippets: needs Powerpack, designed for short text expansions rather than multiline prompts.

PromptPanel focuses on one thing: search-and-paste reusable prompts and snippets through a single panel, local-only, with clipboard guarantee.
