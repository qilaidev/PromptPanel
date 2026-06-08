# Tasks

- [x] Inspect current source, scripts, CI, and existing documentation structure.
- [x] Create OpenSpec documentation-system spec and change record.
- [x] Update `docs/README.md` as the maintained documentation map.
- [x] Update architecture, deployment, configuration, core logic, operations, handoff, and sync docs.
- [x] Wrap library import writes in a single SQLite transaction and document the rollback boundary.
- [x] Align quick panel local ranking with repository ordering for manual `sortOrder`.
- [x] Add regression coverage for import rollback and quick panel manual ordering.
- [x] Verify required links and stale-term checks through `./scripts/check-docs.sh`.
- [x] Run Swift validation (`swift build` passed; `swift test` returned success but this host lacks `xctest`, so it only proved test-target buildability).
