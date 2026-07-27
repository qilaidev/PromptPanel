# Changelog

All notable changes to PromptPanel are tracked here.

The format is based on Keep a Changelog, and this project uses Conventional Commits for commit messages.

## [Unreleased]

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

[Unreleased]: https://github.com/tytsxai/PromptPanel/compare/v1.1.2...HEAD
[1.1.2]: https://github.com/tytsxai/PromptPanel/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/tytsxai/PromptPanel/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/tytsxai/PromptPanel/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/tytsxai/PromptPanel/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/tytsxai/PromptPanel/releases/tag/v1.0.0
