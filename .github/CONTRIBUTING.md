# Contributing to PromptPanel

Thanks for considering a contribution. PromptPanel is a small, intentionally focused project — that focus is what makes it fast and trustworthy, and it's also what makes contributing here a little different from a generic open-source project. Please read this guide before opening a non-trivial issue or PR.

## TL;DR

1. Bug fix or small UX polish? → open a PR, reference an issue if one exists.
2. New feature? → **open an issue first.** The PRD's product boundaries are strict; we'd rather agree on scope before you write Swift.
3. UI change? → align with `frontend-draft/` (the visual source of truth) before touching SwiftUI/AppKit.
4. Cloud sync / teams / workflows? → out of scope by design. See [PRD §4.2](../docs/项目快贴-PRD.md).
5. Docs, SEO, or AI-search wording changed? → run `./scripts/check-docs.sh` and update `llms.txt`, `docs/ai-search/llms-full.txt`, `codemeta.json`, and the Schema.org metadata if needed.

## Project boundaries (read this once)

PromptPanel has **three** rings of features:

- **In-scope (v1):** the core hotkey → search → execute loop, projects, clipboard fallback, basic management UI.
- **Permanently out of scope (4.2):** team collaboration, cloud sync (under any name), complex workflow orchestration. These are product boundaries, not deferred backlog items.
- **Maybe later (4.3):** clipboard history, knowledge-base ingestion, lightweight reminders, variable templates. Only considered if they don't slow the main link.

If your idea falls in 4.2, please pick a different idea. If you're unsure which ring an idea belongs to, open an issue and ask.

For the current public roadmap, accepted contribution themes, and validation matrix, see [docs/路线图与贡献指南.md](../docs/路线图与贡献指南.md).

## Local development

### Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 15+ with the macOS 14 SDK
- Swift 5.10 toolchain (`xcrun swift --version`)

### Build & run

```bash
# Build via SwiftPM (fast)
swift build

# Or build the .app bundle
./scripts/build-app.sh
open dist/PromptPanel.app
```

### Tests

```bash
swift test
```

Add tests for behaviour, not for implementation details. The most useful tests in this repo cover ordering rules, project migration, search filtering, and the execute service's clipboard fallback path.

### Documentation and search gate

```bash
./scripts/check-docs.sh
```

Run this for README, FAQ, docs, metadata, SEO, LLM-index, or public positioning changes. It checks required docs, stale wording, important search keywords, CodeMeta JSON, Schema.org JSON-LD, and navigation links.

### Pre-release sanity check

Before tagging a release we run:

```bash
./scripts/release-readiness.sh --output-dir /tmp/promptpanel-ready-check
```

If you're proposing changes to packaging, signing, or notarization, run this and attach the report to your PR.

## UI changes — `frontend-draft/` is the source of truth

This repo has an unusual rule: **`frontend-draft/` is the visual source of truth.** Before changing a SwiftUI view, the corresponding HTML/JSX mockup in `frontend-draft/` should already reflect the change. This keeps Swift views and design intent from drifting.

If you propose a UI change:

1. Update `frontend-draft/components/<view>.jsx` (or `index.html` if it's a layout-level change) with the new structure.
2. Make the visual change visible in the mockup itself — the repository no longer stores screenshot artifacts. Run `./scripts/capture-ui-qa.sh` locally if you need rendered images for review; its output is git-ignored.
3. Then update the Swift view to match.
4. In the PR, mention the JSX file your Swift change is aligning to.

## Coding style

- Swift code follows the existing module layout: `App/`, `Core/{Database,Repositories,Services,Diagnostics,Utils}`, `Integrations/`, `Features/`. Don't introduce new top-level dirs without discussion.
- Prefer dependency injection over singletons. `AppDelegate` is the assembly root.
- Keep ViewModels free of AppKit/UIKit imports where possible.
- Public APIs across modules: document with a one-line `///` comment when the name doesn't carry the meaning.
- No new third-party dependencies without a discussion in an issue. Current deps: GRDB, KeyboardShortcuts, Sparkle. Each pulls its weight; the bar is high.

## Commit messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add X
fix: prevent Y
perf: cache Z
chore: bump dep
docs: clarify install
test: cover ordering edge case
```

Both English and Chinese commit messages are fine — the existing history mixes them. Pick whichever expresses the change most precisely.

## Pull requests

- Keep PRs small and focused. One concern per PR.
- Update the relevant doc (`README.md`, `CHANGELOG.md`'s `[Unreleased]`, or `docs/`) in the same PR.
- Tests are required for behaviour changes, optional for refactors and docs.
- Run `./scripts/check-docs.sh` when docs, search metadata, examples, roadmap, or public positioning changes.
- Note the OS version and architecture you tested on (e.g. *"verified on macOS 14.5, Apple Silicon"*).
- For UI changes, attach a before/after screenshot.

## Reporting bugs

Please use the bug report issue template. The two pieces of information that solve 80% of bug reports are:

1. **Which target app** (ChatGPT web, Claude web, Cursor, VS Code, Terminal, …) and which paste outcome you saw (copied + pasted / copied only / nothing happened).
2. **The execution log** (main window → Runtime Health → Recent executions). Paste the relevant lines.

## Security

Please don't open public issues for security problems. See [SECURITY.md](SECURITY.md) for the private disclosure path.

## Code of conduct

Be kind. We follow the [Contributor Covenant](CODE_OF_CONDUCT.md). Disagreements are fine; bad-faith arguments are not.

## License

By contributing, you agree that your contributions will be licensed under the MIT license that covers this project.
