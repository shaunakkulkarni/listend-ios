# Today’s Pick Apple Music Freshness Handoff

Date: 2026-05-28  
Repo: `/Users/shaunakkulkarni/Developer/listend-ios`  
Branch at handoff: `main`  
Working tree before this document: clean

## Current State

The Today’s Pick Apple Music freshness rework has been implemented and committed.

Relevant commits:

- `58a734b Refine Journal Assist prompt and validation flow`
  - This commit message is misleading. It contains the large Today’s Pick / recently played / Apple Music freshness implementation.
- `49adc53 Make recommendation source fields optional`
  - Follow-up fix for device launch freeze caused by SwiftData migration risk.

The feature is still album-first. No `Song` model was introduced.

## Implemented Behavior

- User-facing “Tonight’s Pick” was renamed to “Today’s Pick”.
- `TodayPickView` is now the recommendation screen.
- Apple Music personal recommendations are the primary candidate source when available.
- Today’s Pick filters out:
  - albums already logged in Listend,
  - dismissed recommendation albums,
  - current Apple Music recently played albums,
  - albums found in the user’s Apple Music library,
  - albums observed in Listend’s rolling recent-play snapshot within the last 90 days.
- If Apple Music recommendation/freshness checks fail, the app falls back to the old Listend recommendation path and shows:
  - `Apple Music freshness was unavailable, so this pick is based on your Listend logs.`

## Main Files

- `Listend/Listend/Views/Recommendation/TodayPickView.swift`
  - Renamed screen and freshness disclosure UI.
- `Listend/Listend/Services/Recommendation/LocalRecommendationService.swift`
  - Orchestrates Apple Music candidate lookup, freshness filtering, scoring, fallback, receipts, and metadata.
- `Listend/Listend/Services/Recommendation/AppleMusicRecommendationService.swift`
  - MusicKit-backed service for personal recommendations, recent plays, and library checks.
- `Listend/Listend/Models/Recommendation.swift`
  - Added optional `source` and `freshnessStatus`.
  - These are intentionally optional for SwiftData migration compatibility with existing device installs.
- `Listend/Listend/Models/AppleMusicRecentPlaySnapshot.swift`
  - Rolling 90-day freshness snapshot model.
- `Listend/Listend/Persistence/AppleMusicRecentPlaySnapshotStore.swift`
  - Records and reads recent-play freshness snapshots.
- `Listend/Listend/Models/RecentlyPlayedAlbumSnapshot.swift`
  - Separate compact recently played UI cache model.
- `Listend/Listend/Persistence/RecentlyPlayedAlbumCache.swift`
  - Persists recently played albums for Home / album selection.
- `Listend/Listend/Views/Home/HomeView.swift`
  - Shows compact recent albums list and Today’s Pick entry point.

## Important Migration Note

The app froze on physical-device launch after the first implementation. The likely root cause was adding non-optional SwiftData fields to existing `Recommendation` rows.

Fixed in `49adc53` by changing:

```swift
var source: String?
var freshnessStatus: String?
```

New recommendations still set these fields explicitly. Existing recommendations may have `nil`; UI treats anything not equal to `appleFreshnessChecked` as fallback/unavailable.

When testing on device, install over the existing app first. Do not delete the app unless it still freezes and data preservation is no longer important.

## Verification Already Run

Passed:

```bash
xcodebuild test -project Listend/Listend.xcodeproj -scheme Listend -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ListendTests
```

Passed focused UI tests:

```bash
xcodebuild test -project Listend/Listend.xcodeproj -scheme Listend -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ListendUITests/ListendUITests/testTodayPickFeedbackClearsActiveRecommendation -only-testing:ListendUITests/ListendUITests/testTodayPickShowsPreviewUnavailableWithMockService
```

Passed after launch-freeze fix:

```bash
xcodebuild test -project Listend/Listend.xcodeproj -scheme Listend -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ListendTests/ListendTests/appleMusicUnavailableFallsBackToListendRecommendationWithDisclosureMetadata -only-testing:ListendTests/ListendTests/appleMusicFreshnessFilterBlocksRecentLibraryLoggedAndRollingSnapshotAlbums
```

## Next Checks

1. Build and run on a physical device over the existing install.
2. Confirm launch no longer freezes.
3. If launch still freezes, capture the device console from Xcode immediately on launch and inspect for SwiftData/CoreData migration errors.
4. Confirm Apple Music authorization prompt and permission state.
5. Generate Today’s Pick on device with Apple Music available.
6. Confirm generated pick displays:
   - `Checked against Apple Music library and recent plays.`
7. Confirm fallback disclosure appears if Apple Music access is denied or unavailable.

## Known Risks / Follow-ups

- Live Apple Music behavior has not been verified on a physical device yet.
- The MusicKit implementation compiles, but Apple’s personal recommendation response shape should be validated with real user data.
- The “last 3 months” rule is best-effort, not a complete Apple listening-history audit. It depends on current recent-play data plus Listend’s rolling snapshots over time.
- The commit `58a734b` has a misleading message. If preparing a PR, clarify in the PR body that it contains the Today’s Pick rework.
- If app launch freezes again after `49adc53`, likely next suspects are:
  - adding `AppleMusicRecentPlaySnapshot` / `RecentlyPlayedAlbumSnapshot` to the SwiftData schema without an explicit migration plan,
  - a persistent store model mismatch,
  - a device-only MusicKit authorization hang, though no Apple Music calls should run during app init.
