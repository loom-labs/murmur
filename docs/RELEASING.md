# Releasing

Releases are cut automatically. Merging a pull request whose title carries
`#major`, `#minor`, or `#patch` makes CI work out the next version from the
latest `vX.Y.Z` tag, build the DMG, and publish a GitHub release. A title with
no bump tag merges without releasing.

## Notarization

Without an Apple Developer account, releases are **ad-hoc signed**. That is a
valid signature, but it is not a notarized one, so on first launch macOS says:

> "Apple could not verify Beagle is free of malware that may harm your Mac or
> compromise your privacy."

This is Apple reporting the *absence of notarization*, not the presence of
malware. Users get past it with:

```bash
xattr -dr com.apple.quarantine /Applications/Beagle.app
```

or System Settings → Privacy & Security → **Open Anyway**. Both the release
notes and the DMG's install note say so, but it is still a wall in front of
every first-time user.

### Making it go away

Notarization requires the [Apple Developer
Program](https://developer.apple.com/programs/) — $99/year. There is no free
route: Apple will not notarize without a paid team.

Once enrolled, add four repository secrets and the release workflow starts
signing and notarizing on its own. Nothing else changes; the steps are already
in [`release.yml`](../.github/workflows/release.yml) and skip themselves when
the secrets are absent.

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_CERT_P12` | Base64 of your exported *Developer ID Application* certificate |
| `DEVELOPER_ID_CERT_PASSWORD` | The password you set when exporting the `.p12` |
| `APPLE_ID` | The Apple ID email on the developer account |
| `APPLE_TEAM_ID` | Your 10-character team identifier |
| `APPLE_APP_PASSWORD` | An [app-specific password](https://support.apple.com/en-us/102654), **not** your Apple ID password |

Export and encode the certificate:

```bash
# Keychain Access → My Certificates → "Developer ID Application: …"
# → right-click → Export → save as certificate.p12
base64 -i certificate.p12 | pbcopy
```

Then add the secrets:

```bash
gh secret set DEVELOPER_ID_CERT_P12 --repo loom-labs/beagle        # paste the base64
gh secret set DEVELOPER_ID_CERT_PASSWORD --repo loom-labs/beagle
gh secret set APPLE_ID --repo loom-labs/beagle
gh secret set APPLE_TEAM_ID --repo loom-labs/beagle
gh secret set APPLE_APP_PASSWORD --repo loom-labs/beagle
```

The next release will be signed with the Developer ID, submitted to Apple,
and stapled — so the ticket travels with the DMG and the first launch works
even offline. Gatekeeper stops complaining, and the quarantine instructions
drop out of the release notes automatically.

### A side benefit

macOS ties Accessibility and Screen Recording grants to an app's code
signature. An ad-hoc signature is a hash of the binary, so **every release
invalidates the previous grant** and users have to re-add Beagle to the
Accessibility list. A stable Developer ID signature fixes that too: grant once,
and it survives upgrades.

## Local builds

For building from source, `Scripts/make-signing-identity.sh` creates a
self-signed identity so permissions survive rebuilds. That is enough for
development but cannot notarize — only a Developer ID can.
