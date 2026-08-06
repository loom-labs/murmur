#!/usr/bin/env bash
#
# Assemble Beagle.app from a SwiftPM release build.
#
# Deliberately does not use xcodebuild: the whole package builds with the
# Command Line Tools toolchain, so contributors and CI do not need a full Xcode
# install. Building a .app by hand is just a directory layout plus an
# Info.plist, and doing it here keeps the build reproducible.
#
# Usage:
#   Scripts/build-app.sh [--output DIR] [--sign IDENTITY]
#
# Options:
#   --output DIR      Where to write Beagle.app (default: dist)
#   --sign IDENTITY   codesign identity. Defaults to ad-hoc ("-").
#   --version X.Y.Z   Version to stamp. Defaults to the latest vX.Y.Z git tag.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

readonly APP_NAME="Beagle"
readonly BUNDLE_ID="ai.loomlabs.beagle"
readonly MINIMUM_MACOS="14.0"

output_dir="${REPO_ROOT}/dist"
sign_identity="-"
version=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            output_dir="$2"
            shift 2
            ;;
        --sign)
            sign_identity="$2"
            shift 2
            ;;
        --version)
            version="$2"
            shift 2
            ;;
        -h | --help)
            sed -n '2,20p' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *)
            echo "error: unknown option '$1'" >&2
            exit 2
            ;;
    esac
done

# Git tags are the source of truth for released versions. A tree with no tags
# yet — a fresh clone before the first release — builds as 0.0.0 rather than
# failing outright.
if [[ -z "${version}" ]]; then
    version="$(git -C "${REPO_ROOT}" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
    version="${version#v}"
fi
if [[ -z "${version}" ]]; then
    version="0.0.0"
fi
readonly version

echo "==> Building ${APP_NAME} ${version} (release, arm64)"
swift build \
    --package-path "${REPO_ROOT}" \
    --configuration release \
    --arch arm64

binary_path="$(swift build --package-path "${REPO_ROOT}" --configuration release --arch arm64 --show-bin-path)/${APP_NAME}"
readonly binary_path

if [[ ! -x "${binary_path}" ]]; then
    echo "error: expected an executable at ${binary_path}" >&2
    exit 1
fi

readonly app_bundle="${output_dir}/${APP_NAME}.app"
readonly contents="${app_bundle}/Contents"

echo "==> Assembling ${app_bundle}"
rm -rf "${app_bundle}"
mkdir -p "${contents}/MacOS" "${contents}/Resources"

cp "${binary_path}" "${contents}/MacOS/${APP_NAME}"

# LSUIElement keeps Beagle out of the Dock and the ⌘-Tab switcher: it is a
# background utility, and a Dock tile would imply a main window it does not have.
#
# The usage description strings are not optional decoration — macOS kills the
# process on first microphone access if NSMicrophoneUsageDescription is absent.
cat >"${contents}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${version}</string>
    <key>CFBundleVersion</key>
    <string>${version}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MINIMUM_MACOS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Beagle transcribes your speech on this Mac. Audio is never sent anywhere.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Beagle recognises speech locally using its own models.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Licensed under the Apache License 2.0.</string>
</dict>
</plist>
PLIST

if [[ -f "${REPO_ROOT}/Resources/AppIcon.icns" ]]; then
    cp "${REPO_ROOT}/Resources/AppIcon.icns" "${contents}/Resources/AppIcon.icns"
fi

printf 'APPL????' >"${contents}/PkgInfo"

# Prefer a stable local identity over ad-hoc when one exists. An ad-hoc
# signature is a hash of the binary, so it changes on every rebuild and macOS
# treats each build as a new app — silently dropping the Accessibility grant.
# See Scripts/make-signing-identity.sh.
# No `-v`: that lists only *valid* identities, and a self-signed certificate is
# never valid because nothing vouches for it. codesign still signs with it.
if [[ "${sign_identity}" == "-" ]] && security find-identity -p codesigning 2>/dev/null | grep -q "Beagle Dev"; then
    sign_identity="Beagle Dev"
    echo "==> Found a stable signing identity; using it so permissions survive rebuilds"
fi

echo "==> Signing (identity: ${sign_identity})"
# Ad-hoc by default. A real Developer ID identity produces a signature stable
# across rebuilds, which is what stops macOS re-prompting for microphone and
# Accessibility access every time the binary changes.
codesign --force --deep --sign "${sign_identity}" "${app_bundle}"
codesign --verify --verbose=1 "${app_bundle}" 2>&1 | sed 's/^/    /'

size="$(du -sh "${app_bundle}" | cut -f1)"
echo "==> Built ${app_bundle} (${size})"
