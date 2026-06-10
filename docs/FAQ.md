# PromptPanel FAQ

## Quick facts / 快速事实

| Question / 问题 | Answer / 答案 |
| --- | --- |
| What is PromptPanel? / 它是什么？ | A native, local-first macOS prompt manager and snippet launcher. 它是 macOS 原生、本地优先的 Prompt 管理器 / 片段启动器。 |
| Who is it for? / 适合谁？ | AI power users, developers, prompt engineers, technical writers, PMs, consultants, and anyone reusing multiline prompts across apps. 适合高频复用 ChatGPT、Claude、Cursor、Copilot、终端命令和模板的人。 |
| How does it work? / 怎么用？ | Press a global hotkey, search the local library, press Enter, then PromptPanel writes to the clipboard and attempts automatic paste. 全局快捷键唤出面板，搜索，回车，先写剪贴板，再尝试自动粘贴。 |
| What is required? / 需要什么？ | macOS 14+, Xcode 15+ for source builds, and Accessibility permission only when you want automatic paste. 需要 macOS 14+；源码构建需要 Xcode 15+；自动粘贴需要辅助功能权限。 |
| What are the limits? / 边界是什么？ | No cloud sync, no teams, no Windows/Linux build, no browser-extension-only mode, and no notarized binary release asset yet. 无云同步、无团队协作、无 Windows/Linux 版，也暂无已公证二进制发布包。 |

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

Open `Settings → Maintenance`. Use `Export JSON` / `Import JSON` for lossless PromptPanel-to-PromptPanel migration, or `Export MD` / `Import MD` when you want a reviewable Markdown file. Every import creates a local database backup before writing projects or entries.

## Does PromptPanel upload prompt content?

No. Core prompt storage, search, execution, and logging are local. The current release also makes zero outbound calls — Sparkle is bundled but the appcast feed and signing key are not configured in this build, so no update probe happens at all.

## How do I upgrade PromptPanel?

The current release ships with the auto-update path intentionally disabled (no signed appcast is hosted yet). To upgrade:

1. Quit PromptPanel from the menu bar.
2. Build the latest source with `./scripts/build-app.sh`; current GitHub Releases do not attach notarized binary assets yet.
3. Replace `/Applications/PromptPanel.app` with the newly built bundle, or run `dist/PromptPanel.app` directly for local QA.
4. Reopen PromptPanel and confirm the version in `Settings → 运行健康`.

Your data lives in `~/Library/Application Support/PromptPanel` and is preserved across upgrades. The launch maintenance routine writes a backup automatically; you can also click `立即备份` in Settings before swapping the app.

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

The current shipping version is `1.0.1`. `Sources/PromptPanel/Resources/Info.plist`, `codemeta.json`, and `docs/search-metadata.schema.jsonld` are the authoritative version surfaces. Release notes live in `CHANGELOG.md`.

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
