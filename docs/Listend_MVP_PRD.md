# Listend — MVP Product Requirements Document

**Author:** Shaunak Kulkarni  
**Product:** Listend  
**AI Layer:** SoundPrint  
**Platform:** iOS  
**Version:** MVP 0.1–0.5  
**Status:** Codex-ready draft  

---

## 1. Product Summary

Listend is an iOS music diary for logging, rating, and reviewing albums. Over time, the app uses a local AI-inspired taste layer called **SoundPrint** to turn those logs into a structured taste profile, a short personality-style taste summary, and eventually one-album-at-a-time recommendations with receipts.

The full vision is “Letterboxd for music, but with recommendations that actually understand what you liked and disliked.”  

For the MVP implementation, the first priority is not the AI. The first priority is proving the core loop:

> Search or select album → log rating/review/tags → view feed/profile → generate taste signals → explain taste → recommend later

The app must remain useful even before real MusicKit and real Apple Foundation Models are integrated.

---

## 2. MVP Philosophy

The MVP should be built in small, compile-safe phases using Codex + Xcode + Simulator.

Key principle:

> Logging must never be blocked by AI, MusicKit, playback, or recommendation failures.

The MVP should support mock services first, then real integrations later.

---

## 3. Problem Statement

Music recommendation tools often fail because they treat listening history as a flat signal. They may recommend music based on albums a user listened to but did not actually like, and they often provide weak explanations for why something was recommended.

Listend solves this by making the user's own ratings, reviews, tags, and negative opinions part of the recommendation foundation.

---

## 4. Target User

### Primary User

A music listener who enjoys forming opinions about albums and wants a personal logging space that eventually understands their taste.

### Secondary User

A curious listener who wants better recommendations without filling out surveys or manually configuring preferences.

---

## 5. MVP Goals

### MVP 0.1 — Local Logging Foundation

- Create a SwiftUI iOS app shell
- Persist albums and logs locally with SwiftData
- Display a Home / Feed screen with recent logs
- Display a Profile screen with simple stats
- Provide seed/mock album data so the app works before MusicKit
- Allow creating, editing, and deleting logs

### MVP 0.2 — Album Search

- Add searchable album catalog
- Use a mock catalog first
- Integrate MusicKit only after local logging is stable
- Cache selected album metadata locally

### MVP 0.3 — Mock SoundPrint

- Add rule-based sentiment scoring
- Generate basic taste dimensions from ratings, reviews, and tags
- Show supporting evidence receipts from actual logs
- Display a SoundPrint Profile screen

### MVP 0.4 — Persona

- Generate a short, punchy taste persona
- Use deterministic/mock generation first
- Later swap in Apple Foundation Models behind a protocol
- Display persona on Profile and Home

### MVP 0.5 — Tonight's Pick

- Recommend one album at a time
- Use mock/local candidate selection first
- Explain recommendation using real logs and receipts
- Capture user feedback: like, dismiss, save for later, listened

---

## 6. Non-Goals for MVP

The following are intentionally out of scope for the first usable implementation:

- Social features
- User accounts or authentication
- Cloud sync
- Spotify integration
- Android or web
- Song-level logging as a primary feature
- Full Apple Music playback
- Production analytics infrastructure
- Collaborative filtering
- Large-scale recommendation engine
- Complex evaluation harness

---

## 7. Core User Stories

### Logging

- As a user, I want to log an album with a rating so I can track what I listened to.
- As a user, I want to write a short review so the app understands what I liked or disliked.
- As a user, I want to add tags so I can capture what stood out.
- As a user, I want to edit or delete a log.

### Feed

- As a user, I want to see my recent logs in a simple feed.
- As a user, I want to quickly understand what I have logged recently.

### Profile

- As a user, I want to see my total logs, average rating, and most-used tags.
- As a user, I want to see a short SoundPrint taste summary after I have enough logs.

### SoundPrint

- As a user, I want the app to distinguish between albums I liked and albums I disliked.
- As a user, I want negative reviews to count as “do not recommend more like this.”
- As a user, I want taste dimensions backed by evidence from my own logs.

### Recommendations

- As a user, I want one album recommendation at a time.
- As a user, I want to understand why the album was recommended.
- As a user, I want the explanation to reference my actual ratings, tags, or review snippets.

---

## 8. MVP Feature Requirements

## 8.1 Album and Log Management

### Requirements

- User can create a log for an album.
- Rating is required.
- Review is optional.
- Tags are optional.
- User can edit or delete an existing log.
- Logs are persisted locally using SwiftData.
- App ships with seed/mock album data for early development.

### Acceptance Criteria

- A user can add a log in the Simulator without MusicKit.
- Logs appear immediately in the Home feed.
- Logs remain after app relaunch.
- User can edit rating, review, and tags.
- User can delete a log.

---

## 8.2 Home / Feed

### Requirements

- Show recent logs sorted by most recent first.
- Show album title, artist, rating, review preview, tags, and logged date.
- Include navigation to Search / Add Log and Profile.

### Acceptance Criteria

- Home loads from SwiftData.
- Empty state appears when no logs exist.
- Recent logs update after creating, editing, or deleting a log.

---

## 8.3 Profile

### Requirements

- Show total logs.
- Show average rating.
- Show most-used tags.
- Show SoundPrint Persona once available.
- Link to full SoundPrint Profile.

### Acceptance Criteria

- Stats update after log changes.
- Persona area shows a useful placeholder before enough logs exist.
- Profile does not depend on AI services to load.

---

## 8.4 Mock SoundPrint Sentiment

### Requirements

- Every saved log gets a sentiment score.
- Early implementation uses deterministic local rules:
  - Rating >= 4.0 → positive
  - Rating 3.0–3.9 → neutral-positive
  - Rating < 3.0 → negative
  - Negative keywords in review can reduce sentiment
  - Positive keywords in review can increase sentiment
- Sentiment score is stored on the log.
- Sentiment is not shown as a raw score to the user.

### Acceptance Criteria

- A low-rated negative review is marked as a negative signal.
- A high-rated positive review is marked as a positive signal.
- Sentiment calculation does not block saving a log.
- If sentiment fails, fallback is rating-only.

---

## 8.5 SoundPrint Profile

### Requirements

- Display taste dimensions derived from logs.
- MVP fixed dimensions:
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
- Each visible dimension should show:
  - label
  - weight
  - confidence
  - evidence receipt from a real log
- Positive evidence must come from positively reviewed logs.
- Negative logs may inform avoidance signals but should not be shown as positive evidence.

### Acceptance Criteria

- SoundPrint Profile appears after at least 2–3 logs.
- Each visible dimension has at least one stored evidence item.
- Negative reviews do not appear as positive receipts.
- Profile can be generated using mock/rule-based logic.

---

## 8.6 SoundPrint Persona

### Requirements

- Generate after at least 5 logs.
- 2–3 sentences maximum.
- Tone should be specific, direct, and slightly irreverent.
- Persona should reference patterns in ratings, tags, and review language.
- MVP may use template/rule-based generation.
- Later implementation may use Apple Foundation Models behind a service protocol.

### Acceptance Criteria

- Persona is hidden or replaced by a placeholder before 5 logs.
- Persona avoids generic phrases like “eclectic taste” or “wide range of genres.”
- Persona updates after meaningful new logging activity.

---

## 8.7 Tonight's Pick

### Requirements

- Show one recommendation at a time.
- Candidate source can be mock/local at first.
- Recommendation must exclude already-logged albums.
- Recommendation should not be anchored by negative logs.
- Explanation must include receipts from positive logs.
- User can like, dismiss, save for later, or mark as listened.

### Acceptance Criteria

- App can generate a recommendation with only local/mock data.
- Explanation references at least one real user log.
- Dismissed album is not immediately recommended again.
- Feedback is saved locally.

---

## 9. Data Model — MVP

### Album

- id
- title
- artistName
- releaseYear
- genreName
- artworkURL
- appleMusicID optional
- cachedAt

### LogEntry

- id
- albumID
- rating
- reviewText
- tags
- sentimentScore
- sentimentConfidence
- loggedAt
- updatedAt

### TasteDimension

- id
- name
- label
- weight
- confidence
- summary
- updatedAt

### TasteEvidence

- id
- tasteDimensionID
- logEntryID
- snippet
- evidenceType
- strength
- isPositiveEvidence

### SoundPrintPersona

- id
- personaText
- generatedAt
- logCountAtGeneration

### Recommendation

- id
- albumID
- score
- confidence
- status
- explanationText
- createdAt

### RecommendationReceipt

- id
- recommendationID
- logEntryID
- snippet
- linkedDimension

### RecommendationFeedback

- id
- recommendationID
- feedbackType
- createdAt

---

## 10. Screens

| Screen | MVP Purpose |
|---|---|
| Home / Feed | Show recent logs and entry points |
| Search / Add Album | Search mock catalog first, MusicKit later |
| Album Detail | Show album metadata and log CTA |
| Log Entry | Rating, review, tags |
| Profile | Stats and persona |
| SoundPrint Profile | Taste dimensions and evidence |
| Tonight's Pick | One recommendation, explanation, receipts, feedback |

---

## 11. MVP Build Sequence for Codex

### Phase 1 — App Foundation

- SwiftUI app shell
- NavigationStack
- SwiftData setup
- Album and LogEntry models
- Seed data
- Home and Profile placeholder screens

### Phase 2 — Logging

- Add/edit/delete log
- Rating control
- Review text
- Tag entry
- Feed updates from SwiftData

### Phase 3 — Mock Search

- Mock album catalog
- Search screen
- Album detail
- Create log from selected album

### Phase 4 — Mock SoundPrint Sentiment

- Sentiment service protocol
- Mock/rule-based sentiment service
- Store score and confidence on LogEntry
- Add positive/negative signal helpers

### Phase 5 — SoundPrint Profile

- Taste dimension model
- Evidence model
- Rule-based taste extraction
- SoundPrint Profile UI

### Phase 6 — Persona

- Persona model
- Rule-based persona generation
- Profile display
- Quality guardrails

### Phase 7 — Tonight's Pick

- Local candidate selection
- Basic scoring
- Explanation receipts
- Feedback capture

### Phase 8 — Real MusicKit

- Replace mock catalog search with MusicKit search
- Cache MusicKit albums locally
- Keep mock catalog fallback

### Phase 9 — Real Foundation Models

- Replace mock SoundPrint provider with Foundation Models provider
- Keep mock provider available for Simulator/demo fallback
- Add parse validation and fallback behavior

### Phase 10 — Playback Preview

- Add preview playback only
- Full Apple Music playback remains post-MVP enhancement

---

## 12. Success Criteria

The MVP is successful when:

- User can create and manage album logs locally.
- Feed and profile update reliably.
- App can generate mock SoundPrint dimensions from real logs.
- Persona appears after enough logs.
- Tonight's Pick can recommend an unlogged album with receipts.
- Negative logs do not anchor recommendations.
- The app builds and runs in the iOS Simulator.
- Real MusicKit and Foundation Models can be added without rewriting the app.

---

## 13. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---:|---|
| Codex overbuilds future phases | High | Use strict phase prompts |
| Foundation Models availability/API mismatch | High | Use provider protocol and mock implementation first |
| MusicKit setup blocks progress | Medium | Start with mock catalog |
| Recommendation quality is weak with few logs | Medium | Show honest cold-start states |
| Persona feels generic | Medium | Use quality filters and do not show until enough logs |
| SwiftData model complexity grows too early | Medium | Start with simple direct models, add mapping later only if needed |

---

## 14. One-Sentence MVP Statement

Listend MVP is a local-first iOS music diary that lets users log albums, builds a simple evidence-backed SoundPrint taste profile, and recommends one album at a time using the user’s own positive and negative signals.
