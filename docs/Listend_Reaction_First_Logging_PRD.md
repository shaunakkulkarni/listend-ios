# Listend Reaction-First Logging & Canonical Tagging

**Document type:** Product Requirements Document
**Status:** Draft for implementation
**Version:** 1.0
**Date:** July 27, 2026
**Product:** Listend for iOS
**Feature area:** Album logging, canonical tags, SoundPrint, Journal Assist, Today’s Pick
**Priority:** High
**Target:** iOS 26.4+
**Design system:** Midnight Vinyl
**Repository:** https://github.com/shaunakkulkarni/listend-ios

---

## 1. Executive summary

Listend will rework album logging around **structured listener reactions** instead of asking users to begin with an open-ended review or a comma-separated tag field.

After rating an album, users will see a small, relevant set of reaction chips covering mood, energy, sonic character, craft, listening context, personal response, and criticism. Users can quickly select the reactions that fit, browse the complete taxonomy through a grouped **More** sheet, preserve their own custom language, and optionally turn selected reactions into a short journal entry with Journal Assist.

This feature introduces two interoperable catalogs:

1. **Genre & Style Catalog** — normalizes album metadata and supports appropriate catalog queries.
2. **Reaction Tag Catalog** — captures how the listener personally experienced the album.

The feature must remain:

- Local-first
- Fully usable without Apple Intelligence
- Compatible with the current SwiftData schema
- Shared between the main app and Apple Music Share extension
- Safe on iOS 26 using Listend’s existing plain-text Foundation Models path
- Incremental and reviewable, without rewriting unrelated logging or recommendation systems

---

## 2. Companion artifacts

Codex should treat these files as the source of truth for the taxonomy:

- `Listend/ListendShared/Resources/Taxonomy/Listend_Reaction_Tags_v1.json`
- `Listend/ListendShared/Resources/Taxonomy/Listend_Genre_Styles_v1.json`
- `Listend/ListendShared/Resources/Taxonomy/Listend_Ambiguous_Aliases_v1.json`
- `docs/Listend_Canonical_Taxonomy_Spec_v1.md`
- `docs/Listend_Taxonomy_Validation_Report_v1.txt`

Current catalog totals:

- **243 canonical reaction tags**
- **355 genre and style definitions**
- **723 deterministic reaction aliases**
- **20 explicitly ambiguous terms**
- **169 reaction tags eligible for primary suggestions**
- **20 genre families**

The JSON catalogs should not be casually rewritten or reduced during implementation. Any proposed taxonomy changes should be called out separately.

---

## 3. Current product state

### 3.1 Logging

The current logger includes:

- Album context
- Required half-star rating
- Open-ended review field
- Reflection prompt chips
- Journal Assist
- Free-form comma-separated tags
- Suggested tag chips
- Optional track highlights
- Save once album and rating are present

The existing ability to save a rating-only log is correct and must remain.

### 3.2 Tag persistence

`LogEntry` currently persists tags as a JSON-encoded array of strings through `tagsRawValue`, exposed as `[String]` through the `tags` computed property.

This means the first version can introduce canonical reaction tags and custom tags **without a SwiftData migration**.

### 3.3 Current suggestions

The current deterministic tag engine:

- Uses album genre
- Uses a small set of review keyword rules
- Returns up to six suggestions
- Includes broad genre tags
- Is used directly by the main logging flow and Share extension

The app also has a Foundation Models-backed tag provider, but the automatic visible suggestion chips currently use the local engine directly.

### 3.4 Foundation Models

Listend currently uses an iOS 26-safe Foundation Models approach:

```swift
let session = LanguageModelSession(instructions: instructions)
let response = try await session.respond(to: prompt)
```

The shipping app must not reintroduce guided structured-output APIs such as `@Generable`, `@Guide`, or newer schema-driven generation overloads.

### 3.5 Shared app architecture

The main app and Share extension use:

- Shared models
- Shared SwiftData schema
- Shared production store
- Shared normalizers and logging helpers

The taxonomy domain should therefore live in `ListendShared`, while the Foundation Models implementation remains in the main app target.

---

## 4. User problem

Listeners often know their reaction to an album but struggle to immediately explain it in polished prose.

They may think:

- “This was hype.”
- “The production felt icy.”
- “The bars were the best part.”
- “Perfect for a night drive.”
- “The middle dragged.”
- “I need to hear it again.”
- “The sound was great, but the hooks were weak.”

The current experience asks the user to translate those instincts into either:

- An open-ended review, or
- An unstructured comma-separated tag list

This creates several problems:

1. Users may abandon the log after rating.
2. Genre becomes a substitute for personal reaction.
3. Similar reactions fragment across inconsistent wording.
4. Negative reactions are under-captured.
5. SoundPrint receives weak or generic evidence.
6. Journal Assist has too little user-authored context.
7. Free-form custom language is useful but difficult to analyze consistently.

---

## 5. Product hypothesis

If Listend presents a small number of relevant reaction choices immediately after rating, users will create more meaningful logs with less effort.

A useful log should be possible in three actions:

1. Rate the album.
2. Select one or more reactions.
3. Save.

Written reflection, track highlights, and AI assistance remain optional enhancements.

---

## 6. Goals

### 6.1 Primary goals

- Reduce the effort required to explain why an album worked or did not work.
- Increase the percentage of logs containing useful taste evidence.
- Make reaction data more consistent without erasing personal language.
- Improve SoundPrint’s reward and avoidance signals.
- Preserve fast rating-only logging.
- Keep logging functional when Foundation Models are unavailable.

### 6.2 Secondary goals

- Improve Journal Assist grounding.
- Reduce synonymous tag fragmentation.
- Improve Today’s Pick inputs without sending unsuitable context tags into MusicKit searches.
- Use the same canonical vocabulary in the main app and Share extension.
- Establish a reusable semantic layer for future taste insights.

---

## 7. Non-goals

This feature will not:

- Require tags or written reviews.
- Replace ratings.
- Analyze album audio.
- Claim that moods or activities are objective album facts.
- Automatically rewrite a user’s custom phrase.
- Add public, social, or trending hashtags.
- Add a new SwiftData relationship model in the first release.
- Add Foundation Models generation to the Share extension in the first release.
- Create a SoundPrint dimension for every reaction tag.
- Fully personalize rankings in the first phase.
- Generate a full critic-style review without meaningful user input.
- Display the entire taxonomy at once.
- Perform network-based semantic matching or embeddings.

---

## 8. Product principles

### 8.1 Reaction-first, not review-first

The first prompt after rating should help the user name their immediate reaction. Writing comes afterward.

### 8.2 Genre is not a reaction

Genre describes what the release is. Reactions describe what it did for the listener.

Example:

**Metadata**

- Hip-hop

**Listener reactions**

- Hype
- Bars
- Cold production
- Night drive
- Replayable

### 8.3 Personal language remains valid

Canonical tags organize taste. They should not make users feel corrected.

### 8.4 AI is optional assistance

The model may interpret unfamiliar phrases, but deterministic behavior and custom-tag preservation are mandatory.

### 8.5 Saving never waits for AI

The Save action remains available once the album and rating are selected.

### 8.6 Negative evidence matters

Listend should make it as easy to capture:

- Bloated
- Repetitive
- Weak hooks
- Poor sequencing

as it is to capture:

- Hype
- Catchy
- Cohesive
- No skips

---

## 9. Target users and jobs to be done

### 9.1 Quick logger

**Job:** “Help me record what I felt about this album without making me write an essay.”

### 9.2 Reflective journaler

**Job:** “Help me turn my first reactions into a personal journal entry.”

### 9.3 Taste explorer

**Job:** “Use the details in my logs to reveal what I consistently reward or reject.”

### 9.4 Share-sheet logger

**Job:** “Let me quickly log an Apple Music album without losing the same vocabulary and structure I get in the main app.”

---

## 10. Core user stories

- As a listener, I want to select a few reactions so I can create a meaningful log without writing a review.
- As a listener, I want the reaction choices to change based on whether I liked or disliked the album.
- As a listener, I want to browse reactions by category when the first suggestions do not fit.
- As a listener, I want to search using slang or my own words.
- As a listener, I want to keep a phrase even when Listend cannot map it to a canonical tag.
- As a listener, I want Listend to help clarify an ambiguous phrase without silently changing it.
- As a listener, I want selected reactions to help Journal Assist write a grounded personal reflection.
- As a listener, I want my repeated reactions to improve SoundPrint and recommendations over time.
- As a Share-extension user, I want the same canonical vocabulary without requiring Apple Intelligence.

---

## 11. Proposed logging experience

### 11.1 Album and rating

The existing album context remains at the top.

Rating remains required.

After a rating is selected, reveal the reaction section.

### 11.2 Adaptive prompt

#### Rating 4.0–5.0

> **What made it hit?**

Prioritize positive mood, craft, sound, context, and replay reactions.

#### Rating 3.0–3.5

> **What worked—and what didn’t?**

Show a balanced mix of positive, mixed, and critical reactions.

#### Rating 0.5–2.5

> **What lost you?**

Prioritize friction and avoidance tags while still allowing positive exceptions.

These prompts affect ranking only. Every category remains available through More.

### 11.3 Primary suggestion row

Show a maximum of **six** reaction chips plus **More**.

Example for a highly rated hip-hop album:

- Hype
- Bars
- Hooks
- Bass-heavy
- Confident
- Replayable
- More

Users can:

- Select a chip
- Deselect a chip
- Open More
- Save without choosing any chip

### 11.4 More sheet

Present a sheet with:

- Search field
- Selected reactions section
- Grouped category sections
- Custom-tag action
- Optional semantic-resolution action when local search finds no good result

Categories must match the reaction JSON:

1. Mood & Vibe
2. Energy & Movement
3. Sonic Character
4. Craft & Performance
5. Listening Context
6. Personal Reaction
7. Friction & Critique

### 11.5 Optional written reflection

Below reactions, show a collapsed action such as:

> **Add a thought**

Opening it reveals the existing review field.

The prompt may adapt to selected reactions.

Example:

Selected:

- Bars
- Cold production
- Replayable

Prompt:

> What about the writing or production kept pulling you back?

### 11.6 Journal Assist

Journal Assist should use selected reactions as user-authored evidence.

It may help create a short journal starter, but must not invent:

- Lyrics
- Specific production details
- Track moments
- Listening situations
- Emotional claims not supplied by the user

### 11.7 Track highlights

Favorite tracks, weaker tracks, and standout moments remain optional and collapsed by default.

This feature should not rewrite the existing track-highlight system.

### 11.8 Save behavior

A log is saveable when:

- An album is selected.
- A rating is selected.

All other fields remain optional.

---

## 12. Taxonomy model

### 12.1 Genre and style catalog

The genre catalog normalizes metadata from Apple Music and future services.

It may also provide appropriate search terms for recommendation candidate discovery.

Genre is not shown as part of the reaction taxonomy unless the user is explicitly viewing album metadata.

### 12.2 Reaction catalog

The reaction catalog captures the user’s subjective experience.

Each reaction entry includes:

```swift
struct ReactionTagDefinition: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let category: ReactionTagCategory
    let definition: String
    let aliases: [String]
    let polarity: ReactionTagPolarity
    let genreAffinityFamilies: [String]
    let soundPrintDimensions: [String]
    let avoidanceSignals: [String]
    let recommendationRole: RecommendationTagRole
    let isPrimarySuggestion: Bool
}
```

### 12.3 Canonical ID rules

Canonical IDs must:

- Be unique
- Be stable after release
- Use a namespaced form such as `mood.hype`
- Never be generated dynamically
- Never be accepted from model output without validation
- Be treated as implementation identifiers, not user-facing copy

### 12.4 Display-name rules

Display names must:

- Be globally unique after normalization
- Be 28 characters or fewer
- Contain no commas or line breaks
- Preserve intentional punctuation and diacritics
- Be understandable without category context where practical
- Avoid duplicating a different semantic concept

Examples:

- `warm`
- `warm production`
- `dark`
- `dark production`
- `emotionally raw`
- `raw vocals`
- `raw production`
- `driving`
- `propulsive`

### 12.5 Alias rules

Aliases support:

- Synonyms
- Slang
- Alternate punctuation
- Common misspellings
- Regional phrasing
- Search-oriented language

Aliases are not independently persisted as analytics concepts.

Example:

```text
Canonical: hype
Aliases:
- turnt
- amped
- fired up
- goes hard
```

### 12.6 Ambiguous terms

The ambiguous-alias JSON explicitly defines terms that may reasonably mean several things.

Example:

```text
icy
→ cold production
→ confident
→ menacing
```

Listend must show choices instead of selecting one silently.

### 12.7 Display and comparison normalization

Use separate values:

**Display value**

- Preserve accents and intentional punctuation.
- Trim leading/trailing whitespace.
- Collapse repeated whitespace.

**Comparison key**

- Lowercase
- Diacritic-insensitive
- Normalize dash variants
- Collapse whitespace
- Use for deduplication, alias lookup, and exact matching

Do not use the comparison key as the user-facing label.

---

## 13. Suggested-reaction ranking

### 13.1 MVP ranking inputs

The local deterministic ranker may use:

- Rating
- Album genre family
- Existing review text
- Already selected reactions
- Tag polarity
- Genre affinity
- Primary-suggestion eligibility
- Category diversity

### 13.2 Ranking requirements

The first six suggestions should:

- Exclude already selected tags.
- Avoid duplicates.
- Respect rating direction.
- Include multiple categories where possible.
- Avoid six near-synonyms.
- Prefer understandable, commonly useful tags.
- Avoid unsupported claims based solely on title or artist.
- Use genre affinity as a weak prior, not certainty.

### 13.3 Recommended initial scoring

A clean initial scoring approach:

- Base score for `isPrimarySuggestion`
- Rating/polarity compatibility bonus
- Genre-family affinity bonus
- Review keyword or exact alias bonus
- Existing-user-input relevance bonus
- Category-diversity bonus during final selection
- Duplicate or near-synonym penalty
- Already-selected exclusion

Exact weights are implementation details and should be testable constants.

### 13.4 Metadata limitations

Current album metadata does not establish:

- Mood
- Lyrical quality
- Production texture
- Activity fit
- Emotional impact
- Replay value

Suggestions should be framed as:

> **Does any of this fit?**

not:

> **This album is hype and bass-heavy.**

---

## 14. Local search and custom tags

### 14.1 Search order

When a user enters a phrase:

1. Exact canonical display-name match
2. Explicit ambiguous-alias lookup
3. Exact nonambiguous alias match
4. Prefix/token search
5. Lightweight spelling similarity
6. Optional Foundation Models resolution
7. Preserve as custom

An explicitly ambiguous term must not also appear in a reaction tag’s exact-alias list. Catalog validation must reject that overlap so ambiguity prompts cannot be bypassed by an earlier exact match.

### 14.2 Local-first behavior

Local search must be instant and available:

- On all supported devices
- In the Simulator
- In UI tests
- In the Share extension
- When Apple Intelligence is unavailable

### 14.3 Custom tags

Users may always keep a custom phrase.

The first release persists either:

- The canonical display value, or
- The custom display value

The first release does not persist a hidden custom-to-canonical association.

### 14.4 Reopening existing logs

When editing an existing log:

- Exact canonical display names may restore as canonical selections.
- Unknown values remain custom.
- An alias-shaped custom value must not be silently remapped.

If a user intentionally saved `floaty`, it must remain `floaty` when reopened.

---

## 15. Foundation Models semantic resolver

### 15.1 Purpose

Foundation Models may interpret an unfamiliar phrase and compare it with a locally supplied candidate set.

This is a **constrained classifier**, not a free-form tag generator.

### 15.2 Dedicated protocol

Use a dedicated abstraction rather than overloading the current tag-suggestion provider:

```swift
protocol ReactionTagResolving {
    func resolve(
        _ input: ReactionTagResolutionInput
    ) async throws -> ReactionTagResolution
}
```

Suggested implementations:

- `LocalReactionTagResolver`
- `FoundationModelsReactionTagResolver`
- `FallbackReactionTagResolver`
- `MockReactionTagResolver`

### 15.3 Invocation rules

Do not call the model:

- On every keystroke
- When an exact canonical match exists
- When an exact alias exists
- When an ambiguous alias is already defined locally
- As part of saving the log
- In the Share extension during the first release

Invoke only after explicit user action, such as:

> **Find the closest reaction**

### 15.4 Model inputs

Provide only:

- User phrase
- Current category, when known
- Rating
- Selected canonical IDs
- Short review excerpt, when present
- A locally shortlisted set of candidate IDs and definitions

Do not send:

- The full 243-tag catalog
- All 723 aliases
- The full 355-style genre catalog
- Full listening history
- Unnecessary album metadata that could encourage memorized assumptions

### 15.5 Plain-text output contract

Strong match:

```text
RESULT | MATCH
MATCH | mood.hype
```

Ambiguous match:

```text
RESULT | AMBIGUOUS
MATCH | sonic.cold-production
ALTERNATIVE | mood.confident
ALTERNATIVE | mood.menacing
```

No appropriate match:

```text
RESULT | NONE
```

### 15.6 Validation

The parser must reject:

- Unknown IDs
- IDs outside the supplied candidate set
- More than three choices
- Empty output
- Additional unsupported fields
- Malformed lines
- Duplicate results

### 15.7 User confirmation

Strong match:

> “Turnt” sounds closest to **Hype**
> Use Hype · Keep “turnt”

Ambiguous phrase:

> What does “icy” mean here?
> Cold production · Confident · Menacing · Keep “icy”

No match:

> No close match found
> Keep “graduation summer”

### 15.8 Failure behavior

If the model is:

- Unavailable
- Unsupported
- Rate-limited
- Busy
- Cancelled
- Refuses
- Produces malformed output
- Fails validation

Then:

- Preserve the user’s phrase.
- Allow it to be saved as custom.
- Do not block Save.
- Avoid exposing technical failure details unless useful.

### 15.9 iOS 26 constraints

Retain the current plain-text `respond(to:)` implementation.

Do not introduce:

- `@Generable`
- `@Guide`
- Guided structured output
- Dynamic generation schemas
- APIs that reintroduce unavailable symbols into iOS 26 builds

The existing Foundation Models symbol-scan script must continue to pass.

---

## 16. Persistence

### 16.1 MVP

Continue using the current `LogEntry.tags: [String]` behavior.

Examples:

```text
Canonical:
hype
```

```text
Custom:
graduation summer
```

No SwiftData schema change is required.

### 16.2 Future structured persistence

A later version may add a versioned representation containing:

- Canonical IDs
- Display names
- Custom values
- Mapping source
- Taxonomy version
- Category

This is outside the current scope.

---

## 17. Resource-loading architecture

Recommended placement:

```text
Listend/ListendShared/Resources/Taxonomy/
    Listend_Reaction_Tags_v1.json
    Listend_Genre_Styles_v1.json
    Listend_Ambiguous_Aliases_v1.json
```

Requirements:

- Add the resources to both `Listend` and `ListendShareExtension` target membership.
- Decode once into immutable catalog structures.
- Keep loading deterministic and offline.
- Provide dependency injection for unit tests.
- Fail loudly in debug/test when resources are invalid.
- Use a safe empty/local fallback in release rather than crashing the app.
- Do not fetch taxonomy files from a server.

Suggested shared source structure:

```text
Listend/ListendShared/Tagging/
    ReactionTagDefinition.swift
    ReactionTagCategory.swift
    ReactionTagCatalog.swift
    GenreStyleDefinition.swift
    GenreStyleCatalog.swift
    AmbiguousAliasDefinition.swift
    TagTextNormalizer.swift
    ReactionTagSearchIndex.swift
    ReactionTagRanker.swift
    ReactionTagCatalogValidator.swift
```

Foundation Models-specific files remain under the main app target.

---

## 18. SoundPrint integration

### 18.1 Existing semantic layer

The reaction JSON maps canonical tags into the existing SoundPrint dimensions:

- `emotionalDirectness`
- `energy`
- `eraAffinity`
- `experimentation`
- `genreOpenness`
- `instrumentalRichness`
- `lyricFocus`
- `mood`
- `productionStyle`
- `replayability`
- `texturePreference`
- `tracklistConsistency`
- `vocalFocus`

Avoidance signals:

- `energyWithoutPayoff`
- `fillerSensitivity`
- `lowReplayValue`
- `moodMismatch`
- `skipHeavyAlbums`
- `sterileProduction`
- `weakWriting`

### 18.2 Behavior

SoundPrint should:

1. Use direct mappings for known canonical reaction tags.
2. Continue keyword analysis for review text and custom tags.
3. Avoid mapping listening-context tags into unsupported taste dimensions.
4. Treat critique tags as avoidance evidence where the JSON specifies it.
5. Avoid creating a new dimension for every reaction tag.

Examples:

```text
bars → lyricFocus
hype → energy
cold production → productionStyle + texturePreference
no skips → tracklistConsistency + replayability
bloated → fillerSensitivity
weak writing → weakWriting
```

### 18.3 Evidence weighting

Canonical tag selection is explicit user input and may be treated as higher-confidence evidence than a loose keyword coincidence, but lower-confidence than a detailed review plus matching track evidence.

Exact weighting should be centralized and tested.

---

## 19. Today’s Pick integration

### 19.1 Problem

Today’s Pick currently uses tags as potential recommendation signals and catalog candidate queries.

A richer taxonomy introduces tags that should not become MusicKit searches:

- Gym
- Rainy day
- Heartbroken
- Bars
- No skips
- Graduation summer

### 19.2 Reaction recommendation roles

The reaction JSON defines only these allowed roles:

- `tasteSignalOnly`
- `avoidanceSignal`
- `displayOnly`

Reaction tags must not be submitted directly as catalog queries.

The Genre & Style Catalog defines `catalogQuery` entries appropriate for candidate discovery.

### 19.3 Requirements

- Only approved genre/style catalog entries become MusicKit search queries.
- Reaction tags may contribute to SoundPrint or local taste scoring.
- Avoidance tags may reduce confidence or candidate affinity where existing recommendation logic supports it.
- Display-only context tags should not influence album discovery in the first release.
- Existing Today’s Pick modes and scoring behavior must remain intact.

---

## 20. Journal Assist integration

Selected reactions should be passed to Journal Assist as user-authored context.

Requirements:

- Use the selected reaction display names.
- Keep the draft first-person and journal-native.
- Prefer one or two sentences for a quick-log starter.
- Do not invent specifics not supplied by the user.
- Do not make the feature feel like a critic review generator.
- Maintain deterministic fallback behavior.

Example input:

```text
Rating: 4.5
Reactions:
- hype
- bars
- cold production
- night drive
```

Possible draft:

> The cold production and sharp writing made this feel built for a late-night drive. It stayed energetic without losing the details that made me want to run it back.

---

## 21. Share extension

### 21.1 MVP parity

The Share extension should receive:

- Same JSON resources
- Same canonical definitions
- Same local alias lookup
- Same ambiguous alias handling
- Same local search
- Same custom-tag behavior
- Same persisted display values

### 21.2 AI scope

Foundation Models semantic matching is not required in the Share extension for the first release.

When no local match exists:

- Offer Keep as custom immediately.
- Do not block the extension.
- Preserve the fast share-sheet flow.

### 21.3 UI reuse

Where practical, extract reusable SwiftUI components and state models rather than maintaining two separate taxonomies or interaction rules.

Avoid forcing a broad rewrite of the Share extension in Phase 1.

---

## 22. Accessibility

- Every chip exposes selected/unselected state.
- Selection cannot rely on color alone.
- Chip labels remain understandable with VoiceOver.
- Category headers use proper accessibility semantics.
- Dynamic Type does not truncate critical labels.
- Search results announce exact, alias, ambiguous, or custom state where useful.
- Touch targets follow Apple guidance.
- More has a clear accessibility label and hint.
- The full flow remains completable with VoiceOver.
- Selected reactions remain discoverable without precise horizontal scrolling.
- Custom-tag confirmation provides a clear default action.

---

## 23. Privacy and trust

- Taxonomy data is bundled locally.
- User phrases are not sent to a Listend server.
- Foundation Models processing remains on-device.
- Semantic matches are suggestions, not factual classifications.
- The user confirms all model-derived associations.
- Custom language remains under the user’s control.
- The app does not expose hidden psychological claims as facts.

---

## 24. Edge cases

### Missing rating

Do not show rating-specific suggestions until a rating exists. A neutral starter set may be shown only if clearly useful.

### Missing genre

Use rating, common primary reactions, and user-entered text. Do not infer genre from artist name or album title.

### Existing custom tags

Preserve them exactly as normalized display values during editing.

### Positive reaction with low rating

Allow it. A user may dislike an album overall but admire its vocals or production.

### Critical reaction with high rating

Allow it. A great album may still be bloated or contain a weak feature.

### Unsupported language

Allow the custom phrase. Do not require an English canonical match.

### Duplicate custom/canonical value

Deduplicate using normalized comparison keys.

### Alias collision

Show explicit choices rather than picking arbitrarily.

### Long custom phrase

Apply the existing practical tag-length constraint or a clearly defined revised limit. Explain the limit inline.

### More than ten selections

Use a soft recommendation rather than blocking save unless testing establishes a strong reason.

### Taxonomy resource failure

Do not crash production. Preserve rating, review, and custom tag logging with a deterministic fallback.

### Taxonomy version changes

Do not silently rename or reinterpret persisted strings in the first release.

---

## 25. Success signals

### Primary

- Higher percentage of logs containing at least one reaction.
- Lower abandonment after rating.
- Lower median time from opening the logger to saving.
- Strong acceptance of primary suggestion chips.
- Higher SoundPrint evidence coverage per log.

### Secondary

- Increased use of craft, sound, and critique reactions.
- Reduced synonymous-tag fragmentation.
- More grounded Journal Assist drafts.
- Meaningful More-sheet engagement without excessive time spent.
- Low rate of rejected semantic matches.
- Continued use of rating-only logging.
- No regression in Share-extension completion.

Until analytics infrastructure exists, evaluate through:

- TestFlight feedback
- Moderated beta sessions
- Manual logging tasks
- Debug-only instrumentation where appropriate

---

## 26. Rollout plan

### Phase 1 — Taxonomy foundation

Deliver:

- JSON resources added to the project
- Codable models
- Shared loader
- Shared normalizer
- Exact alias resolver
- Ambiguous alias resolver
- Search index
- Catalog validator
- Unit tests

Do not change the visible logging UI yet.

**Branch:**

```text
feature/canonical-tag-taxonomy
```

**Commit:**

```text
Add canonical reaction taxonomy and validation
```

### Phase 2 — Main-app reaction picker

Deliver:

- Adaptive rating prompt
- Six primary suggestions
- Multi-select chips
- More sheet
- Category browsing
- Local search
- Custom tags
- Today’s Pick filtering that prevents reaction and custom tags from becoming raw MusicKit catalog queries
- Existing-review disclosure
- Existing track-highlight behavior preserved

The reaction picker is not launch-safe until this Today’s Pick query filter is active. Do not enable or ship the picker while the recommendation candidate provider still submits every stored tag as a catalog query.

**Branch:**

```text
feature/reaction-first-logging
```

**Commit:**

```text
Add reaction-first album logging flow
```

### Phase 3 — Downstream semantics

Deliver:

- SoundPrint direct canonical mappings
- Today’s Pick canonical taste/avoidance integration beyond the mandatory Phase 2 query filter
- Journal Assist reaction grounding
- Existing-log compatibility tests

**Branch:**

```text
feature/reaction-tag-integrations
```

**Commit:**

```text
Integrate canonical reactions with taste features
```

### Phase 4 — Foundation Models resolver

Deliver:

- Dedicated resolver protocol
- Local resolver
- Foundation Models resolver
- Fallback resolver
- Mock resolver
- Plain-text parser
- Candidate validation
- Confirmation UI
- Real-device iOS 26 testing
- Symbol-scan verification

**Branch:**

```text
feature/custom-reaction-mapping
```

**Commit:**

```text
Add on-device custom reaction matching
```

### Phase 5 — Share-extension parity and personalization

Deliver:

- Grouped local picker in Share extension
- Shared UI/state where practical
- Frequently used reactions
- User-history ranking
- Genre-specific personal ranking

Only begin personalization after the deterministic taxonomy is stable.

---

## 27. Acceptance criteria

### 27.1 Taxonomy foundation

- All companion JSON files decode successfully.
- Every canonical ID is unique.
- Every normalized display name is unique.
- All labels meet character and length rules.
- Exact aliases resolve deterministically.
- Explicitly ambiguous terms do not appear in exact-alias lists.
- Ambiguous aliases return only declared candidates.
- Every reaction has a valid category and polarity.
- Every SoundPrint mapping references an allowed dimension.
- Every avoidance mapping references an allowed signal.
- Every reaction recommendation role is allowed.
- Every genre family and parent reference is valid.
- Resources are available in the app and Share extension.
- Existing logs continue loading without migration.
- No network access is required.

### 27.2 Logging

- Album and rating remain the only required fields.
- Rating reveals the appropriate reaction prompt.
- No more than six primary suggestions are shown.
- More opens the grouped taxonomy.
- Users can select and deselect tags.
- Users can search canonical names and aliases.
- Users can save a custom phrase.
- Existing tags survive editing.
- Track highlights remain optional.
- Save never waits for AI.

### 27.3 Semantic matching

- Exact aliases do not invoke Foundation Models.
- Model calls require explicit user action.
- Model output uses the plain-text safe path.
- Unknown candidate IDs are rejected.
- Ambiguous responses show no more than three choices.
- Keep as custom is always available.
- Model failure does not block saving.
- Foundation Models structured-generation symbols remain absent.

### 27.4 SoundPrint and Today’s Pick

- Canonical reactions map only to existing dimensions/signals.
- Listening-context tags do not create unsupported dimensions.
- Reaction tags are not sent directly as MusicKit catalog queries.
- Approved genre/style entries may be used as catalog queries.
- Existing custom tags continue through the legacy keyword path.
- Existing recommendation modes and eligibility remain functional.

### 27.5 Share extension

- Uses the same taxonomy resources.
- Supports local canonical and alias search.
- Supports custom tags.
- Saves values compatible with the main app.
- Does not require Foundation Models.
- Retains the existing quick-save behavior.

---

## 28. Testing plan

### 28.1 Unit tests

Test:

- JSON decoding
- Catalog counts
- Duplicate IDs
- Duplicate normalized labels
- Invalid aliases
- Ambiguous alias candidates
- Invalid parent genre IDs
- Invalid SoundPrint references
- Invalid recommendation roles
- Display/comparison normalization
- Diacritic preservation
- Exact aliases such as:
  - `turnt → hype`
  - `pen game → bars`
  - `workout → gym`
  - `nighttime → late night`
- Ambiguous terms such as:
  - `icy`
  - `easygoing`
  - `emotional`
  - `clean`
- Custom phrase preservation
- Candidate ranking by rating/polarity
- Category diversity
- Existing string-tag decoding

### 28.2 Resolver tests

Test:

- Exact match
- Alias match
- Ambiguous local match
- Valid model match
- Valid model ambiguity
- `NONE`
- Unknown ID rejection
- Out-of-candidate ID rejection
- Malformed output
- Empty output
- Cancellation propagation
- Fallback to custom

### 28.3 SoundPrint tests

Test:

- Canonical positive mappings
- Canonical avoidance mappings
- Context tags ignored for unsupported dimensions
- Custom keyword behavior preserved
- Review and canonical evidence can coexist
- No new unsupported dimensions are persisted

### 28.4 Today’s Pick tests

Test:

- Reaction tags are excluded from catalog query generation.
- Genre/style tags remain eligible.
- Existing modes still rank candidates.
- Existing eligibility remains unchanged.
- Canonical taste signals do not produce invalid MusicKit searches.

### 28.5 UI tests

Test:

- Rating reveals reactions.
- Chips select and deselect.
- More opens and closes.
- Search finds canonical names.
- Search finds aliases.
- Custom phrase can be saved.
- Existing custom tag remains custom during edit.
- Save works without reactions.
- Save works while model resolution is unavailable.
- VoiceOver identifiers and state labels are present.

### 28.6 Manual QA

Verify on:

- iOS 26 physical device with Apple Intelligence available
- iOS 26 physical device with model unavailable or disabled
- Simulator
- Main app new log
- Existing log edit
- Apple Music Share extension
- Light and dark appearance
- Large Dynamic Type
- VoiceOver
- Low, mixed, and high ratings
- Albums with and without genre metadata

---

## 29. Risks and mitigations

### Vocabulary feels overwhelming

**Mitigation:** Show six primary suggestions and keep the full catalog behind More.

### Suggestions feel generic

**Mitigation:** Use genre affinity, rating polarity, category diversity, and future personal history while preserving custom language.

### Model maps slang incorrectly

**Mitigation:** Require confirmation and always offer Keep as custom.

### Rich tags weaken recommendations

**Mitigation:** Separate genre catalog queries from reaction roles.

### SoundPrint ignores new tags

**Mitigation:** Use direct mappings already included in the reaction JSON.

### Main app and Share extension diverge

**Mitigation:** Put catalogs, normalization, and local resolution in `ListendShared`.

### Runtime JSON loading fails

**Mitigation:** Validate in tests and debug; provide a safe production fallback.

### Taxonomy changes become difficult

**Mitigation:** Keep stable canonical IDs, version the JSONs, and avoid premature structured persistence.

### Scope grows into a complete logger rewrite

**Mitigation:** Deliver phased, reviewable PRs and preserve rating, review, track, and save behavior unless explicitly in scope.

---

## 30. Do-not-change notes for implementation

- Do not change the SwiftData schema in Phase 1.
- Do not remove compatibility with existing tag strings.
- Do not rewrite SoundPrint, Today’s Pick, or Journal Assist wholesale.
- Do not change rating granularity.
- Do not make reactions required.
- Do not block saving for AI.
- Do not add server dependencies.
- Do not add Foundation Models to the Share extension in the first release.
- Do not reintroduce guided structured-output APIs.
- Do not modify unrelated visual systems.
- Do not replace Midnight Vinyl styling with generic system styling.
- Do not hand-edit or reduce the taxonomy without reporting the proposed changes.

---

## 31. Codex handoff instructions

Before changing code:

1. Inspect the current implementations of:
   - `LogEntry`
   - `ListTextNormalizer`
   - `LogEntryEditorView`
   - `LocalTagSuggestionEngine`
   - `TagSuggestionProvider`
   - `FoundationModelsTagSuggestionProvider`
   - `MockSoundPrintProvider`
   - `LocalRecommendationService`
   - `CatalogRecommendationCandidateProvider`
   - `ShareViewController`
   - Existing taxonomy/tag tests
2. Briefly summarize the current architecture.
3. Confirm target membership needs for the JSON resources.
4. Implement only the requested phase.
5. Preserve existing logging and fallback behavior.
6. Add focused automated tests.
7. Run the existing Foundation Models symbol scan where applicable.
8. Summarize:
   - Changed files
   - Tests performed
   - Build status
   - Any taxonomy data issues
   - Follow-up recommendations

Default instruction:

> Before changing code, inspect the existing implementation and briefly summarize the current architecture. Implement the smallest clean change that satisfies the requirements. Do not rewrite unrelated systems. Afterward, summarize changed files, testing performed, and follow-up recommendations.

---

## 32. Final product decision

Listend will use a hybrid reaction-first logging model:

- Rating remains the only required expression.
- Canonical reaction chips provide the fastest meaningful path.
- More provides precision and breadth.
- Custom tags preserve personal language.
- Journal Assist expands user-authored reactions into optional reflection.
- Foundation Models interprets unfamiliar phrases only after explicit user action.
- SoundPrint and Today’s Pick consume structured meaning without requiring a new database architecture.
- The Share extension receives deterministic parity without adding model dependency.

The canonical taxonomy foundation must be implemented and validated before the main logging UI or semantic resolver is introduced.
