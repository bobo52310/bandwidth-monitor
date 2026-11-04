# Bandwidth ECG · Promo Intro v2 · Design Baseline

> Visual system inherited unchanged from `docs/design/promo-intro-zh-tw/DESIGN.md`
> (itself locked to BUSINESS_STRATEGY.md 2.4 + website/src/styles/global.css).
> Copy, numbers and narrative are new. Do not carry over anything from the 2026-05 film's copy.

## Positioning

Bandwidth ECG is **not** a network speed display — it is a **network plan decision-maker**.
Every frame must defend that category.

The one feeling to take away: 測速只看到一瞬間，這個 app 陪你看整個月。

## Brand Voice

Clinical · Calm · Precise · Quietly confident · Human-scale.
Like a Things 3 with a stethoscope. Hospital-grade indie Mac app, not a gamer dashboard.

## Color System

| Token | Hex | Use |
|---|---|---|
| `--paper` | `#FFFFFF` | Scene background |
| `--paper-dim` | `#F9FAFB` | Card surface, inset panels |
| `--grid-fine` | `#F3F4F6` | ECG paper 5mm grid |
| `--grid-bold` | `#E5E7EB` | ECG paper 25mm grid + thin separators |
| `--ink` | `#0F172A` | Primary text |
| `--ink-2` | `#475569` | Secondary text |
| `--ink-3` | `#94A3B8` | Non-text only here (ticks, tag border): fails AA as text on white |
| `--signal` | `#3B82F6` | Signal-blue accent, normal-state highlights |
| `--signal-dark` | `#2563EB` | Eyebrows, links, CTA primary |
| `--amber` | `#F59E0B` | "Approaching limit" warning (unused in this film) |
| `--red` | `#EF4444` | Peak event, live indicator |
| `--green` | `#10B981` | "Stable" / verdict positive state (unused in this film) |

## Type

- **Display / Sans**: Inter (with Noto Sans TC fallback for CJK)
- **Mono**: JetBrains Mono / SF Mono
- Mono numbers everywhere a measurement appears.

## Signature Visual

**ECG paper grid** (5mm fine + 25mm bold lines) on white, with a **PQRST waveform**. When traffic hits a peak, that segment turns `--red` for 0.5s, then returns to `--ink`.

## Storyboard (32s · 1920×1080 · 30fps)

| # | Time | Picture | Copy |
|---|---|---|---|
| 1 Hook | 0–5.5s | Blue signal strip shrinks to one dot on a month-long timeline | 你上次測速，量了 30 秒。→ 一個月有 2,592,000 秒。 |
| 2 Twist | 5.5–11s | Menu bar slides in; heartbeat line leaves the reading; wordmark | 所以它住進選單列，每秒聽一次。 |
| 3 Mechanic | 11–19s | Wave scrolls under the reading; one spike, red 0.5s, marker stays | 每天的尖峰，都留下時間和數字。 |
| 4 Range | 19–26s | 30 daily peaks against the plan line, gap arrow, verdict stamp | 30 天後，不用再憑感覺。 |
| 5 Heart | 26–32s | Same dot, same timeline, now lit end to end | 測速看一瞬間。它陪你看整個月。 |

Scene 1 and Scene 5 share the timeline geometry on purpose (dot at day 12, `TL_Y` 740). Keep them in sync.

## Honesty Rules (binding for every edit)

The previous film claimed things that were not true. This one may only say what the code or the release status supports.

**Do not say or imply:**
- anything about license, source availability, version numbers or OS version requirements
- how to obtain the app, or what it costs; no currency amounts and no savings claims
- "report from real usage" framing; every chart here is a demonstration
- that the app works without a network: it measures latency every 30 seconds (`Services/LatencyMonitor.swift:61`)
- anything about remote storage or moving data between devices
- empty adjectives about speed, ease or capability, in either language

**Verified claims in this film:**
- 每秒聽一次 → 1.0s timer, `Services/NetworkMonitor.swift:27`
- 資料只留在你的 Mac → local persistence only
- 測速約 30 秒 → general duration of a speed test, approved copy
- 2,592,000 秒 → 30 × 86,400

**Status line** is fixed: `即將推出 · bandwidth-ecg.bobochen.dev`.

**Demo numbers** in Scenes 3 and 4 must carry a visible 「示意數據」 tag. Scene 1 numbers do not need one.

## Demo Data → Verdict

The stamp must be what the app itself would print for these inputs. Change one and re-derive the other.

| Input | Value | On screen |
|---|---|---|
| `daysMonitored` | 30 | 30 bars |
| `planDownloadMbps` | 1000 | 你的方案 1000 Mbps |
| `peakDownloadMbps` | 284.6 | 最高 284.6 Mbps, Scene 3 spike |
| `planUploadMbps` | 600 | not shown |
| `peakUploadMbps` | 96.2 | not shown |
| `peakApproachCount` | 0 | not shown; no sample reaches 80% of plan (`PeakApproachTracker.swift:10`) |

`downloadPlanUtilization` = 28.46 → `%.0f%%` prints 28% (`MonthlyReportView.swift` `utilizationBar`).
`uploadPlanUtilization` = 16.03.

`MonthlySummary.recommendation` (`Models/MonthlySummary.swift:133-144`):
days ≥ 7, approach count ≤ 10, download ≤ 90, then download < 30 and upload < 30 and approach == 0 → `.considerDowngrade`.
Display string `可考慮降級方案` (`Utilities/L10n.swift:328`). Stamp color is `--signal-dark`, matching `.blue` for that case (`Views/MonthlyReportView.swift:189`).

The menu bar reading mirrors `menuBarText` (`ViewModels/NetworkMonitorViewModel.swift:172`): `↓ 182.4 ↑ 14.8 Mbps`, one new value per second. It stays `--ink` through the spike: 284.6 is 28% of plan, so no limit warning would apply.

Marker time uses `DateFormatter.timeStyle = .short` → `下午9:47` (`NetworkMonitorViewModel.swift:22`).

## Anti-patterns (do not do)

- No 4-panel feature grid
- No gamified gauges
- No remote-storage iconography (this app keeps everything on the Mac)
- No claim of "our servers"
- No motion that violates `prefers-reduced-motion` spirit (max 1 peak/scene, no infinite spinning)
- No emoji, no AI-generated imagery: everything is hand-built SVG/CSS

## Privacy line

If a frame mentions storage, the line is 「資料只留在你的 Mac。」
