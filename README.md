# Tally

A macOS menu bar app that quietly tracks your developer activity — keystrokes, clicks, git commits, app usage, and more — then surfaces it all in a compact popover with sparkline charts.

## What it tracks

| Category | Metrics |
|----------|---------|
| **Input** | Keystrokes, mouse clicks, scroll distance, mouse travel, copy/paste, undo |
| **Apps** | Active app, time per app, app switches |
| **Files** | File creation/deletion, screenshot detection |
| **Git** | Commits, stashes across configured repos |
| **System** | Window count, RAM usage, dark/light mode time |

Everything is stored locally in SQLite. Nothing leaves your machine unless you configure remote push.

## Features

- **Menu bar popover** — today's stats at a glance with expandable 7-day sparklines
- **Achievements** — unlock milestones like commit streaks and keystroke counts
- **Local dashboard** — browse detailed analytics at `localhost:7777`
- **Remote push** — optionally send daily summaries to an external endpoint (Bearer token auth)
- **Privacy-first** — no keylogging, no screen recording, no content capture

## Requirements

- macOS 12+ (Monterey or later)
- **Accessibility permission** — required for input event monitoring via CGEventTap

## Getting started

1. Open `Tally.xcodeproj` in Xcode
2. Build and run (Cmd+R)
3. Complete the onboarding wizard — grant Accessibility, pick your tools and git repos
4. Tally moves to the menu bar and starts tracking

## Architecture

```
Tally/
├── App/              # SwiftUI views, menu bar popover, onboarding
│   ├── Components/   # SparklineChart, ChipSelector, StatRow, etc.
│   └── Onboarding/   # 5-step setup wizard
├── Collectors/       # Data collection (CGEventTap, FSEvents, git, system)
├── Engine/           # LiveStats (in-memory), Database (GRDB/SQLite), Achievements
├── Server/           # Embedded HTTP server, remote push, Keychain
├── Models/           # UserConfig, StatEvent, DailySummary, Achievement
└── Resources/        # Achievement definitions (JSON)
```

**Data flow:** Collectors gather raw events → LiveStats holds in-memory counters for instant UI → Database persists to SQLite in 5-minute buckets → MenuBarView refreshes every 5 seconds.

## Tech stack

- Swift 6, SwiftUI
- GRDB (SQLite ORM)
- Swifter (embedded HTTP server)
- CGEventTap, FSEvents, NSWorkspace notifications

## Data storage

All data lives in `~/Library/Application Support/Tally/`:
- `tally.db` — SQLite database
- `config.json` — user preferences and tool selections

## License

All rights reserved.
