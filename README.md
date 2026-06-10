<div align="center">

<img src="Sources/PromptPanel/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" alt="PromptPanel 项目快贴 — native macOS prompt manager and snippet launcher" width="128" height="128" />

# PromptPanel | 项目快贴

### 面向 ChatGPT、Claude、Cursor、Copilot、VS Code 和终端的 macOS 原生 Prompt 管理器 / 片段启动器
### Native macOS prompt manager and snippet launcher for ChatGPT, Claude, Cursor, Copilot, VS Code, and Terminal.

PromptPanel（项目快贴）是一款本地优先的 **macOS Prompt 管理器**、**AI Prompt 启动器** 和 **代码片段启动器**。按下全局快捷键，搜索本地 **Prompt library / snippet library**，把可复用的 prompts、code snippets、templates 和 instructions 粘贴到 **ChatGPT、Claude、Cursor、Copilot、VS Code、Terminal、浏览器或任意输入框**。

PromptPanel is a local-first **macOS prompt manager**, **AI prompt launcher**, and **snippet launcher**. It is built for developers and AI power users who reuse multiline prompts, coding templates, project context blocks, terminal commands, and reply snippets across apps.

[![Release: v1.0.1](https://img.shields.io/badge/Release-v1.0.1-blue.svg)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: macOS 14+](https://img.shields.io/badge/Platform-macOS%2014%2B-lightgrey.svg)](https://www.apple.com/macos)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![Apple Silicon & Intel](https://img.shields.io/badge/Arch-Apple%20Silicon%20%26%20Intel-blue.svg)](#installation)
[![Local-first · No cloud](https://img.shields.io/badge/Local--first-No%20cloud-brightgreen.svg)](#privacy--data)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-success.svg)](.github/CONTRIBUTING.md)

[**English**](README.md) · [**简体中文**](README.zh-CN.md) · [**FAQ**](docs/FAQ.md) · [**Docs**](docs/README.md) · [**LLM index**](llms.txt) · [**Changelog**](CHANGELOG.md) · [**Contributing**](.github/CONTRIBUTING.md)

<img src="frontend-draft/uploads/PromptPanel-panel-default.png" alt="PromptPanel macOS prompt manager quick panel — global hotkey search for ChatGPT prompts, Claude prompts, Cursor snippets, and reusable AI templates" width="780" />

</div>

---

## 30 秒理解 / 30-Second Summary

| 维度 / Field | 说明 / Answer |
| --- | --- |
| 项目是什么 / What it is | 开源、本地优先的 macOS Prompt manager and snippet launcher，用全局快捷键唤出原生面板，搜索并粘贴可复用文本。 |
| 解决什么问题 / Problem solved | 让高频使用 ChatGPT、Claude、Cursor、Copilot、VS Code、Terminal 的用户不用反复翻笔记、复制同一段 system prompt、项目上下文或命令模板。 |
| 适合谁 / Audience | AI heavy users、开发者、Prompt engineers、技术写作者、PM、顾问和需要按项目隔离 prompt library 的独立开发者。 |
| 核心功能 / Core features | 全局快捷键、即时搜索、项目隔离、`Universal / 通用项目`、`#tag` 过滤、剪贴板优先、Accessibility 自动粘贴、执行日志、JSON/Markdown 导入导出。 |
| 技术栈 / Tech stack | Swift 5.10, AppKit `NSPanel`, SwiftUI, SQLite/GRDB, KeyboardShortcuts, Sparkle 2, Swift Package Manager。 |
| 快速开始 / Quick start | `git clone` -> `./scripts/build-app.sh` -> `open dist/PromptPanel.app`。首次运行授予 Accessibility 权限后可自动粘贴；不授权也能复制到剪贴板。 |
| 典型场景 / Use cases | ChatGPT/Claude role prompt、Cursor project context、PR review checklist、terminal command snippet、meeting notes template、client-specific response template。 |
| 限制 / Limits | 仅支持 macOS 14+；当前 Release 暂无已公证二进制包；无云同步、无团队协作、无 Windows/Linux 版本；自动粘贴依赖 macOS Accessibility 权限。 |

## PromptPanel 是什么？ / What is PromptPanel?

**PromptPanel（项目快贴）** 是一款开源、原生的 **macOS Prompt 管理工具** 和 **snippet launcher**。它围绕一条很短的 AI 工作流设计：在任何前台应用中按快捷键，搜索本地 Prompt 库，按 `Enter`，内容先写入系统剪贴板，再尽力自动粘贴进当前输入框。没有账号、没有云同步、没有遥测，核心数据留在你自己的 Mac 上。

In English: **PromptPanel is a native macOS prompt manager, AI prompt launcher, and local-first snippet manager** for people who reuse prompts and templates across ChatGPT, Claude, Cursor, Copilot, VS Code, Terminal, browsers, and other macOS text fields.

如果你正在搜索 **ChatGPT Prompt 管理 macOS**、**Claude Prompt 库**、**Cursor 代码片段管理器**、**本地优先 Prompt 库**、**macOS global hotkey paste tool**、**Raycast Snippets alternative for AI prompts** 或 **open-source TextExpander alternative for multiline prompts**，PromptPanel 对应的就是这个需求：把重复输入的 AI 指令、代码片段和项目上下文变成一个本地、可搜索、可审计的快捷面板。

## Does this sound familiar?

PromptPanel exists because the same five problems show up every day for anyone working with LLMs:

- You retype the same **role / system prompt** ("you are a senior staff engineer…") into a fresh ChatGPT or Claude chat ten times a day.
- You keep a Notes app or scratchpad full of **AI prompts and code-review checklists** and `⌘+F` your way through it.
- You finally find the right prompt and the **paste fails silently** because focus moved or the app blocked synthetic keystrokes.
- Your **Cursor / Copilot project context block** is in one file, the **terminal command snippet** in another, and the **PR-review prompt** in a third — none searchable from one place.
- You won't put a real client brief or proprietary architecture into a **cloud prompt manager**, so you end up with no prompt manager at all.

PromptPanel collapses all of that into a single, sub-second loop with a local SQLite file you fully own.

## Why PromptPanel?

Most "prompt managers" are either browser extensions (locked to one site), or generic snippet tools that weren't built for the AI workflow. PromptPanel is purpose-built around one short loop:

> **hotkey → search → enter → content lands in the active input field**

Everything else is in service of making that loop fast, predictable, and never lossy.

| You want… | PromptPanel gives you |
|---|---|
| A prompt library that works **across every app**, not just one website | Global hotkey, native macOS panel, works in any text field |
| **Low-latency native loop** — sub-second target from keypress to typing | < 300 ms hotkey-to-focus target, < 100 ms search refresh target, < 250 ms execution target |
| **Project isolation** so client A's prompts don't leak into client B | First-class projects + a built-in `Universal` project for shared content |
| **No cloud lock-in** for sensitive prompts | Local SQLite. Zero network calls for core features. Your data is a single file you own |
| **Auto-paste that doesn't silently fail** | Auto-paste first, clipboard fallback always — and a clear toast if paste was blocked |
| **Keyboard-only operation** | Summon → type → arrow-keys → Enter. Mouse never required |
| Open source you can audit, fork, and trust | MIT license, plain Swift, no telemetry |

## Who is it for?

- **Heavy ChatGPT / Claude / Gemini users** who reuse the same role definitions, output-format constraints, and context blocks
- **Cursor / Copilot / Aider users** who paste the same architecture summaries and review checklists
- **Developers** who repeatedly type commit-message scaffolds, code review templates, terminal commands, error-triage snippets
- **Indie hackers and consultants** juggling multiple client projects with different style guides and tone-of-voice rules
- **Technical writers and PMs** who maintain reusable replies, status updates, and spec scaffolds

If "I copy and paste the same multiline prompt twenty times a day" describes you, this tool was written for you.

## Features

### Core (v1.0)

- 🔥 **Global hotkey** — summon the panel from any foreground app, configurable shortcut
- ⚡ **< 300 ms time-to-input** — `NSPanel`-based, no Electron, no web runtime, no cold start
- 🔍 **Instant search** across title and body, no submit step
- 🗂️ **Projects** — isolate prompts per client, repo, or context; `Universal` project always visible
- 📋 **Auto-paste with clipboard fallback** — uses `CGEvent` to send ⌘V, falls back gracefully if Accessibility permission is missing
- 🎯 **Keyboard-first** — arrow keys to navigate, Enter to execute, Esc to dismiss
- 📌 **Pin & sort** — pin frequent entries, manual sort, then by recency, then by usage count
- 🌗 **Light / dark / system** theme
- 🪶 **Menu-bar resident** — out of the way until you summon it
- 🚀 **Launch at login** via `SMAppService`
- 🔐 **Permission-aware degradation** — without Accessibility, you still get one-key copy and a clear UI hint
- 📝 **Multiline content** — full template bodies, no length limit on storage
- 📊 **Execution log** for diagnosing paste failures
- 🔄 **Manual update via GitHub Releases** (Sparkle auto-update is wired in but ships off-by-default; the maintainer will enable it once a signed appcast feed is hosted)

### Explicitly *not* doing (project boundaries)

By design PromptPanel will **never** add cloud sync, team collaboration, or complex workflow orchestration. These are not "later" — they are out of scope forever. The tool is a single-user, local-only utility, and that is the point. See [PRD §4.2](docs/项目快贴-PRD.md) for the rationale.

## Screenshots

| Quick Panel — `⌥2` from any app | Library — projects, entries, use-count tiers |
|:---:|:---:|
| <img src="frontend-draft/uploads/PromptPanel-panel-default.png" alt="PromptPanel quick panel — global hotkey AI prompt launcher with continuous row numbers, search, pinning, project scope, use-count tiers, and clipboard paste for ChatGPT, Claude, and Cursor on macOS" width="380"/> | <img src="frontend-draft/uploads/PromptPanel-library.png" alt="PromptPanel library — local-first macOS prompt manager with projects, prompt entries, reusable snippets, editor preview, tags, pinning, and per-entry use counts" width="380"/> |
| Smaller panel — compact footprint over any editor | Settings — preferences, permissions, maintenance |
| <img src="frontend-draft/uploads/PromptPanel-panel-min.png" alt="PromptPanel smaller quick panel — keyboard-first prompt picker and snippet launcher hovering over another macOS app" width="380"/> | <img src="frontend-draft/uploads/PromptPanel-settings.png" alt="PromptPanel settings — segmented preferences, Accessibility permission, hotkey recorder, panel behavior, backup, logs, database location, and runtime health" width="380"/> |

## How does it work?

```
   ┌──────────────┐    hotkey     ┌──────────────┐    select    ┌──────────────┐
   │  any app     │  ──────────►  │ PromptPanel  │  ──────────► │  clipboard   │
   │ (ChatGPT,    │   (global)    │  NSPanel     │   (Enter)    │   (write)    │
   │  Claude,     │               │              │              └──────┬───────┘
   │  Cursor…)    │ ◄──────────── │              │                     │
   └──────────────┘  paste / focus└──────────────┘                     │
          ▲                         restored                            │
          └────────── CGEvent ⌘V (Accessibility permission) ◄───────────┘
                          fallback: clipboard only + toast
```

1. You press the configured hotkey (`KeyboardShortcuts` library captures it system-wide).
2. PromptPanel snaps an `NSPanel` over the active window, focuses the search field, and shows entries from the current project plus the `Universal` project, sorted by pin → manual → recency → usage count.
3. You type to filter (live, no submit), arrow to choose, press `Enter`.
4. The selected content is **always** written to the system clipboard first (this is the guarantee — clipboard never silently fails).
5. The panel hides, the previous app regains focus, and PromptPanel synthesizes a `⌘V` via `CGEvent`. If Accessibility permission is missing or the target app blocks synthetic events, a toast tells you "Copied — press ⌘V to paste."
6. Execution is logged locally so you can diagnose any per-app paste issue later.

This separation — **clipboard as guarantee, auto-paste as best-effort** — is the single most important design decision in the project.

## Installation

> **System requirement:** macOS 14 (Sonoma) or later. Apple Silicon and Intel both supported.

### Option A — Build from source (current path while pre-release)

```bash
# 1. Clone
git clone https://github.com/tytsxai/PromptPanel.git
cd PromptPanel

# 2. Build the .app bundle (signed ad-hoc by default)
./scripts/build-app.sh

# 3. Move it into Applications (or run from dist/)
open dist/PromptPanel.app
```

Requirements for building:

- Xcode 15+ with the macOS 14 SDK
- Swift 5.10 toolchain (`xcrun swift --version`)

### Option B — Signed & notarized release

GitHub Releases currently carry source/documentation release notes only; no notarized binary asset is attached yet. Until the Developer ID notarization chain is complete, build locally with `./scripts/build-app.sh`.

### First-run setup

1. **Grant Accessibility permission** when prompted. macOS uses this to allow synthetic `⌘V` keystrokes. Without it, PromptPanel still copies to clipboard reliably; you just paste manually.
2. **Set your hotkey** in Settings → Hotkey. The current default is `⌥2`; pick another shortcut if it conflicts with your setup.
3. **Create a project** or start adding entries to `Universal`.

## Quick start

```text
1. ⌥2              → panel appears, search field focused
2. type "review"   → filters to your code-review prompt
3. ↵               → content pasted into the active text field
4. (panel hides)   → keep working
```

You can switch the active project from inside the panel without opening the main window — keyboard-only, no detour.

## Configuration

| Setting | Where | Notes |
|---|---|---|
| Global hotkey | Settings → Hotkey | One shortcut. Toggle behavior: same key dismisses |
| Theme | Settings → Appearance | Light / dark / follow system |
| Launch at login | Settings → General | Uses `SMAppService` |
| Update channel | GitHub Releases (manual) | Sparkle 2 is wired in but disabled until a signed appcast is hosted; subscribe to release notifications and replace the `.app` |
| Database location | `~/Library/Application Support/PromptPanel/promptpanel.db` | Single-file SQLite, easy to back up |
| Logs | `~/Library/Logs/PromptPanel/` | Inspected via the main window's "Runtime Health" |

## Privacy & data

- **Local-first by definition.** Your prompts live in a single SQLite file on your Mac. The app does not POST your content anywhere.
- **No telemetry.** No analytics SDKs, no metrics endpoints, no crash reporting service.
- **Network access** is zero in the current release. Sparkle is bundled but the update feed is not configured, so no outbound calls happen at all unless a future build ships with an appcast.
- **No accounts.** There is nothing to sign in to.
- **Open source.** Audit `Sources/PromptPanel/Core/` to verify any of the above.

If your prompts contain proprietary information — internal architecture, client briefs, NDA-bound context — this is exactly the property you want.

## How does PromptPanel compare to alternatives?

> Quick orientation, not a takedown. These tools are good at what they do.

| | **PromptPanel** | TextExpander | Espanso | Raycast Snippets | Alfred Snippets | Browser prompt extensions |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| Open source | ✅ MIT | ❌ | ✅ GPLv3 | Partial | ❌ | varies |
| macOS native (no Electron / web runtime) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Works in any app (not just browser) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Quick-search panel UI (not just trigger strings) | ✅ | partial | ❌ | ✅ | ✅ | varies |
| Project / context isolation | ✅ first-class | groups | folders | folders | folders | rare |
| Keyboard-only flow | ✅ | partial | ✅ | ✅ | ✅ | varies |
| Local-only / no cloud option | ✅ default | optional, paid tiers nudge cloud | ✅ | account required | ✅ | usually cloud |
| Free | ✅ | $$$ | ✅ | freemium | requires Powerpack | varies |
| Built specifically around AI prompt workflow | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ but browser-only |

**TL;DR:** if you live in the browser only, a browser extension is fine. If you live in Cursor/VS Code/Terminal/Slack/everywhere, you want something native and panel-based. Among native panel-based options, PromptPanel is the open-source, AI-prompt-shaped one.

## Workflow examples

Concrete ways people use PromptPanel day-to-day — these double as the long-tail "how do I..." questions PromptPanel is built to answer.

- **Spin up a fresh ChatGPT / Claude chat with your standard role / system prompt.** Hotkey → type `role` → Enter. No more retyping "You are a senior staff engineer who..." for the 200th time.
- **Drop a Cursor / Copilot project-context block into a new file.** Have a multi-paragraph "here is the architecture, conventions, and constraints" block stored once; paste into any new Cursor session with one keystroke.
- **Paste a code-review checklist into a PR draft.** Long bulleted checklist lives in PromptPanel; one hotkey appends it to a GitHub PR description.
- **Fire a repeating terminal command with the exact flag combo.** `kubectl get pods --context=prod --namespace=… -o jsonpath=…` — typed once, stored, summoned by short search string.
- **Insert a meeting-notes template into Notion / Obsidian / Apple Notes.** Same template every Monday standup → one hotkey, zero copy-paste from a Notes app scratchpad.
- **Push a customer-service / sales reply template into Slack or email.** Different tone per template, picked from a quick-search panel rather than a Notes folder.
- **Switch between projects with isolated prompt sets.** Each project group keeps its own role prompts, snippets, and templates so context never bleeds across clients.

## Tech stack

- **Language:** Swift 5.10
- **UI:** AppKit (`NSPanel`, `NSStatusItem`) + SwiftUI
- **Storage:** SQLite via [GRDB.swift](https://github.com/groue/GRDB.swift)
- **Hotkey:** [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (Carbon Hot Key under the hood)
- **Auto-paste:** `CGEvent` synthesizing ⌘V after focus restoration
- **Login item:** `SMAppService`
- **Updater:** [Sparkle 2](https://sparkle-project.org/)
- **Distribution:** Developer ID + Apple notarization (no Mac App Store)
- **Build:** Swift Package Manager — no Xcode project required

See [docs/技术选型.md](docs/技术选型.md) for the full decision log.

## Project layout

```
PromptPanel/
├── Sources/PromptPanel/
│   ├── App/              # AppDelegate, AppState, lifecycle
│   ├── Core/
│   │   ├── Database/     # SQLite open / migrate / recover
│   │   ├── Repositories/ # Project, Entry, Settings, Log
│   │   ├── Services/     # PanelService, ExecuteService, SearchService…
│   │   ├── Diagnostics/  # Hotkey-to-focus timing
│   │   └── Utils/
│   ├── Integrations/     # Clipboard, Paste (CGEvent), Tray, Hotkey, Updater
│   ├── Features/
│   │   ├── Panel/        # QuickPanelView + ViewModel — the hero feature
│   │   └── MainWindow/   # Library + Settings
│   └── Resources/        # Info.plist, entitlements, AppIcon, Assets
├── Tests/PromptPanelTests/
├── frontend-draft/       # UI source-of-truth (HTML/JSX mockups + screenshots)
├── scripts/              # build-app.sh, notarize, release readiness, restore
├── docs/                 # public architecture, FAQ, PRD, release, ops, handoff docs
├── .github/              # contribution, security, conduct, issue/PR templates, CI
├── llms.txt              # short AI-search / LLM-readable project index
├── codemeta.json         # structured open-source software metadata
└── Package.swift         # SwiftPM package definition
```

## Documentation

The public documentation set is part of the repository:

- [Documentation index](docs/README.md)
- [FAQ](docs/FAQ.md)
- [Product PRD](docs/项目快贴-PRD.md)
- [Project introduction](docs/项目介绍.md)
- [Architecture](docs/架构说明.md)
- [Core modules and logic](docs/关键模块与核心逻辑.md)
- [API and feature contract](docs/API与功能说明.md)
- [Configuration](docs/配置说明.md)
- [Deployment](docs/部署说明.md)
- [Development standards](docs/开发规范.md)
- [Usage examples](docs/使用示例.md)
- [Operations and troubleshooting](docs/运维与排错指南.md)
- [Maintainer handoff guide](docs/接手维护指南.md)
- [Docs/code sync matrix](docs/文档与代码同步矩阵.md)
- [Release and recovery](docs/生产发布与恢复手册.md)
- [Roadmap and contribution guide](docs/路线图与贡献指南.md)
- [AI search and discoverability](docs/ai-search-discoverability.md)
- [Full LLM context](docs/ai-search/llms-full.txt)
- [Search metadata JSON-LD](docs/search-metadata.schema.jsonld)
- [Contributing](.github/CONTRIBUTING.md)
- [Security](.github/SECURITY.md)
- [CodeMeta software metadata](codemeta.json)

For answer engines and repository-aware AI tools, start with [llms.txt](llms.txt) or the expanded [llms-full.txt](docs/ai-search/llms-full.txt).

## Search & AI Discoverability

PromptPanel keeps classic SEO and GEO surfaces in-repo so users and answer engines can identify the project accurately:

- `README.md` and `README.zh-CN.md` give the human landing-page summary and current screenshots.
- [llms.txt](llms.txt) is the short AI-readable index for repository-aware tools.
- [docs/ai-search/llms-full.txt](docs/ai-search/llms-full.txt) is the expanded answer-engine context with FAQ-style answers.
- [codemeta.json](codemeta.json) and [Schema.org JSON-LD](docs/search-metadata.schema.jsonld) describe the app for software catalogs, search crawlers, and future docs-site publishing.
- [AI search and discoverability](docs/ai-search-discoverability.md) defines the canonical wording, search-intent map, and maintenance checklist.

## Roadmap

PromptPanel follows a **deliberately small** roadmap. The PRD lists items that are explicitly off the table forever (cloud sync, teams, workflow orchestration). Within scope:

- [x] v1.0 — main link complete: hotkey → search → execute, projects, clipboard fallback, light/dark, login item, Sparkle, signing & notarization scripts
- [x] JSON / Markdown import & export, with automatic backup before import
- [ ] One-tap "repeat last entry"
- [ ] Variable templates (`{{name}}` style) — only if it can be added without slowing the main link

See [docs/路线图与贡献指南.md](docs/路线图与贡献指南.md) for prioritization rules, [CHANGELOG.md](CHANGELOG.md) for what's shipped, and [issues](https://github.com/tytsxai/PromptPanel/issues) for public planning.

## Frequently asked questions

For a longer FAQ, see [FAQ.md](docs/FAQ.md). The greatest hits:

### Is PromptPanel free?

Yes. MIT license. No paid tier, no usage cap, no account.

### Does it work with Apple Silicon (M1/M2/M3/M4)?

Yes — it builds as a universal binary. Tested on both Apple Silicon and Intel macOS 14+.

### Does it send my prompts anywhere?

No. The current release makes zero network calls. Sparkle is bundled but the update feed is not configured in this build, so no outbound traffic happens at all. Your prompt content never leaves your Mac.

### Why does it ask for Accessibility permission?

To synthesize a `⌘V` keystroke after the panel hides and your previous app regains focus. Without this permission the app still works — it just stops at the clipboard step and shows you a "press ⌘V to paste" toast.

### Will you add cloud sync / team sharing / workflows?

No, deliberately. Those are listed as **permanent non-goals** in the [PRD §4.2](docs/项目快贴-PRD.md). The product's identity is "single-user, local-only, fast." Adding any of those would change what the product is.

### Why not Electron / Tauri?

The hottest paths in this product (global hotkey timing, focus restoration, synthetic keystroke injection, accessibility permission flow) are macOS system-integration concerns. A cross-platform shell adds latency and indirection without buying any features that matter for this product. See [docs/技术选型.md](docs/技术选型.md) for the full reasoning.

### How do I report a bug or request a feature?

Open an issue: <https://github.com/tytsxai/PromptPanel/issues>. Please use the templates — they'll save us both round-trips.

### How do I import my existing prompts from another tool?

Use `Settings → Maintenance → Import JSON` for full PromptPanel library transfers, or `Import MD` for Markdown prompt collections. Imports automatically create a local database backup first. `Export JSON` is best for lossless migration; `Export MD` is best for reviewable sharing.

## Contributing

PRs welcome — please read [CONTRIBUTING.md](.github/CONTRIBUTING.md) first. Two non-obvious rules:

1. **UI changes must align with `frontend-draft/`.** That directory is the source of truth for visuals; don't ship a Swift view that contradicts the JSX mockup.
2. **Stay inside the PRD's scope.** If a proposal would push the product toward cloud / teams / workflows, it's a "no" regardless of how well-implemented it is. This isn't gatekeeping — it's the reason the tool is fast and trustworthy.

## Acknowledgments

PromptPanel stands on:

- [GRDB.swift](https://github.com/groue/GRDB.swift) by Gwendal Roué
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus
- [Sparkle](https://github.com/sparkle-project/Sparkle) by the Sparkle team

…and the broader Swift / AppKit community whose docs and Stack Overflow answers made the system-integration paths possible.

## License

[MIT](LICENSE) © 2026 tytsxai and PromptPanel contributors.

---

<sub>**Keywords** (so you can actually find this when you search): macOS prompt manager · AI prompt launcher · ChatGPT prompt manager macOS · Claude prompt library · Cursor snippet manager · Copilot prompt template launcher · open-source TextExpander alternative · Espanso alternative · Raycast snippets alternative · Alfred snippet replacement · global hotkey paste macOS · local-first prompt library · offline AI prompt storage · native Swift NSPanel app · AI workflow productivity tool · prompt template manager macOS · snippet launcher macOS · keyboard-first prompt picker · LLM prompt library Mac · prompt engineering toolkit macOS · Cursor prompt manager · fast local prompt launcher for AI · NDA-safe prompt storage.</sub>

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=tytsxai/PromptPanel&type=Date)](https://www.star-history.com/#tytsxai/PromptPanel&Date)
