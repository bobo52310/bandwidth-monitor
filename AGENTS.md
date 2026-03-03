# Repository Guidelines

## Project Structure & Module Organization

- `BandwidthECG.xcworkspace`: open this workspace in Xcode (preferred).
- `BandwidthECG/`: app shell (entry point, assets, test plan).
- `BandwidthECGPackage/`: Swift Package containing almost all feature code.
  - `Sources/BandwidthECGFeature/Views/`: SwiftUI views (menu bar popover, charts, settings).
  - `Sources/BandwidthECGFeature/ViewModels/`: state + coordination (MVVM).
  - `Sources/BandwidthECGFeature/Services/`: networking/speed polling, history, anomaly detection, speed test, leaderboard.
  - `Sources/BandwidthECGFeature/Models/`: domain models and preferences.
- `Config/`: `.xcconfig` build settings + entitlements.
- Tests:
  - `BandwidthECGPackage/Tests/BandwidthECGFeatureTests/`: unit tests (Swift Testing).
  - `BandwidthECGUITests/`: UI tests.

## Build, Test, and Development Commands

```bash
# Open in Xcode
open BandwidthECG.xcworkspace

# Build and launch (Debug / Release)
./build.sh
./build.sh Release

# Run all tests (CLI)
xcodebuild test -workspace BandwidthECG.xcworkspace -scheme BandwidthECG -destination 'platform=macOS'

# Run package tests faster (no app build)
cd BandwidthECGPackage && swift test
```

## Coding Style & Naming Conventions

- Swift 6 + SwiftUI; keep types `UpperCamelCase`, members `lowerCamelCase`.
- Indentation: 4 spaces; prefer small focused types and readable SwiftUI view composition.
- User-facing strings are Traditional Chinese (Taiwan). Keep new UI copy consistent.
- No repo-wide linter/formatter is enforced; keep diffs minimal and let Xcode format.

## Testing Guidelines

- Unit tests use Swift Testing (`import Testing`, `@Test`, `#expect(...)`).
- Name test files `*Tests.swift` and keep tests close to the module under test.
- Include at least one new/updated test for behavior changes that aren’t purely UI.

## Commit & Pull Request Guidelines

- Use Conventional Commits seen in history: `feat:`, `fix:`, `docs:`, `chore:` (optional scope if helpful).
- PRs should include: problem/solution summary, testing steps (Xcode / CLI), and screenshots or screen recordings for UI changes.
- If changing entitlements or configs, call it out explicitly (files in `Config/`).

## Security & Configuration Tips

- Don’t commit secrets, personal data, or local paths (e.g., DerivedData).
- Speed tests may require external tooling (e.g., Speedtest CLI); document new dependencies in `README.md`.
