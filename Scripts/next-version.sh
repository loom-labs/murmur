#!/usr/bin/env bash
#
# Resolve the next semantic version from a commit message bump tag.
#
# Reads the current version from ./VERSION, looks for `#major`, `#minor`, or
# `#patch` in the message passed as $1, and prints the bumped version to stdout.
# Prints nothing and exits 1 when the message carries no bump tag, which is the
# signal to the release workflow that this commit should not cut a release.
#
# Usage:
#   Scripts/next-version.sh "feat: add streaming synthesis #minor"   # -> 0.2.0
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly VERSION_FILE="${REPO_ROOT}/VERSION"

message="${1:-}"

if [[ -z "${message}" ]]; then
    echo "usage: $(basename "$0") <commit-message>" >&2
    exit 2
fi

if [[ ! -f "${VERSION_FILE}" ]]; then
    echo "error: ${VERSION_FILE} not found" >&2
    exit 2
fi

current="$(tr -d '[:space:]' <"${VERSION_FILE}")"

if [[ ! "${current}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "error: VERSION must be MAJOR.MINOR.PATCH, got '${current}'" >&2
    exit 2
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

# Longest tag wins so that a message containing both never depends on ordering.
if [[ "${message}" == *"#major"* ]]; then
    major=$((major + 1))
    minor=0
    patch=0
elif [[ "${message}" == *"#minor"* ]]; then
    minor=$((minor + 1))
    patch=0
elif [[ "${message}" == *"#patch"* ]]; then
    patch=$((patch + 1))
else
    exit 1
fi

echo "${major}.${minor}.${patch}"
