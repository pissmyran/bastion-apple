# Kom igång

## Förutsättningar

Swift (senaste versionen) för paketet. Xcode och XcodeGen på macOS för apparna. Kodsignering och App Store-nycklar finns aldrig i repot.

## Bygg och testa

Bygg och testa Swift-paketet (fungerar på Linux och macOS):

```bash
swift build && swift test
```

Generera Xcode-projektet (bara på macOS):

```bash
sh App/generate-project.sh
```

Apparna byggs med Xcode på macOS. Targets: `Bastion` (iOS och iPadOS), `Bastion-macOS` och `Bastion-tvOS`. Kör alltid `App/generate-project.sh`, aldrig `xcodegen` direkt: skriptet läser beroendeversionerna i `App/Package.swift` och skickar dem vidare.

## Innehåll

| Plats | Innehåll |
| --- | --- |
| `Sources/SSHCore/` | Delad SSH-kärna: sessioner, SFTP, vidarebefordran, synk och kryptering |
| `Sources/bastion-cli/` | Kommandoradsverktyg ovanpå SSHCore |
| `Tests/` | Tester för SSHCore och de gemensamma fixturerna för synkformatet |
| `App/` | iOS-, iPadOS- och macOS-appen, XcodeGen-spec och fastlane |
| `App/TVApp/` | tvOS-appen |
| `Package.swift` | Swift-paketet med SSHCore och bastion-cli |
