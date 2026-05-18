# Contributing to OpenFoldr

Thanks for helping improve OpenFoldr.

## Before You Start

- Read the product specification in _project/spec/spec.md.
- Review security expectations in _project/spec/security.md.
- Search open issues to avoid duplicate work.

## How to Contribute

1. Open or claim an issue.
2. Propose a clear implementation plan.
3. Submit a pull request with focused changes.
4. Include tests and documentation updates.

## Branching Strategy

- `develop` is the primary integration branch for active development.
- `main` is the stable release branch.
- Create feature branches from `develop`.
- Merge feature branches back into `develop` via pull request.
- Merge `develop` into `main` for release milestones.

## Pull Request Expectations

- Keep PRs small and scoped.
- Add or update tests for behavioral changes.
- Document protocol or API changes.
- Include risk notes for security-sensitive changes.

## Commit Guidelines

Use clear commit messages. Suggested format:

- feat: add resumable upload chunk validator
- fix: reject symlink escape in path guard
- docs: update v1 conflict handling contract

## Reporting Bugs

Use the bug template in .github/ISSUE_TEMPLATE.

## Security Reports

Do not file public issues for vulnerabilities. Follow SECURITY.md.

## Code of Conduct

By participating, you agree to follow CODE_OF_CONDUCT.md.
