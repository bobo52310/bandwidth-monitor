# Contributing to Bandwidth ECG

Thanks for your interest. Bug reports, feature ideas and pull requests are all welcome.

By contributing you agree that your contribution is released under the project's [MIT License](LICENSE).

## Before you start

- For a bug, search the [issues](https://github.com/bobo52310/bandwidth-monitor/issues) first, then open one with the bug report template.
- For a larger change or a new feature, open an issue to discuss it before writing code, so we can agree on the approach.
- Security problems do **not** go in public issues. See [SECURITY.md](SECURITY.md).

## Requirements

- macOS 14.0 or later and Xcode 26 (Swift 6.2) for the app.
- Node.js 22.23.4 for the landing page in `website/` (see `website/.node-version`; `fnm` or `nvm` will pick it up).

## Build and test

```bash
git clone https://github.com/bobo52310/bandwidth-monitor.git
cd bandwidth-monitor

# App: build only (Debug, arm64). It does not launch the app.
./build.sh

# App: unit tests. The log must say "Test run with N tests" with N > 0.
swift test --package-path BandwidthECGPackage

# Website
cd website
npm ci
npm run build
node scripts/check-i18n.mjs --dist
```

`swift test` does not build the app target, so also run `./build.sh` when you touch `BandwidthECG/`, `Config/` or public API. You can open `BandwidthECG.xcworkspace` in Xcode instead and press Cmd+R.

Debug builds are ad hoc signed and use the bundle ID `com.bobo52310.BandwidthECG.debug`, so you do not need an Apple Developer team. The CI workflow runs the same app tests and website checks on every pull request.

### Running the app safely

- Run Debug builds only (`./build.sh debug --run`). They have their own sandbox container.
- Do not launch a Release build or the real bundle ID `com.bobo52310.BandwidthECG` for testing: it uses the container that holds the installed app's real data, and environment variables such as `CFFIXED_USER_HOME` do not isolate it.
- Do not change the Release bundle ID or the Application Support location (`~/Library/Application Support/BandwidthECG` inside the container). Existing users' data lives there.

## Code guidelines

- Swift 6 and SwiftUI. Types are `UpperCamelCase`, members `lowerCamelCase`, indentation is 4 spaces. Keep diffs small and focused; there is no repo-wide formatter.
- Almost all code lives in `BandwidthECGPackage/Sources/BandwidthECGFeature/`. The app target is a thin shell. Public API used across modules needs `public`.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`). Name files `*Tests.swift`. Add or update at least one test for any behaviour change that is not purely UI.
- Never disable, skip or delete a failing test to get a change through. Fix the code or the test.
- If you change entitlements or anything in `Config/`, say so in the pull request. If you add network access or an entitlement, document it in `README.md` and `README.zh-TW.md`. The only outgoing request today is the latency probe.

### User-facing strings (the localisation rule)

Every string a user can see goes through `Utilities/L10n.swift` and `BandwidthECG/Localizable.xcstrings`:

1. Add a `static let` in `L10n.swift` using `String(localized:defaultValue:)`. The `defaultValue` is Traditional Chinese (Taiwan).
2. Add the same key to `Localizable.xcstrings` with all four translations: `zh-Hant`, `en`, `ja` and `ko`.
3. Do not hard-code Chinese (or any user-visible) text in views.

`L10nCatalogTests` fails on a missing key, an orphan key, a missing translation or a hard-coded Chinese string in UI code, so `swift test` will tell you.

The landing page follows the same idea: copy lives in `website/src/i18n/locales/{zh-Hant,en,ja,ko}.json`, and every locale must have the same keys. `node scripts/check-i18n.mjs --dist` checks the key sets and rejects wording the product cannot back up (for example performance figures or download calls to action before a release exists).

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/), as in the project history:

```
feat(website): link source on GitHub
fix(app): keep the legacy in-progress month in the report
docs: English README, contributing and security policy
chore(build): isolate Debug bundle ID and harden build script
ci: add app and website workflows
```

- Types in use: `feat`, `fix`, `docs`, `chore`, `ci`, `refactor`, `perf`, `test`. An optional scope such as `app`, `website` or `i18n` helps.
- Write the subject in the imperative, and explain the why in the body when it is not obvious.
- Every commit should build and pass the tests.
- **Never use `--no-verify`** (or otherwise skip hooks or checks). If a hook fails, fix the cause.
- Do not commit secrets, personal data or local paths (for example `DerivedData`, `.env` files, absolute `/Users/...` paths).

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Make your change, with tests, and run the build and test commands above.
3. Open a pull request using the template: summary of the problem and solution, how you tested it, and screenshots or a short screen recording for UI changes.
4. Keep the pull request to one logical change. Small, focused pull requests are reviewed faster.

If you change `README.md`, update `README.zh-TW.md` to match (and the other way round).
