# AGENTS.md

## Read first

1. [CLAUDE.md](CLAUDE.md): core rules, commands and review.
2. [docs/architecture.md](docs/architecture.md): components and security boundaries.
3. [docs/operations.md](docs/operations.md): verification before pushing.
4. [docs/sync-format.md](docs/sync-format.md): when the host list or sync is involved.

## Working rules

- Branches, pull requests and review follow the core rules in `CLAUDE.md`.
- Read the whole review, including threads GitHub marks as `outdated`, and check that the root cause is actually fixed.
- Change build paths and manifests together with the documentation.
- Values that reach a shell go through `env:` and quoted variables.
- Never put secrets or credentials in the repo or in public documentation.
- Everything is written in English.

## Agent skills

- **Issues:** read `docs/agents/issue-tracker.md` before reading, creating or publishing issues.
- **Domain:** follow `docs/agents/domain.md`.
