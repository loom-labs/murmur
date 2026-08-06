#!/usr/bin/env bash
#
# Resolve the next semantic version from a commit message bump tag.
#
# The current version comes from the most recent `vX.Y.Z` git tag, which makes
# the tag history the single source of truth. There is deliberately no VERSION
# file to keep in sync: `main` is protected, so a release job could not push a
# bumped file back to it anyway.
#
# Looks for `#major`, `#minor`, or `#patch` in the message passed as $1 and
# prints the bumped version to stdout. Prints nothing and exits 1 when the
# message carries no bump tag — the signal to the release workflow that this
# commit should not cut a release.
#
# Usage:
#   Scripts/next-version.sh "feat: add streaming synthesis #minor"   # -> 0.2.0
#
set -euo pipefail

message="${1:-}"

if [[ -z "${message}" ]]; then
    echo "usage: $(basename "$0") <commit-message>" >&2
    exit 2
fi

# `git describe` finds the nearest reachable tag; `|| true` covers a repository
# with no tags at all, which is the state before the first release.
current="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
current="${current#v}"

if [[ -z "${current}" ]]; then
    current="0.0.0"
fi

if [[ ! "${current}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "error: latest tag is not vMAJOR.MINOR.PATCH, got 'v${current}'" >&2
    exit 2
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

# Checked most-significant first, so a message carrying more than one tag
# resolves by precedence rather than by ordering within the string.
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
