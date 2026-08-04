# Contributing to GloWalk

Thanks for wanting to contribute! Please read the whole guide first — it keeps
the project easy to review and maintain.

## Sign the CLA

GloWalk is an open-source project. Before your code can be merged, you must sign
the [Individual Contributor License Agreement](CLA.md), which grants the project
maintainers the rights to use, distribute, and develop your contribution.

Signing takes one small pull request — see [CLA.md](CLA.md#how-to-sign). The CLA
check on your other pull requests stays red until you do. Maintainers (write
access or higher) are exempt.

## Getting started

1. **Find or open an issue.** Say what you plan to do so maintainers and other
   contributors know it isn't being worked on twice.
2. **Fork** the repository and create a branch off `master` with a short
   descriptive name, e.g. `fix/gps-drift` or `feat/compass-animation`.
3. Make your changes with small, focused commits (see conventions below).
4. Open a pull request back to `master` and fill in the description template.

## Pull request checks

A few lightweight checks run on every PR (no build, so they are fast):

- **Whitespace / conflict markers** — no trailing whitespace or merge-conflict
  markers in the diff (`git diff --check`).
- **PR description** — the description should be at least a few lines so
  reviewers and the changelog have context.
- **Commit message convention** — commit subjects start with a conventional
  prefix (see below).
- **CLA** — the author must have signed the CLA (see above).

## Commit message convention

Commit subjects use the conventional prefixes used throughout the repo:

```
feat:      new feature or user-facing behavior
fix:       bug fix
chore:     maintenance, tooling, dependencies, build version
docs:      documentation only
refactor:  code change that fixes no bug and adds no feature
test:      adding or updating tests
perf:      performance improvement
style:     formatting, whitespace, no code change
ci:        CI configuration and scripts
build:     build system changes (rare)
revert:    reverting a previous commit
```

Examples: `feat: add lunar calendar card`, `fix: GPS distance double-count`,
`chore: bump build version to 5`.

Write the subject in the imperative mood and keep it under ~72 characters. Use
the body to explain *why* the change is needed, not just *what* it does.

## Code style

- **Swift** — match the surrounding code: its comment density, naming, and
  idiom. Use `///` for documented members and explain non-obvious decisions in
  comments (this codebase leans on comments to explain *why*).
- **Threading** — the app is Swift 6 / strict-concurrency aware. `@MainActor`
  types are common; hop back to the main actor with `Task { @MainActor in ... }`
  from `@Sendable` callbacks rather than force-syncing isolation.
- **Localization** — user-facing strings go through the string catalog
  (`Localizable.xcstrings`) and are exposed via `L10n` in
  `GloWalk/Extensions/L10n.swift`. Add `en` / `zh-Hans` / `zh-Hant` entries for
  every new key.
- Keep PRs small enough to review. Split unrelated changes into separate PRs.

## Building and testing

The project uses Xcode. From the command line:

```sh
# Build (Debug)
xcodebuild -scheme GloWalk -destination 'generic/platform=iOS Simulator' build

# Run tests
xcodebuild -scheme GloWalk -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Make sure existing tests still pass and add tests for new logic where practical
(see `GloWalkTests/`). The sensor/daylight code depends on real-device camera
behavior, so verify camera- and sensor-related changes on a physical device.

## Reporting bugs

Open an issue with:

- device model and iOS version,
- steps to reproduce,
- expected vs. actual behavior,
- logs or screenshots if relevant.
