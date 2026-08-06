#!/usr/bin/env bash
#
# Build Beagle.app and wrap it in a distributable DMG.
#
# Produces dist/Beagle-<version>-arm64.dmg containing the app and a symlink to
# /Applications, which is the drag-to-install layout users expect.
#
# Usage:
#   Scripts/make-dmg.sh [--version X.Y.Z] [--sign IDENTITY]
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

readonly APP_NAME="Beagle"
readonly OUTPUT_DIR="${REPO_ROOT}/dist"

version=""
sign_identity="-"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            version="$2"
            shift 2
            ;;
        --sign)
            sign_identity="$2"
            shift 2
            ;;
        -h | --help)
            sed -n '2,10p' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *)
            echo "error: unknown option '$1'" >&2
            exit 2
            ;;
    esac
done

build_args=(--output "${OUTPUT_DIR}" --sign "${sign_identity}")
if [[ -n "${version}" ]]; then
    build_args+=(--version "${version}")
fi

"${REPO_ROOT}/Scripts/build-app.sh" "${build_args[@]}"

# Read the version back out of the built bundle so the DMG's name can never
# disagree with what is inside it.
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "${OUTPUT_DIR}/${APP_NAME}.app/Contents/Info.plist")"
readonly version

readonly dmg_path="${OUTPUT_DIR}/${APP_NAME}-${version}-arm64.dmg"
staging_dir="$(mktemp -d)"
readonly staging_dir
trap 'rm -rf "${staging_dir}"' EXIT

echo "==> Staging disk image contents"
cp -R "${OUTPUT_DIR}/${APP_NAME}.app" "${staging_dir}/"
ln -s /Applications "${staging_dir}/Applications"

# An install note beside the app. The build is ad-hoc signed rather than
# notarized, so Gatekeeper refuses the first launch.
cat >"${staging_dir}/READ ME FIRST.txt" <<NOTE
${APP_NAME} ${version}

1. Drag ${APP_NAME} to the Applications folder.

2. This build is ad-hoc signed, not notarized, so macOS will refuse to open it
   the first time. Clear the quarantine flag from Terminal:

       xattr -dr com.apple.quarantine /Applications/${APP_NAME}.app

3. Launch ${APP_NAME}. It lives in the menu bar — there is no Dock icon.

Shortcuts
    Control-Option-L    dictate (hold to talk, or press to toggle)
    Control-Option-K    read the current selection aloud
    Control-Option-J    capture a screen region and read it aloud

You can also drop text or a .txt/.md file onto the floating orb.

${APP_NAME} asks for Microphone, Accessibility, and Screen Recording access the
first time you use the feature that needs each one. Speech models download once
on first use, then everything runs on your Mac. Nothing is uploaded, ever.

If Accessibility was granted to an earlier version and pasting stops working,
remove the stale entry: System Settings > Privacy & Security > Accessibility,
select ${APP_NAME}, press minus, then plus and pick it again. macOS ties that
grant to the app's signature, which changes with every release.

https://github.com/loom-labs/beagle
NOTE

echo "==> Creating ${dmg_path}"
rm -f "${dmg_path}"
# UDZO is zlib-compressed and read-only: the smallest widely-compatible format.
hdiutil create \
    -volname "${APP_NAME} ${version}" \
    -srcfolder "${staging_dir}" \
    -ov \
    -format UDZO \
    -quiet \
    "${dmg_path}"

size="$(du -h "${dmg_path}" | cut -f1)"
echo "==> Built ${dmg_path} (${size})"
