# Tally

A macOS menu bar app that quietly tracks your developer activity — keystrokes, clicks, app usage, screenshots, and system stats — then surfaces it all in a compact popover with sparkline charts.

## What it tracks

| Category | Metrics |
|----------|---------|
| **Input** | Keystrokes, left/right clicks, scroll distance, mouse travel, copy/paste, undo (Cmd+Z), launcher opens |
| **Apps** | Active app, time per app, app switches |
| **Files** | Screenshots (auto-detected via folder watching + pattern matching) |
| **System** | Window count (current + peak + intraday timeline), dark/light mode time, peak RAM, sleep/wake cycles, late-night activity |

Everything is stored locally in SQLite. Nothing leaves your machine unless you configure remote push.

## Features

- **Menu bar popover** — today's stats at a glance with expandable 7-day sparkline history
- **Intraday window chart** — window count over time with current and peak indicators
- **Achievements** — JSON-driven milestones triggered by stat thresholds (e.g. keystroke counts, scroll distance, late-night sessions)
- **Apple Intelligence punchline** — on macOS 26+, generates a witty one-liner about your day using on-device FoundationModels
- **Remote push** — optionally send daily summaries to any HTTPS endpoint with Bearer token auth (see [tally-endpoint](https://github.com/arthurmonnet/tally-endpoint) for a ready-to-deploy receiver)
- **Privacy-first** — counts events only, never records content, keystrokes, or screen captures

## Requirements

- macOS 14+ (Sonoma or later)
- **Accessibility permission** — required for keyboard and mouse event monitoring via CGEventTap

## Getting started

1. Open `Tally.xcodeproj` in Xcode
2. Build and run (Cmd+R)
3. Complete the onboarding wizard (welcome, privacy, accessibility, screenshots, ready)
4. Tally moves to the menu bar and starts tracking

## Architecture

```
Tally/
├── App/              # SwiftUI views, menu bar popover, settings
│   ├── Components/   # SparklineChart, StatRow, WindowChart, AppBar, SectionHeader, etc.
│   └── Onboarding/   # 5-step setup wizard (welcome → privacy → accessibility → screenshots → ready)
├── Collectors/       # Data collection: InputCollector (CGEventTap), AppCollector (NSWorkspace),
│                     #   FileCollector (FSEvents), SystemCollector (sysctl, dark mode, windows)
├── Engine/           # LiveStats (in-memory counters), Database (GRDB/SQLite),
│                     #   StatsEngine (aggregation), AchievementEngine, PunchlineGenerator
├── Models/           # UserConfig, StatEvent, DailySummary, Achievement, AppFilter, PushFrequency
├── Server/           # RemotePush (payload builder), PushScheduler, KeychainHelper
└── Resources/        # achievements.json
```

**Data flow:** Collectors gather raw events → LiveStats holds in-memory counters for instant UI → Database persists to SQLite in 5-minute buckets → StatsEngine compiles daily/weekly aggregates → RemotePush optionally sends summaries to an external endpoint.

## Tech stack

- Swift 5, SwiftUI
- [GRDB.swift](https://github.com/groue/GRDB.swift) 7.10 (SQLite)
- CGEventTap, FSEvents, NSWorkspace notifications
- FoundationModels (Apple Intelligence, macOS 26+, optional)

## Data storage

All data lives in `~/Library/Application Support/Tally/`:
- `tally.db` — SQLite database (5-minute bucket UPSERT)
- `config.json` — user preferences and tool selections

The app does not use a sandbox — this is required for CGEventTap to function at the system level.

## License

[MIT](LICENSE)
