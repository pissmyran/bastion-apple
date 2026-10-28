# Release

## Versioner

Bastion för Apple har egna versioner, oberoende av de andra plattformarna. Versionen är en SemVer-tagg `vMAJOR.MINOR.PATCH` med en GitHub Release. Plattformens egna versionsfält, till exempel en appbutiks byggnummer, är något annat.

## PR-titeln styr versionen

PR-titeln blir commiten på `main` och följer Conventional Commits. Releasen räknar fram versionen från titlarna sedan förra releasen:

| Titel | Ger |
| --- | --- |
| `!` efter typen eller `BREAKING CHANGE:` | major |
| `feat:` | minor |
| `fix:`, `perf:`, `revert:` | patch |
| `docs:`, `refactor:`, `test:`, `build:`, `ci:`, `chore:` | ingen release |

## Flödet

1. En PR mergas till `main`.
2. `.github/workflows/release.yml` räknar fram versionen från commitarna sedan senaste tagg, eller sedan commiten i `.github/release-baseline` om ingen tagg finns ännu.
3. Releasen väntar tills kontrollerna i `.github/release-required-checks` är gröna på samma commit.
4. Taggen och GitHub Releasen skapas.
5. Dokumentationen byggs från taggen och publiceras på [GitHub Pages](https://pissmyran.github.io/bastion_apple/).

En merge som bara innehåller till exempel `docs:` släpper ingen ny version, och därför publiceras dokumentationen först vid nästa release.

## Kontroller som krävs

`.github/release-required-checks` innehåller en kontroll per rad. I dag är det CodeQL-analysen för plattformens språk (`Analyze (swift)`). När ett bygg- och testworkflow finns ska dess kontroll läggas till där.

## Release är inte distribution

En GitHub Release publicerar ingenting till en appbutik eller pakethanterare. Distribution är ett separat steg.

## Rätta en felaktig release

Taggar flyttas aldrig. Rätta i stället med en vanlig PR (`fix:` eller `revert:`), så skapar nästa release en ny version.
