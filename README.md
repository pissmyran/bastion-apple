# Bastion for Apple

**Documentation:** [myrpisset.github.io/bastion-apple](https://myrpisset.github.io/bastion-apple/)

Bastion is an SSH client. This repo holds the version for iOS, iPadOS, macOS and tvOS, built with Swift, SwiftNIO SSH, SwiftUI and XcodeGen. The other platforms have their own repos: [Bastion for Linux](https://github.com/Myrpisset/bastion-linux), [Bastion for Windows](https://github.com/Myrpisset/bastion-windows), [Bastion for Android](https://github.com/Myrpisset/bastion-android). The [Bastion hub](https://github.com/Myrpisset/bastion) ties them together.

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

Test the tvOS OAuth token store outside Xcode (Linux only):

```bash
bash Tests/TVAppTests/run-token-store-tests.sh
```

Generate the Xcode project (macOS only):

```bash
sh App/generate-project.sh
```

The apps are built with Xcode on macOS. Targets: `Bastion` (iOS and iPadOS), `Bastion-macOS` and `Bastion-tvOS`. Always run `App/generate-project.sh`, never `xcodegen` directly: the script reads the exact SwiftTerm version in `App/Package.swift` and pins the generated project to it.

## CodeRabbit reviews

[`.coderabbit.yaml`](.coderabbit.yaml) inherits shared settings from
`Myrpisset/coderabbit` and adds Apple security, platform and verification guidance.
Explicit links to the Bastion hub, Linux, Windows and Android repositories support
cross-platform documentation and sync compatibility reviews. See
[review configuration verification](docs/operations.md#coderabbit-configuration).

## More

- [The documentation](https://myrpisset.github.io/bastion-apple/): getting started, architecture, operations, sync format and releases
- [SECURITY.md](SECURITY.md): report a vulnerability
- [CONTRIBUTING.md](CONTRIBUTING.md): contribute
