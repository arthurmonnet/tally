# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tally is a native macOS menu bar app (Swift/SwiftUI) that tracks developer activity stats in real-time — keystrokes, clicks, app usage, screenshots, and system state. It persists data to SQLite and can push daily summaries to a remote endpoint.

## Build & Run

- **Open:** `Tally.xcworkspace` (not `.xcodeproj`) — SPM dependency: GRDB 7.10
- **Build:** `xcodebuild -scheme Tally build` or Cmd+R in Xcode
- **Target:** macOS 14.0+, Swift 5, bundle ID `arthurmonnet.Tally`
- **No test suite exists yet**

## Architecture

The app follows a **collect → aggregate → display → push** pipeline:

```
Collectors (CGEventTap, FSEvents, NSWorkspace, sysctl)
    ↓ real-time events
LiveStats (@Observable in-memory counters — instant UI)
    ↓ periodic flush (10s)
Database (SQLite/GRDB — 5-minute buckets via UPSERT)
    ↓ daily compilation
StatsEngine (aggregate daily/weekly stats)
    ↓ scheduled push
RemotePush (JSON POST to portfolio endpoint)
```

### Key directories

- `Collectors/` — Four independent data collectors, each owning one event source
- `Engine/` — Database (GRDB migrations + queries), LiveStats (in-memory shadow), StatsEngine (aggregation), AchievementEngine (JSON-driven unlocks)
- `Models/` — Immutable data types: StatEvent, DailySummary, UserConfig, Achievement, AppFilter
- `Server/` — RemotePush payload builder, PushScheduler (interval-based + on-quit + on-wake), KeychainHelper
- `App/` — SwiftUI views: MenuBarView (popover), Components/ (SparklineChart, ChipSelector, etc.), Onboarding/ (6-step wizard requiring Accessibility permission)

### Important patterns

- **LiveStats** shadows DB totals in memory so the menu bar UI never queries SQLite for current values
- **InputCollector** requires Accessibility permission (CGEventTap) — onboarding gates this
- **StatEvent** uses bucket-based UPSERT: `INSERT ... ON CONFLICT(bucket, statKey) DO UPDATE`
- **Achievements** are defined in `Resources/achievements.json` with stat-threshold conditions
- **RemotePush** payload is version 2 JSON with 20+ fields, documented in `docs/api.html`

## Remote push

The app can push daily stats to any HTTPS endpoint. See `docs/api.html` for the full payload schema and integration guide.
