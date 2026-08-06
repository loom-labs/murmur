#!/usr/bin/env bash
#
# Create a stable self-signed code-signing identity for local development.
#
# Why this exists: macOS keys Accessibility and Screen Recording grants to an
# app's code signature. An ad-hoc signature ("-") is derived from the binary's
# contents, so **every rebuild produces a different identity** and macOS treats
# the app as brand new — the permission you granted five minutes ago no longer
# applies, and posted keyboard events are silently dropped.
#
# Signing with a fixed certificate gives a constant designated requirement, so a
# grant survives rebuilds.
#
# This only matters when building from source. A released DMG is installed once,
# so its ad-hoc signature never changes under the user.
#
# Usage:
#   Scripts/make-signing-identity.sh          # create it if missing
#   Scripts/build-app.sh --sign "Beagle Dev"    # then build with it
#
set -euo pipefail

readonly IDENTITY_NAME="${1:-Beagle Dev}"
readonly KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-certificate -c "${IDENTITY_NAME}" "${KEYCHAIN}" >/dev/null 2>&1; then
    echo "Identity '${IDENTITY_NAME}' already exists."
    echo "Build with: Scripts/build-app.sh --sign '${IDENTITY_NAME}'"
    exit 0
fi

workdir="$(mktemp -d)"
readonly workdir
trap 'rm -rf "${workdir}"' EXIT

echo "==> Generating a self-signed code-signing certificate"

# extendedKeyUsage=codeSigning is the part that matters: without it `codesign`
# refuses the certificate even though the key is valid.
cat >"${workdir}/openssl.cnf" <<CONF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no

[ dn ]
CN = ${IDENTITY_NAME}

[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "${workdir}/key.pem" \
    -out "${workdir}/cert.pem" \
    -days 3650 \
    -config "${workdir}/openssl.cnf" >/dev/null 2>&1

# Two things here are load-bearing, and both were wrong before:
#
#   -legacy      OpenSSL 3 defaults to AES-256-CBC with a SHA-256 MAC, which
#                Apple's Security framework cannot read. Importing such a file
#                fails with "MAC verification failed during PKCS12 import
#                (wrong password?)" — a misleading error, since the password is
#                fine. -legacy falls back to the algorithms macOS accepts.
#
#   a password   An empty PKCS#12 password fails the same import even with
#                -legacy. The value does not matter; it is used once, here.
p12_password="$(uuidgen)"
readonly p12_password

openssl pkcs12 -export -legacy \
    -inkey "${workdir}/key.pem" \
    -in "${workdir}/cert.pem" \
    -out "${workdir}/identity.p12" \
    -passout "pass:${p12_password}" >/dev/null 2>&1

echo "==> Importing into the login keychain"
echo "    macOS will ask for your password, and again to trust the certificate."

# -T codesign pre-authorizes codesign to use the key, so builds do not each
# stop on a keychain dialog.
security import "${workdir}/identity.p12" \
    -k "${KEYCHAIN}" \
    -P "${p12_password}" \
    -T /usr/bin/codesign

# Authorize codesign against the imported key. `-k` is deliberately omitted so
# macOS prompts for the login keychain password: an earlier version passed
# `-k ""`, which assumed an empty keychain password, silently failed on every
# real account, and left codesign stopping on a dialog at each build instead.
echo
echo "==> macOS will now ask for your login password to authorize codesign."
if ! security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s "${KEYCHAIN}" >/dev/null 2>&1; then
    echo "    Skipped — codesign may prompt on first use. Choose \"Always Allow\"."
fi

# Deliberately no `security add-trusted-cert`. A self-signed certificate is
# never "valid" to `find-identity -v`, but codesign signs with it regardless —
# trust governs verification, not signing. Skipping it avoids an admin
# authorization prompt for no benefit.

echo
echo "Created '${IDENTITY_NAME}'."
echo
echo "Build signed with it:"
echo "    Scripts/build-app.sh --sign '${IDENTITY_NAME}'"
echo
echo "Then grant Accessibility once, and it will survive rebuilds."
