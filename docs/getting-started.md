# Getting started

## Prerequisites

- **The Swift package:** a Swift toolchain with tools version 5.9 or later, on Linux or macOS.
- **The apps:** macOS with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- **The documentation:** Python and [Zensical](https://zensical.org/).

Signing certificates, provisioning profiles and App Store Connect keys are never in the repo; see [Architecture](architecture.md#signing-and-distribution).

## Build and test

Build and test the Swift package (works on Linux and macOS):

```bash
swift build && swift test
```

Run a single test class:

```bash
swift test --filter SSHCoreTests.SyncEngineTests
```

Run a single test method (replace `testLastWriteWins` with the method you want):

```bash
swift test --filter SSHCoreTests.SyncEngineTests/testLastWriteWins
```

Test the GUI prototype (required when `docs/prototype/bastion-gui.html` changes; needs Node.js):

```bash
node --test Tests/Prototype/terminal.test.js
```

Generate the Xcode project (macOS only):

```bash
sh App/generate-project.sh
```

The apps are built with Xcode on macOS. Targets: `Bastion` (iOS and iPadOS), `Bastion-macOS` and `Bastion-tvOS`. Always run `App/generate-project.sh`, never `xcodegen` directly: the script reads the exact SwiftTerm version in `App/Package.swift` and generates from `App/project.dependencies.yml`, which includes `project.yml` and pins SwiftTerm to that version.

Build the documentation:

```bash
pip install --upgrade zensical
```

```bash
zensical build --strict
```

## The command-line tool

`bastion-cli` exercises SSHCore against a real server:

```bash
swift run bastion-cli user@host[:port] "command"
swift run bastion-cli -L [bindHost:]bindPort:targetHost:targetPort user@host[:port]
swift run bastion-cli -R [bindHost:]bindPort:targetHost:targetPort user@host[:port]
swift run bastion-cli -D [bindHost:]bindPort user@host[:port]
swift run bastion-cli -J [user@]jumphost[:port] user@host[:port] "command"
```

The password is read from `BASTION_PASSWORD` (otherwise from stdin). An Ed25519 key can be given as a raw 32-byte seed in hex through `BASTION_ED25519_HEX`. `ProxyJump` lines in `~/.ssh/config` are honoured; `-J` wins if both are set.

## Contents

| Path | Contents |
| --- | --- |
| `Sources/SSHCore/` | Shared core: SSH sessions, SFTP, forwarding, sync and encryption, and the service integrations |
| `Sources/bastion-cli/` | Command-line tool on top of SSHCore |
| `Tests/SSHCoreTests/` | Tests for SSHCore |
| `Tests/fixtures/` | Wire-format fixtures shared with the other platforms |
| `Tests/Prototype/` | Node tests for the GUI prototype in `docs/prototype/` |
| `App/` | The iOS, iPadOS and macOS app, the XcodeGen specs and fastlane |
| `App/TVApp/` | The tvOS app |
| `Package.swift` | The Swift package with SSHCore and bastion-cli |
