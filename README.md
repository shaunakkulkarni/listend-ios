# Listend

Listend is an iOS music diary for logging, rating, and reviewing albums. Think Letterboxd for music: a local-first album journal that turns your own ratings, reviews, and tags into a taste profile called **SoundPrint**.

The app is built in SwiftUI with SwiftData persistence. It can run in the simulator with mock services, while device builds can use MusicKit and Apple Foundation Models behind fallback wrappers.

## What It Does

- Log albums with a star rating, review, tags, and track highlights.
- Browse recent logs from Home and the Logs tab.
- Search for albums through MusicKit with mock/fallback catalog support.
- Load recently played albums when MusicKit is available.
- Build a SoundPrint profile from stored logs, including sentiment, taste dimensions, evidence, and persona text.
- Generate a Today's Pick recommendation with receipts and feedback actions.
- Fall back to mock/local services when Apple services are unavailable.

## Project Layout

```text
Listend/
  Listend.xcodeproj
  Listend/
    Models/              SwiftData models
    Persistence/         local caches and store helpers
    Services/            MusicKit, SoundPrint, recommendations, previews, tags
    Utilities/           shared text normalization helpers
    Views/               SwiftUI screens and shared UI components
  ListendTests/          Swift Testing unit tests
  ListendUITests/        XCTest UI flows
docs/                    product, technical, and design notes
screenshots/             UI audit artifacts
```

## Requirements

- macOS with Xcode capable of building iOS 26.4 targets.
- iOS Simulator for local development.
- Apple developer signing configured for device builds.
- Apple Music authorization for live catalog, recently played, previews, and recommendation freshness.

The simulator path is intentionally useful without MusicKit or Foundation Models: simulator and UI-test runs use mock/fallback services where needed.

## Getting Started

Open the project:

```bash
open Listend/Listend.xcodeproj
```

Build from the command line:

```bash
xcodebuild build \
  -project Listend/Listend.xcodeproj \
  -scheme Listend \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Run unit tests:

```bash
xcodebuild test \
  -project Listend/Listend.xcodeproj \
  -scheme Listend \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ListendTests
```

Run UI tests:

```bash
xcodebuild test \
  -project Listend/Listend.xcodeproj \
  -scheme Listend \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ListendUITests
```

## Runtime Modes

Listend chooses services at app startup:

- UI tests use mock catalog, recently played, SoundPrint, tag suggestion, journal assist, and preview services.
- Simulator builds use mock SoundPrint and mock tag suggestions, with fallbacks around MusicKit-backed catalog and previews.
- Device builds can use MusicKit and Foundation Models, with local/mock fallbacks so logging remains usable when those integrations fail.

This keeps the core loop available even when Apple Music access is denied or AI features are unavailable.

## Data Model

The local SwiftData schema includes:

- `Album`
- `LogEntry`
- `TasteDimension`
- `TasteEvidence`
- `SoundPrintPersona`
- `Recommendation`
- `RecommendationReceipt`
- `RecommendationFeedback`
- `RecentlyPlayedAlbumSnapshot`
- `AppleMusicRecentPlaySnapshot`

Migration caution: avoid adding non-optional fields to existing SwiftData models unless there is a migration plan. See `docs/Today_Pick_Apple_Music_Handoff.md` for a recent example.

## Useful Docs

- `docs/Listend_MVP_PRD.md` - product requirements and MVP scope
- `docs/Listend_MVP_TechSpec.md` - architecture and implementation plan
- `docs/Listend_First_Class_iOS_Design_System.md` - current iOS design direction
- `docs/Listend_Midnight_Vinyl_Design_System.md` - visual language notes
- `docs/Today_Pick_Apple_Music_Handoff.md` - Today's Pick and Apple Music freshness handoff

## Current Status

Listend is an MVP-stage iOS app with local logging, album search, SoundPrint, Today's Pick, Apple Music integration points, and test coverage for core flows. The app should remain useful without live Apple services; integrations are layered behind protocols and fallbacks.
