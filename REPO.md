# REPO.md

Bastion for Apple is an SSH client for iOS, iPadOS, macOS and tvOS. A shared Swift package (`SSHCore`) holds all non-UI logic; the apps and a small CLI sit on top of it.

## Stack

- Swift, SwiftNIO SSH and swift-crypto for the core; SwiftUI and SwiftTerm for the apps.
- XcodeGen (via `App/generate-project.sh`) and fastlane for the app projects.
- Zensical for the documentation site; Node.js and Python for the small test scripts in `Tests/`. ZIP extraction also needs Python 3 with POSIX `dir_fd` and `O_NOFOLLOW` support on the remote host.

## Commands

All working commands are listed in `AGENTS.md`. Beyond those:

- Run the CLI: `swift run bastion-cli` (needs a Swift toolchain).
- There is no linter or formatter configured.
- The Swift commands and the CLI password-prompt test need a Swift toolchain; the prototype test (`node --test`) runs anywhere with Node.js.

## Where things live

- `Sources/SSHCore/` is the only code shared by all apps; `App/` is app-only and cannot be built on Linux.
- `docs/prototype/` is a standalone HTML GUI prototype with its own tests in `Tests/Prototype/`.
- `.github/release-required-checks` and `.github/release-baseline` control when a release may be cut.

## Release

Merging to `main` creates a SemVer tag and GitHub Release only when the commits since the previous release, or since `.github/release-baseline` when no stable tag exists (judged by PR title, Conventional Commits) require a version bump; a `docs:` merge alone does not release or publish documentation. Documentation is published from the tag to GitHub Pages. A release does not publish to any app store; distribution is a separate step. Details: `docs/release.md`.

## Repo-specific rules

- The Linux, Windows and Android apps live in other repos and share no code with this one; do not assume feature parity.
- `swift-nio` is pinned exactly and `swift-nio-ssh` follows a temporary branch; check the comments in `Package.swift` before changing either.
