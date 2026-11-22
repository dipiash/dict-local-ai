# Releasing

Public source releases are produced by GitHub Actions from a semantic version tag after the check workflow passes, as a draft. Do not publish a tag until the native acceptance checklist and security/licensing checks pass. CI does not use a local signing certificate or publish unsigned binaries.

For a locally signed DMG run `DICT_BUILD_VERSION=0.1.0 task dmg` (choose the actual release version), or run `task dmg` from an exact `vMAJOR.MINOR.PATCH` tag. It produces `dist/Dict-Local-AI.dmg`, a ZIP and SHA256SUMS. The background and Finder layout are authored before `hdiutil create -srcfolder`; the script does not explicitly mount to arrange icons. Verify visually on macOS. Do not distribute a local/Apple Development build as a notarized product.

For public distribution configure a Developer ID Application certificate and a notarytool Keychain profile. Build the current app, then run:

```sh
DICT_RELEASE_DEVELOPER_ID='<Developer ID Application identity>' \
DICT_NOTARY_PROFILE='<keychain profile>' task release:notarize
```

The release task produces a ZIP containing the stapled app, a signed and stapled DMG, and a checksum file in `dist/public/`. Inspect these artifacts and verify that they match the intended source tag. For the ZIP installer, run `DICT_REPOSITORY=owner/repo DICT_RELEASE_TEAM_ID=EXPECTEDID ./install.sh` with the Apple Team ID confirmed independently from the publisher. The installer checks the signing identity and Gatekeeper before replacing an installed copy. Use the README source-install instructions while a verified public binary is unavailable. Do not pipe unreviewed scripts to shell.

Before the first push, enable secret scanning/push protection, Dependabot alerts, private security reporting, and branch protection/rulesets in GitHub settings. Review all tracked files and scan the fresh history with Gitleaks. Run CI in a private staging repository first. The workflow uses the checksum-pinned Gitleaks CLI. Never push the private development history.
