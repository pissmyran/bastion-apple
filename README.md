# Bastion för Apple

**Dokumentation:** [pissmyran.github.io/bastion_apple](https://pissmyran.github.io/bastion_apple/)

Bastion är en SSH-klient. Det här repot innehåller versionen för iOS, iPadOS, macOS och tvOS, byggd med Swift, SwiftNIO SSH, SwiftUI och XcodeGen. Övriga plattformar har egna repon: [Bastion för Linux](https://github.com/pissmyran/bastion_linux), [Bastion för Windows](https://github.com/pissmyran/bastion_windows), [Bastion för Android](https://github.com/pissmyran/bastion_android).

## Innehåll

| Plats | Innehåll |
| --- | --- |
| `Sources/SSHCore/` | Delad SSH-kärna: sessioner, SFTP, vidarebefordran, synk och kryptering |
| `Sources/bastion-cli/` | Kommandoradsverktyg ovanpå SSHCore |
| `Tests/` | Tester för SSHCore och de gemensamma fixturerna för synkformatet |
| `App/` | iOS-, iPadOS- och macOS-appen, XcodeGen-spec och fastlane |
| `App/TVApp/` | tvOS-appen |
| `Package.swift` | Swift-paketet med SSHCore och bastion-cli |

## Kom igång

Bygg och testa Swift-paketet (fungerar på Linux och macOS):

```bash
swift build && swift test
```

Generera Xcode-projektet (bara på macOS):

```bash
sh App/generate-project.sh
```

Apparna byggs med Xcode på macOS. Targets: `Bastion` (iOS och iPadOS), `Bastion-macOS` och `Bastion-tvOS`. Kör alltid `App/generate-project.sh`, aldrig `xcodegen` direkt: skriptet läser beroendeversionerna i `App/Package.swift` och skickar dem vidare.

## Mer

- [Dokumentationen](https://pissmyran.github.io/bastion_apple/) – kom igång, arkitektur, drift, synkformat och release
- [SECURITY.md](SECURITY.md) – rapportera en sårbarhet
- [CONTRIBUTING.md](CONTRIBUTING.md) – bidra
