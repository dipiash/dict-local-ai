# ADR 0003 — Stable local signing and separate public distribution

Status: accepted

Retain Bundle ID app.dictlocalai.desktop and a pinned local signing identity to preserve TCC across updates. Do not automatically reset user permission grants. Generate the branded DMG without explicitly mounting it for styling. Public binaries require separate Developer ID signing and notarization. Source-only CI releases do not need private certificates.
