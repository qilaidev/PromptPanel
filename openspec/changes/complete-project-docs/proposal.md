# Complete Project Documentation And Stability Baseline

## Why

PromptPanel already has many useful documents, but the handoff baseline needs to be closed as a coherent system. A new maintainer should not have to infer the architecture, deployment limits, configuration layers, import/export reliability rules, backup/recovery behavior, release checks, or docs/code sync expectations from scattered source files.

The project instructions also require OpenSpec-driven development for development tasks. This change records the documentation-system work before updating the maintained docs.

During the same audit, two reliability-sensitive implementation gaps were found: JSON library import could leave partial writes after a mid-import failure, and the quick panel local ranking could ignore manual `sortOrder`. Both affect maintained behavior and must be captured in the same baseline before handoff.

## What Changes

- Add an OpenSpec current specification for the project documentation system.
- Add this OpenSpec change record with proposal, tasks, and requirement delta.
- Update documentation entry points and handoff pages to reflect the current code and script reality.
- Tighten deployment documentation around local `.app` runtime versus container/server distribution support.
- Document recent reliability-sensitive implementation facts:
  - JSON library import creates a backup after parsing/validation and wraps writes in one SQLite transaction.
  - `ProjectRepository.writeInTransaction` is an explicit cross-repository transaction boundary.
  - quick panel ranking preserves manual `sortOrder` before usage count.
- Keep the executable documentation gate as the verification boundary.
- Add regression coverage for import rollback and quick panel manual ordering.

## Scope

In scope:

- `openspec/`
- `docs/`
- documentation navigation and maintenance guidance
- `LibraryTransferService` JSON/Markdown import write boundary
- quick panel ranking after local filtering

Out of scope:

- database schema changes
- release artifact generation
- containerizing or serverizing the app runtime

## Risks

- Documentation can become broad but still hard to maintain if ownership rules are vague. This is mitigated by `docs/文档与代码同步矩阵.md` and `scripts/check-docs.sh`.
- OpenSpec can become ceremonial if it is not connected to actual docs. This change keeps OpenSpec focused on the documentation system and points back to executable verification.

## Validation

- `./scripts/check-docs.sh`
- `swift build`
- `swift test` when the host has a working XCTest runner
- targeted regression tests:
  - `testLibraryJSONImportRollsBackPartialWritesWhenEntryInsertFails`
  - `testQuickPanelRankingRespectsManualSortOrderBeforeUsage`
