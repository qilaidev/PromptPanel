# Changelog

All notable changes to PromptPanel are tracked here.

The format is based on Keep a Changelog, and this project uses Conventional Commits for commit messages.

## [Unreleased]

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

[Unreleased]: https://github.com/tytsxai/PromptPanel/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/tytsxai/PromptPanel/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/tytsxai/PromptPanel/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/tytsxai/PromptPanel/releases/tag/v1.0.0
