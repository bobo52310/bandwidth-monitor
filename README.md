# Bandwidth ECG

**English** · [繁體中文](README.zh-TW.md)

A macOS menu bar app that shows your network speed in real time and keeps track of your peaks, so you can decide with data whether your internet plan is too small, about right, or more than you need.

[![macOS](https://img.shields.io/badge/macOS-14.0+-blue)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange)](#requirements)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-Charts-green)](#requirements)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

> **Status: pre-release.** There is no prebuilt download yet. To try the app, [build it from source](#build-from-source). Project site: [bandwidth-ecg.bobochen.dev](https://bandwidth-ecg.bobochen.dev).

---

## Intro animation

![Bandwidth ECG, a 28-second intro](docs/promo/intro-en.gif)

> You pay for 1 Gbps and actually use 18% of it. Bandwidth ECG sits quietly in the menu bar for 30 days and then gives you a verdict: upgrade, downgrade, or stay where you are.

[MP4 (EN)](docs/promo/intro-en.mp4) · [MP4 (zh-TW)](docs/promo/intro-zh-tw.mp4) · [GIF (zh-TW)](docs/promo/intro-zh-tw.gif)

The animation sources (HyperFrames compositions) are in [`docs/design/promo-intro/`](docs/design/promo-intro/) and [`docs/design/promo-intro-zh-tw/`](docs/design/promo-intro-zh-tw/).

---

## Features

### See your connection at a glance
- **Live menu bar readout** of download and upload speed.
- **Chart ranges** of 1, 5, 15, 30 minutes and 1 hour, plus 3, 6, 12 and 24 hours.
- **Hover tooltips** on the chart show the exact time and speed.
- **24-hour history.** The chart keeps one point per 10 seconds (average and maximum) for 24 hours, and it survives a restart.
- **Stat cards** for the current speed and the today, all-time and 1-hour peaks.

### Peak tracking and the monthly report
- **Today / all-time / 1-hour peaks**, with the time each one happened.
- **Near-limit events.** Staying at or above 80% of your plan speed for 30 seconds counts as one event; the app records the daily count and the times.
- **Monthly report** built from a full record of every day, using sustained 3-second peaks, with an upgrade / keep / downgrade suggestion ([how it decides](#how-the-upgrade-suggestion-works)).
- **Connection quality:** latency, jitter, disconnect count and total outage time.

### Flexible display
- **Units:** Mbps or MB/s.
- **Menu bar modes:** download + upload, download only, upload only, or compact.
- **Visual alerts:** the menu bar turns orange with a `▲` marker once speed reaches the notification threshold (default 95% of your plan), and red with `▲▲` at the plan speed. The markers do not rely on colour, and with "Increase contrast" on, the colours are dropped and the markers stay.
- **Languages:** English, Traditional Chinese, Japanese and Korean, selectable in Settings (a language change needs a restart).

### Behaves like a menu bar app
- Menu bar only by default (no Dock icon); "Show in Dock" is a setting.
- Optional **Launch at Login** (off by default, registered with `SMAppService`).
- Optional **system notifications** when speed approaches your plan.
- **CSV export** of the last 24 hours and of your peak records.

---

## Requirements

- macOS 14.0 (Sonoma) or later. There is no fallback for older systems.
- Xcode 26 (Swift 6.2) to build from source.
- Apple Silicon or Intel. Release builds are universal; `./build.sh` builds Debug for arm64 only.

---

## Build from source

```bash
git clone https://github.com/bobo52310/bandwidth-monitor.git
cd bandwidth-monitor

# Option 1: Xcode
open BandwidthECG.xcworkspace      # then press Cmd+R

# Option 2: the build script
./build.sh                         # Debug build for arm64. Builds only, does not launch
./build.sh debug --run             # Debug build, then launch it
./build.sh release                 # Universal Release build. Builds only (cannot be combined with --run)
```

The app lands in `.build/DerivedData/Build/Products/<Debug|Release>/BandwidthECG.app`.

**Signing**

- **Debug builds** are ad hoc signed ("Sign to Run Locally") and use the bundle ID `com.bobo52310.BandwidthECG.debug`. You do **not** need an Apple Developer team or account.
- **Release builds** use the bundle ID `com.bobo52310.BandwidthECG` and no signing team is configured in this repository. To run or distribute a Release build you need to sign it yourself with your own team (and, for your own fork, your own bundle ID in `Config/Shared.xcconfig`).
- Debug and Release use different bundle IDs. The app is sandboxed, so each one keeps its data in its own container, and a Debug build never touches the data of an installed Release build.

### Run the tests

```bash
# Package unit tests only (does not build the app target, fastest)
swift test --package-path BandwidthECGPackage

# Through the Xcode scheme (the default test plan contains the unit tests only)
xcodebuild test -workspace BandwidthECG.xcworkspace \
                -scheme BandwidthECG \
                -destination 'platform=macOS,arch=arm64'
```

Check that the log says `Test run with N tests` with N greater than 0. `BandwidthECGUITests` holds a single placeholder test and is not part of the default test plan, so these commands do not launch the app.

---

## Using the app

### First launch

1. The first launch shows a short onboarding window (you can bring it back from Settings). The icon appears at the right of the menu bar.
2. Click the icon, open **Settings**, and enter your plan speed (download and upload are separate, for example 300 / 300 Mbps).
3. Monitoring starts straight away and the menu bar shows live speeds.

### Menu bar formats

- **Show both:** `↓ 288.9 ↑ 15.2 Mbps`
- **Download only:** `↓ 288.9 Mbps`
- **Upload only:** `↑ 15.2 Mbps`
- **Compact:** `↓288.9/↑15.2 Mbps`

Download and upload are each compared with their own plan speed, and the higher of the two decides the alert level:

| Speed | Menu bar |
|---|---|
| Below the notification threshold (default 95% of plan; 90, 95 or 98%) | Normal |
| At or above the notification threshold | Orange, `▲` in front, e.g. `▲ ↓ 288.9 ↑ 15.2 Mbps` |
| At or above the plan speed | Red, `▲▲` in front |

The alert level rises at once and falls back only after 3 seconds, so it does not flicker when your speed hovers around a threshold.

### Controls

- **Left-click** the menu bar icon to open or close the panel (when the panel is pinned, it toggles the pinned panel).
- **Right-click** (or Control-click) the icon for a menu with "Open Bandwidth ECG" and "Quit".
- **Open the app again** from Finder or Spotlight to show the panel. This is the way to reach it when a crowded menu bar hides the icon; the panel appears as a pinned panel.
- **Esc** or a click outside closes the panel (a pinned panel stays).

### The panel

An illustration; the real values and layout depend on your settings and window size.

```
Bandwidth ECG                              [Pin] [Settings]

  [1m 5m 15m 30m 1h]  [Longer ranges ▾]
  (chart: download / upload lines, hover for time and speed)

Approaching speed limit (↓300 / ↑300 Mbps)             3
  Triggered at: 09:15  13:42  14:35

Download                         Upload
  Today's peak: 295.4 Mbps         Today's peak: 250.7 Mbps
  All-time peak: 298.1 Mbps  (x)   All-time peak: 280.5 Mbps  (x)
  1-hour peak: 290.2 Mbps          1-hour peak: 245.1 Mbps
               14:35                            14:22

Network: Stable
Connection quality: latency 24 ms   jitter 3.1 ms
Disconnects today: 0

[Export Data ▾]  [Monthly Report]  [Reset Peaks]  [Quit Application]
```

- A peak that reaches the notification threshold turns orange and bold, with how long ago it happened.
- The `(x)` next to an all-time peak clears that direction only (after a confirmation).
- "Pin" turns the window into a panel that stays on screen; its position is remembered across restarts.
- When latency monitoring is off, the connection quality row reads "Latency monitoring is off".

### Monthly report

"Monthly Report" shows, per month: download / upload peak, average speed, plan speed, plan usage, near-limit events, disconnects, average latency and jitter, and days monitored. It exports to CSV (the CSV also includes total outage time).

- It is derived from a full record of every day, not from periodic snapshots, so an evening or overnight peak counts.
- A peak is a **sustained 3-second** speed (the lowest of three consecutive samples), so a one-second spike does not inflate the result.
- It counts traffic of this Mac only, including local network transfers.
- A day counts as monitored once at least 10 minutes were recorded.
- Each day is judged against the plan speed set on that day, so changing plans mid-month does not rewrite earlier days.
- "Reset Peaks" does not touch the monthly report data. It does clear the near-limit counts and the 24-hour chart history.

### How the upgrade suggestion works

All thresholds live in [`ReportRules.swift`](BandwidthECGPackage/Sources/BandwidthECGFeature/Models/ReportRules.swift).

| Suggestion | Condition |
|---|---|
| Not enough data | Fewer than 7 monitored days |
| Upgrade recommended | The sustained peak is above 90% of the plan on at least 3 days (download or upload) |
| Consider downgrading | At least 14 monitored days, no day above 90%, and the P95 of the daily sustained peaks is below 30% of the plan for both download and upload |
| Current plan fits | Everything else |

A short peak now and then is normal. What matters is whether you stay close to the limit for a sustained time.

### Export

"Export Data" offers two CSV files and always goes through the system save panel, so you choose the location:

- **Export Last 24 Hours:** one row per 10 seconds, with average and maximum.
- **Export Peak History:** today, all-time and 1-hour peaks.

---

## Data and privacy

- **Network requests.** Latency monitoring sends one HTTPS `HEAD` request to `www.apple.com` every 30 seconds to measure round-trip time. The request carries none of your monitoring data. You can turn it off in **Settings > Network Settings > Enable Latency Monitoring**, after which nothing is sent. This is the app's only outgoing request. There are no accounts and no ads.
- **Where data lives.** The app is sandboxed, so everything is inside its container: `~/Library/Containers/com.bobo52310.BandwidthECG/Data/Library/Application Support/BandwidthECG/` (Debug builds use `com.bobo52310.BandwidthECG.debug`).
  - `daily-records.json`: one record per day (the source of the monthly report), kept for 400 days.
  - `history-10s.json`: the 24-hour chart history.
  - `error_log.txt`: the error log. Above 1 MB it rolls over to `error_log.1.txt`, and only one older file is kept.
  - Preferences are in the container's `Library/Preferences/` plist.
- **Export permission.** An exported CSV is written only to the location you pick in the save panel (the sandbox's "user selected file" entitlement).

---

## Project structure

The project is an Xcode workspace plus a local Swift package:

```
bandwidth-monitor/
├── BandwidthECG.xcworkspace/      # Open this in Xcode
├── BandwidthECG.xcodeproj/        # App shell
├── BandwidthECG/                  # App target (minimal)
│   ├── Assets.xcassets/                 # Assets, including the app icon
│   ├── Localizable.xcstrings            # Strings (zh-Hant, en, ja, ko)
│   ├── BandwidthECG.xctestplan          # Test plan (not shipped in the app)
│   └── BandwidthECGApp.swift            # App entry point
├── Config/                        # XCConfig build settings and entitlements
│   ├── Shared.xcconfig / Debug.xcconfig / Release.xcconfig / Tests.xcconfig
│   └── BandwidthECG.entitlements        # Sandbox settings
├── BandwidthECGPackage/           # Where almost all of the code lives
│   ├── Package.swift
│   ├── Sources/BandwidthECGFeature/     # Feature code
│   └── Tests/                           # Unit tests (Swift Testing)
├── BandwidthECGUITests/           # UI tests (a placeholder, not in the default test plan)
├── build.sh                       # Build script
├── website/                       # Landing page (Astro)
└── docs/                          # Promo media and compositions; docs/archive/ is historical notes
```

### Core components

- **NetworkMonitor:** samples network traffic once per second.
- **PeakRecorder:** today / all-time / 1-hour peaks.
- **PeakApproachTracker:** near-limit event counting.
- **NetworkHistoryRecorder:** chart history (10-second average and maximum, 24 hours).
- **DailyRecordStore:** daily records, the source of the monthly report.
- **MonthlyReportService:** derives the monthly report and the plan suggestion.
- **LatencyMonitor / DisconnectTracker / NetworkAnomalyDetector:** latency, disconnect and anomaly detection.
- **NotificationService:** notifications when speed approaches your plan.
- **DataExportService:** CSV export.
- **NetworkMonitorViewModel:** the main coordinator.
- **StatusBarController:** the menu bar item and panel.
- **UserPreferences:** user settings.

### Build configuration

Build settings are managed in `Config/*.xcconfig`: `Shared.xcconfig` (bundle ID, deployment target macOS 14.0, Info.plist keys such as "no Dock icon", app category, copyright), `Debug.xcconfig` (adds `.debug` to the bundle ID), `Release.xcconfig` and `Tests.xcconfig`. The entitlements are the sandbox, outgoing network connections and user-selected file read/write. The project uses the Swift 6 language mode.

---

## Troubleshooting

**The build fails with Swift concurrency errors.** Use Xcode 26 or later with a macOS 14.0+ deployment target (the project uses the Swift 6 language mode).

**I can't see the menu bar icon or speed.** A crowded menu bar can push the icon off screen. Open Bandwidth ECG again from Finder or Spotlight to bring up the panel. A shorter menu bar mode (compact, download only, upload only) also helps.

**The speed shows 0 or looks wrong.** Check that the Mac is online and generate some traffic. A VPN can affect the numbers.

**The app seems to use a lot of resources.** Long chart ranges (3 to 24 hours) draw more points than short ones. Close the panel or pick a shorter range, and if it keeps happening open an issue with your macOS version.

**Launch at Login does not work.** Move the app to `/Applications` or `~/Applications` first. A copy that runs from a disk image or the Downloads folder does not survive a login-item restart, so the toggle is disabled with a hint. If Settings asks for permission, allow Bandwidth ECG in **System Settings > General > Login Items**. The toggle shows the system's current state, so removing the item in System Settings turns it off.

**The monthly report says "Not enough data".** It needs at least 7 monitored days, and a day only counts after 10 minutes of monitoring.

**I don't want the app to send any request.** Turn off **Enable Latency Monitoring** in Settings > Network Settings.

---

## Manual testing without touching real data

The installed app keeps its preferences and data in `~/Library/Containers/com.bobo52310.BandwidthECG`. Environment variables such as `CFFIXED_USER_HOME` do **not** isolate a sandboxed app.

- Use `./build.sh debug --run`. The Debug build has its own bundle ID and container.
- Avoid launching a Release build with the real bundle ID if you also use the released app. To check Release behaviour, copy the `.app` out of the repository, change `CFBundleIdentifier` in its `Info.plist` to a throwaway ID, re-sign it ad hoc with `codesign --force --sign -`, and launch only the copy.

---

## Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first: it covers how to build and test, the localisation rule for user-facing strings, and the commit style. Security problems go through [SECURITY.md](SECURITY.md), not public issues.

## License

Released under the [MIT License](LICENSE). Copyright (c) 2026 Bobo Chen.

## Acknowledgements

- Charts are drawn with [SwiftUI Charts](https://developer.apple.com/documentation/charts).
- The project layout was inspired by [XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP).

## Contact

Questions and ideas: open a [GitHub issue](https://github.com/bobo52310/bandwidth-monitor/issues).
