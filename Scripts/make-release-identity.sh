#!/usr/bin/env bash
#
# Create a stable code-signing identity for releases and upload it to GitHub
# Actions as a secret.
#
# Why this exists
# ---------------
# Releases are signed ad-hoc by default, and an ad-hoc signature has no stable
# identity — its hash changes with every build. macOS keys the Accessibility
# grant to the signature, so every release looks like a brand-new application
# to TCC. Users have to delete the old entry and re-grant the permission on
# every single upgrade, and stale entries accumulate in System Settings.
#
# Signing every release with the *same* certificate fixes that: the identity
# stops moving, and a grant given once survives upgrades.
#
# What this does NOT do
# ---------------------
# It does not stop Gatekeeper warning that Apple cannot verify the app. That
# requires notarization, which requires a paid Apple Developer Program
# membership. This certificate is self-signed — it makes the identity *stable*,
# not *trusted*. The release workflow already notarizes automatically if you
# later add real Apple credentials.
#
# Usage
# -----
#   Scripts/make-release-identity.sh [repository]
#
# The private key never leaves your machine except as an encrypted GitHub
# secret, and no key material is printed to the terminal.

set -euo pipefail

readonly REPO="${1:-loom-labs/beagle}"
readonly COMMON_NAME="Beagle Release Signing"

if ! command -v gh >/dev/null 2>&1; then
    echo "error: the GitHub CLI (gh) is required" >&2
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "error: not signed in to GitHub — run 'gh auth login'" >&2
    exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
chmod 700 "${workdir}"

echo "==> Generating a stable signing certificate"

cat > "${workdir}/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no

[dn]
CN = ${COMMON_NAME}

[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "${workdir}/key.pem" \
    -out "${workdir}/cert.pem" \
    -days 3650 \
    -config "${workdir}/openssl.cnf" >/dev/null 2>&1

# -legacy and a non-empty password are both required for macOS to import the
# result. See Scripts/make-signing-identity.sh for the full explanation.
p12_password="$(uuidgen)"
readonly p12_password

openssl pkcs12 -export -legacy \
    -inkey "${workdir}/key.pem" \
    -in "${workdir}/cert.pem" \
    -out "${workdir}/identity.p12" \
    -passout "pass:${p12_password}" >/dev/null 2>&1

echo "==> Uploading to ${REPO} as encrypted secrets"

base64 < "${workdir}/identity.p12" | gh secret set DEVELOPER_ID_CERT_P12 --repo "${REPO}"
printf '%s' "${p12_password}" | gh secret set DEVELOPER_ID_CERT_PASSWORD --repo "${REPO}"

echo
echo "Done. Releases from now on are signed with a stable identity."
echo
echo "One migration step for anyone already running Beagle, including you:"
echo "  1. Install the next release."
echo "  2. Remove every existing Beagle entry from System Settings >"
echo "     Privacy & Security > Accessibility."
echo "  3. Grant it once more, and relaunch."
echo
echo "That is the last time it will be necessary — later upgrades keep the grant."
