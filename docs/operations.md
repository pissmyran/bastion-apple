# Operations and verification

## Before every push

There are no build or test checks in CI. The tests below are the only test gate, so they run locally before every push:

Build and test the Swift package (works on Linux and macOS):

```bash
swift build && swift test
```

Generate the Xcode project (macOS only):

```bash
sh App/generate-project.sh
```

## In CI

- **CodeQL** (GitHub's default setup) analyzes the code on every pull request and on `main`. Errors and serious security alerts block merging.
- **The documentation** is built strictly with Zensical when `docs/` or `zensical.toml` changes in a pull request.
- **The release** waits for the checks in `.github/release-required-checks`; see [Releases](release.md).

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
