# Getting started

## Prerequisites

Swift (latest version) for the package. Xcode and XcodeGen on macOS for the apps. Code signing and App Store keys are never in the repo.

## Build and test

Build and test the Swift package (works on Linux and macOS):

```bash
swift build && swift test
```

Generate the Xcode project (macOS only):

```bash
sh App/generate-project.sh
```

The apps are built with Xcode on macOS. Targets: `Bastion` (iOS and iPadOS), `Bastion-macOS` and `Bastion-tvOS`. Always run `App/generate-project.sh`, never `xcodegen` directly: the script reads the dependency versions in `App/Package.swift` and passes them on.

## Contents

| Path | Contents |
| --- | --- |
| `Sources/SSHCore/` | Shared SSH core: sessions, SFTP, forwarding, sync and encryption |
| `Sources/bastion-cli/` | Command-line tool on top of SSHCore |
| `Tests/` | Tests for SSHCore and the shared sync-format fixtures |
| `App/` | The iOS, iPadOS and macOS app, the XcodeGen spec and fastlane |
| `App/TVApp/` | The tvOS app |
| `Package.swift` | The Swift package with SSHCore and bastion-cli |
