# Bandwidth ECG · Promo Intro · Design Baseline

> Locked to BUSINESS_STRATEGY.md 2.4 (Brand Voice) + website/src/styles/global.css.
> Any visual outside these rules requires explicit override.

## Positioning

Bandwidth ECG is **not** a network speed display — it is a **network plan decision-maker**.
Every frame must defend that category.

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
| `--ink-3` | `#94A3B8` | Mono labels, session strip |
| `--signal` | `#3B82F6` | Signal-blue accent, normal-state highlights |
| `--signal-dark` | `#2563EB` | Eyebrows, links, CTA primary |
| `--amber` | `#F59E0B` | "Approaching limit" warning |
| `--red` | `#EF4444` | Peak event, live indicator |
| `--green` | `#10B981` | "Stable" / verdict positive state |

## Type

- **Display / Sans**: Inter (with Noto Sans TC fallback for CJK)
- **Mono**: JetBrains Mono / SF Mono
- Mono numbers everywhere a measurement appears.

## Signature Visual

**ECG paper grid** (5mm fine + 25mm bold lines) on white, with a **PQRST waveform** tracing left → right. When traffic hits a peak, that segment turns `--red` for 0.5s, then returns to `--ink`.

## Narrative Arc (28s)

1. **Hook · 0–4.5s** — The bill says 1 Gbps. The ECG strip says 18%. The gap.
2. **Twist · 4.5–9s** — Bandwidth ECG enters as the listener — quiet, clinical.
3. **Mechanic · 9–16s** — Menu-bar close-up: live numbers + waveform with a peak that turns red.
4. **Range · 15.5–23s** — 30-day histogram → verdict card ("Downgrade to 300 Mbps · save $480/yr").
5. **Heart · 22.5–28s** — Wordmark + "Stop overpaying your ISP." + 3 chips (100% local · MIT · macOS 14+).

## Anti-patterns (do not do)

- No "fast / easy / simple / powerful" copy
- No 4-panel feature grid
- No gamified gauges
- No cloud icons (this app is 100% local)
- No claim of "our servers" / "our cloud"
- No motion that violates `prefers-reduced-motion` spirit (max 1 peak/scene, no infinite spinning)

## Privacy line

If a frame mentions storage, the line is "Stays on your Mac. Nowhere else."
Never "synced", "cloud", "uploaded".
