# Operations and verification

## Before every push

CI builds and tests the Swift package on macOS (`.github/workflows/swift.yml`), but the checks below still run locally before every push:

Build and test the Swift package (works on Linux and macOS):

```bash
swift build && swift test
```

Generate the Xcode project (macOS only):

```bash
sh App/generate-project.sh
```

When `docs/` or `zensical.toml` changes, build the documentation the same way CI does:

```bash
pip install --upgrade zensical
```

```bash
zensical build --clean --strict
```

The apps cannot be built on Linux. If a target could not be built or tested, say so in the pull request.

## In CI

- **CodeQL** (advanced setup, `.github/workflows/codeql.yml`) analyzes the code on pull requests and on `main`. Changes that only touch `docs/` (except `docs/prototype/`), `*.md` or `zensical.toml` do not trigger it. On pull requests each language runs only when its own files change: Actions for `.github/workflows` and `.github/actions`, JavaScript/TypeScript for `.js`/`.ts`/`.html`/`package.json`, Python for `.py`, Ruby for `.rb`, `Gemfile` and fastlane files, and Swift for `.swift`, `Package.swift`, `Package.resolved` and anything under `Sources/`, `App/`, `Tests/SSHCoreTests/` or `Tests/fixtures/`. Changing the CodeQL workflow itself runs every language. Every push to `main` that is not documentation-only runs all languages, so the `Analyze (swift)` check required for releases exists. The Swift job builds the root package and the three app targets (`Bastion`, `Bastion-macOS`, `Bastion-tvOS`, unsigned) so that the app sources in `App/` are analyzed too. GitHub's default setup must stay disabled (Settings > Code security > Code scanning), because GitHub rejects advanced-setup uploads while it is enabled. Errors and serious security alerts block merging.
- **The documentation** is built strictly with Zensical when `docs/` or `zensical.toml` changes in a pull request.
- **The release** waits for the checks in `.github/release-required-checks` (today `Analyze (swift)`); see [Releases](release.md).
- **The Wiki** is regenerated from `README.md` and `docs/` on every push to `main` that touches them (`.github/workflows/wiki-sync.yml`).

## Troubleshooting after a dependency change

Check in this order:

1. `App/Package.swift`
2. that `App/generate-project.sh` reads the right version
3. the package link in the generated project
4. that `App/Package.swift` is excluded from the app's source files
5. the build for the failing target

## Security rules

- Private keys, tokens and passwords never go into the repo, logs or test data.
- Values that reach a shell are quoted and preferably passed through `env:`.
- A dependency is updated in the manifest that actually owns it.

## CodeRabbit configuration

The root `.coderabbit.yaml` inherits shared settings from `Pissmyran/coderabbit`.
Keep shared settings there; local path instructions cover Apple security,
dependency and target boundaries, credential storage and verification evidence.
The linked Bastion hub provides shared documentation context; Linux, Windows and
Android links provide sync compatibility context where implemented. A link does
not imply identical platform features or grant repository access.

For configuration changes, validate the complete YAML against the schema linked
at the top of the file and check that each path pattern matches its intended
tracked files. Compare with the latest main configuration to preserve existing
security guidance. Path instructions merge with local entries first and unique
parent paths appended; a matching local path replaces the parent's instruction.
See [configuration inheritance](https://docs.coderabbit.ai/configuration/configuration-inheritance).

After delivery, request `@coderabbitai configuration` on the PR and use its
annotated effective configuration to confirm inherited
path instructions remain present, security scanners remain enabled, automatic
approvals remain disabled, pre-merge checks remain advisory and paid generation
features remain disabled. Check linked-repository eligibility and integration
access for each repository in the active account. All four links use the same
GitHub owner, but eligibility also depends on the CodeRabbit App being installed
on each repository and available plan slots. See
[multi-repo requirements](https://docs.coderabbit.ai/knowledge-base/multi-repo-analysis#platform-requirements).
YAML cannot grant entitlements
or enforce a spending limit. Report unavailable account, access and resolved
configuration checks explicitly in the PR.
