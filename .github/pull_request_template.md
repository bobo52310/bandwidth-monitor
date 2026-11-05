## Summary

<!-- What problem does this solve, and how? Link the issue it closes, e.g. "Closes #123". -->

## Testing

<!-- How did you test it? Tick what you ran. -->

- [ ] `swift test --package-path BandwidthECGPackage` (the log says `Test run with N tests`, N > 0)
- [ ] `./build.sh` (needed when touching `BandwidthECG/`, `Config/` or public API)
- [ ] Website changes only: `cd website && npm ci && npm run build && node scripts/check-i18n.mjs --dist`

## Screenshots or screen recording

<!-- Required for UI changes. -->

## Checklist

- [ ] New or changed user-facing strings go through `L10n.swift` and `Localizable.xcstrings` in zh-Hant, en, ja and ko (or `website/src/i18n/locales/*.json` for the site)
- [ ] Added or updated a test for any behaviour change that is not purely UI
- [ ] Commits follow Conventional Commits, and no hooks or checks were skipped (`--no-verify`)
- [ ] `README.md` and `README.zh-TW.md` updated if behaviour, network access or entitlements changed
- [ ] If this changes `Config/` or the entitlements, I called it out above
