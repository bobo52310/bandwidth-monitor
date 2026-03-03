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

# Build with script
./build.sh            # Debug build
./build.sh Release    # Release build

# Run tests
xcodebuild test -workspace BandwidthECG.xcworkspace \
                -scheme BandwidthECG \
                -destination 'platform=macOS'
```

## Project Structure

```
BandwidthECG/
├── BandwidthECG.xcworkspace/           # Open this in Xcode
├── BandwidthECG/                       # App target (minimal)
│   ├── BandwidthECGApp.swift           # Entry point
│   ├── Assets.xcassets/
│   └── BandwidthECG.entitlements
├── BandwidthECGPackage/                # Primary development area
│   ├── Package.swift
│   ├── Sources/BandwidthECGFeature/    # Feature code
│   └── Tests/                                # Unit tests
├── BandwidthECGUITests/
├── Config/                                   # XCConfig build settings
├── screenshots/
├── website/                                  # Marketing/landing page
└── docs/
```

## Development Notes

- Core components: NetworkMonitor (speed sampling), PeakRecorder (peak tracking), PeakApproachTracker (near-peak counting), StatusBarController (menu bar display)
- Display modes: upload+download, download only, upload only, compact
- Units: Mbps or MB/s, user-configurable
- Visual alerts when approaching plan speed limits (orange/red)
- Multiple chart time ranges: 1min, 5min, 15min, 30min, 1hr, 24hr
- Menu bar only by default (no Dock icon); Dock visibility is a user setting
- Target performance: CPU < 1%, memory < 50MB
