# AGENTS.md – bastion-apple

Bastion for Apple: the SSH client for iOS, iPadOS, macOS and tvOS, built with Swift, SwiftNIO SSH, SwiftUI and XcodeGen.

Read the shared rules at the start of every session: [GOVERNANCE.md](https://raw.githubusercontent.com/Myrpisset/.github/main/GOVERNANCE.md) and [BASTION.md](https://raw.githubusercontent.com/Myrpisset/.github/main/BASTION.md).

## Read first

1. [docs/architecture.md](docs/architecture.md): components and security boundaries.
2. [docs/operations.md](docs/operations.md): verification before pushing.
3. [docs/sync-format.md](docs/sync-format.md): when the host list or sync is involved.

## Commands

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

Build the documentation (required when `docs/` or `zensical.toml` changes):

```bash
pip install --upgrade zensical
```

```bash
zensical build --strict
```

Test the GUI prototype (required when `docs/prototype/bastion-gui.html` changes; needs Node.js):

```bash
node --test Tests/Prototype/terminal.test.js
```

Test the CLI password prompt (after `swift build`; needs Python 3 and a POSIX terminal):

```bash
python3 Tests/cli_password_prompt_test.py
```

Generate the Xcode project (macOS only):

```bash
sh App/generate-project.sh
```

The apps are built with Xcode on macOS. Targets: `Bastion` (iOS and iPadOS), `Bastion-macOS` and `Bastion-tvOS`.

## Rules

- **Signing:** `App/project.yml` holds signing *settings* (team ID, signing style, provisioning profile names) and `App/fastlane/` fetches certificates with `match`. Never commit certificates, provisioning profiles, private keys, App Store Connect API keys or match passwords; they come from environment variables and the encrypted match repository.
- **SSHCore is the source of the sync format.** If `Host`, `HostStore`, `Snippet`, `SyncEngine`, `SyncCrypto` or the fixtures in `Tests/fixtures/` change, follow `docs/sync-format.md`.
- **Project generation** always goes through `App/generate-project.sh`, never `xcodegen` directly: the script reads the exact SwiftTerm version in `App/Package.swift` and generates from `App/project.dependencies.yml`, which includes `project.yml` and pins SwiftTerm to that version. `App/Package.swift` never becomes app source.
- **The apps cannot be built on Linux.** Build and test the Swift package.
- **Releases:** the pull request title decides the version; see `docs/release.md`.
- **Extra care:** host key verification, session lifetime, sync format and encryption, OAuth and project generation in `App/`.

## CodeRabbit configuration

Keep `inheritance: true` in `.coderabbit.yaml`; shared settings belong in
`Myrpisset/coderabbit`. Local instructions cover Apple security boundaries,
platform availability, verification and shared sync compatibility. Preserve the
explicit Bastion hub, Linux, Windows and Android links without assuming feature
parity or repository access. Follow [docs/operations.md](docs/operations.md#coderabbit-configuration)
when validating configuration changes.
