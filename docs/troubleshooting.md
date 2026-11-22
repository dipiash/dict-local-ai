# Troubleshooting

**Dictation did not paste:** check Accessibility and that the target editor has focus at stop. Try manual Command-V; the clipboard fallback should contain the result if automatic delivery was unavailable. `paste_posted_unconfirmed` means the event was posted, not proof of receipt. Do not perform blind duplicate insertion.

**Permissions / duplicate copies:** close the app and use `task permissions:doctor`. The development path is `~/Applications/Dict Local AI.app`. Keep one installed copy. `task install` preserves the designated signing requirement and refuses conflicting copies. Only use `task permissions:reset` for deliberate recovery, not routine rebuilds.

**Gatekeeper:** local code signing is not notarization. Use a trusted local build for development; public binary distribution requires Developer ID and notarization. Do not disable Gatekeeper system-wide.

**Models:** explicitly install through Settings → Models. Verify available space and connection during downloads, then test offline. Model receipts are checked before restoration. **Logs:** `task logs:tail` or `task logs:open`; review and redact all diagnostic data before sharing. For a hang, `scripts/development/capture-hang.sh` may collect a local sample; do not publish raw reports.
