# Drift och verifiering

## Före varje push

Det finns inga bygg- eller testkontroller i CI. Testerna nedan är den enda testgrinden, så de körs lokalt före varje push:

Bygg och testa Swift-paketet (fungerar på Linux och macOS):

```bash
swift build && swift test
```

Generera Xcode-projektet (bara på macOS):

```bash
sh App/generate-project.sh
```

## I CI

- **CodeQL** (GitHubs standardinställning) analyserar koden på varje pull request och på `main`. Fel och allvarliga säkerhetslarm stoppar merge.
- **Dokumentationen** byggs strikt med Zensical när `docs/` eller `zensical.toml` ändras i en pull request.
- **Releasen** väntar på kontrollerna i `.github/release-required-checks`; se [Release](release.md).

## Felsökning efter beroendeändring

Kontrollera i den här ordningen:

1. `App/Package.swift`
2. att `App/generate-project.sh` läser rätt version
3. paketkopplingen i det genererade projektet
4. att `App/Package.swift` är undantagen från appens källfiler
5. bygget för det target som fallerar

## Säkerhetsregler

- Privata nycklar, tokens och lösenord läggs aldrig i repot, i loggar eller i testdata.
- Värden som når ett skal citeras och skickas helst via `env:`.
- Ett beroende uppdateras i det manifest som faktiskt äger det.
