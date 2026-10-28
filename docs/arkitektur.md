# Arkitektur

Bastion för Apple består av en delad kärna och tre appar ovanpå den.

```text
              +--------------------+
              |      SSHCore       |
              |  SwiftNIO SSH, NIO |
              +---------+----------+
                        |
       +----------------+-----------------+
       |                |                 |
  bastion-cli      iOS och macOS        tvOS
     Swift         App/ (SwiftUI)     App/TVApp/
```

## SSHCore

`Sources/SSHCore/` innehåller allt som inte är gränssnitt: SSH-sessioner, värdnyckelkontroll, SFTP, port- och SOCKS-vidarebefordran, värdlistan, synkmotorn och krypteringen av synkfilen. Kärnan byggs och testas med Swift Package Manager utan Xcode.

## Apparna

- **iOS, iPadOS och macOS** delar koden i `App/`. Terminalen bygger på SwiftTerm.
- **tvOS** ligger i `App/TVApp/` och får inte SwiftTerm eller API:er som saknas på tvOS. Inloggning mot molntjänster sker med device flow.
- **Xcode-projektet** genereras av XcodeGen från `App/project.yml`. `App/Package.swift` är beroendemanifestet som Renovate läser; det får aldrig hamna bland appens källfiler.

## Beroendegränser

| Manifest | Äger |
| --- | --- |
| `Package.swift` | SSHCore och bastion-cli |
| `App/Package.swift` | Apparnas Swift-paket, till exempel SwiftTerm |
| `App/Gemfile` | fastlane |

Uppdatera ett beroende i det manifest som faktiskt äger det.

## Säkerhetsgräns

SSHCore äger värdnyckelkontroll och autentisering. Gränssnittet får aldrig bygga egna genvägar förbi kärnans kontroller. Nycklar och lösenord lagras i nyckelringen, aldrig i filer i repot eller i testdata.
