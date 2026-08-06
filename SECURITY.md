# Security

## Reporting a vulnerability

Please report security issues privately through GitHub's
[private vulnerability reporting](https://github.com/loom-labs/beagle/security/advisories/new)
rather than opening a public issue.

Include what you did, what happened, and the macOS version and chip. A working
proof of concept helps but is not required.

## What Beagle can reach

Beagle is a background utility that holds three sensitive capabilities. Each is
requested only when the feature that needs it is first used.

| Capability | Why | What it can see |
|---|---|---|
| **Microphone** | Dictation | Audio while you hold the dictation key, and only then |
| **Accessibility** | Pasting at the cursor, reading the selection | Lets Beagle post ⌘V and ⌘C; it does **not** install an event tap, so it never observes your keystrokes |
| **Screen Recording** | Read-the-screen | The region you drag out, and only when you invoke it |

Beagle does **not** register a `CGEventTap`. Global shortcuts use Carbon's
`RegisterEventHotKey`, which delivers only the specific combinations Beagle
registered. Putting the app in the path of every keystroke on the machine would
be both a privacy liability and a performance one.

## Network

After the one-time model download, Beagle makes **no network requests**. There
is no account, no API key, no analytics, and no crash reporting.

Weights come from Hugging Face over HTTPS on first use, via
[FluidAudio](https://github.com/FluidInference/FluidAudio). You can verify the
claim on a machine that already has the models cached:

```bash
lsof -nP -p "$(pgrep -f 'Beagle.app/Contents/MacOS/Beagle')" | grep -E 'TCP|UDP'
```

That returns nothing on a running instance.

## Data handling

**Audio** is held in memory, transcribed, and discarded. It is never written to
disk and never leaves the machine.

**Screen captures** are written to the per-user temporary directory
(`/var/folders/…/T/`, mode `0700`), read once by the OCR pass, and deleted
immediately afterwards.

**The clipboard** is borrowed briefly to paste a transcript, then restored.
Two deliberate protections:

- If the clipboard holds an entry a password manager marked with
  `org.nspasteboard.ConcealedType`, Beagle **does not read it**. Copying a
  credential into Beagle's memory would serve no purpose, and restoring it
  afterwards would extend its lifetime past the point the manager meant to
  clear it. In that case the clipboard is cleared instead — neither the secret
  nor the transcript is left behind.
- Transcripts are marked `org.nspasteboard.TransientType`, so clipboard-history
  apps do not archive text you dictated.

**Logs** record lengths, durations, and timings — never transcript text,
selections, or recognised screen content. Check for yourself:

```bash
log show --predicate 'subsystem == "ai.loomlabs.beagle"' --last 1h --info
```

## Code signing

Releases are **ad-hoc signed and not notarized**, because notarization requires
a paid Apple Developer account. Two consequences you should know about:

1. macOS says it *"could not verify Beagle is free of malware"* on first launch.
   That is the absence of a notarization ticket, not a finding.
2. An ad-hoc signature is a hash of the binary, so it changes with every
   release, and macOS treats each release as a different app for permission
   purposes. Accessibility has to be re-granted after an upgrade.

If you would rather not trust a binary at all, build from source —
`./Scripts/build-app.sh` produces the same app.

See [docs/RELEASING.md](docs/RELEASING.md) for how notarization gets enabled.

## Supply chain

- One dependency: FluidAudio (Apache-2.0), pinned by revision in
  `Package.resolved`.
- Its one binary artifact is a `.xcframework` pinned by SHA-256 checksum, so a
  substituted download fails the build.
- CI runs with `contents: read`; only the release job gets `contents: write`.
- No third-party GitHub Actions beyond `actions/checkout` and `actions/cache`.
- `main` is protected: pull requests only, linear history, required status
  checks, no force pushes.

## Scope

Beagle is not sandboxed. It needs to post events into other applications and
capture the screen, neither of which the App Sandbox permits. A compromise of
the app is therefore a compromise of those capabilities — which is the reason
the permission list above is kept as small as it is.
