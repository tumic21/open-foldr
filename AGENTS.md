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

## Security and Safety

- Follow `SECURITY.md` for vulnerability handling.
- Preserve filesystem sandbox guarantees and role-based access controls.
- Treat protocol/security changes as high-risk and require tests.

## Documentation Pointers

- Product spec: `_project/spec/spec.md`
- Protocol draft: `_project/spec/protocol-v1.md`
- Threat model: `_project/spec/security.md`
- Implementation board: `_project/spec/implementation-board.md`
