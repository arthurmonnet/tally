# Changelog

All notable changes to Tally are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [0.2.3] - 2026-03-25

### Fixed
- The rightmost sparkline column is now always reserved for the current day after midnight rollovers, even when the menu stays open across days

## [0.2.2] - 2026-03-24

### Fixed
- Keystroke and other stat sparklines now keep today's bar in sync with the live total instead of freezing on the first loaded history value

## [0.1.4] - 2026-03-21

### Fixed
- LiveStats counters now reset at midnight — previously counters accumulated across days until app restart

## [0.1.2] - 2026-03-17

### Fixed
- Resolved Swift concurrency warnings around quit-time push scheduling
- Removed app icon catalog warning caused by an unassigned icon file
- Removed Xcode warning about Info.plist being included in Copy Bundle Resources

## [0.1.0] - 2026-03-15

Initial public release.

### Added
- macOS menu bar app tracking keystrokes, clicks, app usage, screenshots, and system state
- SQLite persistence via GRDB with 5-minute bucket UPSERT
- LiveStats for real-time in-memory counters and instant UI updates
- 5-step onboarding wizard with Accessibility permission gate
- Achievement engine with JSON-driven unlocks
- Remote push of daily summaries to any HTTPS endpoint (Bearer token auth)
- App icons sent as base64 PNG in push payload
- Apple Intelligence punchline via on-device FoundationModels (macOS 26+)
- Intraday window chart, sparkline history, app filter
- Structured logging via os.Logger
- Release script for automated builds and notarization
