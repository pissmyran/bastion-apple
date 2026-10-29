# Bastion for Apple

**Documentation:** [pissmyran.github.io/bastion_apple](https://pissmyran.github.io/bastion_apple/)

Bastion is an SSH client. This repo holds the version for iOS, iPadOS, macOS and tvOS, built with Swift, SwiftNIO SSH, SwiftUI and XcodeGen. The other platforms have their own repos: [Bastion for Linux](https://github.com/pissmyran/bastion_linux), [Bastion for Windows](https://github.com/pissmyran/bastion_windows), [Bastion for Android](https://github.com/pissmyran/bastion_android). The [Bastion hub](https://github.com/pissmyran/bastion) ties them together.

## Contents

| Path | Contents |
| --- | --- |
| `Sources/SSHCore/` | Shared SSH core: sessions, SFTP, forwarding, sync and encryption |
| `Sources/bastion-cli/` | Command-line tool on top of SSHCore |
| `Tests/` | Tests for SSHCore and the shared sync-format fixtures |
| `App/` | The iOS, iPadOS and macOS app, the XcodeGen spec and fastlane |
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

The apps are built with Xcode on macOS. Targets: `Bastion` (iOS and iPadOS), `Bastion-macOS` and `Bastion-tvOS`. Always run `App/generate-project.sh`, never `xcodegen` directly: the script reads the dependency versions in `App/Package.swift` and passes them on.

## More

- [The documentation](https://pissmyran.github.io/bastion_apple/): getting started, architecture, operations, sync format and releases
- [SECURITY.md](SECURITY.md): report a vulnerability
- [CONTRIBUTING.md](CONTRIBUTING.md): contribute
