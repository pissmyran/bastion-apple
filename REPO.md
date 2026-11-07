# REPO.md

Bastion for Apple is an SSH client for iOS, iPadOS, macOS and tvOS. A shared Swift package (`SSHCore`) holds all non-UI logic; the apps and a small CLI sit on top of it.

## Stack

- Swift, SwiftNIO SSH and swift-crypto for the core; SwiftUI and SwiftTerm for the apps.
- XcodeGen (through `App/generate-project.sh`) and fastlane for the app projects.
- Zensical for the documentation site; Node.js and Python for the small test scripts in `Tests/`.

## Commands

- Documentation (required when `docs/` or `zensical.toml` changes): `pip install --upgrade zensical`, then `zensical build --strict`.
- GUI prototype tests (required when `docs/prototype/bastion-gui.html` changes; needs Node.js): `node --test Tests/Prototype/terminal.test.js`.
- The Swift package is built and tested with SwiftPM (`swift build`, `swift test`); this needs a Swift toolchain.
- The apps are built with Xcode on macOS only. Generate the project with `sh App/generate-project.sh`, never with `xcodegen` directly: the script pins SwiftTerm to the version in `App/Package.swift`.
- There is no linter or formatter configured.

## Where things live

- `Sources/SSHCore/` is the only code shared by all apps; `App/` is app-only and cannot be built on Linux.
- `docs/prototype/` is a standalone HTML GUI prototype with its own tests in `Tests/Prototype/`.
- `Tests/fixtures/` holds the sync-format fixtures; changes to the sync types or sync-format fixtures must follow `docs/sync-format.md`.
- `.github/release-required-checks` and `.github/release-baseline` control when a release may be cut.

## Release

Merging to `main` creates a SemVer tag and GitHub Release only when the commits since the previous release require a version bump (judged by PR title, Conventional Commits); a `docs:` merge alone does not release. Documentation is published from the tag to GitHub Pages. A release does not publish to any app store. Details: `docs/release.md`.

## Repo-specific rules

- `App/project.yml` holds signing settings only. Certificates, profiles, private keys and App Store Connect keys come from environment variables and the encrypted match repository, never from the repo.
- CodeQL runs from `.github/workflows/codeql.yml` (advanced setup); GitHub's default setup must stay disabled.
- The Linux, Windows and Android apps live in other repos and share no code with this one; do not assume feature parity.
- `swift-nio` is pinned exactly and `swift-nio-ssh` follows a temporary branch; check the comments in `Package.swift` before changing either.
