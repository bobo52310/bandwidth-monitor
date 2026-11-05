# Repository Guidelines

## Project Structure & Module Organization

- `BandwidthECG.xcworkspace`: open this workspace in Xcode (preferred).
- `BandwidthECG/`: app shell (entry point, assets, `Localizable.xcstrings`, test plan).
- `BandwidthECGPackage/`: Swift Package containing almost all feature code.
  - `Sources/BandwidthECGFeature/Views/`: SwiftUI views (menu bar popover, charts, settings).
  - `Sources/BandwidthECGFeature/ViewModels/`: state + coordination (MVVM).
  - `Sources/BandwidthECGFeature/Services/`: speed sampling, peak and daily records, 24-hour history, monthly report, latency, disconnect and anomaly detection, notifications, CSV export.
  - `Sources/BandwidthECGFeature/Utilities/`: `L10n.swift` (every user-facing string), injected clock and dependencies, paths.
  - `Sources/BandwidthECGFeature/Models/`: domain models and preferences.
- `Config/`: `.xcconfig` build settings + `BandwidthECG.entitlements`.
- `website/`: the Astro landing page (4 locales). `docs/`: promo media in `docs/promo/`, video compositions in `docs/design/`, and `docs/archive/` (historical planning notes, not current documentation).
- Tests:
  - `BandwidthECGPackage/Tests/BandwidthECGFeatureTests/`: unit tests (Swift Testing).
  - `BandwidthECGUITests/`: UI tests.

## Build, Test, and Development Commands

```bash
# Open in Xcode
open BandwidthECG.xcworkspace

# Build only (output: .build/DerivedData/Build/Products/<Debug|Release>/BandwidthECG.app)
./build.sh                  # Debug, arm64
./build.sh release          # Release, universal; never launched

# Build, then launch the Debug app (bundle ID com.bobo52310.BandwidthECG.debug)
./build.sh debug --run

# Run all tests (CLI)
xcodebuild test -workspace BandwidthECG.xcworkspace -scheme BandwidthECG -destination 'platform=macOS,arch=arm64'

# Run package tests faster (no app build)
swift test --package-path BandwidthECGPackage

# Website (Node 22.23.4, see website/.node-version)
cd website && npm ci && npm run build && node scripts/check-i18n.mjs --dist
```

`swift test` does not build the app target; run `./build.sh` too after touching `BandwidthECG/`, `Config/` or public API. Check that the test log says `Test run with N tests` with N > 0: a run can discover 0 tests and still exit 0.

## Running the App Safely

- Debug builds use bundle ID `com.bobo52310.BandwidthECG.debug`, so they have their own sandbox container. Release uses the real ID `com.bobo52310.BandwidthECG` and the user's real container (`~/Library/Containers/com.bobo52310.BandwidthECG`).
- Never launch a Release build or the real bundle ID for testing. `CFFIXED_USER_HOME` does not isolate it. For a manual check of a Release build, copy the `.app` outside the repo, change `CFBundleIdentifier` to a throwaway ID, re-sign ad hoc (`codesign --force --sign -`), and run only the copy.
- `BandwidthECGUITests` is not in the default test plan, so `xcodebuild test` does not launch the app.

## Coding Style & Naming Conventions

- Swift 6 + SwiftUI; keep types `UpperCamelCase`, members `lowerCamelCase`.
- Indentation: 4 spaces; prefer small focused types and readable SwiftUI view composition.
- User-facing strings live in `Utilities/L10n.swift` with a Traditional Chinese (Taiwan) `defaultValue`; the app ships zh-Hant, en, ja and ko in `BandwidthECG/Localizable.xcstrings`. Add a key to both. `L10nCatalogTests` fails on a missing key, an orphan key, a missing translation or a hard-coded Chinese string in UI code.
- Website copy lives in `website/src/i18n/locales/{zh-Hant,en,ja,ko}.json`; every locale needs the same keys. `node scripts/check-i18n.mjs --dist` checks the key sets and bans unverifiable claims.
- No repo-wide linter/formatter is enforced; keep diffs minimal and let Xcode format.

## Testing Guidelines

- Unit tests use Swift Testing (`import Testing`, `@Test`, `#expect(...)`).
- Name test files `*Tests.swift` and keep tests close to the module under test.
- Include at least one new/updated test for behavior changes that aren’t purely UI.

## Commit & Pull Request Guidelines

- Use Conventional Commits seen in history: `feat:`, `fix:`, `docs:`, `chore:`, `ci:` (optional scope if helpful).
- Never skip hooks (`--no-verify`), and never disable or skip a failing test to get a change in. See `CONTRIBUTING.md`.
- PRs should include: problem/solution summary, testing steps (Xcode / CLI), and screenshots or screen recordings for UI changes.
- If changing entitlements or configs, call it out explicitly (files in `Config/`).

## Security & Configuration Tips

- Don’t commit secrets, personal data, or local paths (e.g., DerivedData).
- The app is sandboxed (`Config/BandwidthECG.entitlements`: app sandbox, outgoing network, user-selected files read/write). The only outgoing request is the latency probe (HTTPS HEAD to apple.com every 30 seconds, switchable in Settings). Document any new network access or entitlement in `README.md` and `README.zh-TW.md`.
- Don’t change the Release bundle ID or the Application Support location (`~/Library/Application Support/BandwidthECG`, inside the container); existing user data lives there.
