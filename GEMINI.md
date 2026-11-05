# Bandwidth ECG

## Project Overview

Bandwidth ECG is a macOS menu bar app for real-time network speed monitoring and peak tracking. It records download and upload speeds, daily and all-time peaks and a monthly report, so users can decide with data whether to upgrade (or downgrade) their internet plan.

This file is a short brief for Gemini CLI. `AGENTS.md` has the repository guidelines and `CLAUDE.md` the detailed development notes; keep the three consistent with each other and with the code.

**Key Technologies:**
- **Language:** Swift 6.2 (Swift 6 language mode)
- **Frameworks:** SwiftUI, SwiftUI Charts
- **Platform:** macOS 14.0+ (no fallback for older systems), Xcode 26 to build
- **Architecture:** Xcode workspace + local Swift Package (`BandwidthECGPackage`), build settings in `Config/*.xcconfig`

**Core Features:**
- **Real-time monitoring:** download and upload speed in the menu bar (download+upload, download only, upload only or compact), in Mbps or MB/s.
- **Charts:** 1, 5, 15, 30 min and 1 h, plus 3, 6, 12 and 24 h ranges with hover tooltips. History is kept as 10 s points (average and maximum) for 24 hours.
- **Peak tracking:** today, all-time and 1-hour peaks, plus counts of sustained near-plan-speed events.
- **Monthly report:** built from full-day records with sustained 3 s peaks, with an upgrade / keep / downgrade suggestion. All thresholds are in `Models/ReportRules.swift`.
- **Connection quality:** latency and jitter (HTTPS HEAD to apple.com every 30 s, can be switched off), disconnect tracking and anomaly detection.
- **Alerts:** menu bar turns orange at the notification threshold and red at the plan speed, with a text cue (`▲` / `▲▲`); optional system notifications.
- **CSV export** of the last 24 hours and of the peak records, through the save panel (sandbox).
- **Languages:** zh-Hant, en, ja, ko.

## Architecture

### Directory Structure

- **`BandwidthECG.xcworkspace`**: open this in Xcode.
- **`BandwidthECG/`**: thin app shell (`BandwidthECGApp.swift`, assets, `Localizable.xcstrings`, test plan).
- **`BandwidthECGPackage/`**: almost all code, as a Swift Package.
  - **`Sources/BandwidthECGFeature/`**: views, view models, services, models, utilities.
  - **`Tests/BandwidthECGFeatureTests/`**: unit tests (Swift Testing).
- **`Config/`**: `.xcconfig` build settings and `BandwidthECG.entitlements`.
- **`BandwidthECGUITests/`**: placeholder UI tests, not in the default test plan.
- **`website/`**: Astro landing page. **`docs/`**: promo media and compositions; `docs/archive/` is historical, not current.

### Key Components (`BandwidthECGPackage`)

| Component | Type | Description |
|-----------|------|-------------|
| **`NetworkMonitor`** | Service | Reads interface byte counters with `getifaddrs` once per second. |
| **`NetworkMonitorViewModel`** | ViewModel | Central coordinator. Receives samples from `NetworkMonitor` and distributes them. |
| **`StatusBarController`** | View | Manages the menu bar item and the popover / pinned panel. |
| **`PeakRecorder`** | Service | Today, all-time and 1-hour peaks. |
| **`PeakApproachTracker`** | Service | Counts sustained near-plan-speed events per day. |
| **`NetworkHistoryRecorder`** | Service | 10 s average and max points for the charts, 24 h retention (`history-10s.json`). |
| **`DailyRecordStore`** + **`MonthlyReportService`** | Service | Full-day records and the monthly report derived from them. |
| **`LatencyMonitor`** / **`DisconnectTracker`** / **`NetworkAnomalyDetector`** | Service | Latency and jitter, disconnect events, and drop / zero-speed anomalies. |

### Data Flow

1.  **Polling:** `NetworkMonitor` samples the network interfaces every second.
2.  **Distribution:** `NetworkMonitorViewModel` feeds each sample to `PeakRecorder`, `PeakApproachTracker`, `NetworkHistoryRecorder`, `DailyRecordStore`, `NetworkAnomalyDetector` and `NotificationService`, and computes the menu bar alert level; `StatusBarController` observes it to draw the menu bar text.
3.  **Rendering:** SwiftUI views observe the view model and update the UI.

## Building and Running

**Prerequisites:** macOS 14.0+ and Xcode 26 (Swift 6.2). No external tools are needed.

**Commands:**

*   **Build (Debug, does not launch the app):**
    ```bash
    ./build.sh
    ```

*   **Build (Release, universal, never launched):**
    ```bash
    ./build.sh release
    ```

*   **Open in Xcode:**
    ```bash
    open BandwidthECG.xcworkspace
    ```

*   **Run unit tests (fast, no app build; the log must say `Test run with N tests`, N > 0):**
    ```bash
    swift test --package-path BandwidthECGPackage
    ```

*   **Run unit tests through Xcode:**
    ```bash
    xcodebuild test -workspace BandwidthECG.xcworkspace \
                    -scheme BandwidthECG \
                    -destination 'platform=macOS,arch=arm64'
    ```

*   **Website (Node 22.23.4):**
    ```bash
    cd website && npm ci && npm run build && node scripts/check-i18n.mjs --dist
    ```

**Running the app:** Debug builds use bundle ID `com.bobo52310.BandwidthECG.debug` (their own sandbox container). Never launch a Release build or the real bundle ID `com.bobo52310.BandwidthECG`; `CFFIXED_USER_HOME` does not isolate it. See `AGENTS.md` ("Running the App Safely").

## Development Conventions

*   **Strings:** every user-facing string goes through `Utilities/L10n.swift` (Traditional Chinese `defaultValue`) and `BandwidthECG/Localizable.xcstrings` (zh-Hant, en, ja, ko); `L10nCatalogTests` enforces it. Code comments are in English.
*   **Testing:** Swift Testing (`import Testing`, `@Test`, `#expect`). Add or update a test for behaviour changes.
*   **Style:** standard Swift 6 and SwiftUI conventions, 4-space indentation, small focused types.
*   **Sandboxing:** the app is sandboxed (see `Config/BandwidthECG.entitlements`). The only outgoing request is the latency probe.
*   **Dependencies:** none today; any addition goes through `BandwidthECGPackage/Package.swift`.
*   **Commits:** Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, `ci:`). Never use `--no-verify` and never disable a failing test. See `CONTRIBUTING.md`.
