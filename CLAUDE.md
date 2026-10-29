# CLAUDE.md – bastion_apple

@AGENTS.md

Guidance for Claude Code in `pissmyran/bastion_apple`: Bastion for Apple, the SSH client for iOS, iPadOS, macOS and tvOS, built with Swift, SwiftNIO SSH, SwiftUI and XcodeGen. The other platforms have their own repos: [Bastion for Linux](https://github.com/pissmyran/bastion_linux), [Bastion for Windows](https://github.com/pissmyran/bastion_windows), [Bastion for Android](https://github.com/pissmyran/bastion_android).

The shared rules for all repos live in [GOVERNANCE.md](https://github.com/pissmyran/.github/blob/main/GOVERNANCE.md) in `pissmyran/.github`. The core rules below are a verbatim copy. At the start of every session, compare the version in the marker with the source:

```sh
curl -fsS https://raw.githubusercontent.com/pissmyran/.github/main/GOVERNANCE.md
```

If the copy is older, update it first in a separate PR (`docs: sync core rules from .github`).

## Core rules

<!-- core-rules:start version=2026-10-29 source=https://github.com/pissmyran/.github/blob/main/GOVERNANCE.md -->
1. **No personal values.** The repository is public. Never write real IDs, domains, email addresses, names, keys, payment links or account details in code, configuration, tests, documentation or commit messages. Use placeholders and `example.com` values.
2. **No secrets.** Tokens, passwords, sessions and keys never end up in Git, logs, issues or public documentation. Secrets live outside the repository (Cloudflare, GitHub environments, `wrangler secret put`, the sandbox proxy).
3. **Stay in scope.** Work only in the repositories you were assigned. Never ask for broader token permissions. If a task needs more, describe it in an issue and let the owner decide.
4. **Branch and pull request.** Every session starts from the latest `main` (`git fetch origin main`) on its own branch. `main` changes only through a squash-merged pull request. Nobody pushes directly to `main`. One session's work stays in one pull request.
5. **Test locally before every push.** CI runs no test checks. The repository's own tests and checks (the Commands section of its `CLAUDE.md`) are the only test gate. Never push with failing tests, and write tests for what you change.
6. **Never touch workflows.** Do not change `.github/workflows/`, `.github/actions/` or `CODEOWNERS`, not even to fix an error. The token has no Workflows permission, so such a push is rejected. If a change is needed, describe it in an issue and let the owner make it. Only Renovate and Dependabot update them.
7. **Review.** CodeRabbit, Sourcery and Codex review, and CodeQL (GitHub default setup) scans. Resolve every review thread before merge. Reply in the thread with what you changed, or with the reason if the finding is noise.
8. **Auto-merge last.** Enable auto-merge only when the review bots have reviewed the latest commit (CodeRabbit skips `docs/` and `*.md`; for those changes Sourcery and Codex are enough), all threads are resolved and every check that runs on the pull request is green, including checks the rules do not require.
9. **Fix the cause, not the symptom.** When something fails or a review asks for a change: read everything, find the cause and redo that part properly. Small obvious errors may be fixed directly. Never weaken a test, skip a check or silence a warning.
10. **Security first.** Security alerts (CodeQL, Dependabot, secret scanning, Renovate) come before other work. Open an issue for each alert and link it from the fix with `Closes #n`. Never copy a secret value into an issue. If an alert would expose an exploitable weakness or a live secret, use a private draft security advisory instead of a public issue.
11. **Latest versions.** Never add new pins to a version number; use `@latest`, `node`, `latest` and version ranges. Existing pins that Renovate keeps current (for example `packageManager`, `requirements-docs.txt`, `.node-version`, lockfiles and actions pinned to a commit SHA) stay, and only Renovate changes them.
12. **Commits and titles.** Commit with the git identity the sandbox provides. Never change git's user, email or signing, and never use `--no-verify`. The pull request title becomes the commit on `main` and follows Conventional Commits in English: `type: description` or `type(scope): description`, with type feat, fix, docs, refactor, perf, test, build, ci, chore, style or revert.
13. **Documentation in the same pull request.** When behaviour, settings or commands change, update `README.md`, `docs/` and the repository's `CLAUDE.md` in the same pull request.
14. **No stray branches.** Delete the branch when the pull request is merged or closed. Pull requests from forks are suggestions: make the change yourself on your own branch if it is wanted, and close the original with thanks and a link.
15. **Zero cost.** Never enable anything that can cost money.
16. **Model before task.** Before every new task, state which model fits it best and that it must be activated before work starts. Switching is not automatic. Do not start the task until the owner has confirmed or switched.
<!-- core-rules:end -->

## Commands

Build and test the Swift package (works on Linux and macOS):

```bash
swift build && swift test
```

Generate the Xcode project (macOS only):

```bash
sh App/generate-project.sh
```

The apps are built with Xcode on macOS. Targets: `Bastion` (iOS and iPadOS), `Bastion-macOS` and `Bastion-tvOS`. Always run `App/generate-project.sh`, never `xcodegen` directly: the script reads the dependency versions in `App/Package.swift` and passes them on.

## Rules for this repo

- **Language:** everything in this repo is English: code, comments, docstrings, documentation, PR titles and bodies, commit messages, review replies and labels. Older code still has Swedish comments and UI text; write every new or changed comment and string in English.
- **No signing in the repo:** never add code signing, certificates, provisioning profiles or App Store keys.
- **SSHCore is the source of the sync format.** If `Host`, `HostStore`, `Snippet`, `SyncEngine`, `SyncCrypto` or the fixtures in `Tests/fixtures/` change, follow the steps in `docs/sync-format.md`.
- **Project generation** always goes through `App/generate-project.sh`, and `App/Package.swift` must never become app source.
- **The apps cannot be built on Linux.** Build and test the Swift package locally and say in the PR that the apps could not be built.
- **The documentation** is a Zensical site: `docs/`, `zensical.toml` and the home page template in `overrides/home.html`. Build it locally with `pip install --upgrade zensical` and `zensical build --strict`. New pages go into `nav` in `zensical.toml`.
- **The release** is driven by the PR titles and the checks in `.github/release-required-checks`; see `docs/release.md`.

## Review in this repo

- **Gate:** `main` requires a PR, signed commits, linear history, resolved review threads and CodeQL without errors or serious alerts. No other checks are required, but the ones that run must be green. The local tests under Commands are the test gate.
- **CodeRabbit:** inherits the central configuration in `pissmyran/coderabbit`. The repo's `.coderabbit.yaml` points out risk areas with their own review instructions; read the part for the files you change before you start.
- **Sourcery and Codex:** also review, as GitHub apps without their own configuration here, and they review documentation too. Treat their threads like CodeRabbit's.
- **Extra care:** host key verification, session lifetime, sync format and encryption, OAuth and project generation in `App/`.

## GitHub from the sandbox

The sandbox injects the agent's fine-grained token for `github.com` and `api.github.com`, so `git` and `gh` work as usual. The token reaches only this agent's repositories.

Open a pull request:

```sh
gh pr create --base main --title '<title>' --body '<body>'
```

Show the checks on a pull request:

```sh
gh pr checks <n>
```

List the inline review comments (each `id` is used for replies):

```sh
gh api repos/pissmyran/bastion_apple/pulls/<n>/comments
```

Reply to a review comment:

```sh
gh api repos/pissmyran/bastion_apple/pulls/<n>/comments/<id>/replies -f body='<reply>'
```

List the review threads with their node IDs (`id`) and first comment:

```sh
gh api graphql -f query='query { repository(owner: "pissmyran", name: "bastion_apple") { pullRequest(number: <n>) { reviewThreads(first: 100) { nodes { id isResolved comments(first: 1) { nodes { databaseId body } } } } } } }'
```

Resolve a review thread, using the thread's node ID, not the comment ID:

```sh
gh api graphql -f query='mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { isResolved } } }' -f id='<thread-id>'
```

Enable auto-merge and delete the branch after merge:

```sh
gh pr merge <n> --auto --squash --delete-branch
```

Close a pull request and delete its branch:

```sh
gh pr close <n> --delete-branch
```

List Dependabot alerts:

```sh
gh api repos/pissmyran/bastion_apple/dependabot/alerts
```

List code scanning alerts:

```sh
gh api repos/pissmyran/bastion_apple/code-scanning/alerts
```

List secret scanning alerts:

```sh
gh api repos/pissmyran/bastion_apple/secret-scanning/alerts
```
