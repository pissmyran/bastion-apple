> Guide: [AI- och Copilot-inställningar på GitHub](https://github.com/pissmyran/.github/blob/main/public/ai-och-copilot.md) · [English](https://github.com/pissmyran/.github/blob/main/public/eng/ai-and-copilot.md)

# Bastion for Apple

**Documentation:** [docs.denied.se/bastion-apple](https://docs.denied.se/bastion-apple/)

Bastion is an SSH client. This repo holds the version for iOS, iPadOS, macOS and tvOS, built with Swift, SwiftNIO SSH, SwiftUI and XcodeGen. The other platforms have their own repos: [Bastion for Linux](https://github.com/Pissmyran/bastion-linux), [Bastion for Windows](https://github.com/Pissmyran/bastion-windows), [Bastion for Android](https://github.com/Pissmyran/bastion-android). The [Bastion hub](https://github.com/Pissmyran/bastion) ties them together.

## Contents

| Path | Contents |
| --- | --- |
| `Sources/SSHCore/` | Shared SSH core: sessions, SFTP, forwarding, sync and encryption |
| `Sources/bastion-cli/` | Command-line tool on top of SSHCore |
| `Tests/SSHCoreTests/` | Tests for SSHCore |
| `Tests/fixtures/` | Wire-format fixtures shared with the other platforms |
| `App/` | The iOS, iPadOS and macOS app, the XcodeGen specs and fastlane |
| `App/TVApp/` | The tvOS app |
| `Package.swift` | The Swift package with SSHCore and bastion-cli |

## Getting started

Build and test the Swift package (works on Linux and macOS):

```bash
swift build && swift test
```

Generate the Xcode project (macOS only):

```bash
sh App/generate-project.sh
```

The apps are built with Xcode on macOS. Targets: `Bastion` (iOS and iPadOS), `Bastion-macOS` and `Bastion-tvOS`. Always run `App/generate-project.sh`, never `xcodegen` directly: the script reads the exact SwiftTerm version in `App/Package.swift` and pins the generated project to it.

## CodeRabbit reviews

[`.coderabbit.yaml`](.coderabbit.yaml) inherits shared settings from
`Pissmyran/coderabbit` and adds Apple security, platform and verification guidance.
Explicit links to the Bastion hub, Linux, Windows and Android repositories support
cross-platform documentation and sync compatibility reviews. See
[review configuration verification](docs/operations.md#coderabbit-configuration).

## CodeQL

CodeQL runs from [`.github/workflows/codeql.yml`](.github/workflows/codeql.yml) (advanced setup). GitHub's default setup must stay disabled. Which languages run when, including the Swift analysis of the app targets, is described in [CI](docs/operations.md#in-ci).

## More

- [The documentation](https://docs.denied.se/bastion-apple/): getting started, architecture, operations, sync format and releases
- [SECURITY.md](SECURITY.md): report a vulnerability
- [CONTRIBUTING.md](CONTRIBUTING.md): contribute
