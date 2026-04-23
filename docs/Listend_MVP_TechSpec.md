# Listend — MVP Technical Specification

**Author:** Shaunak Kulkarni  
**Product:** Listend  
**AI Layer:** SoundPrint  
**Platform:** iOS  
**Stack:** SwiftUI, SwiftData, MusicKit later, Apple Foundation Models later  
**Build Tool:** Codex + Xcode  
**Version:** MVP 0.1–0.5  
**Status:** Codex-ready draft  

---

## 1. Purpose

This technical specification defines a practical MVP implementation plan for Listend.

The original product vision includes MusicKit, Apple Foundation Models, recommendations, explanations, playback, and evaluation. This MVP spec intentionally starts smaller so Codex can build the app phase-by-phase without breaking the project.

The first technical goal is:

> Build a local-first album logging app that runs in the iOS Simulator.

The second technical goal is:

> Add SoundPrint through mock/rule-based services first, then swap in real MusicKit and Apple Foundation Models later.

---

## 2. Core Engineering Principles

1. **The app must compile after every phase.**
2. **Logging must never be blocked by AI.**
3. **Use mock services before real integrations.**
4. **Do not implement future phases early.**
5. **Keep SwiftData models simple at first.**
6. **Use protocols around risky dependencies.**
7. **Every SoundPrint claim must be backed by stored user data.**

---

## 3. MVP Technical Scope

### In Scope

- SwiftUI app shell
- NavigationStack-based navigation
- SwiftData local persistence
- Album and log management
- Mock album catalog
- Feed screen
- Profile screen
- Rule-based sentiment scoring
- Rule-based taste dimensions
- Evidence receipts
- Rule-based persona generation
- Local Tonight's Pick recommendation
- Recommendation feedback capture
- MusicKit integration later
- Foundation Models integration later

### Out of Scope for First MVP Pass

- Cloud sync
- Authentication
- Social features
- Spotify
- Full Apple Music playback
- Complex song-level logging
- Production analytics
- Large-scale collaborative filtering
- Advanced evaluation harness

---

## 4. Architecture

Use a simple layered architecture:

```text
Presentation Layer
SwiftUI Views + ViewModels

Domain Layer
Business rules, SoundPrint orchestration, recommendation logic

Data Layer
SwiftData models and repositories

Integration Layer
Mock catalog, MusicKit later, mock SoundPrint, Foundation Models later
```

For early phases, avoid over-abstracting. SwiftData `@Model` classes may be used directly by ViewModels where practical. Introduce domain DTOs only when needed for service boundaries.

---

## 5. Project Structure

```text
Listend/
├── App/
│   ├── ListendApp.swift
│   ├── AppRouter.swift
│   └── AppEnvironment.swift
├── Models/
│   ├── Album.swift
│   ├── LogEntry.swift
│   ├── TasteDimension.swift
│   ├── TasteEvidence.swift
│   ├── SoundPrintPersona.swift
│   ├── Recommendation.swift
│   ├── RecommendationReceipt.swift
│   └── RecommendationFeedback.swift
├── Views/
│   ├── Home/
│   ├── Search/
│   ├── AlbumDetail/
│   ├── LogEntry/
│   ├── Profile/
│   ├── SoundPrint/
│   └── Recommendation/
├── ViewModels/
│   ├── HomeViewModel.swift
│   ├── SearchViewModel.swift
│   ├── AlbumDetailViewModel.swift
│   ├── LogEntryViewModel.swift
│   ├── ProfileViewModel.swift
│   ├── SoundPrintViewModel.swift
│   └── RecommendationViewModel.swift
├── Services/
│   ├── Catalog/
│   │   ├── AlbumCatalogService.swift
│   │   ├── MockAlbumCatalogService.swift
│   │   └── MusicKitAlbumCatalogService.swift
│   ├── SoundPrint/
│   │   ├── SoundPrintProvider.swift
│   │   ├── MockSoundPrintProvider.swift
│   │   ├── FoundationModelsSoundPrintProvider.swift
│   │   ├── SentimentScoringService.swift
│   │   ├── TasteExtractionService.swift
│   │   ├── PersonaGenerationService.swift
│   │   └── SoundPrintOrchestrator.swift
│   └── Recommendation/
│       ├── RecommendationService.swift
│       ├── RecommendationRankingService.swift
│       └── ExplanationReceiptService.swift
├── Repositories/
│   ├── AlbumRepository.swift
│   ├── LogRepository.swift
│   ├── TasteRepository.swift
│   └── RecommendationRepository.swift
├── Persistence/
│   ├── SwiftDataStack.swift
│   └── SeedData.swift
├── Utilities/
│   ├── Constants.swift
│   ├── Extensions/
│   └── Formatters/
└── Tests/
    ├── Unit/
    └── Integration/
```

---

## 6. Platform and Dependency Strategy

### 6.1 iOS Target

Use the latest stable iOS target available in the local Xcode environment.

For early phases, avoid APIs that require a real device or Apple developer entitlements.

### 6.2 MusicKit

MusicKit is not required for Phases 1–7. Use `MockAlbumCatalogService` first.

MusicKit should be introduced only after local logging, feed, profile, and mock SoundPrint are stable.

### 6.3 Apple Foundation Models

Foundation Models should not be required for the app to compile in early phases.

Implement SoundPrint behind a protocol:

```swift
protocol SoundPrintProvider {
    func analyzeSentiment(input: SentimentInput) async throws -> SentimentResult
    func extractTasteSignals(input: TasteExtractionInput) async throws -> TasteExtractionResult
    func generatePersona(input: PersonaInput) async throws -> PersonaResult
}
```

Use:

```swift
final class MockSoundPrintProvider: SoundPrintProvider
```

first.

Add:

```swift
final class FoundationModelsSoundPrintProvider: SoundPrintProvider
```

later.

The app should be able to run entirely with `MockSoundPrintProvider`.

---

## 7. SwiftData Models

## 7.1 Album

```swift
@Model
final class Album {
    var id: UUID
    var appleMusicID: String?
    var title: String
    var artistName: String
    var releaseYear: Int?
    var genreName: String?
    var artworkURL: String?
    var cachedAt: Date

    init(
        id: UUID = UUID(),
        appleMusicID: String? = nil,
        title: String,
        artistName: String,
        releaseYear: Int? = nil,
        genreName: String? = nil,
        artworkURL: String? = nil,
        cachedAt: Date = Date()
    ) {
        self.id = id
        self.appleMusicID = appleMusicID
        self.title = title
        self.artistName = artistName
        self.releaseYear = releaseYear
        self.genreName = genreName
        self.artworkURL = artworkURL
        self.cachedAt = cachedAt
    }
}
```

## 7.2 LogEntry

```swift
@Model
final class LogEntry {
    var id: UUID
    var album: Album?
    var rating: Double
    var reviewText: String
    var tagsRawValue: String
    var sentimentScore: Double?
    var sentimentConfidence: Double?
    var loggedAt: Date
    var updatedAt: Date

    var tags: [String] {
        get {
            tagsRawValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            tagsRawValue = newValue.joined(separator: ",")
        }
    }

    var isPositiveSignal: Bool {
        (sentimentScore ?? ratingDerivedSentimentScore) >= 0.0
    }

    var isNegativeSignal: Bool {
        (sentimentScore ?? ratingDerivedSentimentScore) < -0.2
    }

    var canAnchorRecommendation: Bool {
        !isNegativeSignal
    }

    private var ratingDerivedSentimentScore: Double {
        if rating >= 4.0 { return 0.7 }
        if rating >= 3.0 { return 0.2 }
        return -0.5
    }

    init(
        id: UUID = UUID(),
        album: Album?,
        rating: Double,
        reviewText: String = "",
        tags: [String] = [],
        sentimentScore: Double? = nil,
        sentimentConfidence: Double? = nil,
        loggedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.album = album
        self.rating = rating
        self.reviewText = reviewText
        self.tagsRawValue = tags.joined(separator: ",")
        self.sentimentScore = sentimentScore
        self.sentimentConfidence = sentimentConfidence
        self.loggedAt = loggedAt
        self.updatedAt = updatedAt
    }
}
```

## 7.3 TasteDimension

```swift
@Model
final class TasteDimension {
    var id: UUID
    var name: String
    var label: String
    var weight: Double
    var confidence: Double
    var summary: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        label: String,
        weight: Double,
        confidence: Double,
        summary: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.label = label
        self.weight = weight
        self.confidence = confidence
        self.summary = summary
        self.updatedAt = updatedAt
    }
}
```

## 7.4 TasteEvidence

```swift
@Model
final class TasteEvidence {
    var id: UUID
    var dimensionName: String
    var logEntryID: UUID
    var snippet: String
    var evidenceType: String
    var strength: Double
    var isPositiveEvidence: Bool

    init(
        id: UUID = UUID(),
        dimensionName: String,
        logEntryID: UUID,
        snippet: String,
        evidenceType: String,
        strength: Double,
        isPositiveEvidence: Bool
    ) {
        self.id = id
        self.dimensionName = dimensionName
        self.logEntryID = logEntryID
        self.snippet = snippet
        self.evidenceType = evidenceType
        self.strength = strength
        self.isPositiveEvidence = isPositiveEvidence
    }
}
```

## 7.5 SoundPrintPersona

```swift
@Model
final class SoundPrintPersona {
    var id: UUID
    var personaText: String
    var generatedAt: Date
    var logCountAtGeneration: Int

    init(
        id: UUID = UUID(),
        personaText: String,
        generatedAt: Date = Date(),
        logCountAtGeneration: Int
    ) {
        self.id = id
        self.personaText = personaText
        self.generatedAt = generatedAt
        self.logCountAtGeneration = logCountAtGeneration
    }
}
```

## 7.6 Recommendation

```swift
@Model
final class Recommendation {
    var id: UUID
    var album: Album?
    var score: Double
    var confidence: Double
    var status: String
    var explanationText: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        album: Album?,
        score: Double,
        confidence: Double,
        status: String = "active",
        explanationText: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.album = album
        self.score = score
        self.confidence = confidence
        self.status = status
        self.explanationText = explanationText
        self.createdAt = createdAt
    }
}
```

## 7.7 RecommendationReceipt

```swift
@Model
final class RecommendationReceipt {
    var id: UUID
    var recommendationID: UUID
    var logEntryID: UUID
    var snippet: String
    var linkedDimension: String?

    init(
        id: UUID = UUID(),
        recommendationID: UUID,
        logEntryID: UUID,
        snippet: String,
        linkedDimension: String? = nil
    ) {
        self.id = id
        self.recommendationID = recommendationID
        self.logEntryID = logEntryID
        self.snippet = snippet
        self.linkedDimension = linkedDimension
    }
}
```

## 7.8 RecommendationFeedback

```swift
@Model
final class RecommendationFeedback {
    var id: UUID
    var recommendationID: UUID
    var feedbackType: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        recommendationID: UUID,
        feedbackType: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.recommendationID = recommendationID
        self.feedbackType = feedbackType
        self.createdAt = createdAt
    }
}
```

---

## 8. Shared Enums

```swift
enum TasteDimensionKey: String, Codable, CaseIterable {
    case mood
    case energy
    case productionStyle
    case vocalFocus
    case lyricFocus
    case experimentation
    case instrumentalRichness
    case genreOpenness
    case eraAffinity
    case replayability
}

enum RecommendationStatus: String, Codable {
    case active
    case dismissed
    case saved
    case accepted
}

enum RecommendationFeedbackType: String, Codable {
    case liked
    case dismissed
    case savedForLater
    case listened
}
```

---

## 9. Service Protocols

## 9.1 AlbumCatalogService

```swift
protocol AlbumCatalogService {
    func searchAlbums(query: String) async throws -> [AlbumSearchResult]
    func albumDetails(id: String) async throws -> AlbumSearchResult?
}

struct AlbumSearchResult: Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let releaseYear: Int?
    let genreName: String?
    let artworkURL: String?
}
```

Implement first:

```swift
final class MockAlbumCatalogService: AlbumCatalogService
```

Implement later:

```swift
final class MusicKitAlbumCatalogService: AlbumCatalogService
```

---

## 9.2 SoundPrintProvider

```swift
protocol SoundPrintProvider {
    func analyzeSentiment(input: SentimentInput) async throws -> SentimentResult
    func extractTasteSignals(input: TasteExtractionInput) async throws -> TasteExtractionResult
    func generatePersona(input: PersonaInput) async throws -> PersonaResult
}

struct SentimentInput {
    let rating: Double
    let reviewText: String
    let tags: [String]
}

struct SentimentResult {
    let score: Double
    let confidence: Double
}

struct TasteExtractionInput {
    let logID: UUID
    let albumTitle: String
    let artistName: String
    let genreName: String?
    let releaseYear: Int?
    let rating: Double
    let reviewText: String
    let tags: [String]
    let sentimentScore: Double
}

struct TasteSignal {
    let dimension: TasteDimensionKey
    let label: String
    let weight: Double
    let confidence: Double
    let evidenceSnippet: String
    let isPositiveEvidence: Bool
}

struct TasteExtractionResult {
    let signals: [TasteSignal]
}

struct PersonaInput {
    let dimensions: [TasteDimension]
    let recentLogs: [LogEntry]
    let totalLogCount: Int
}

struct PersonaResult {
    let text: String
}
```

---

## 10. Mock SoundPrint Rules

## 10.1 Sentiment

```text
Base score:
rating >= 4.0: 0.7
rating 3.0–3.9: 0.2
rating < 3.0: -0.5

Positive keyword boost:
love, loved, great, favorite, beautiful, amazing, replay, catchy, incredible

Negative keyword penalty:
hate, hated, boring, overrated, bad, weak, annoying, forgettable, disappointing

Clamp final score between -1.0 and 1.0.
Confidence:
- 0.8 if review has text
- 0.6 if rating only
```

## 10.2 Taste Extraction

Rule-based extraction can map simple text and tag signals to dimensions:

```text
dark, sad, moody, melancholic -> mood
energetic, intense, aggressive -> energy
polished, glossy, clean -> productionStyle
raw, rough, lo-fi -> productionStyle
vocals, voice, singer -> vocalFocus
lyrics, writing, storytelling -> lyricFocus
weird, experimental, unpredictable -> experimentation
dense, layered, lush -> instrumentalRichness
genre-bending, fusion -> genreOpenness
classic, old-school, 90s, 2000s -> eraAffinity
replay, repeat, addictive -> replayability
```

Only positive logs should create positive evidence. Negative logs may create avoidance evidence for future recommendation penalties.

---

## 11. Repositories

Repositories should hide SwiftData query details.

```swift
protocol AlbumRepository {
    func upsertAlbum(from result: AlbumSearchResult) async throws -> Album
    func fetchAlbum(byID id: UUID) async throws -> Album?
    func fetchAlbum(byAppleMusicID id: String) async throws -> Album?
    func fetchAllAlbums() async throws -> [Album]
}
```

```swift
protocol LogRepository {
    func createLog(album: Album, rating: Double, reviewText: String, tags: [String]) async throws -> LogEntry
    func updateLog(_ log: LogEntry) async throws
    func deleteLog(_ log: LogEntry) async throws
    func fetchLog(byID id: UUID) async throws -> LogEntry?
    func fetchRecentLogs(limit: Int) async throws -> [LogEntry]
    func fetchAllLogs() async throws -> [LogEntry]
    func fetchPositiveLogs() async throws -> [LogEntry]
    func fetchNegativeLogs() async throws -> [LogEntry]
    func updateSentiment(logID: UUID, score: Double, confidence: Double) async throws
    func totalLogCount() async throws -> Int
}
```

```swift
protocol TasteRepository {
    func saveOrUpdateDimension(_ dimension: TasteDimension) async throws
    func saveEvidence(_ evidence: TasteEvidence) async throws
    func fetchTopDimensions(limit: Int) async throws -> [TasteDimension]
    func fetchEvidence(forDimensionName name: String) async throws -> [TasteEvidence]
    func fetchAllEvidence() async throws -> [TasteEvidence]
    func savePersona(_ persona: SoundPrintPersona) async throws
    func fetchCurrentPersona() async throws -> SoundPrintPersona?
}
```

```swift
protocol RecommendationRepository {
    func saveRecommendation(_ recommendation: Recommendation) async throws
    func fetchActiveRecommendation() async throws -> Recommendation?
    func fetchRecentRecommendations(limit: Int) async throws -> [Recommendation]
    func updateRecommendationStatus(id: UUID, status: RecommendationStatus) async throws
    func saveReceipt(_ receipt: RecommendationReceipt) async throws
    func fetchReceipts(for recommendationID: UUID) async throws -> [RecommendationReceipt]
    func saveFeedback(_ feedback: RecommendationFeedback) async throws
}
```

---

## 12. SoundPrint Orchestrator

The orchestrator runs after log creation.

```swift
actor SoundPrintOrchestrator {
    private let logRepository: LogRepository
    private let tasteRepository: TasteRepository
    private let provider: SoundPrintProvider

    init(
        logRepository: LogRepository,
        tasteRepository: TasteRepository,
        provider: SoundPrintProvider
    ) {
        self.logRepository = logRepository
        self.tasteRepository = tasteRepository
        self.provider = provider
    }

    func processLog(logID: UUID) async {
        do {
            guard let log = try await logRepository.fetchLog(byID: logID) else { return }

            let sentiment = try await provider.analyzeSentiment(
                input: SentimentInput(
                    rating: log.rating,
                    reviewText: log.reviewText,
                    tags: log.tags
                )
            )

            try await logRepository.updateSentiment(
                logID: logID,
                score: sentiment.score,
                confidence: sentiment.confidence
            )

            guard let album = log.album else { return }

            let extraction = try await provider.extractTasteSignals(
                input: TasteExtractionInput(
                    logID: log.id,
                    albumTitle: album.title,
                    artistName: album.artistName,
                    genreName: album.genreName,
                    releaseYear: album.releaseYear,
                    rating: log.rating,
                    reviewText: log.reviewText,
                    tags: log.tags,
                    sentimentScore: sentiment.score
                )
            )

            for signal in extraction.signals {
                let dimension = TasteDimension(
                    name: signal.dimension.rawValue,
                    label: signal.label,
                    weight: signal.weight,
                    confidence: signal.confidence,
                    summary: signal.label
                )

                try await tasteRepository.saveOrUpdateDimension(dimension)

                let evidence = TasteEvidence(
                    dimensionName: signal.dimension.rawValue,
                    logEntryID: log.id,
                    snippet: signal.evidenceSnippet,
                    evidenceType: "reviewOrTag",
                    strength: signal.weight,
                    isPositiveEvidence: signal.isPositiveEvidence
                )

                try await tasteRepository.saveEvidence(evidence)
            }

            let logCount = try await logRepository.totalLogCount()

            if logCount >= 5 {
                let dimensions = try await tasteRepository.fetchTopDimensions(limit: 10)
                let recentLogs = try await logRepository.fetchRecentLogs(limit: 10)

                let persona = try await provider.generatePersona(
                    input: PersonaInput(
                        dimensions: dimensions,
                        recentLogs: recentLogs,
                        totalLogCount: logCount
                    )
                )

                let record = SoundPrintPersona(
                    personaText: persona.text,
                    logCountAtGeneration: logCount
                )

                try await tasteRepository.savePersona(record)
            }
        } catch {
            // MVP rule: never block logging because SoundPrint failed.
            return
        }
    }
}
```

---

## 13. Recommendation Logic — MVP

Use simple deterministic local scoring first.

### Candidate Source

- Use albums from mock catalog or cached local albums.
- Exclude already-logged albums.
- Exclude recently dismissed recommendations.

### Placeholder Scoring

```text
+0.30 if candidate genre matches a positive log genre
+0.20 if candidate release era matches a liked era
+0.20 if candidate has keywords matching positive tags/evidence
+0.10 novelty bonus if artist has not been logged
-0.40 if candidate genre strongly matches negative logs
-0.20 if artist was recently recommended
```

### Explanation Rules

Use receipt-first explanations:

```text
"Because you rated [Album] [rating] stars and tagged it [tag]."
"Your review of [Album] mentioned '[snippet]', which points toward [dimension]."
```

Do not generate claims without evidence.

---

## 14. ViewModel Responsibilities

## 14.1 HomeViewModel

- Fetch recent logs
- Fetch current persona
- Expose empty state
- Route to Search and Profile

## 14.2 SearchViewModel

- Manage query text
- Call `AlbumCatalogService`
- Show mock results first
- Navigate to Album Detail

## 14.3 AlbumDetailViewModel

- Display selected album
- Check if album already logged
- Route to Log Entry

## 14.4 LogEntryViewModel

- Hold rating, review text, and tags
- Validate rating is present
- Save log
- Trigger `SoundPrintOrchestrator.processLog(logID:)` asynchronously
- Return to Home

## 14.5 ProfileViewModel

- Fetch total logs
- Calculate average rating
- Calculate most-used tags
- Fetch persona
- Route to SoundPrint Profile

## 14.6 SoundPrintViewModel

- Fetch top dimensions
- Fetch evidence per dimension
- Hide dimensions with very low confidence

## 14.7 RecommendationViewModel

- Generate local recommendation
- Fetch receipts
- Capture feedback
- Update recommendation status

---

## 15. Screen Specs

## 15.1 Home

- Header: Listend
- Persona preview card if available
- Recent logs list
- Empty state if no logs
- Button: Add / Search Album
- Button or tab: Profile
- Button: Tonight's Pick once enough logs exist

## 15.2 Search

- Search bar
- Mock catalog results
- Album row: artwork placeholder, title, artist, year, genre
- Tap result to Album Detail

## 15.3 Album Detail

- Album artwork placeholder
- Title
- Artist
- Year
- Genre
- Button: Log this album
- Already logged state if applicable

## 15.4 Log Entry

- Album summary
- Rating picker, 0.5 to 5.0
- Review text editor
- Tags input
- Save button
- Cancel button

## 15.5 Profile

- Total logs
- Average rating
- Most-used tags
- Persona card
- Link to SoundPrint Profile

## 15.6 SoundPrint Profile

- Header: How SoundPrint sees your taste
- Dimension cards
- Weight/confidence indicators
- Expandable receipts

## 15.7 Tonight's Pick

- Recommended album card
- Explanation text
- Receipts
- Feedback buttons:
  - Like
  - Dismiss
  - Save for later
  - Listened

---

## 16. Error Handling

| Failure | MVP Behavior |
|---|---|
| SwiftData save fails | Show user-facing error |
| Mock catalog empty | Show empty state |
| SoundPrint sentiment fails | Use rating fallback |
| Taste extraction fails | Keep log, skip profile update |
| Persona generation fails | Keep previous persona or placeholder |
| Recommendation fails | Show “Log more albums first” state |
| MusicKit unavailable later | Use mock catalog fallback |
| Foundation Models unavailable later | Use mock SoundPrint provider |

---

## 17. Testing Strategy

### Unit Tests

- Rating-to-sentiment mapping
- Keyword sentiment adjustment
- Positive/negative signal helper properties
- Tag parsing
- Taste dimension extraction rules
- Persona quality filter
- Recommendation candidate filtering
- Recommendation scoring
- Receipt generation

### Integration Tests

- Create log → sentiment generated → log updated
- Create log → taste evidence generated
- Five logs → persona generated
- Negative log → not used as recommendation anchor
- Dismissed recommendation → not immediately repeated

### Manual QA

- Launch app fresh
- Add first log
- Relaunch app and verify persistence
- Add 5 logs and verify persona
- Add negative review and verify it does not create positive evidence
- Generate Tonight's Pick and verify receipts reference real logs

---

## 18. Codex Build Rules

Codex should follow these rules:

1. Implement only the requested phase.
2. Do not add MusicKit before the MusicKit phase.
3. Do not add Foundation Models before the Foundation Models phase.
4. Do not add full playback in MVP.
5. Do not add authentication, cloud sync, social, Spotify, or analytics.
6. Keep files small and readable.
7. Prefer working code over perfect architecture.
8. Leave the app compiling after every task.
9. Summarize changed files after implementation.
10. Ask before making large architectural changes.

---

## 19. Codex Phase Prompts

## Phase 1 Prompt

```markdown
We are building Listend, an iOS SwiftUI app.

Use docs/Listend_MVP_PRD.md and docs/Listend_MVP_TechSpec.md as context.

Implement Phase 1 only.

Scope:
- SwiftUI app shell
- NavigationStack
- SwiftData setup
- Album and LogEntry models only
- Seed data
- Home screen with recent seeded logs
- Profile screen with placeholder stats
- Search placeholder screen
- No MusicKit
- No Foundation Models
- No recommendation engine
- No playback

Constraints:
- App must compile and run in iOS Simulator.
- Do not implement future phases.
- Keep code simple and reviewable.

Before coding:
1. Inspect the repo.
2. Summarize current state.
3. List files to create or modify.
4. Wait for approval.
```

## Phase 2 Prompt

```markdown
Implement Phase 2 only: local logging.

Scope:
- Add Log Entry screen
- Allow user to create a log for a seeded/mock album
- Rating is required
- Review and tags are optional
- Save to SwiftData
- Display logs on Home feed
- Support edit and delete

Do not add MusicKit, Foundation Models, recommendations, playback, or social features.
App must compile and run after changes.
```

## Phase 3 Prompt

```markdown
Implement Phase 3 only: mock album search and album detail.

Scope:
- Create MockAlbumCatalogService
- Add Search screen with query field
- Search mock album catalog
- Add Album Detail screen
- Allow user to start a log from Album Detail
- Cache selected album in SwiftData

Do not add MusicKit yet.
App must compile and run after changes.
```

## Phase 4 Prompt

```markdown
Implement Phase 4 only: mock SoundPrint sentiment.

Scope:
- Add SoundPrintProvider protocol
- Add MockSoundPrintProvider
- Implement rule-based sentiment scoring
- Store sentimentScore and sentimentConfidence on LogEntry after save
- Add isPositiveSignal, isNegativeSignal, and canAnchorRecommendation helpers
- Ensure logging is never blocked if sentiment processing fails

Do not add Foundation Models yet.
App must compile and run after changes.
```

## Phase 5 Prompt

```markdown
Implement Phase 5 only: SoundPrint Profile.

Scope:
- Add TasteDimension and TasteEvidence models
- Add rule-based taste extraction from positive logs
- Store evidence receipts
- Add SoundPrint Profile screen
- Show dimension cards with weight, confidence, and receipts
- Ensure negative logs do not appear as positive evidence

Do not add recommendations or Foundation Models.
App must compile and run after changes.
```

## Phase 6 Prompt

```markdown
Implement Phase 6 only: SoundPrint Persona.

Scope:
- Add SoundPrintPersona model
- Generate persona after at least 5 logs
- Use rule-based/template generation
- Add quality filter to avoid generic phrases like “eclectic taste”
- Display persona on Home and Profile

Do not add Foundation Models yet.
App must compile and run after changes.
```

## Phase 7 Prompt

```markdown
Implement Phase 7 only: Tonight's Pick using local/mock data.

Scope:
- Add Recommendation, RecommendationReceipt, and RecommendationFeedback models
- Generate one recommendation from unlogged mock/local albums
- Exclude already-logged albums
- Avoid anchoring recommendations on negative logs
- Add receipt-backed explanation
- Add feedback actions: like, dismiss, save for later, listened

Do not add MusicKit, Foundation Models, playback, or clarifying questions yet.
App must compile and run after changes.
```

---

## 20. Technical Definition of Done

The MVP technical implementation is complete when:

- App builds and runs in iOS Simulator.
- User can create, edit, delete, and view album logs.
- Logs persist locally with SwiftData.
- Mock album search works.
- SoundPrint sentiment runs after log save.
- Positive and negative signals are stored.
- SoundPrint Profile displays dimensions with evidence.
- Persona appears after 5 logs.
- Tonight's Pick recommends one unlogged album with receipts.
- Negative logs do not anchor recommendations.
- MusicKit and Foundation Models can be added later behind protocols without rewriting core flows.
