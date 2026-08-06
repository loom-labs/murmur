<div align="center">

# Murmur

**Local voice in, local voice out — for macOS.**

Press a key, speak, and your words land in whatever app you were typing in.
Drop text on the orb, and your Mac reads it back. Nothing leaves the machine.

[![CI](https://github.com/loom-labs/murmur/actions/workflows/ci.yml/badge.svg)](https://github.com/loom-labs/murmur/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20·%20Apple%20Silicon-black.svg)](#requirements)

</div>

---

## What it does

| | |
|---|---|
| **Dictate anywhere** | Hold a hotkey, talk, release. The transcript is pasted at your cursor in any app. |
| **Read anything aloud** | Select text and hit a hotkey, or drag text and files onto the floating orb. |
| **Read the screen** | Snap a region of the screen; Murmur OCRs it and speaks it. |
| **Stay out of the way** | A 44-point orb and a menu bar icon. No Dock tile, no window unless you ask. |

Everything runs on the Apple Neural Engine. No API keys, no network calls after
the first model download, no telemetry.

## Why it is fast

Murmur is a single statically linked Swift binary — roughly 8 MB, no Electron,
no Python, no bundled runtime. Inference is offloaded to the ANE rather than the
GPU, which is what keeps it usable as an always-on background app instead of
something that spins your fans.

| | Model | Size | Speed |
|---|---|---|---|
| Speech → text | [Parakeet TDT v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) (0.6 B, int8) | ~650 MB | ~120× realtime |
| Text → speech | [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) (Apache-2.0) | ~330 MB | 3–11× realtime |

Both run through [FluidAudio](https://github.com/FluidInference/FluidAudio), an
Apache-2.0 Swift SDK that ships Core ML conversions of both models. Weights are
downloaded once on first use and cached in
`~/Library/Application Support/FluidAudio/Models`, shared with any other
FluidAudio-based app you already run.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (M1 or newer) — the Core ML graphs are ANE-only, there is no
  Intel build
- ~1 GB of disk for model weights

## Install

Download the DMG from [Releases](https://github.com/loom-labs/murmur/releases),
drag `Murmur.app` to `/Applications`, and launch it.

The build is ad-hoc signed rather than notarized, so Gatekeeper will complain the
first time. Clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/Murmur.app
```

### Build from source

```bash
git clone https://github.com/loom-labs/murmur.git && cd murmur && ./Scripts/build-app.sh
```

## Permissions

Murmur asks for three things, each only when you first use the feature that
needs it:

| Permission | Needed for | Where |
|---|---|---|
| Microphone | Dictation | System Settings → Privacy & Security → Microphone |
| Accessibility | Pasting text at your cursor, reading your selection | → Accessibility |
| Screen Recording | Screenshot-to-speech | → Screen Recording |

## Development

```bash
swift build          # debug build
swift test           # unit tests
swift format lint -r -s Sources Tests   # lint
./Scripts/build-app.sh                  # assemble Murmur.app
```

The package splits into three targets: `MurmurCore` (audio, speech engines,
settings — no AppKit), `MurmurUI` (SwiftUI views), and `MurmurApp` (lifecycle,
hotkeys, windows). See [CONTRIBUTING.md](CONTRIBUTING.md) for the branch and
commit conventions.

## License

[Apache 2.0](LICENSE). Model weights carry their own licenses — Kokoro-82M is
Apache-2.0, Parakeet TDT v3 is CC-BY-4.0.
