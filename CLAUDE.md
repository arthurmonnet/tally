# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tally is a native macOS menu bar app (Swift/SwiftUI) that tracks developer activity stats in real-time — keystrokes, clicks, app usage, screenshots, and system state. It persists data to SQLite and can push daily summaries to a remote endpoint.

- **Repo:** `github.com/arthurmonnet/Tally`
- **Version:** 0.1.0 (initial public release, 2026-03-15)
- **License:** See repo

## Build & Run

- **Open:** `Tally.xcworkspace` (not `.xcodeproj`) — required for SPM resolution
- **Build:** `xcodebuild -scheme Tally build` or Cmd+R in Xcode
- **Resolve packages:** `xcodebuild -resolvePackageDependencies -scheme Tally`
- **Target:** macOS 14.0+ (Sonoma), Swift 5
- **Bundle ID:** `com.arthurmonnet.tally`
- **Dependency:** GRDB.swift 7.0+ (SQLite, via SPM)
- **Optional framework:** FoundationModels (macOS 26+, for AI-generated punchlines)
- **No test suite exists yet**

## Release & Distribution

### Local release
```bash
scripts/release.sh
```
Requires `scripts/release-config.sh` (gitignored) with `TEAM_ID`, `APPLE_ID`, `APP_PASSWORD`.
Pipeline: clean → archive → export → DMG → notarize → staple → verify.

### CI/CD (GitHub Actions)
Trigger: push a tag matching `v*` (e.g., `git tag v0.1.0 && git push --tags`).
Workflow: `.github/workflows/release.yml` — archives, signs with Developer ID, creates DMG, notarizes, staples, uploads to GitHub Releases.

Required GitHub secrets:
- `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD`
- `APPLE_TEAM_ID`, `APPLE_ID`, `APPLE_APP_PASSWORD`

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
RemotePush (JSON POST to configured endpoint)
```

### Key directories

```
Tally/
├── App/              SwiftUI views and app entry point
│   ├── Components/   Reusable UI: SparklineChart, ChipSelector, WindowChart, etc.
│   └── Onboarding/   5-step setup wizard (Welcome → Privacy → Accessibility → Screenshots → Ready)
├── Collectors/       Four independent data collectors, each owning one event source
│   ├── InputCollector    CGEventTap — keystrokes, clicks, scroll, copy/paste, Cmd+Z
│   ├── AppCollector      NSWorkspace — app switches, foreground app tracking
│   ├── FileCollector     FSEvents — screenshot detection in configured folder
│   └── SystemCollector   sysctl, dark mode, window count, sleep/wake detection
├── Engine/           Core logic
│   ├── Database          GRDB migrations + queries, 5-minute bucket UPSERT
│   ├── LiveStats         @Observable in-memory shadow of DB totals (instant UI)
│   ├── StatsEngine       Daily/weekly aggregation
│   ├── AchievementEngine JSON-driven unlock system (achievements.json)
│   └── PunchlineGenerator  On-device AI commentary via FoundationModels (macOS 26+)
├── Models/           Immutable value types: StatEvent, DailySummary, UserConfig, Achievement, AppFilter
├── Server/           Remote push infrastructure
│   ├── RemotePush        Payload builder (v2 JSON, 20+ fields, base64 app icons)
│   ├── PushScheduler     Interval-based + on-quit + on-wake scheduling
│   └── KeychainHelper    Secure token storage
├── Resources/        achievements.json (8 achievements with stat thresholds)
└── Assets.xcassets/  App icons (transparent), menu bar icon, accent color
```

### Important patterns

- **LiveStats** shadows DB totals in memory so the menu bar UI never queries SQLite for current values
- **InputCollector** requires Accessibility permission (CGEventTap) — onboarding gates this
- **StatEvent** uses bucket-based UPSERT: `INSERT ... ON CONFLICT(bucket, statKey) DO UPDATE`
- **AppState** (`TallyApp.swift`) is the root @Observable — owns all collectors, engines, and schedulers
- **Activation policy** switches: `.regular` during onboarding (dock icon visible), `.accessory` after (menu bar only)
- **Achievements** are defined in `Resources/achievements.json` with stat-threshold conditions (8 achievements)
- **PunchlineGenerator** uses Apple Intelligence on-device model (macOS 26+) with 1h cooldown and 20% change threshold
- **RemotePush** payload is version 2 JSON with 20+ fields, documented in `docs/api.html`
- **Structured logging** via `os.Logger` with subsystem `arthurmonnet.Tally`

## Remote Push

The app can push daily stats to any HTTPS endpoint with Bearer token auth. See `docs/api.html` for the full payload schema and integration guide.

## Development Workflow

### Branching
- `main` — stable branch, all releases tagged here
- Feature branches as needed (e.g., `popover-round2-polish`)

### Commit messages
Follow conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`, `ci:`

### Code style
- **Immutable models** — all Models/ types are value types, never mutate in place
- **Small focused files** — average ~140 LOC, max ~760 LOC across 36 files
- **Feature-based organization** — grouped by domain (Collectors, Engine, Models, Server, App)
- **@MainActor + @Observable** — used for all stateful classes (AppState, LiveStats, PunchlineGenerator)

### Before committing
- [ ] Build succeeds: `xcodebuild -scheme Tally build`
- [ ] No hardcoded secrets
- [ ] Errors handled with structured logging
- [ ] New models are immutable value types

### Testing
No test suite exists yet. When adding tests:
- Target 80%+ coverage
- Use TDD (red → green → refactor)
- Test collectors, engine logic, and models independently

### Secrets (never commit)
- `scripts/release-config.sh` — local release credentials
- Any `.env` files
- API keys, tokens, passwords
