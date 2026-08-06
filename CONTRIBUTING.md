# Contributing

Thanks for taking the time. This document covers the mechanics; for what the
project is trying to be, see the [README](README.md).

## Getting set up

You need macOS 14+ on Apple Silicon and a Swift 6 toolchain (Xcode 16 or the
Command Line Tools — Murmur builds without a full Xcode install).

```bash
git clone https://github.com/loom-labs/murmur.git
cd murmur
swift build && swift test
```

## Branches

Branch off `main`, named `<type>/<short-description>` in kebab-case:

```
feat/streaming-transcription
fix/orb-drops-focus
docs/permission-troubleshooting
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`, `ci`.

`main` is protected — it takes pull requests only.

## Commits

```
<type>: <description> #<bump>
```

Lowercase, imperative, under ~70 characters before the bump tag. No scope
parentheses. Keep commits atomic: one reviewable change each.

```
feat: stream kokoro synthesis sentence by sentence #minor
fix: release the audio engine when dictation is cancelled #patch
```

## Versioning

Murmur is versioned with semver, and releases are cut automatically. The
`#major` / `#minor` / `#patch` tag in the **pull request title** decides the
bump — when the PR squash-merges to `main`, CI reads that tag, bumps
[`VERSION`](VERSION), tags the commit, builds the DMG, and publishes a release.

| Tag | Use for |
|---|---|
| `#major` | Breaking changes to settings, hotkeys, or on-disk layout |
| `#minor` | New user-facing capability |
| `#patch` | Bug fixes, docs, refactors, dependency bumps |

A PR title with no bump tag merges without cutting a release. That is the right
choice for pure-internal changes.

## Pull requests

Keep the description short and concrete:

```markdown
## Summary
- 2–5 bullets: what changed and why

## Test status
- [x] unit tests passing
- [x] verified by hand on an M-series Mac

## Visual output
<screenshot, terminal output, or before/after>
```

CI must be green — lint, build, and tests all run on every PR.

## Code style

Formatting is enforced by `swift format` against [`.swift-format`](.swift-format):

```bash
swift format -i -r Sources Tests      # fix
swift format lint -r -s Sources Tests # check
```

Beyond formatting:

- **No `#Preview`.** That macro is implemented by a compiler plugin bundled with
  Xcode. Murmur builds with the Command Line Tools toolchain — in CI and for
  contributors without a full Xcode install — and `#Preview` fails to compile
  there. Preview views by running the app.
- **Keep `MurmurCore` free of SwiftUI.** Core owns audio, the speech engines,
  input, and orchestration; it imports AppKit where the platform requires it
  (the pasteboard, permissions, `NSEvent`). What it must never contain is a
  `View`. That boundary is what keeps the engines testable and keeps the UI
  layer replaceable.
- **Comments explain why, not what.** If the code needs a paragraph to describe
  what it does, the code is the problem.
- **Handle errors explicitly.** No silent `try?` on anything a user would want
  to hear about.
- Files stay under ~400 lines; functions under ~50.

## Reporting bugs

Open an issue with your macOS version, chip, and — if it is a crash or a hang —
the relevant lines from Console.app filtered to subsystem `ai.loomlabs.murmur`.
