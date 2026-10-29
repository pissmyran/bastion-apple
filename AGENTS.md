# AGENTS.md – bastion_apple

Bastion for Apple: the SSH client for iOS, iPadOS, macOS and tvOS, built with Swift, SwiftNIO SSH, SwiftUI and XcodeGen.

Read the shared rules at the start of every session: [GOVERNANCE.md](https://raw.githubusercontent.com/pissmyran/.github/main/GOVERNANCE.md) and [BASTION.md](https://raw.githubusercontent.com/pissmyran/.github/main/BASTION.md).

## Read first

1. [docs/architecture.md](docs/architecture.md): components and security boundaries.
2. [docs/operations.md](docs/operations.md): verification before pushing.
3. [docs/sync-format.md](docs/sync-format.md): when the host list or sync is involved.

## Commands

Build and test the Swift package (works on Linux and macOS):

```bash
swift build && swift test
```

Generate the Xcode project (macOS only):

```bash
sh App/generate-project.sh
```

The apps are built with Xcode on macOS. Targets: `Bastion` (iOS and iPadOS), `Bastion-macOS` and `Bastion-tvOS`.

## Rules

- **No signing in the repository:** never add code signing, certificates, provisioning profiles or App Store keys.
- **SSHCore is the source of the sync format.** If `Host`, `HostStore`, `Snippet`, `SyncEngine`, `SyncCrypto` or the fixtures in `Tests/fixtures/` change, follow `docs/sync-format.md`.
- **Project generation** always goes through `App/generate-project.sh`, never `xcodegen` directly: the script reads the dependency versions in `App/Package.swift` and passes them on. `App/Package.swift` never becomes app source.
- **The apps cannot be built on Linux.** Build and test the Swift package.
- **Extra care:** host key verification, session lifetime, sync format and encryption, OAuth and project generation in `App/`.
