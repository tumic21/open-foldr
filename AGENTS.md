# AGENTS

Guidance for coding agents and contributors working in this repository.

## Repository Rules

- Use `develop` as the main integration branch.
- Use `main` for stable release milestones.
- Keep pull requests focused and small.
- Update docs when behavior, API, or security model changes.

## Planning Workspace

- `_project/` is a local planning workspace for notes, drafts, and internal task planning.
- `_project/` is intentionally ignored by git and is not part of version-controlled source.
- Do not depend on `_project/` files at runtime.
- If a planning item becomes implementation-relevant, move it into tracked docs or source files.
- During implementation, mark completed steps and phases in implementation plans and specifications.

## Security and Safety

- Follow `SECURITY.md` for vulnerability handling.
- Preserve filesystem sandbox guarantees and role-based access controls.
- Treat protocol/security changes as high-risk and require tests.

## Testing and CI Policy

- This project MUST use GitHub Actions for automated testing on pull requests and pushes to `develop`.
- Test strategy MUST include all three layers:
	- Unit tests: validate isolated functions, utilities, and small components.
	- Integration tests: validate interactions between modules, API handlers, storage, and protocol flows.
	- System tests: validate end-to-end behavior for host and guest workflows under realistic conditions.
- Pull requests SHOULD include or update tests for changed behavior.
- **Every new feature MUST be accompanied by tests in the same commit.** Do not implement a feature and defer its tests to a later phase or PR.
- Changes that affect protocol, security, permissions, filesystem access, or conflict handling MUST include integration or system test coverage.
- Failing checks in any required test layer MUST block merge until resolved.

## Documentation Pointers

- Product spec: `_project/spec/spec.md`
- Protocol draft: `_project/spec/protocol-v1.md`
- Threat model: `_project/spec/security.md`
- Implementation board: `_project/spec/implementation-board.md`
