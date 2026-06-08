# Project Documentation Specification

## Purpose

PromptPanel documentation is part of the maintained product surface. It must let a new maintainer understand, build, verify, release, troubleshoot, recover, and extend the project without private handoff context.

## Requirements

### Requirement: Maintainer Documentation Coverage

The repository MUST keep versioned documentation for:

- architecture and runtime boundaries
- local, container, and server deployment semantics
- configuration layers, environment variables, storage paths, and user settings
- key modules, core execution logic, search, persistence, import/export, and release scripts
- operations, diagnostics, troubleshooting, recovery, and rollback
- development rules and documentation/code synchronization rules

#### Scenario: A maintainer starts from the repository

- **GIVEN** a maintainer has only the repository contents
- **WHEN** they open `docs/README.md`
- **THEN** they can reach the architecture, deployment, configuration, core logic, operations, handoff, and documentation sync pages
- **AND** those pages describe current code and script behavior rather than future plans.

### Requirement: Documentation And Code Stay Synchronized

The repository MUST provide an executable documentation gate that checks required documentation entry points, local Markdown links, stale terms, environment variable coverage, script coverage, search metadata, and CI integration.

#### Scenario: A code or script change introduces a new operational surface

- **GIVEN** a change modifies source, scripts, CI, packaging, configuration, or UI baseline behavior
- **WHEN** the change is prepared for handoff
- **THEN** the corresponding `docs/` pages listed in `docs/文档与代码同步矩阵.md` are updated
- **AND** `./scripts/check-docs.sh` passes.

### Requirement: Deployment Documentation Reflects Product Reality

Deployment documentation MUST distinguish supported runtime deployment from supporting distribution infrastructure.

#### Scenario: Someone asks for local, container, and server deployment

- **GIVEN** PromptPanel is a native macOS GUI app
- **WHEN** deployment documentation describes local, container, and server options
- **THEN** local macOS `.app` deployment is documented as the only product runtime
- **AND** containers and ordinary servers are documented only as build, CI, static hosting, appcast, or distribution support surfaces.

### Requirement: OpenSpec Change Trail

Documentation-system work MUST have an OpenSpec change record when it changes the project handoff baseline.

#### Scenario: The documentation system is expanded or reorganized

- **GIVEN** a documentation-system change affects maintainer onboarding, release, operations, or synchronization rules
- **WHEN** implementation starts
- **THEN** `openspec/changes/<change-id>/proposal.md`, `tasks.md`, and relevant spec deltas are present
- **AND** accepted current behavior is reflected under `openspec/specs/`.

### Requirement: Reliability-Sensitive Behavior Is Captured In Handoff Docs

Reliability-sensitive behavior that affects data consistency or shortcut execution MUST be captured in source tests, OpenSpec, and maintainer documentation.

#### Scenario: Library import and quick panel ranking change

- **GIVEN** library import transaction behavior or quick panel ranking keys change
- **WHEN** the change is prepared for handoff
- **THEN** regression tests cover the behavior
- **AND** OpenSpec describes the accepted behavior
- **AND** affected `docs/` pages describe the operational and maintenance implications.
