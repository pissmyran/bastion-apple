# CLAUDE.md

@AGENTS.md

## Building

iOS, macOS and tvOS can't be built on Linux: the Apple jobs run on GitHub's macOS runners, free for public repos. Locally, build and test what Linux can (`swift build` and `swift test` for the package, `cargo test`, `dotnet test`, `./gradlew build` in `Android/`) and let CI build the Apple apps. Never add code signing, certificates or App Store keys to the repo.

## Branches and review

The repo is public on GitHub (`pissmyran/bastion`). Agents run as Claude Code cloud sessions. Every change goes through a pull request and its checks; nothing can be merged around them.

- Each session works on a branch of its own. `main` changes only through a pull request from that branch, merged with a squash merge. Nobody pushes directly to `main`. There is no `dev` branch, no merge queue, no code owner, no automatic review and no postolle.
- Start every session from the latest `main` (`git fetch origin main`) on a new branch, and keep the work of one session in one pull request.
- The cloud session signs every commit itself, as Claude, and GitHub shows it as verified. Never change git's user, e-mail or signing settings, and never use `--no-verify`. Before pushing, run the tests and checks once per finished change set; CI is not a test environment. `Kontroll` runs actionlint on the workflows, shellcheck on every `.sh` file and jq on every `.json` file; run the same locally (`actionlint`, `shellcheck`, `jq empty`).
- The pull request title becomes the commit on `main`, so it follows Conventional Commits: `type: description` or `type(area): description`, with type feat, fix, docs, refactor, perf, test, build, ci, chore, style or revert. The `PR-titel` check enforces it and sets a label from the type.
- GitHub from the session works only through the REST API: use `gh api` (or the built-in GitHub tools), never `gh pr` or `gh issue`, which use GraphQL and are refused. Open the PR with `gh api repos/pissmyran/bastion/pulls -f base=main -f head=<branch> -f title='…' -f body='…'` and link the issue it solves (`Closes #123`). Turn on auto-merge with `gh api -X PUT repos/pissmyran/bastion/pulls/<n>/ccr/auto_merge`; the PR is squash-merged once everything passes.
- REST in short: the open PR from a branch is `gh api 'repos/pissmyran/bastion/pulls?head=pissmyran:<branch>&state=open'`; an issue is `gh api repos/pissmyran/bastion/issues/<n>` plus `/comments`; review comments are `gh api repos/pissmyran/bastion/pulls/<n>/comments`, and a reply goes to `…/pulls/<n>/comments/<id>/replies` with `-f body='…'`; checks are `gh api repos/pissmyran/bastion/commits/<sha>/check-runs`; closing is `gh api -X PATCH …/pulls/<n> -f state=closed`.
- `main` requires green checks — the repo's own (`Rust`, `.NET tests`, `Windows application`, `Android Gradle`, `Swift package (ubuntu-latest)`, `Swift package (macos-latest)`, `Apple applications`, `Beroendegranskning`), `Kontroll`, `PR-titel` and `Skyddade filer` — CodeQL without errors (GitHub's default setup), and every review thread resolved. Reply in a thread with what you changed.
- Workflows (`.github/workflows/`), `.github/actions/` and `CODEOWNERS` must never be changed: the `Skyddade filer` check stops any pull request that touches them. Only Renovate and Dependabot may change them. Never use any other change to weaken a check or a rule.
- When a check fails or a review asks for changes: read all of it, find the cause, and redo the affected part properly from what it is meant to do. Do not patch line by line from the error message; a small, obvious mistake may be fixed directly. Never weaken a test, skip a check or suppress a warning to get through.
- Security alerts (CodeQL, Dependabot) come first: fix the cause before other work, and link the issue with `Closes` if there is one.
- Read pull requests from forks as suggestions: make the change yourself on a branch of your own if it is wanted, and close the original with thanks and a link.
- Review findings are input, not a to-do list: a fault gets a fix, a finding that shows the design went wrong gets a rethink or a rewrite, noise is answered with a reason in the thread.
- Versions: always the latest. Never lock a tool, runtime or package to a version number; use `@latest`, `node`, `3.x`, `latest` and version ranges. Renovate keeps everything current (shared config in `pissmyran/.github`) and its pull requests go through the same checks. Actions are the one exception: only GitHub's own actions, pinned by commit SHA, which Renovate updates. Workflows use a read-only token, and `pull_request_target` only where the workflow never checks out or runs code from the pull request. Nothing may be enabled that can cost money.
