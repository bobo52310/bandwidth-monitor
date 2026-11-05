# CLAUDE.md

## Project Overview

Bandwidth ECG is a macOS menu bar app for real-time network speed monitoring and peak tracking. It helps users make data-driven decisions about whether to upgrade their internet plan by recording download/upload speeds, daily peaks, and historical highs.

## Tech Stack

- Swift 6.2+, macOS 14.0+
- SwiftUI + SwiftUI Charts
- Xcode workspace + SPM package architecture
- XCConfig-based build settings

## Common Commands

```bash
# Open in Xcode
open BandwidthECG.xcworkspace

# Build with script (build only; never launches unless --run, which is Debug only)
./build.sh            # Debug build
./build.sh release    # Release build (universal)

# Run tests
swift test --package-path BandwidthECGPackage    # fast; log must say "Test run with N tests", N > 0
xcodebuild test -workspace BandwidthECG.xcworkspace \
                -scheme BandwidthECG \
                -destination 'platform=macOS,arch=arm64'
```

## Project Structure

```
bandwidth-monitor/
├── BandwidthECG.xcworkspace/           # Open this in Xcode
├── BandwidthECG/                       # App target (minimal)
│   ├── BandwidthECGApp.swift           # Entry point
│   ├── Assets.xcassets/
│   └── Localizable.xcstrings           # zh-Hant, en, ja, ko
├── BandwidthECGPackage/                # Primary development area
│   ├── Package.swift
│   ├── Sources/BandwidthECGFeature/    # Feature code
│   └── Tests/                                # Unit tests
├── BandwidthECGUITests/                      # Placeholder; not in the default test plan
├── Config/                                   # XCConfig build settings + BandwidthECG.entitlements
├── website/                                  # Marketing/landing page (Astro)
└── docs/                                     # promo/ media, design/ promo compositions, archive/ historical notes (not current docs)
```

## Development Notes

- Core components: NetworkMonitor (speed sampling), PeakRecorder (peak tracking), PeakApproachTracker (near-peak events), DailyRecordStore + MonthlyReportService (monthly report from full-day records, sustained 3 s peaks), NetworkHistoryRecorder (10 s average + max, `history-10s.json`, 24 h retention), StatusBarController (menu bar display)
- All report thresholds live in `Models/ReportRules.swift`
- Display modes: download+upload, download only, upload only, compact (`↓288.9/↑15.2 Mbps`)
- Units: Mbps or MB/s, user-configurable
- Menu bar alerts: orange from the notification threshold, red from the plan, with a `▲` / `▲▲` text cue (not colour only)
- Chart ranges: 1, 5, 15, 30 min and 1 h, plus 3, 6, 12, 24 h
- Menu bar only by default (no Dock icon, `LSUIElement`); Dock visibility is a user setting. Right click opens a menu; opening the app again shows the panel
- Launch at login uses `SMAppService`; export goes through the save panel (sandbox)
- User-facing strings go in `Utilities/L10n.swift` and `Localizable.xcstrings` (`L10nCatalogTests` enforces it)
- Target performance: CPU < 1%, memory < 50MB
- Min macOS 14.0 (no fallback for older systems), Xcode 26

## Launching the App (read before running anything)

- Debug builds use bundle ID `com.bobo52310.BandwidthECG.debug`; Release uses the real `com.bobo52310.BandwidthECG`, whose sandbox container holds the user's real data
- Never launch a Release build or the real bundle ID. `CFFIXED_USER_HOME` does not isolate it
- For manual QA, run a copy of the built `.app` from outside the repo: change `CFBundleIdentifier` to a throwaway ID and re-sign ad hoc (`codesign --force --sign -`)
