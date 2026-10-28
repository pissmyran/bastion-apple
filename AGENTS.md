# AGENTS.md

## Läs först

1. [CLAUDE.md](CLAUDE.md) – kärnregler, kommandon och granskning.
2. [docs/arkitektur.md](docs/arkitektur.md) – komponenter och säkerhetsgränser.
3. [docs/drift.md](docs/drift.md) – verifiering före push.
4. [docs/synkformat.md](docs/synkformat.md) – när värdlistan eller synken berörs.

## Arbetsregler

- Gren, pull request och granskning följer kärnreglerna i `CLAUDE.md`.
- Läs hela granskningen, även trådar som GitHub markerar som `outdated`, och kontrollera att grundproblemet faktiskt är löst.
- Ändra byggvägar och manifest tillsammans med dokumentationen.
- Värden som når ett skal hanteras via `env:` och citerade variabler.
- Lägg aldrig hemligheter eller inloggningsuppgifter i repot eller i publik dokumentation.

## Agentfärdigheter

- **Issues:** läs `docs/agents/issue-tracker.md` innan du läser, skapar eller publicerar ärenden.
- **Domän:** följ `docs/agents/domain.md`.
