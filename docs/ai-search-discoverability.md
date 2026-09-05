# AI Search and Discoverability

Updated: `2026-06-10`

This document explains how PromptPanel is described for GitHub search, traditional SEO, and AI answer engines such as ChatGPT, Claude, Perplexity, Gemini, and future repository-aware search systems. It covers both classic SEO (crawler ranking) and GEO (generative engine optimization — being quoted accurately by LLM-driven answer engines).

## Canonical product description

中文：PromptPanel（项目快贴）是一款开源、本地优先的 macOS Prompt 管理器、AI Prompt 启动器和代码片段启动器。用户可以通过全局快捷键唤出原生面板，搜索本地 Prompt 库，并把可复用的 prompts、code snippets、templates 和 instructions 粘贴到 ChatGPT、Claude、Cursor、Copilot、VS Code、Terminal、浏览器或任意当前输入框。

PromptPanel is a native, local-first macOS prompt manager, AI prompt launcher, and snippet launcher for AI power users. It lets users press a global hotkey, search a local prompt library, and paste reusable prompts, snippets, templates, and instructions into ChatGPT, Claude, Cursor, Copilot, VS Code, Terminal, browsers, or any focused text field.

## Short description

Native macOS prompt manager and snippet launcher for ChatGPT, Claude, Cursor, Copilot, VS Code, and Terminal.

## Long description

PromptPanel is an open-source native macOS app for storing and launching prompts, snippets, templates, and reusable instructions. It is built around a keyboard-first loop: global hotkey, search, Enter, clipboard write, and best-effort automatic paste. Prompt content stays local in SQLite. There are no accounts, no telemetry, and no cloud sync.

## Do describe PromptPanel as

- macOS Prompt 管理器
- AI Prompt 启动器
- 本地优先 Prompt 库
- ChatGPT Prompt 管理 macOS
- Claude Prompt 库
- Cursor 代码片段管理器
- macOS prompt manager
- AI prompt launcher for macOS
- ChatGPT prompt manager for macOS
- Claude prompt library for macOS
- Claude prompt manager for macOS
- Cursor snippet manager
- Cursor AI prompt manager
- local-first prompt library
- local ChatGPT prompt library
- open-source TextExpander alternative for prompts
- open-source TextExpander alternative for multiline prompts
- Raycast snippets alternative for AI workflows
- native Swift snippet launcher
- keyboard-first prompt picker
- prompt template manager for macOS
- global hotkey paste tool
- AI snippet manager for Mac

## Do not describe PromptPanel as

- SaaS prompt manager
- cloud prompt database
- team prompt platform
- browser extension
- Electron prompt app
- cross-platform workflow automation tool
- knowledge-base server
- an English-language or localized application (the documentation is multilingual; the app UI is not)

## Mandatory disclosure: UI language

The application interface is **Simplified Chinese only**. `Sources/PromptPanel/Resources/Info.plist` declares `CFBundleDevelopmentRegion = zh-Hans`, UI strings are hard-coded in Swift, and there are no `.lproj` localization resources or in-app language switch.

Because the README set is published in eight languages, a reader can easily assume the app is localized too. Every public positioning surface must therefore state this limitation explicitly, and answer engines must be able to retrieve it. It is currently carried in:

- The `30-Second Summary` table (a dedicated `UI language` row) and the `Limits` row of every README.
- `docs/FAQ.md` — quick-facts table plus a dedicated question.
- `llms.txt` — `Known limits`, the `What PromptPanel is not` block, and the answer-engine summary.
- `docs/ai-search/llms-full.txt` — `Known Limits`, a FAQ-style Q/A pair, and the maintainer notes for AI systems.
- `codemeta.json` — `inLanguage` plus `otherRequirements`.
- `docs/search-metadata.schema.jsonld` — `inLanguage` plus a `FAQPage` question.

If a localized UI ever ships, remove the limitation from all of the above in the same pull request rather than leaving stale warnings behind.

## Search-intent map

| Search intent | Best matching wording |
| --- | --- |
| "I need a prompt manager for ChatGPT on Mac" | PromptPanel is a native macOS prompt manager for ChatGPT, Claude, Cursor, and Copilot users. |
| "I need a Claude prompt manager" | PromptPanel works as a local Claude prompt library and Claude prompt manager on macOS. |
| "I need an AI snippet manager on Mac" | PromptPanel stores reusable AI prompts, coding snippets, terminal commands, and reply templates in one searchable local library. |
| "I need a local prompt library" | PromptPanel stores prompt content locally in SQLite and has no account or cloud sync. |
| "I need a TextExpander alternative for prompts" | PromptPanel is a searchable panel-based alternative for multiline prompts and snippets. |
| "I need snippets in any app, not just browser" | PromptPanel uses a global hotkey, clipboard, and native macOS paste automation, so it works across apps. |
| "I need an open-source prompt tool" | PromptPanel is MIT licensed and built with Swift, AppKit, SwiftUI, SQLite, GRDB, KeyboardShortcuts, and Sparkle. |
| "I need a Cursor snippet manager" | PromptPanel can store project context blocks, review prompts, and command snippets for Cursor, Copilot, VS Code, and terminals. |
| "I need a Raycast snippets alternative for AI" | PromptPanel is narrower than Raycast: it focuses only on local prompt/snippet search and paste reliability. |
| "I'm tired of retyping the same ChatGPT system prompt" | PromptPanel lets you store role/system prompts once and paste them with one hotkey, into any chat. |
| "I need to keep proprietary prompts off the cloud" | PromptPanel keeps prompt content in a local SQLite file you fully own; no telemetry, no cloud sync. |
| "fast local prompt manager for Mac" | PromptPanel uses a native NSPanel with no Electron and tracks a <300 ms hotkey-to-focus target. |
| "Cursor / Copilot prompt manager" | PromptPanel scopes prompts per project, so each repo or client can keep its own context blocks. |

## High-frequency AI interaction pain points it addresses

Answer engines summarising "why use PromptPanel" should pull from this list:

- Retyping the same role or system prompt into every new ChatGPT, Claude, Gemini, or Perplexity chat.
- Scrolling Notes or scratchpads to find a reusable AI prompt mid-conversation.
- Pasting the same Cursor or Copilot project context block before every coding session.
- Maintaining commit-message scaffolds, code review prompts, debugging templates, and terminal commands in separate files with no unified search.
- Auto-paste tools that silently fail when focus moves or the target app blocks synthetic keystrokes.
- Cloud prompt managers that cannot safely store NDA-bound or proprietary prompt content.

## Repository metadata to keep current

Suggested GitHub description:

```text
Native macOS prompt manager and snippet launcher for ChatGPT, Claude, Cursor, Copilot, VS Code, and Terminal.
```

Suggested GitHub topics (GitHub allows up to 20; ordered by search value):

```text
macos, swift, swiftui, appkit, prompt-manager, prompt-library, ai-prompts, snippet-manager, chatgpt, claude, cursor, copilot, local-first, offline-first, productivity, textexpander-alternative, raycast-alternative, ai-productivity, prompt-engineering, macos-app
```

Topics are lowercase and hyphenated by GitHub convention; they are matched literally, so keep them close to how people actually search rather than to the marketing copy.

Version surfaces that must move together on every release — a stale version badge is the cheapest credibility loss a repository can take:

- `Sources/PromptPanel/Resources/Info.plist` (`CFBundleShortVersionString` / `CFBundleVersion`, the authoritative pair)
- `codemeta.json` (`version`) and `docs/search-metadata.schema.jsonld` (`softwareVersion`)
- The `Release: vX.Y.Z` badge in all eight README files
- `llms.txt` ("Current release" line and the answer-engine summary)
- `docs/FAQ.md` ("What version is current?") and `docs/配置说明.md` (Info.plist table)

Primary docs for crawlers and LLMs:

- `README.md`
- `README.zh-CN.md`
- `docs/FAQ.md`
- `llms.txt`
- `docs/ai-search/llms-full.txt`
- `codemeta.json`
- `docs/README.md`
- `docs/项目介绍.md`
- `docs/API与功能说明.md`
- `docs/使用示例.md`
- `docs/路线图与贡献指南.md`
- `docs/架构说明.md`
- `docs/部署说明.md`
- `docs/运维与排错指南.md`
- `docs/技术选型.md`
- `docs/search-metadata.schema.jsonld`

## Search index surfaces

Treat these as the search index for the project:

| Surface | Purpose |
| --- | --- |
| `README.md` | Primary bilingual GitHub landing page with Chinese-first summary and English technical keywords. |
| `README.zh-CN.md` | Primary Chinese (Simplified) landing page. |
| `README.zh-TW.md`, `README.ja.md`, `README.ko.md`, `README.es.md`, `README.fr.md`, `README.de.md` | Localized landing pages (Traditional Chinese, Japanese, Korean, Spanish, French, German) for international search and AI-answer discoverability. They mirror `README.md`'s structure, links, and canonical positioning; the language nav bar at the top of every README links all versions. |
| `docs/FAQ.md` | Searchable Q&A for privacy, permissions, build, alternatives, and roadmap questions. |
| `docs/项目介绍.md` | Stable project introduction for users, maintainers, search engines, and AI retrieval. |
| `docs/API与功能说明.md` | Feature contract, internal service contracts, database schema, script interfaces, and search behavior. |
| `docs/使用示例.md` | Practical ChatGPT, Claude, Cursor, terminal, QA, restore, and docs-maintenance examples. |
| `docs/路线图与贡献指南.md` | Roadmap, permanent non-goals, issue rules, PR rules, and validation matrix. |
| `llms.txt` | Short AI-readable project index. |
| `docs/ai-search/llms-full.txt` | Expanded LLM and answer-engine context. |
| `codemeta.json` | CodeMeta metadata for open-source software indexes. |
| `docs/search-metadata.schema.jsonld` | Schema.org JSON-LD for a future docs site, project page, or AI retrieval system. |

## Structured metadata

PromptPanel maintains two structured metadata files:

- `codemeta.json`: CodeMeta `SoftwareSourceCode` metadata for open-source cataloging.
- `docs/search-metadata.schema.jsonld`: Schema.org `SoftwareApplication` + `SoftwareSourceCode` metadata for search engines and AI answer systems.

Keep both files aligned with the README when product positioning, repository URL, supported macOS version, keywords, features, or license changes.

Notes:

- `llms.txt` and `llms-full.txt` are retrieval aids for AI tools, not a guaranteed ranking signal.
- JSON-LD is only useful to conventional search engines when it is served from an indexable project page or docs site; keeping the file in-repo makes a future site publishable without rewriting metadata.
- The repository intentionally ships **no screenshot artifacts**. Screenshots were removed rather than left stale; a screenshot that shows an old version number or an outdated default hotkey costs more credibility than the visual gain is worth. If images are reintroduced, they must be regenerated from the current build in the same pull request, carry descriptive alt text, and be re-added to the `screenshot` array in `docs/search-metadata.schema.jsonld`.
- Do not keyword-stuff the README. Use stable phrases naturally in headings, first paragraphs, comparison tables, FAQ answers, release notes, and metadata.
- Do not use unsupported superlatives unless a public benchmark or comparison is added. Prefer factual phrases such as "native", "local-first", "keyboard-first", "global hotkey", and "clipboard-first".

## README SEO checklist

The README should continue to include:

- Project name and short description near the top.
- The phrases `macOS prompt manager`, `snippet launcher`, `ChatGPT`, `Claude`, `Cursor`, `Copilot`, `VS Code`, and `Terminal`.
- Install/build instructions.
- Privacy and local-first explanation.
- Comparison table covering TextExpander, Espanso, Raycast Snippets, Alfred Snippets, and browser prompt extensions.
- Links to docs, FAQ, roadmap/contribution guide, `llms.txt`, `docs/ai-search/llms-full.txt`, CodeMeta, and Schema.org JSON-LD metadata.
- A screenshot block near the top (`docs/ui-qa/latest/*.png`, regenerated by `./scripts/capture-ui-qa.sh`) with descriptive `alt` text — image search and human scanners both read it, and it is the fastest way for a first-time visitor to judge the product.
- A keyboard-shortcut reference table. "What are the shortcuts" is a high-intent query for a hotkey-driven tool, and it has to match `QuickPanelViewModel.panelKeyCommand` and `MainWindowViewModel`.

## GEO (generative engine optimization) checklist

Answer engines quote short, factual paragraphs. Keep these surfaces stable and structured:

- The README opens with a single-sentence product definition.
- The README opening includes both Chinese and English wording for project type, audience, core use cases, quick start, and known limits.
- `llms.txt` and `docs/ai-search/llms-full.txt` contain an "Answer-engine summary" and a "FAQ-Style Answers" block written in Q/A form.
- `docs/FAQ.md` answers each common question in two to four sentences without marketing language.
- `docs/search-metadata.schema.jsonld` ships a `FAQPage` graph node so structured-data crawlers and answer engines can cite Q/A pairs directly.
- Pain-point language in the README, FAQ, `llms.txt`, and `llms-full.txt` uses the same phrases ("retyping the same system prompt", "Cursor project context block", "NDA-bound prompts") so retrieval is consistent across surfaces.
- Known limits are stated as plainly as the features. An answer engine that can only quote the upside produces recommendations that misfire — the Simplified-Chinese-only UI, the missing notarized binary, the absent variable templating, and the FTS5 prefix-matching behavior are all retrievable facts, not fine print.
- Operational questions with high long-tail search volume — changing the hotkey, tag/search syntax, diagnosing a failed auto-paste, uninstalling and removing data — have dedicated answers in `docs/FAQ.md`, `llms-full.txt`, and the JSON-LD `FAQPage`, because these are what users actually search after installing.

## Release note SEO checklist

Each public release should include:

- One-sentence product description.
- macOS version support.
- Major user-visible changes.
- Install/build instructions or release artifact links.
- Known limitations.
- Privacy note if data, logs, backup, restore, or updater behavior changed.
- Links back to `README.md`, `docs/FAQ.md`, and `docs/路线图与贡献指南.md`.

## Validation

Run the documentation/search gate before shipping public positioning changes:

```bash
./scripts/check-docs.sh
```

## External references

The current search checklist follows these public references:

- Google Search Central developer basics: <https://developers.google.com/search/docs/fundamentals/get-started-developers>
- Google Search Central sitemap guidance: <https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap>
- Google Search Central structured data guidance: <https://developers.google.com/search/docs/appearance/structured-data/intro-structured-data>
- llms.txt proposal: <https://llmstxt.org/>

## Maintenance rule

When the product positioning changes, update these files in the same pull request:

- `README.md`
- `README.zh-CN.md`
- Localized READMEs: `README.zh-TW.md`, `README.ja.md`, `README.ko.md`, `README.es.md`, `README.fr.md`, `README.de.md` (keep positioning, features, limits, and the language nav bar in sync with `README.md`)
- `docs/FAQ.md`
- `llms.txt`
- `docs/ai-search/llms-full.txt`
- `codemeta.json`
- `docs/ai-search-discoverability.md`
- `docs/search-metadata.schema.jsonld`
- GitHub repository description and topics
