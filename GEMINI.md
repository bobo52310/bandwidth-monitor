# Bandwidth ECG (網路峰值監控器)

## Project Overview

Bandwidth ECG is a modern macOS menu bar application designed to monitor real-time network speeds and track peak usage statistics. Its primary goal is to provide users with data-driven insights to help them decide whether to upgrade their internet plans.

**Key Technologies:**
- **Language:** Swift 6.0+
- **Framework:** SwiftUI
- **Platform:** macOS 14.0+ (Sonoma or later)
- **Architecture:** Xcode Workspace + Swift Package Manager (SPM)

**Core Features:**
- **Real-time Monitoring:** Displays upload/download speeds directly in the menu bar.
- **Charts:** Interactive history charts ranging from 1 minute to 24 hours.
- **Peak Tracking:** Records daily and all-time peak speeds.
- **Speed Test:** Integrated Speedtest CLI support with community leaderboards.
- **Anomaly Detection:** Detects and alerts on network drops or significant speed reductions.

## Architecture

The project follows a modular structure using an Xcode Workspace and a local Swift Package.

### Directory Structure

- **`BandwidthECG.xcworkspace`**: The main entry point for opening the project in Xcode.
- **`BandwidthECG/`**: The app shell containing the entry point (`BandwidthECGApp.swift`) and entitlements.
- **`BandwidthECGPackage/`**: The core feature code, structured as a Swift Package.
  - **`Sources/BandwidthECGFeature/`**: Contains all views, view models, services, and models.
  - **`Tests/BandwidthECGFeatureTests/`**: Contains unit tests.

### Key Components (`BandwidthECGPackage`)

| Component | Type | Description |
|-----------|------|-------------|
| **`NetworkMonitor`** | Service | Low-level network byte polling using `getifaddrs`. Polls every 1 second. |
| **`NetworkMonitorViewModel`** | ViewModel | Central state coordinator. Receives updates from `NetworkMonitor` and distributes data. |
| **`StatusBarController`** | View | Manages the menu bar item and the popover window. |
| **`PeakRecorder`** | Service | Tracks daily and all-time peak speeds. |
| **`NetworkHistoryRecorder`** | Service | Maintains time-series data for the history charts. |
| **`NetworkAnomalyDetector`** | Service | Detects unusual network patterns like drops or severe lags. |

### Data Flow

1.  **Polling:** `NetworkMonitor` polls system network interfaces every second.
2.  **Publishing:** Raw speed data is published to `NetworkMonitorViewModel`.
3.  **Distribution:** The ViewModel processes the data and updates:
    -   `PeakRecorder` (for statistics)
    -   `NetworkHistoryRecorder` (for charts)
    -   `NetworkAnomalyDetector` (for alerts)
    -   `StatusBarController` (for menu bar text)
4.  **Rendering:** SwiftUI views observe the ViewModel and update the UI.

## Building and Running

**Prerequisites:**
-   macOS 14.0+
-   Xcode 26+ (Swift 6.2)
-   Speedtest CLI (optional, for speed test features): `brew install speedtest-cli`

**Commands:**

*   **Build and Run (Debug):**
    ```bash
    ./build.sh
    ```

*   **Build and Run (Release):**
    ```bash
    ./build.sh Release
    ```

*   **Open in Xcode:**
    ```bash
    open BandwidthECG.xcworkspace
    ```

*   **Run Unit Tests:**
    ```bash
    xcodebuild test -workspace BandwidthECG.xcworkspace \
                    -scheme BandwidthECG \
                    -destination 'platform=macOS'
    ```

*   **Run UI Tests:**
    ```bash
    xcodebuild test -workspace BandwidthECG.xcworkspace \
                    -scheme BandwidthECG \
                    -destination 'platform=macOS' \
                    -only-testing:BandwidthECGUITests
    ```

## Development Conventions

*   **Language:** The application UI and code comments should be in **Traditional Chinese (Taiwan)**.
*   **Testing:** Use the Swift Testing framework (`@Test` macro).
*   **Style:** Follow standard Swift 6 and SwiftUI conventions.
*   **Sandboxing:** The app is sandboxed (see `BandwidthECG.entitlements`).
*   **Dependencies:** External dependencies should be managed via `Package.swift`.
