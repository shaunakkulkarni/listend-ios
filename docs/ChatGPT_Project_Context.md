# Listend Project Context for ChatGPT

Use this file as a handoff brief when planning the next steps for Listend. It summarizes the current repo, what the app already does, the main architectural decisions, and the most useful directions for future feature work.

## Short Product Description

Listend is an iOS music diary: "Letterboxd but music." Users log albums, rate them, write short reviews, add tags, and build a local taste profile called SoundPrint. The core product thesis is that explicit ratings, reviews, tags, and negative opinions are better recommendation signals than raw listening history alone.

The app is intentionally local-first. Logging should keep working even if MusicKit, Apple Foundation Models, previews, recommendations, or tag suggestions fail.

## Current Repository Snapshot

- Repo root: `listend-ios`
- Main project: `Listend/Listend.xcodeproj`
- Main app target: `Listend`
- Unit test target: `ListendTests`
- UI test target: `ListendUITests`
- Stack: SwiftUI, SwiftData, MusicKit integration points, optional Apple Foundation Models integration points, AVFoundation for preview playback
- Deployment target in Xcode project: iOS 26.4
- Scheme: `Listend`
- README is minimal. The richer context lives in `docs/Listend_MVP_PRD.md`, `docs/Listend_MVP_TechSpec.md`, and `docs/Listend_Academic_Report.md`.

At audit time, `docs/Listend_Academic_Report.md` and `docs/Listend_Academic_Report.docx` were untracked files in git. Treat them as local working-tree context unless they get committed.

## Product Goals From Existing Docs

The MVP goal is:

Search or select album -> log rating/review/tags -> view feed/profile -> generate taste signals -> explain taste -> recommend one album later.

MVP phases described in the docs:

1. Local logging foundation with SwiftData.
2. Album search with mock catalog first, MusicKit later.
3. Mock/rule-based SoundPrint sentiment and taste dimensions.
4. Persona generation.
5. Tonight's Pick, one recommendation at a time with receipts and feedback.

Key product rule:

Logging must never be blocked by AI, MusicKit, playback, or recommendation failures.

## What Is Already Implemented

The app is well past a bare shell. It already includes:

- A SwiftUI tab app with Home, Logs, Search, and Profile tabs.
- SwiftData local persistence for albums, logs, taste dimensions, evidence, persona, recommendations, recommendation receipts, and feedback.
- Search flow using an album catalog service.
- Album detail flow with artwork, metadata, preview button, and "Log this album."
- Add-log flow that can start from search or recently played albums.
- Log create/edit/delete.
- Star rating control with half-star support.
- Review text and comma-separated tags.
- Local and model-backed tag suggestions with validation.
- Home dashboard with stats, latest log preview, recently played section, SoundPrint module, and Tonight's Pick entry point.
- Logs tab with history list and empty state.
- Profile stats with total logs, average rating, top tags, SoundPrint persona, and SoundPrint profile link.
- SoundPrint profile with taste dimensions, weights, confidence, and evidence receipts.
- Tonight's Pick with local recommendation generation, explanation text, receipts, preview control, and feedback actions.
- MusicKit catalog, recently played, and preview service implementations behind protocols.
- Mock and fallback service implementations so simulator/UI tests can run without real integrations.
- Optional Foundation Models SoundPrint and tag suggestion providers behind validation and fallback wrappers.
- Broad unit tests and UI tests.

## Main App Structure

Important files:

- `Listend/Listend/ListendApp.swift`
  - Builds the SwiftData `ModelContainer`.
  - Registers all SwiftData model classes.
  - Chooses real, mock, or fallback service implementations based on launch arguments and simulator/device.
  - UI tests use mocks.
  - Simulator uses mock SoundPrint and mock tag suggestions.
  - Device builds can use MusicKit and Foundation Models behind fallbacks.

- `Listend/Listend/ContentView.swift`
  - Defines the four primary tabs: Home, Logs, Search, Profile.
  - Wraps each tab in a `NavigationStack`.

- `Listend/Listend/Models/`
  - SwiftData models and recommendation enums/constants.

- `Listend/Listend/Services/`
  - Protocols and implementations for catalog search, recently played albums, previews, tag suggestions, SoundPrint, and recommendations.

- `Listend/Listend/Views/`
  - Feature views grouped by Home, Logs, Search, AlbumDetail, LogEntry, Profile, Recommendation, and Shared components.

- `Listend/Listend/Persistence/`
  - Album cache upsert helper and preview data containers.

## SwiftData Models

`Album`

- Cached catalog item.
- Fields include UUID, optional Apple Music ID, title, artist, release year, genre, artwork URL, and cached date.

`LogEntry`

- User-authored album log.
- Fields include album relationship, rating, review text, raw comma-separated tags, sentiment score/confidence, logged date, updated date.
- Computed helpers:
  - `tags`
  - `isPositiveSignal`
  - `isNegativeSignal`
  - `canAnchorRecommendation`
- If stored sentiment is missing, it falls back to `MockSoundPrintProvider.baseScore(for:)`.

`TasteDimension`

- Aggregated SoundPrint dimension.
- Fields include name, label, weight, confidence, summary, updated date.

`TasteEvidence`

- Evidence receipt for a taste dimension.
- Stores dimension name, source log ID, snippet, type, strength, confidence, and whether it is positive evidence.

`SoundPrintPersona`

- Short generated taste summary.
- Stored with generation date and log count at generation.

`Recommendation`

- One active or historical pick.
- Fields include album relationship, score, confidence, status, explanation text, created date.

`RecommendationReceipt`

- Snapshot evidence for a recommendation.
- Stores source album title, artist, rating, snippet, and linked dimension.
- Important: this can survive source log deletion because it stores a human-readable snapshot.

`RecommendationFeedback`

- Stores user feedback for a recommendation: liked, dismissed, saved for later, listened.

## Service Architecture

The code uses protocols around external or risky dependencies:

- `AlbumCatalogServiceProtocol`
  - `MockAlbumCatalogService`
  - `MusicKitAlbumCatalogService`
  - `FallbackAlbumCatalogService`

- `RecentlyPlayedAlbumServiceProtocol`
  - `MockRecentlyPlayedAlbumService`
  - `MusicKitRecentlyPlayedAlbumService`

- `AlbumPreviewServiceProtocol`
  - `MockAlbumPreviewService`
  - `MusicKitAlbumPreviewService`
  - `FallbackAlbumPreviewService`

- `TagSuggestionProvider`
  - `MockTagSuggestionProvider`
  - `LocalTagSuggestionProvider`
  - `FoundationModelsTagSuggestionProvider`
  - `FallbackTagSuggestionProvider`

- `SoundPrintProvider`
  - `MockSoundPrintProvider`
  - `FoundationModelsSoundPrintProvider`
  - `FallbackSoundPrintProvider`

This structure is a strong design decision. Preserve it when adding new integrations.

## SoundPrint Pipeline

SoundPrint is the local taste-modeling layer.

Current flow after saving a log:

1. `LogEntryEditorView` saves the log locally first.
2. It dismisses the editor immediately.
3. `SoundPrintProfileRefreshCoordinator.processSavedLog(...)` runs async.
4. `LogSentimentUpdater` writes sentiment score/confidence.
5. `SoundPrintProfileBuilder` rebuilds taste dimensions and evidence.
6. If there are at least 5 logs, the builder refreshes the persona.

The important product behavior is that the user is not kept waiting for AI or profile generation before the log is saved.

## Mock SoundPrint Rules

Sentiment scoring:

- Rating >= 4.0 -> base score 0.7.
- Rating 3.0 to 3.9 -> base score 0.2.
- Rating < 3.0 -> base score -0.5.
- Positive keywords add 0.1 each.
- Negative keywords subtract 0.2 each.
- Score is clamped from -1.0 to 1.0.
- Confidence is 0.8 with review text and 0.6 without review text.

Taste extraction:

- Only non-negative/positive sentiment can produce positive taste evidence.
- Negative logs return no positive taste signals.
- Taste rules are keyword-based.
- Fixed dimensions:
  - mood
  - energy
  - productionStyle
  - vocalFocus
  - lyricFocus
  - experimentation
  - instrumentalRichness
  - genreOpenness
  - eraAffinity
  - replayability

Persona:

- Generated after at least 5 logs.
- Must be at least 80 characters.
- Must avoid generic banned phrases like "eclectic taste" and "wide range of genres."
- Must reference concrete inputs such as dimensions, tags, albums, artists, or review snippets.
- If generation fails, existing persona is preserved.
- If log count drops below 5, stale persona is removed.

## Foundation Models Integration

There are optional Foundation Models providers for SoundPrint and tag suggestions.

Important implementation notes:

- They are guarded with `#if canImport(FoundationModels)` and availability checks.
- They request compact JSON output.
- They decode JSON defensively, including extracting a JSON object from extra text.
- Validators reject malformed, empty, generic, or invented output.
- `FallbackSoundPrintProvider` uses the mock provider if the Foundation Models provider fails, except it propagates cancellation.
- `FallbackTagSuggestionProvider` uses a local provider fallback.

Future model work should extend validation instead of trusting generated output directly.

## MusicKit Integration

MusicKit exists in three areas:

- Catalog search and album details: `MusicKitAlbumCatalogService`
- Recently played albums: `MusicKitRecentlyPlayedAlbumService`
- Preview playback lookup: `MusicKitAlbumPreviewService`

Important implementation notes:

- Services request Music authorization.
- Metadata is mapped through small value structs before producing `AlbumSearchResult` or `AlbumPreview`.
- Fallback services return mock/local behavior when MusicKit fails.
- UI tests use mock services.

Potential risks:

- MusicKit behavior is only partly testable in simulator.
- Real-device authorization and entitlement behavior still needs hands-on validation.
- Preview availability depends on MusicKit catalog track metadata and preview asset URLs.

## Recommendation System

`LocalRecommendationService` implements Tonight's Pick.

Current algorithm:

1. Reuse any active recommendation if present.
2. Fetch logs, albums, evidence, and recommendation history.
3. Choose positive anchors:
   - Must have an album.
   - Must not be negative.
   - Must have rating >= 4.0.
4. Build candidate albums:
   - Static mock catalog by default.
   - Or live catalog queries via `CatalogRecommendationCandidateProvider`.
5. Exclude already logged albums.
6. Exclude dismissed recommendations while alternatives exist.
7. Score candidates.
8. Insert `Recommendation`.
9. Insert `RecommendationReceipt` snapshots.

Scoring:

- Base score: +0.20.
- Genre match with positive anchor: +0.30.
- Release decade match: +0.20.
- Tag/evidence overlap: +0.20.
- New artist compared with anchors: +0.10.
- Genre match with a negative log: -0.40.
- Recently recommended artist: -0.20.
- Score is clamped from 0.0 to 1.0.
- Confidence is derived from score and capped below 1.0.

Feedback:

- Like, dismiss, save for later, and listened all update recommendation status and persist `RecommendationFeedback`.
- Dismissed picks are skipped in future generation.

Current recommendation limitations:

- Similarity is simple and metadata-heavy.
- Candidate quality depends heavily on the catalog candidate provider.
- Taste dimensions only help if their names overlap with candidate text, which is weak for real-world recommendation quality.
- There is no offline evaluation harness yet.

## UI Flows

Home:

- Header with app identity, log count, average rating, add log button.
- Tonight's Pick module appears when there is an active recommendation or a positive anchor log.
- Recently Played section can load albums from MusicKit or mocks.
- SoundPrint summary module appears when persona exists.
- Latest Log preview links to log detail.

Logs:

- Empty state if no logs.
- List of all logs sorted newest first.
- Rows navigate to detail.

Search:

- Search by album, artist, or genre.
- Debounced by 350ms.
- Uses catalog service.
- Rows navigate to Album Detail.

Album Detail:

- Shows artwork, title, artist, metadata.
- Has album preview control.
- Shows "Already logged" if matching cached/logged album exists.
- Otherwise lets user log the album.

Add Log / Album Selection:

- Add Log from Home opens album selection.
- Album selection auto-loads recently played albums.
- It also supports search.
- Selecting an album caches/upserts it, then opens the editor with that album preselected.

Log Editor:

- Requires selected album and rating.
- Review is optional.
- Tags are optional comma-separated text.
- Suggested tag chips appear from local/model providers.
- Save writes local data first, dismisses, then kicks off async SoundPrint refresh.

Log Detail:

- Shows album, rating, dates, review, tags.
- Supports edit.
- Supports delete with confirmation.
- Delete refreshes SoundPrint after removing the log.

Profile:

- Shows total logs, average rating, top tags.
- Shows persona once unlocked.
- Shows SoundPrint profile link after at least 2 positive logs and dimensions exist.

SoundPrint Profile:

- Shows dimensions sorted by weight.
- Each dimension has summary, weight, confidence, and expandable evidence receipts.

Tonight's Pick:

- If no pick exists, user can generate one if they have a positive anchor.
- Active pick shows album, confidence, explanation, preview, receipts.
- Feedback clears active pick and stores feedback.

## Testing Status

Tests exist in:

- `Listend/ListendTests/ListendTests.swift`
- `Listend/ListendUITests/ListendUITests.swift`
- `Listend/ListendUITests/ListendUITestsLaunchTests.swift`

The unit test suite is broad. It covers:

- Mock sentiment polarity and clamping.
- Fallback behavior and cancellation behavior.
- Foundation Models validation.
- Log signal helpers.
- Star rating calculations.
- Sentiment fallback persistence.
- SoundPrint profile rebuild, stale data removal, and failure preservation.
- Persona generation and quality filters.
- Recommendation generation, scoring, active recommendation reuse, feedback, dismissed candidates, receipt durability.
- MusicKit metadata mapping.
- Album cache upsert behavior.
- Recently played mocks.
- Album selection cache behavior.
- Tag suggestion providers and validators.
- Preview mappers and fallback preview behavior.
- Catalog fallback behavior.
- Live catalog candidate generation logic.

The UI tests cover:

- Create, edit, delete log.
- Profile stats update.
- Persistence after relaunch.
- Home dashboard surfaces.
- Logs empty/history states.
- Latest log preview.
- Recently played album selection.
- Add-log album chooser.
- Search result to editor.
- Rating requirement.
- Suggested tag chip behavior.
- Immediate dismissal after local save.
- Tonight's Pick feedback.
- Preview unavailable state with mock service.

Suggested verification commands:

```sh
xcodebuild test -project Listend/Listend.xcodeproj -scheme Listend -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ListendTests
xcodebuild test -project Listend/Listend.xcodeproj -scheme Listend -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ListendUITests
```

If the iPhone 17 simulator is unavailable, list devices with:

```sh
xcrun simctl list devices available
```

## Current Product Strengths

- The core local logging loop is implemented.
- The app remains usable with mock services.
- External integrations are isolated behind protocols.
- The SoundPrint/recommendation evidence chain is auditable.
- Negative logs are treated carefully and do not become positive evidence.
- Generated model output is validated before use.
- UI tests cover the main diary workflow.
- Unit tests cover much of the novel logic.

## Current Product Gaps and Risks

- Recommendation quality is still heuristic and likely not strong enough for real user trust.
- The candidate pool is limited unless MusicKit search is available and working well.
- Taste dimensions are fixed and keyword-based; they may miss nuanced or user-specific taste.
- Sentiment does not handle sarcasm, negation, mixed reviews, or aspect-based opinions.
- There is no explicit recommendation evaluation harness.
- There is no onboarding or explanation of why logging matters.
- There are no social features, accounts, cloud sync, or cross-device persistence.
- Real-device MusicKit/Foundation Models behavior still needs validation.
- There is no mature design system beyond shared surfaces/components.
- No privacy/settings surface is visible yet.
- No import/export or backup path is implemented.

## Good Next Feature Directions

Consider these as planning candidates, not decisions:

1. Recommendation Quality Evaluation
   - Add seeded taste profiles and expected recommendation outcomes.
   - Score picks for relevance, novelty, and explanation quality.
   - This would make future recommendation changes safer.

2. Better Candidate Expansion
   - Use positive anchors to issue multiple MusicKit searches by genre, artist, tags, and similar metadata.
   - Deduplicate and rank richer candidates.
   - Keep mock fallback behavior.

3. Smarter SoundPrint Parsing
   - Add negation-aware sentiment and aspect-specific extraction.
   - Example: "great production but boring vocals" should not turn all mentioned attributes positive.

4. User-Controlled SoundPrint
   - Let users inspect, hide, correct, or pin taste dimensions.
   - This fits the evidence-backed philosophy and builds trust.

5. Recommendation Feedback Learning
   - Use feedback to penalize dismissed artists/genres/tags and boost liked/listened picks.
   - Store lightweight preference adjustments locally.

6. Onboarding and First-Run Seed Flow
   - Help users log their first 3 to 5 albums quickly.
   - Could offer favorites, recent Apple Music albums, or mock/sample albums in simulator.

7. Album Collections
   - Want to listen, favorites, disliked, replay shelf.
   - This would make recommendations and diary browsing more useful.

8. Profile and Diary Browsing
   - Filters by rating, tag, genre, year, artist, date.
   - Calendar or stats views.

9. Import/Export
   - Export logs as JSON/CSV.
   - Import seed logs for testing or migration.
   - Useful before cloud sync exists.

10. Privacy and Integration Settings
   - Show local-first data policy.
   - Manage Apple Music access.
   - Choose mock/local/model providers in debug builds.

## Design and Engineering Principles To Preserve

- Save logs locally before doing any async AI/service work.
- Keep external dependencies behind protocols.
- Preserve mock services for simulator and tests.
- Validate all model-generated structured output.
- Do not let negative logs create positive evidence.
- Persist explanation receipts as snapshots.
- Prefer deterministic behavior for MVP recommendation logic.
- Keep SwiftData models simple unless a feature requires more structure.
- Extend tests around any change to recommendation or SoundPrint behavior.

## Useful Planning Prompts For ChatGPT

Use one of these prompts with this context file:

1. "Given this project context, propose the next 3 product milestones for Listend, focusing on the fastest path to a compelling TestFlight beta."

2. "Design a recommendation quality evaluation harness for this codebase. Include data fixtures, metrics, acceptance criteria, and where the code should live."

3. "Plan a next-generation SoundPrint model that handles mixed reviews and negation while preserving the local-first fallback architecture."

4. "Design an onboarding flow that gets a new user to five meaningful album logs quickly without feeling like a survey."

5. "Review the current architecture and suggest the highest-leverage refactors before adding more features."

6. "Create an implementation plan for user-controllable SoundPrint dimensions, including data model changes, UI, tests, and migration risks."

7. "Design a privacy/settings screen for Listend that explains local data, MusicKit, and Foundation Models clearly."

## Likely First Technical Milestone

The highest-leverage next milestone is probably an evaluation and feedback loop for recommendations:

- Add deterministic seeded users/log histories.
- Generate recommendations for each seed profile.
- Assert expected exclusions and rough ranking behavior.
- Add feedback-influenced scoring.
- Add visible explanation quality checks.

Why this first: the app's central differentiator is "recommendations that understand what you liked and disliked." The current architecture supports this, but the recommendation algorithm is still simple. Improving it without an evaluation harness risks making behavior feel better in one case and worse elsewhere.

