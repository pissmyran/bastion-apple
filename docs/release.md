# Releases

## Versions

Bastion for Apple has its own versions, independent of the other platforms. A version is a SemVer tag `vMAJOR.MINOR.PATCH` with a GitHub Release. The platform's own version fields, for example an app store build number, are something else.

## The PR title sets the version

The PR title becomes the commit on `main` and follows Conventional Commits. The release computes the version from the titles since the previous release:

| Title | Gives |
| --- | --- |
| `!` after the type or `BREAKING CHANGE:` | major |
| `feat:` | minor |
| `fix:`, `perf:`, `revert:` | patch |
| `docs:`, `refactor:`, `test:`, `build:`, `ci:`, `chore:` | no release |

A `Release-As: major|minor|patch|none` trailer in the commit message overrides the bump the commit type would give. A breaking change always gives a major release, whatever `Release-As` says.

## The flow

1. A PR is merged to `main`.
2. `.github/workflows/release.yml` computes the version from the commits since the latest tag, or since the commit in `.github/release-baseline` if there is no tag yet.
3. The release waits until the checks in `.github/release-required-checks` are green on the same commit.
4. The tag and the GitHub Release are created.
5. For a stable release, `.github/workflows/docs.yml` builds the documentation from the tag and publishes it on [GitHub Pages](https://myrpisset.github.io/bastion-apple/).

A merge that only contains, for example, `docs:` releases no new version, so the documentation is published at the next release. The documentation workflow also runs every hour and republishes the latest stable release.

## Manual releases and release candidates

`release.yml` can also be started by hand (`workflow_dispatch`). `release_type` forces a bump (`patch`, `minor`, `major`; never lower than the commits require) or `promote`s the active release candidate to stable. `channel: rc` creates a prerelease tag `vMAJOR.MINOR.PATCH-rc.N`; prereleases do not publish the documentation.

## Required checks

`.github/release-required-checks` holds one check per line. Today it is the CodeQL analysis for the platform's language (`Analyze (swift)`). When a build and test workflow exists, its check should be added there.

## A release is not distribution

A GitHub Release publishes nothing to an app store or package manager. Distribution is a separate step.

## Fixing a bad release

Tags are never moved. Fix it with a regular PR (`fix:` or `revert:`) instead, and the next release creates a new version.
