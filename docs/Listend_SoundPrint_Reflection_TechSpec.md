# Listend SoundPrint Listening Reflection — Technical Specification

**Document type:** Technical specification

**Status:** Draft for implementation handoff

**Version:** 1.0

**Date:** July 28, 2026

**Product:** Listend for iOS

**Platform:** iOS 26.4+

**Stack:** SwiftUI, SwiftData, Apple Foundation Models

**Companion requirements:** `docs/Listend_SoundPrint_Reflection_Requirements.md`

---

## 1. Purpose

This specification defines the smallest safe implementation that turns the
existing SoundPrint persona/profile into an earned, user-initiated SoundPrint
Reflection.

The implementation must reuse:

- Existing `LogEntry` data
- Canonical reaction tags
- Existing taste dimensions, avoidance signals, and evidence
- Existing `SoundPrintProvider` abstraction
- Existing Foundation Models plain-text generation
- Existing local fallback
- Existing `SoundPrintPersona` persistence
- Existing generator-source metadata

It must not create a second AI insight pipeline.

---

## 2. Source-of-truth documents

Read these before implementation:

1. `docs/Listend_SoundPrint_Reflection_Requirements.md`
2. `docs/Listend_Reaction_First_Logging_PRD.md`
3. `docs/Listend_Canonical_Taxonomy_Spec_v1.md`
4. `docs/iOS26_FoundationModels_Strategy_Handoff.md`

If this specification conflicts with the SoundPrint persona requirements in an
older MVP document, this specification controls the new user-facing experience.

The reaction taxonomy, logging save requirements, Today’s Pick behavior, and
iOS 26 Foundation Models safety constraints remain unchanged.

---

## 3. Current architecture

### 3.1 Persistence

The shared SwiftData schema includes:

- `LogEntry`
- `TasteDimension`
- `TasteEvidence`
- `TasteAvoidanceSignal`
- `SoundPrintPersona`
- Recommendation models

Relevant paths:

```text
Listend/ListendShared/Models/LogEntry.swift
Listend/ListendShared/Models/TasteDimension.swift
Listend/ListendShared/Models/TasteEvidence.swift
Listend/ListendShared/Models/TasteAvoidanceSignal.swift
Listend/ListendShared/Models/SoundPrintPersona.swift
Listend/ListendShared/Persistence/ListendModelSchema.swift
```

`LogEntry` already stores:

- Rating
- Review text
- String-array tags through the legacy-compatible raw field
- Favorite tracks
- Weaker/skipped tracks
- Standout moment
- Sentiment score and confidence
- Creation and update dates

`SoundPrintPersona` already stores:

- Primary generated text
- Generation date
- Log count at generation
- Optional compact headline, summary, and bullets
- Generation source
- Legacy tone

### 3.2 Provider boundary

`SoundPrintProvider` exposes:

```swift
protocol SoundPrintProvider {
    func analyzeSentiment(input: SentimentInput) async throws -> SentimentResult
    func extractTasteSignals(input: TasteExtractionInput) async throws -> TasteExtractionResult
    func generatePersona(input: PersonaInput) async throws -> PersonaResult
    func generateCompactSummary(input: CompactSummaryInput) async throws -> CompactSummaryResult
}
```

The first implementation should retain this protocol. Internal `Persona` names
are legacy implementation details and do not need a broad rename.

### 3.3 Provider selection

`SoundPrintProviderFactory` currently selects:

- `MockSoundPrintProvider` for UI tests, Simulator, or disabled Apple
  Intelligence preference
- `FallbackSoundPrintProvider` on eligible physical devices
  - Primary: `FoundationModelsSoundPrintProvider`
  - Fallback: `MockSoundPrintProvider`

This selection remains unchanged.

### 3.4 Current build flow

The existing path is:

```text
Log save
  → SoundPrintProfileRefreshCoordinator.processSavedLog
  → sentiment update
  → SoundPrintProfileBuilder.rebuildProfile
  → replace dimensions/evidence/avoidance
  → generate or replace persona
  → generate compact summary
```

The problem is that `rebuildProfile` combines:

1. Background signal maintenance
2. User-facing artifact generation

The new design must separate those policies while continuing to use one builder.

### 3.5 Current UI

Relevant paths:

```text
Listend/Listend/Views/Home/HomeView.swift
Listend/Listend/Views/Profile/ProfileView.swift
Listend/Listend/Views/Profile/SoundPrintProfileView.swift
Listend/Listend/Views/Profile/SoundPrintSettingsView.swift
Listend/Listend/Views/Profile/TasteInsightsView.swift
Listend/Listend/Views/Shared/SoundPrintGenerationSourceBadge.swift
Listend/Listend/Views/Shared/SoundPrintPersonaToneBadge.swift
```

Current Profile presents a persona card, settings link, and separate profile
link. The new design consolidates those into one primary SoundPrint Reflection
entry.

---

## 4. Target architecture

```text
Reaction-first LogEntry
        │
        ├── save/edit remains immediate
        │
        ├── sentiment update
        │
        └── signals-only profile rebuild
                ├── TasteDimension
                ├── TasteEvidence
                └── TasteAvoidanceSignal

Explicit Create / Update action
        │
        └── reflection profile rebuild
                ├── refresh deterministic signals
                ├── build bounded PersonaInput
                ├── Foundation Models text response
                ├── local validation
                ├── deterministic fallback if needed
                └── replace current SoundPrintPersona only on success

Presentation
        ├── Profile eligibility/current/update state
        ├── SoundPrint Reflection detail + receipts
        └── compact Home card only after success
```

The existing models remain the source of truth. The UI changes semantics and
cadence without introducing a parallel persistence layer.

---

## 5. Persistence decision

### 5.1 Reuse `SoundPrintPersona`

Do not add a new `ListeningReflection` SwiftData model in v1.

Map existing fields as follows:

| Existing field | Reflection meaning |
|---|---|
| `personaText` | Primary SoundPrint Reflection prose |
| `generatedAt` | Reflection generation date |
| `logCountAtGeneration` | Number of logs represented by the artifact |
| `generationSourceRawValue` | Actual generator source |
| `headline` | Optional legacy compact headline |
| `summaryText` | Optional legacy compact summary |
| `bulletsRawValue` | Optional legacy compact bullets |
| `toneRawValue` | Compatibility-only metadata |

The new detail screen should treat `personaText` as the complete primary
artifact. Compact summary fields are optional enrichment and must not be
required for a valid reflection.

### 5.2 No archive

Maintain at most one current `SoundPrintPersona`, matching the existing
single-current-record behavior.

On successful generation:

- Update the newest existing record in place, or insert one if absent.
- Delete duplicate legacy records after a valid replacement is available.
- Update `generatedAt`, `logCountAtGeneration`, `generationSource`, and stored
  balanced tone.

On failure:

- Do not modify or delete the current valid record.

### 5.3 No schema migration

No new required or optional SwiftData field is necessary for v1.

If an implementation proposal requires a schema change, stop and document why
the existing fields and local preference state are insufficient before editing
the schema.

---

## 6. Thresholds and refresh policy

Extend the existing centralized thresholds:

```swift
enum SoundPrintProfileThresholds {
    static let earlySignalMinimumLogCount = 3
    static let personaMinimumLogCount = 5
    static let fullerProfileMinimumLogCount = 10
    static let whatsChangingMinimumLogCount = 20

    static let reflectionRefreshLogIncrement = 5
}
```

`personaMinimumLogCount` remains the persistence/internal name for compatibility.
The UI calls this the first-reflection threshold.

### 6.1 Derived values

For a current record:

```swift
newLogCount = max(0, currentLogCount - persona.logCountAtGeneration)
```

A normal update is eligible when:

```swift
newLogCount >= SoundPrintProfileThresholds.reflectionRefreshLogIncrement
```

### 6.2 History mutation flag

Count alone cannot reliably detect every edit/delete combination. Add a
non-SwiftData local preference:

```swift
enum SoundPrintPreferenceKey {
    static let preferAppleIntelligence = "soundPrint.preferAppleIntelligence"
    static let personaTone = "soundPrint.personaTone" // legacy read compatibility
    static let reflectionNeedsRefresh = "soundPrint.reflectionNeedsRefresh"
}
```

Set `reflectionNeedsRefresh` to `true` when:

- An existing log is edited after a reflection exists.
- A log is deleted after a reflection exists.

Do not set it for a newly created log; new-log cadence is derived from
`logCountAtGeneration`.

Set it to `false` when:

- A new reflection is successfully persisted.
- No reflection exists.
- Total log count falls below the first-reflection threshold and the old
  artifact is invalidated.

This flag is a local cache invalidation hint, not user data and not a second
source of reflection content.

---

## 7. Reflection state model

Create a small pure state resolver under the SoundPrint service or Profile
feature area. Suggested name:

```text
Listend/Listend/Services/SoundPrint/SoundPrintReflectionStatus.swift
```

Suggested types:

```swift
struct SoundPrintReflectionStatus: Equatable {
    enum Phase: Equatable {
        case collecting
        case readyToCreate
        case current
        case readyToUpdate
    }

    enum UpdateReason: Equatable {
        case newLogs(Int)
        case historyChanged
    }

    let phase: Phase
    let logCount: Int
    let requiredLogCount: Int
    let representedLogCount: Int?
    let newLogCount: Int
    let updateReason: UpdateReason?
}
```

Inputs:

```swift
static func resolve(
    logCount: Int,
    persona: SoundPrintPersona?,
    historyChanged: Bool
) -> SoundPrintReflectionStatus
```

Pure phase rules:

| Condition | Phase |
|---|---|
| `logCount < 5` | `collecting` |
| `logCount >= 5`, no persona | `readyToCreate` |
| Persona exists, history changed | `readyToUpdate` |
| Persona exists, current count is below represented count | `readyToUpdate` |
| Persona exists, `newLogCount >= 5` | `readyToUpdate` |
| Persona exists, otherwise | `current` |

Loading and error are coordinator overlays, not persisted phases:

- `isRebuilding == true` → generating presentation
- `lastError != nil` → error presentation while retaining the derived stable
  phase and current record

Do not put SwiftData objects directly into an `Equatable` state enum.

---

## 8. Build modes

Introduce an explicit build mode:

```swift
enum SoundPrintProfileBuildMode {
    case signalsOnly
    case generateReflection
}
```

Update the builder signature:

```swift
@MainActor
func rebuildProfile(
    in modelContext: ModelContext,
    mode: SoundPrintProfileBuildMode
) async throws
```

Avoid a default mode. Every call site should state whether it is maintaining
signals or intentionally generating user-facing prose.

### 8.1 `signalsOnly`

This mode:

1. Fetches logs.
2. Recomputes/persists dimensions, evidence, and avoidance signals.
3. Does not call `generatePersona`.
4. Does not call `generateCompactSummary`.
5. Does not replace a valid current reflection.
6. Removes/hides the current reflection if log count falls below five.

`signalsOnly` is used for:

- New log save
- Existing log edit
- Log deletion
- Other background profile maintenance

The sentiment update may continue using the configured provider before the
signals-only rebuild. The key rule is that full reflection prose is not
generated automatically.

### 8.2 `generateReflection`

This mode:

1. Requires at least five logs.
2. Rebuilds current dimensions, evidence, and avoidance signals.
3. Builds bounded `PersonaInput`.
4. Calls `generatePersona`.
5. Applies the existing builder-level validation gate.
6. Persists only a validated result.
7. Clears `reflectionNeedsRefresh` after persistence succeeds.
8. May attempt compact-summary generation as optional legacy enrichment.

If the primary reflection fails, throw a user-presentable builder error to the
coordinator rather than swallowing it.

Suggested error:

```swift
enum SoundPrintProfileBuildError: Error {
    case insufficientLogs
    case invalidReflection
    case unavailable
}
```

Provider-specific errors should remain wrapped or mapped before they reach UI
copy.

---

## 9. Coordinator changes

Keep `SoundPrintProfileRefreshCoordinator` as the app-scoped concurrency gate.

Recommended public API:

```swift
@Observable
@MainActor
final class SoundPrintProfileRefreshCoordinator {
    private(set) var isRebuilding = false
    private(set) var lastError: String?

    func processSavedLog(
        _ log: LogEntry,
        mutation: SoundPrintLogMutation,
        in modelContext: ModelContext,
        provider: SoundPrintProvider
    ) async

    func processDeletedLog(
        in modelContext: ModelContext,
        provider: SoundPrintProvider
    ) async

    func generateReflection(
        in modelContext: ModelContext,
        provider: SoundPrintProvider
    ) async
}

enum SoundPrintLogMutation {
    case created
    case updated
}
```

Behavior:

- `processSavedLog(.created)` updates sentiment and runs `signalsOnly`.
- `processSavedLog(.updated)` marks history changed, updates sentiment, and runs
  `signalsOnly`.
- `processDeletedLog` marks history changed and runs `signalsOnly`.
- `generateReflection` runs `generateReflection` mode and clears the history
  flag only after success.

### 9.1 Concurrency

Retain the current single-rebuild gate.

For background signal work:

- Coalesce repeated requests using the existing `needsAnotherRefresh` behavior.

For explicit generation:

- Ignore or disable duplicate user requests while one is active.
- Do not downgrade an explicit generation request to a signals-only repeat.
- If a signals-only rebuild is active when the user requests generation, queue
  one explicit generation pass after it.

If the existing boolean queue cannot preserve requested mode, replace it with a
small pending-mode value:

```swift
private var pendingMode: SoundPrintProfileBuildMode?
```

Merge rule:

```text
generateReflection outranks signalsOnly
```

Do not introduce actors, task registries, or a general job scheduler for this
feature.

### 9.2 Cancellation

- Propagate `CancellationError`.
- Do not convert cancellation into a local fallback output.
- Reset loading state in `defer`.
- Keep the current reflection unchanged.
- Do not show a destructive failure message for user-initiated cancellation.

---

## 10. Reflection input

Retain `PersonaInput` for the first pass.

### 10.1 Bounds

Use bounded, deterministic selection:

- At most 10 recent logs, matching the current builder
- At most 5 top dimensions
- At most 3 avoidance signals
- At most 5 top tags/reactions
- Review excerpts trimmed to a reasonable per-log limit
- Empty review/tag/track fields omitted from prompt prose

Do not pass all stored logs into a single prompt.

### 10.2 Evidence priority

Prefer source information in this order:

1. Detailed written thought plus matching reactions/track evidence
2. Canonical selected reactions
3. Rating plus a short written thought
4. Custom tags with deterministic keyword support
5. Rating-only evidence

Rating-only logs are valid but should produce fewer and more modest claims.

### 10.3 Voice

New reflection generation always uses:

```swift
let tone: SoundPrintPersonaTone = .balanced
```

Do not read `SoundPrintPersonaTone.current` for new reflections.

Preserve the enum, raw persisted value, old records, and provider signatures for
compatibility.

---

## 11. Prompt changes

Update the existing persona prompt functions rather than adding a new prompt
subsystem.

Relevant file:

```text
Listend/Listend/Services/SoundPrint/Prompts/SoundPrintPromptTemplates.swift
```

### 11.1 Instruction contract

The new `personaInstructions` should describe a listening reflection, not a
persona:

```text
You write a short reflection for a listener based only on their Listend album
journal. Observe what the current logs suggest; do not define the listener's
identity.
```

Required rules:

- Address the listener as `you`.
- One or two short paragraphs.
- Maximum 90 words.
- No more than three substantive claims.
- Name at least one supplied album, artist, reaction, or review phrase.
- Prefer relationships and tensions over lists.
- Use `so far`, `in these logs`, or similar qualification when appropriate.
- Translate internal analysis labels into normal listener language.
- Do not print internal dimension or avoidance keys.
- Do not invent music facts.
- Do not claim repeats/replays without explicit support.
- Do not mention prompts, schemas, validation, models, or personas.

### 11.2 Output format

Continue requesting plain prose from `generatePersona`.

Do not introduce JSON, `@Generable`, schemas, or guided output merely to return
one short reflection.

### 11.3 Compact summary

The primary artifact is `personaText`.

For v1:

- Compact summary generation may remain for compatibility.
- Compact summary failure must not invalidate a valid primary reflection.
- New UI must not require headline, summary, or bullets.
- Do not add a third model call.

A later cleanup may remove the compact-summary path after confirming no other
surface depends on it.

---

## 12. Validation

Update `SoundPrintOutputValidator` to enforce the reflection contract while
preserving existing grounding and banned-phrase checks.

Relevant file:

```text
Listend/Listend/Services/SoundPrint/Validation/SoundPrintOutputValidator.swift
```

Required validation:

- Non-empty trimmed text
- Maximum 90 words
- Reasonable minimum content length
- At least one concrete supplied user-facing grounding signal
- No internal analysis key or label leakage
- No banned generic phrase
- No prompt/protocol markers
- No `persona`, `the user`, or self-referential model language
- No unsupported absolute-frequency wording

Validation must remain local and deterministic.

The builder must run validation even when a provider already claims success.

---

## 13. UI implementation

### 13.1 Profile

Update:

```text
Listend/Listend/Views/Profile/ProfileView.swift
```

Keep the existing `Stats` section and `Your Taste So Far` link.

Replace the current multi-row SoundPrint section with one primary card/row
driven by `SoundPrintReflectionStatus`.

States:

**Collecting**

- Title: `SoundPrint`
- Progress: `N of 5 logs`
- Description: reflection forms from ratings, reactions, and notes
- No Home module

**Ready to create**

- Title: `Your first SoundPrint is ready`
- Button: `Create my SoundPrint`
- Shows Apple Intelligence availability only as supporting status

**Current**

- Title: `SoundPrint Reflection`
- Short excerpt
- Source badge
- `Based on N logs`
- Link to detail
- Optional `N new logs since this reflection`

**Ready to update**

- Keep current excerpt
- Add `Your SoundPrint is ready for an update`
- Button: `Update my SoundPrint`

Keep settings reachable from the reflection detail or a secondary navigation
link. Do not keep a separate high-prominence settings row beside the artifact.

Stable identifiers:

```text
soundPrintReflectionCard
soundPrintProgressText
createSoundPrintButton
updateSoundPrintButton
soundPrintGenerationProgress
soundPrintGenerationError
soundPrintReflectionLink
```

### 13.2 Reflection detail

Rework the existing:

```text
Listend/Listend/Views/Profile/SoundPrintProfileView.swift
```

The Swift type may keep its current name. Change user-facing title to:

```text
SoundPrint Reflection
```

Recommended layout:

1. Reflection card
   - Generated text
   - Generation date
   - `Based on N logs`
   - Generation source badge
2. Freshness/update card when needed
3. `What you're rewarding`
   - Top grounded dimension summaries
   - Disclosed receipts
4. `What tends to lose you`
   - Only when avoidance evidence exists and the fuller-profile threshold is met
5. Privacy footer
6. Secondary route to SoundPrint settings

Remove from the primary detail:

- `Persona` heading
- `How SoundPrint sees your taste`
- Persona tone badge
- Weight bars
- Strength bars
- Confidence bars
- Raw percentages
- Duplicate compact-summary card when it restates the reflection

Keep:

- Reader-facing dimension labels and summaries
- Receipt disclosure rows
- Album, artist, rating, and source snippets
- Existing handling when an original log is unavailable

### 13.3 Home

Update:

```text
Listend/Listend/Views/Home/HomeView.swift
```

Rules:

- No SoundPrint module when no valid record exists.
- No locked progress card.
- Existing current records may show one compact module.
- Rename the module heading to `SoundPrint Reflection`.
- Prefer a compact excerpt of `personaText`; use legacy headline only when useful.
- Keep the generation source badge.
- Remove persona tone badge.
- Keep existing navigation behavior unless a small, reliable direct detail route
  already exists.

### 13.4 Settings

Update:

```text
Listend/Listend/Views/Profile/SoundPrintSettingsView.swift
```

Keep:

- Apple Intelligence availability
- `Prefer Apple Intelligence` toggle
- Last generator status
- Explicit retry/update action when eligible

Remove from normal user-facing settings:

- Persona tone picker
- Instructions implying that a preference change immediately regenerates
  SoundPrint

Do not remove:

- `SoundPrintPersonaTone` enum
- `toneRawValue`
- Compatibility decoding
- Tests that prove old values still load

### 13.5 Generator badge

Continue using:

```text
Listend/Listend/Views/Shared/SoundPrintGenerationSourceBadge.swift
```

Labels remain:

- `Apple Intelligence`
- `Local fallback`
- `SoundPrint unavailable` where applicable

Unknown source remains self-hiding for legacy records.

---

## 14. Save, edit, and delete integration

### 14.1 New log

In `LogEntryEditorView`:

1. Persist the log immediately.
2. Dismiss/complete the save flow normally.
3. Call `processSavedLog(... mutation: .created)`.
4. Update sentiment and signals.
5. Do not generate/replace reflection prose.

### 14.2 Existing log edit

In `LogEntryEditorView`:

1. Persist the edit.
2. Mark reflection history dirty if a reflection exists.
3. Call `processSavedLog(... mutation: .updated)`.
4. Keep current reflection until explicit update.

### 14.3 Delete

In `LogEntryDetailView`:

1. Delete and save through the existing path.
2. Mark reflection history dirty if a reflection exists.
3. Run signals-only rebuild.
4. If the remaining log count is below five, invalidate the current artifact.
5. Do not automatically generate replacement prose.

### 14.4 Share extension

New logs arriving through the shared store naturally change the log count.

No Share extension Foundation Models integration is required.

If the main app does not immediately rebuild signals after an extension save,
retain the current shared-store refresh behavior; do not add background
cross-process generation.

---

## 15. Failure behavior

### 15.1 Foundation Models unavailable

The provider factory and fallback remain authoritative.

Expected results:

- Eligible physical device and valid output → `.foundationModels`
- Simulator/UI tests → `.localFallback`
- Unsupported/disabled device → `.localFallback`
- Primary failure with valid fallback → `.localFallback`

The UI displays the actual result source.

### 15.2 Invalid output

- Reject locally.
- Allow the provider's existing bounded retry/fallback behavior.
- Never persist invalid prose.
- Keep the current record.
- Show a retryable, reader-friendly error when no provider returns a valid
  reflection.

### 15.3 Signal rebuild failure

- Preserve the last valid reflection and previously persisted profile data where
  possible.
- Do not delete existing dimensions before all replacement signal values are
  ready.
- If the current implementation already computes pending values before
  replacement, retain that behavior.

### 15.4 Compact-summary failure

- Keep the valid primary reflection.
- Do not show an error solely because optional legacy compact enrichment failed.
- Do not display stale compact fields as if they belong to a newly generated
  reflection; clear or hide them when their generation does not succeed.

---

## 16. Backward compatibility

### 16.1 Existing personas

Existing `SoundPrintPersona` rows should display as current reflections when:

- Log count is still at least five.
- `personaText` passes basic display safety.

The first new explicit update rewrites the text using reflection prompts and
balanced tone.

### 16.2 Existing source metadata

- `nil` or invalid source maps to `.unknown`.
- Unknown source badge remains hidden.
- Existing source-refresh logic must not automatically regenerate reflection
  prose merely to populate missing metadata.

If metadata backfill is required, it must be a separate explicit operation or
remain unknown.

### 16.3 Existing tone metadata

- Old `analyst` or `wrapped` records remain readable.
- Do not show tone badges on new primary surfaces.
- New generations persist `.balanced`.

### 16.4 Existing compact summaries

Existing headline/summary/bullets may remain stored.
The new detail UI does not need to display them.

---

## 17. Test plan

Prefer pure unit tests for policy/state, provider doubles for orchestration, and
one focused UI flow. Do not require physical Apple Intelligence in automated
tests.

### 17.1 New state tests

Suggested file:

```text
Listend/ListendTests/SoundPrintReflectionStatusTests.swift
```

Test:

- 0 logs → collecting, 5 required
- 4 logs → collecting with accurate progress
- 5 logs and no record → ready to create
- Current record at 5 logs and total 5 → current
- Record at 5 and total 9 → current with 4 new
- Record at 5 and total 10 → ready to update with 5 new
- History dirty → ready to update before five new logs
- Total count below represented count → ready to update or collecting when
  below threshold
- Successful generation inputs reset new count through persisted
  `logCountAtGeneration`

### 17.2 Builder tests

Add focused tests proving:

- `signalsOnly` persists dimensions/evidence but never calls
  `generatePersona`.
- `signalsOnly` never changes an existing valid reflection.
- `generateReflection` calls generation exactly once.
- `generateReflection` requires five logs.
- A valid result updates text, source, date, and represented log count.
- An invalid or throwing result preserves the previous record.
- A valid primary reflection survives compact-summary failure.
- Below-threshold history invalidates/hides the artifact.
- Successful generation uses `.balanced` regardless of legacy tone preference.
- Successful generation clears the history-dirty preference.

Use a recording provider rather than inspecting Foundation Models directly.

### 17.3 Coordinator tests

Test:

- Created log selects `signalsOnly`.
- Updated log marks history dirty and selects `signalsOnly`.
- Delete marks history dirty and selects `signalsOnly`.
- Explicit create/update selects `generateReflection`.
- Duplicate explicit requests coalesce.
- Explicit generation outranks a queued signals-only request.
- Cancellation does not fall back or set destructive error state.

### 17.4 Prompt and validator tests

Test:

- Prompt frames output as a reflection, not a persona.
- Prompt includes bounded evidence.
- Valid grounded reflection passes.
- More than 90 words fails.
- Internal keys fail.
- Generic banned language fails.
- Ungrounded prose fails.
- `the user`, prompt leakage, and model self-reference fail.
- Qualified, evidence-backed language passes.

### 17.5 UI tests

Use mock data and existing UI-test store patterns.

Test one primary journey:

1. Seed five eligible logs and no reflection.
2. Open Profile.
3. Confirm `Create my SoundPrint`.
4. Tap create.
5. Confirm generated reflection appears.
6. Confirm `Local fallback` in UI-test mode.
7. Confirm `Based on 5 logs`.
8. Open detail.
9. Confirm at least one receipt section.

Add small state assertions for:

- No Home card before generation
- Home card after generation
- Update action after a seeded ten-log/current-at-five state
- Existing reflection remains visible after a simulated generation failure

Do not add broad screenshot testing unless requested.

### 17.6 Existing regression tests

The following existing areas must stay green:

- Reaction integration tests
- Taste Insights tests
- SoundPrint provider/fallback tests
- SoundPrint source metadata tests
- Receipt display tests
- Journal Assist tests
- Today’s Pick tests
- Shared-store logging tests

---

## 18. Validation commands

Use an available simulator name from the current Xcode environment. Existing
project conventions use `iPhone 17` when available.

### 18.1 Focused tests

```bash
xcodebuild test \
  -project Listend/Listend.xcodeproj \
  -scheme Listend \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ListendTests/SoundPrintReflectionStatusTests
```

Run the relevant existing SoundPrint suite or test target after focused tests.
Treat a run reporting zero executed tests as inconclusive.

### 18.2 Build

```bash
xcodebuild \
  -project Listend/Listend.xcodeproj \
  -scheme Listend \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

### 18.3 Patch hygiene

```bash
git diff --check
```

### 18.4 Foundation Models source scan

Mandatory when any Foundation Models or prompt/validator file changes:

```bash
scripts/check-foundationmodels-symbols.sh
```

### 18.5 Release binary scan

Before TestFlight:

1. Build/archive the Release product.
2. Scan the actual app binary.

```bash
nm -u /path/to/Listend.app/Listend \
  | rg 'Generable|promptRepresentation|generatedContent|GenerationSchema|respond.*generating'
```

The scan must return no guided-generation symbol hits.

---

## 19. Physical-device test plan

Automated tests cannot prove Foundation Models runtime behavior.

On an iOS 26 physical device with Apple Intelligence available:

1. Install a fresh TestFlight or device build.
2. Confirm app launch does not crash.
3. Reach five logs without automatic reflection generation.
4. Select `Create my SoundPrint`.
5. Confirm output appears and source says `Apple Intelligence`.
6. Confirm the output is under 90 words and grounded in visible receipts.
7. Confirm no internal analysis labels appear.
8. Save one more log and confirm the reflection remains unchanged.
9. Reach five new logs and confirm update availability.
10. Trigger an update and confirm the old artifact remains until success.
11. Edit an older log and confirm update availability.
12. Disable Apple Intelligence preference and confirm the local fallback remains
    clearly labeled.
13. Re-enable the preference and confirm no automatic replacement occurs.
14. Confirm Journal Assist and reaction resolution still work.
15. Capture logs for any Foundation Models failure while verifying saved journal
    data remains intact.

On Simulator:

- Confirm all states and UI using deterministic mock/local output.
- Do not claim Simulator validation proves Apple Intelligence generation.

---

## 20. Implementation sequence

Implement as small reviewable phases.

### Phase A — State and generation policy

Files:

```text
SoundPrintProfileThresholds.swift
SoundPrintReflectionStatus.swift (new)
SoundPrintProfileBuilder.swift
SoundPrintProfileRefreshCoordinator.swift
LogEntryEditorView.swift
LogEntryDetailView.swift
SoundPrintSettings.swift
```

Deliver:

- Pure reflection status
- Five-log refresh increment
- Signals-only versus explicit-generation modes
- History dirty flag
- Non-destructive failure behavior
- Focused state/builder/coordinator tests

Do not change visual layout beyond what is necessary to expose a temporary
create/update action for testing.

### Phase B — Product surfaces

Files:

```text
ProfileView.swift
SoundPrintProfileView.swift
SoundPrintSettingsView.swift
HomeView.swift
SoundPrintGenerationSourceBadge.swift (only if copy needs adjustment)
UI tests and previews
```

Deliver:

- Consolidated Profile entry
- Reflection detail copy/layout
- Grounded evidence without technical metric bars
- Compact post-generation Home card
- Secondary settings placement
- Tone UI removal from primary surfaces

Do not change prompts in this phase.

### Phase C — Reflection prompt and validation

Files:

```text
SoundPrintPromptTemplates.swift
FoundationModelsSoundPrintProvider.swift (only if needed)
SoundPrintOutputValidator.swift
MockSoundPrintProvider.swift
Focused prompt/validator/provider tests
```

Deliver:

- Reflection language contract
- 90-word validation
- Grounding validation
- Balanced voice
- Deterministic fallback parity
- Foundation Models source scan
- Release build and binary scan
- Physical-device checklist

Do not introduce guided output or a new provider protocol.

---

## 21. Expected file impact

Expected modifications:

```text
Listend/Listend/Services/SoundPrint/SoundPrintProfileThresholds.swift
Listend/Listend/Services/SoundPrint/SoundPrintProfileBuilder.swift
Listend/Listend/Services/SoundPrint/SoundPrintProfileRefreshCoordinator.swift
Listend/Listend/Services/SoundPrint/SoundPrintSettings.swift
Listend/Listend/Services/SoundPrint/Prompts/SoundPrintPromptTemplates.swift
Listend/Listend/Services/SoundPrint/Validation/SoundPrintOutputValidator.swift
Listend/Listend/Services/SoundPrint/MockSoundPrintProvider.swift
Listend/Listend/Views/Profile/ProfileView.swift
Listend/Listend/Views/Profile/SoundPrintProfileView.swift
Listend/Listend/Views/Profile/SoundPrintSettingsView.swift
Listend/Listend/Views/Home/HomeView.swift
Listend/Listend/Views/LogEntry/LogEntryEditorView.swift
Listend/Listend/Views/LogEntry/LogEntryDetailView.swift
Listend/ListendTests/
Listend/ListendUITests/
```

Expected new file:

```text
Listend/Listend/Services/SoundPrint/SoundPrintReflectionStatus.swift
```

Files that should not require modification:

```text
Listend/ListendShared/Models/LogEntry.swift
Listend/ListendShared/Models/SoundPrintPersona.swift
Listend/ListendShared/Persistence/ListendModelSchema.swift
Listend/Listend/Views/Profile/TasteInsights.swift
Listend/Listend/Views/Profile/TasteInsightsView.swift
Listend/Listend/Services/Recommendation/
Listend/ListendShared/Resources/Taxonomy/
ListendShareExtension/
```

If implementation expands materially beyond this list, stop and explain why.

---

## 22. Do-not-change constraints

- Do not modify the SwiftData schema.
- Do not add a new reflection model.
- Do not create a second taste-insight service.
- Do not rename all persona types in the first pass.
- Do not make reactions or reviews required.
- Do not block Save on sentiment, signals, or generation.
- Do not auto-generate reflection prose after every log.
- Do not erase the current reflection before a replacement validates.
- Do not remove deterministic fallback.
- Do not label fallback output as Apple Intelligence.
- Do not add Foundation Models to the Share extension.
- Do not change Today’s Pick ranking, eligibility, or active-pick behavior.
- Do not change reaction taxonomy data.
- Do not reintroduce guided structured-output APIs.
- Do not treat a zero-test run as successful verification.
- Do not overwrite unrelated local work.

---

## 23. Coding-agent execution contract

The implementation agent should begin with:

1. `git status --short --branch`
2. A concise architecture summary based on the files in Section 3
3. The selected implementation phase
4. A list of files it expects to touch

During implementation:

- Preserve unrelated dirty files and user changes.
- Use the existing patterns before introducing abstractions.
- Keep every phase compile-safe.
- Add tests with each behavior change.
- Do not commit or push unless explicitly asked.

At handoff, report:

- Phase completed
- Changed files
- Behavior before and after
- Tests executed and exact executed-test counts when available
- Build result
- `git diff --check` result
- Foundation Models source/symbol scan result when applicable
- Physical-device validation still required
- Any deviation from this specification

Recommended agent prompt:

> Read the SoundPrint Reflection requirements and technical specification in
> full. Inspect the current implementation before editing. Implement only the
> selected phase using the existing SoundPrint provider, persistence, receipts,
> and fallback architecture. Preserve logging and Today’s Pick behavior. Do not
> add a SwiftData model or guided Foundation Models API. Add focused tests and
> report exact validation evidence.
