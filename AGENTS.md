# AGENTS.md

## Läs först

1. [docs/index.md](docs/index.md) — dokumentationskarta.
2. [docs/project-context.md](docs/project-context.md) — plattformar och bygginvarianter.
3. [docs/architecture.md](docs/architecture.md) — komponentgränser.
4. [docs/operations.md](docs/operations.md) — verifieringskommandon och plattformsspecifik drift.

Repositoryts egna dokument, manifests, workflows och versionerade konfiguration är auktoritativa för Bastions tekniska arbete.

## Arbetsregler

- Gren, pull request och granskning följer avsnittet Branches and review i `CLAUDE.md`: arbetet sker på en egen gren per session, med en pull request mot `main`.
- Commits och PR-titlar följer Conventional Commits, exempelvis `feat:`, `fix:`, `docs:`, `chore:`, `ci:` eller `test:`.
- Läs hela reviewn, inklusive trådar som GitHub markerar som `outdated`, och verifiera att grundproblemet faktiskt är löst.
- Bevara gränsen mellan delad `SSHCore` och plattformsspecifika UI/appar.
- Apple-projektgenerering ska gå via `App/generate-project.sh` när dependency-wrappern behövs.
- `App/Package.swift` får inte börja kompileras som vanlig app-source i Xcode-targets.
- Ändra plattformsspecifika build paths och manifests tillsammans med relevant dokumentation.
- Repo-specifika värden som når shell ska hanteras via `env:` och citerade variabler.
- Lägg aldrig secrets eller credentials i repository eller publik dokumentation.
- Extern GitHub-governance är provider-state. Anta inte organization-scope eller andra org-funktioner utan live-verifiering.

## Agent skills

### Issue tracker

Use this repository's GitHub Issues for issues and specifications. Read `docs/agents/issue-tracker.md` before reading, creating, or publishing tickets.

### Domain docs

Use the single-context convention in `docs/agents/domain.md`; existing project-context, architecture, operations, and ADR documentation remain authoritative.

