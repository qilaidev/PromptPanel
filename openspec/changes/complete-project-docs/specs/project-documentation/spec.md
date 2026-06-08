## ADDED Requirements

### Requirement: Complete Maintainer Handoff Documentation

The project SHALL provide a complete, versioned maintainer documentation system in `docs/` that covers architecture, deployment, configuration, key modules, operations, troubleshooting, development workflow, and documentation/code synchronization.

#### Scenario: New maintainer receives only repository access

- **GIVEN** the maintainer has a clean clone of PromptPanel
- **WHEN** they read `docs/README.md`
- **THEN** they can identify the correct documents for architecture, deployment, configuration, core logic, operations, release, recovery, and extension work
- **AND** they can run the documented build and validation commands without relying on private notes.

### Requirement: Reality-Based Deployment Guidance

The deployment documentation SHALL describe local macOS `.app` execution as the only product runtime and SHALL describe containers and servers only as CI, static hosting, appcast hosting, or distribution support surfaces.

#### Scenario: Operator asks for container deployment

- **GIVEN** the operator wants to deploy PromptPanel in a container
- **WHEN** they read `docs/部署说明.md`
- **THEN** the document clearly states that the product cannot run in a Linux container
- **AND** it describes what container or server infrastructure may still do for release distribution.

### Requirement: Documentation Synchronization Gate

The repository SHALL keep `scripts/check-docs.sh` as the executable documentation gate and SHALL document when to update each major document.

#### Scenario: A developer changes scripts, configuration, or runtime behavior

- **GIVEN** the developer changes a behavior covered by source, scripts, CI, packaging, configuration, or UI baseline
- **WHEN** they prepare the change for review
- **THEN** they update the corresponding documents listed in `docs/文档与代码同步矩阵.md`
- **AND** they run `./scripts/check-docs.sh`.

### Requirement: Library Import Atomicity Is Documented And Verified

JSON and Markdown library import writes SHALL keep project and entry mutations in one SQLite transaction after the import file has been parsed, validated, and backed up.

#### Scenario: Entry write fails during import

- **GIVEN** an import payload contains a new project and a new entry
- **WHEN** entry insertion fails after the project write has been attempted
- **THEN** the import throws
- **AND** the newly imported project is not persisted
- **AND** the newly imported entry is not persisted
- **AND** the write-before backup remains the recovery boundary.

### Requirement: Quick Panel Ranking Preserves Manual Ordering

The quick panel local ranking SHALL keep the repository ordering contract after local filtering: pinned entries first, then higher `sortOrder`, then recency, usage count, current project priority, update time, and id.

#### Scenario: Lower usage entry has higher manual order

- **GIVEN** two candidate entries are both in the active project
- **AND** one entry has higher `sortOrder` but lower `useCount`
- **WHEN** the quick panel ranks entries for shortcut display
- **THEN** the entry with higher `sortOrder` appears first.
