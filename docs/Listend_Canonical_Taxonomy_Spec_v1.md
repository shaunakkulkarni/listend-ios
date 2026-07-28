# Listend Canonical Taxonomy Specification

**Version:** 1.0.0-draft
**Date:** July 27, 2026
**Product:** Listend for iOS
**Scope:** Canonical genre/style normalization, listener reaction vocabulary, alias resolution, SoundPrint mappings, and recommendation roles.

## 1. Decision summary

Listend should maintain two separate but interoperable catalogs:

1. **Genre & Style Catalog** — normalizes metadata from Apple Music and future services. Genre describes what a release is.
2. **Reaction Tag Catalog** — captures how a listener experienced the release. Reactions cover mood, movement, sound, craft, context, personal response, and criticism.

This draft contains **355 genre/style entries**, **243 reaction tags**, **723 exact reaction aliases**, and **20 explicitly ambiguous terms**. Only **169** reactions are eligible for the six-chip primary suggestion row; the rest are discoverable through More and search.

The catalog is intentionally larger than the visible UI. Users should never see the full vocabulary at once.

## 2. Current-stack compatibility

- Continue persisting selected values through `LogEntry.tags: [String]`; no SwiftData migration is required for v1.
- Use stable canonical IDs in code, but save the canonical `displayName` until structured tag persistence is introduced.
- Place catalog definitions, normalization, alias resolution, and deterministic ranking in `ListendShared` so the app and Share extension use the same vocabulary.
- Keep Foundation Models implementations in the main app target.
- Use only the existing iOS 26-safe plain-text `LanguageModelSession.respond(to:)` path.
- Preserve rating-only save behavior. Taxonomy search and AI resolution must never block Save.

## 3. Canonical models

```swift
enum ReactionTagCategory: String, Sendable, CaseIterable {
    case moodVibe
    case energyMovement
    case sonicCharacter
    case craftPerformance
    case listeningContext
    case personalReaction
    case frictionCritique
}

enum ReactionTagPolarity: String, Sendable {
    case positive
    case neutral
    case negative
    case mixed
}

enum RecommendationTagRole: String, Sendable {
    case tasteSignalOnly
    case avoidanceSignal
    case displayOnly
}

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

struct GenreStyleDefinition: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let family: String
    let aliases: [String]
    let parentID: String?
}
```

## 4. ID and display rules

- IDs are stable, nonlocalized identifiers: `mood.dreamy`, `craft.bars`, `genre.hip-hop`.
- Reaction display names are lowercase and optimized for chip readability.
- Genre display names preserve established capitalization and diacritics, such as `MPB`, `K-R&B`, `música mexicana`, and `raï`.
- Reaction display names must be globally unique after comparison normalization.
- A visible label may not exceed 28 characters and may not contain commas or line breaks.
- Do not reuse one visible label for multiple meanings. Use `warm production`, `raw vocals`, and `raw production` instead of several unrelated tags named `warm` or `raw`.

## 5. Normalization

Maintain two separate normalization functions:

### Display normalization

- Trim leading and trailing whitespace.
- Collapse repeated internal whitespace.
- Preserve diacritics, apostrophes, intentional capitalization, and hyphens.
- Preserve a custom phrase exactly except for whitespace cleanup and safety limits.

### Comparison normalization

- Apply Unicode compatibility decomposition.
- Fold case and diacritics.
- Normalize en/em dashes to a hyphen.
- Collapse repeated whitespace.
- Use only for deduplication, lookup, and search.

The comparison key must never be shown as the user-facing value.

## 6. Exact and ambiguous aliases

Exact aliases resolve locally and deterministically. An exact alias may point to only one canonical tag.

Terms with multiple defensible meanings belong in the explicit ambiguous-alias catalog and must not be silently resolved.

Resolution order:

1. Exact canonical display-name match
2. Explicit ambiguous-alias choices
3. Exact nonambiguous alias match
4. Local prefix/token search
5. Conservative typo matching
6. User-triggered Foundation Models semantic resolution
7. Keep as a custom tag

An explicitly ambiguous term must not also appear in any reaction tag's exact-alias list. Catalog validation must reject that overlap so the clarification choices cannot be shadowed by deterministic exact matching.

## 7. Local search behavior

- Search canonical display names, exact aliases, category names, and definitions.
- Rank display-name prefix matches above alias matches.
- Rank whole-token matches above substring matches.
- Never use artist or album title text to infer genre or subjective reactions.
- Typo matching should be limited to terms of at least four characters and small edit distances.
- Return no more than 20 search results.
- Show category labels in search results when the same natural-language idea may be confused across categories.

## 8. Primary suggestion ranking

The logger displays six suggestions plus More.

Candidate sources, in descending trust:

1. Explicit review or note language
2. Existing selected reactions
3. The user’s prior canonical tag history
4. Rating and polarity
5. Genre-family affinity as a weak prior
6. Common globally useful reaction tags

Genre affinity is a ranking hint only. It must never be presented as an objective claim about the album.

### Rating polarity multipliers

| Rating | Positive | Neutral | Mixed | Negative |
|---|---:|---:|---:|---:|
| 4.0–5.0 | 1.00 | 0.80 | 0.55 | 0.30 |
| 3.0–3.5 | 0.80 | 0.90 | 1.00 | 0.80 |
| 0.5–2.5 | 0.35 | 0.70 | 0.85 | 1.00 |

### Diversity rules for the top six

- Prefer no more than two results from one category.
- For ratings under 3.0, up to three Friction & Critique results are allowed.
- When evidence exists, include at least one Craft & Performance or Sonic Character result.
- Prefer at least one Personal Reaction result for ratings of 3.0 or higher.
- Do not show multiple near-synonyms, such as `replayable`, `on repeat`, and `no skips`, unless user history strongly supports them.
- Listening Context tags should appear only when user text, prior usage, or a clear explicit choice supports them.

## 9. Foundation Models semantic resolver

Foundation Models are used only after local matching fails and the user explicitly submits a phrase.

Provide the model:

- The submitted phrase
- Optional active category
- Rating
- Existing selected reactions
- A short review excerpt
- A locally produced shortlist of at most 12 canonical candidates
- IDs, display names, and one-sentence definitions for those candidates

Do not send the full taxonomy or full alias corpus.

Accepted line formats:

```text
RESULT | MATCH
MATCH | mood.dreamy
```

```text
RESULT | AMBIGUOUS
MATCH | sonic.cold-production
ALTERNATIVE | mood.confident
ALTERNATIVE | mood.menacing
```

```text
RESULT | NONE
```

Validation:

- All returned IDs must be in the supplied shortlist.
- At most three candidates may be returned.
- Additional prose is rejected.
- Unknown IDs are rejected.
- Any parsing, availability, rate-limit, locale, refusal, or cancellation failure falls back to keeping the custom phrase.
- Never display model-generated confidence percentages.

## 10. Persistence behavior

- Canonical choice: persist the canonical display name.
- Custom choice: persist the user’s cleaned custom phrase.
- Reopening a log maps exact canonical display values back to canonical IDs.
- Reopening a log must not reinterpret a saved custom alias. A user who kept `floaty` should continue seeing `floaty`.
- Existing legacy tags remain valid custom tags.
- Do not persist hidden custom-to-canonical associations in v1.

## 11. SoundPrint integration

Reaction tags may map directly into the existing SoundPrint dimensions:

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

Critique tags may map into the existing avoidance signals:

- `energyWithoutPayoff`
- `fillerSensitivity`
- `lowReplayValue`
- `moodMismatch`
- `skipHeavyAlbums`
- `sterileProduction`
- `weakWriting`

Rules:

- Canonical mappings are deterministic and should be evaluated before free-text keyword rules.
- Custom tags and reviews continue through the existing text-analysis path.
- A positive craft tag on a low-rated album is scoped evidence, not proof of broad preference.
- A critique tag on a highly rated album creates capped avoidance evidence rather than overriding the overall positive rating.
- Listening Context tags do not create SoundPrint dimensions in v1.
- Multiple tags mapping to the same dimension should strengthen confidence with caps rather than create duplicate evidence records.

## 12. Today’s Pick integration

- Genre/style entries may be used as catalog query terms.
- Reaction tags never become raw MusicKit search queries.
- `tasteSignalOnly` reactions may influence preference evidence and explanations.
- `avoidanceSignal` reactions may reduce affinity only through validated avoidance evidence.
- `displayOnly` reactions remain journal context.
- Custom tags remain display-only unless existing SoundPrint text rules recognize them.
- Reaction-query filtering is a launch dependency for the reaction picker. The picker must not be enabled or shipped while Today’s Pick still submits every stored tag as a raw catalog query.

## 13. Journal Assist integration

- Treat selected reactions as user-authored evidence.
- Preserve the user’s exact selected language where natural.
- Do not invent sounds, lyrics, track moments, or listening situations.
- Use reaction categories to build a short first-person starter, not a critic-style review.
- Allow the user to edit or reject the draft before saving.

## 14. Share extension

- Use the same JSON-backed shared catalogs.
- Support canonical search, exact aliases, ambiguous choices, and custom tags.
- Do not invoke Foundation Models in the extension for v1.
- If local resolution fails, preserve the custom phrase immediately.
- Persist the same canonical display values as the main app.

## 15. Versioning

- Catalog version uses semantic versioning.
- Patch: definition, alias, or typo fixes that do not change meaning.
- Minor: additive tags or aliases.
- Major: removed IDs, merged meanings, or behavioral changes.
- IDs must never be reused for a different meaning.
- Renaming a display value requires a future structured-persistence migration plan; do not silently rewrite existing logs in v1.

## 16. Validation requirements

The build or unit-test suite must fail when:

- An ID is duplicated.
- A normalized display name is duplicated.
- An exact alias resolves to more than one tag.
- An explicitly ambiguous term also appears as an exact alias.
- An ambiguous alias references an unknown ID or more than three candidates.
- A reaction display name exceeds 28 characters.
- A reaction label contains a comma or line break.
- A SoundPrint mapping references an unknown dimension.
- An avoidance mapping references an unknown signal.
- A genre affinity references an unknown family.
- A genre parent references an unknown ID.

## 17. Suggested code organization

```text
Listend/ListendShared/Tagging/
    ReactionTagDefinition.swift
    ReactionTagCategory.swift
    ReactionTagCatalog.swift
    GenreStyleDefinition.swift
    GenreStyleCatalog.swift
    AmbiguousTagAlias.swift
    TagTextNormalizer.swift
    LocalReactionTagResolver.swift
    ReactionTagRanker.swift
    TaxonomyValidator.swift

Listend/ListendShared/Resources/Taxonomy/
    Listend_Reaction_Tags_v1.json
    Listend_Genre_Styles_v1.json
    Listend_Ambiguous_Aliases_v1.json

Listend/Listend/Services/TagResolution/
    ReactionTagResolutionProvider.swift
    FoundationModelsReactionTagResolver.swift
    FallbackReactionTagResolver.swift
    MockReactionTagResolver.swift
    ReactionTagResolutionValidator.swift

Listend/Listend/Views/LogEntry/
    ReactionPickerSection.swift
    ReactionTagChip.swift
    ReactionTagBrowserSheet.swift
    CustomTagResolutionView.swift
```

## 18. Test matrix

| Scenario | Expected result |
|---|---|
| `turnt` | Exact alias → `hype` |
| `pen game` | Exact alias → `bars` |
| `nighttime` | Exact alias → `late night` |
| `warm` | Explicit choices: `comforting` or `warm production` |
| `icy` | Explicit choices: `cold production`, `confident`, or `menacing` |
| `floaty` | Explicit choices: `dreamy`, `ethereal`, or `airy` |
| `easygoing` | Explicit choices: `carefree` or `laid-back` |
| `emotional` | Explicit choices: `moving`, `emotionally resonant`, or `vulnerable` |
| `clean` | Explicit choices: `polished`, `spacious`, or `too polished` |
| `graduation summer` | No close match → preserve custom phrase |
| Model returns unknown ID | Reject and preserve custom phrase |
| Foundation Models unavailable | Local catalog remains fully usable |
| Existing log contains `warm, late night` | Load both as existing values; do not silently rewrite |
| Low rating + `strong vocals` | Preserve positive scoped evidence |
| High rating + `bloated` | Preserve critique with capped avoidance evidence |
| Share extension unknown phrase | Keep custom without model dependency |

## 19. Catalog counts

### Reaction categories

| Category | Total | Primary eligible |
|---|---:|---:|
| Mood & Vibe | 36 | 31 |
| Energy & Movement | 16 | 12 |
| Sonic Character | 39 | 28 |
| Craft & Performance | 51 | 31 |
| Listening Context | 37 | 22 |
| Personal Reaction | 22 | 16 |
| Friction & Critique | 42 | 29 |

### Genre families

| Family | Total |
|---|---:|
| Hip-Hop & Rap | 16 |
| R&B, Soul & Funk | 14 |
| Pop | 19 |
| Rock | 21 |
| Punk, Hardcore & Metal | 22 |
| Electronic & Dance | 33 |
| Jazz & Blues | 18 |
| Country, Folk & Americana | 17 |
| Caribbean | 11 |
| African | 16 |
| Latin | 22 |
| Brazilian | 12 |
| South Asian | 20 |
| East Asian | 20 |
| Middle Eastern & North African | 16 |
| Classical | 16 |
| Ambient, New Age & Experimental | 16 |
| Soundtrack & Stage | 9 |
| Spiritual & Religious | 12 |
| Global & Traditional | 25 |

## 20. Explicit ambiguous aliases

| Term | Candidate tags | Clarifying prompt |
|---|---|---|
| icy | cold production, confident, menacing | Does “icy” describe the sound, the attitude, or the mood? |
| raw | raw production, raw vocals, vulnerable | Does “raw” describe the production, the vocals, or the emotional openness? |
| warm | comforting, warm production | Does “warm” describe how it feels or how it sounds? |
| floaty | dreamy, ethereal, airy | Is “floaty” more dreamy, otherworldly, or airy in sound? |
| chill | laid-back, mellow, calm | Does “chill” mean relaxed pacing, soft intensity, or emotional calm? |
| easygoing | carefree, laid-back | Does “easygoing” describe the mood or the pacing? |
| alone | lonely, solo listening | Does “alone” describe the emotion or how you want to listen? |
| full of soul | soulful, soulful vocals | Does this describe the overall feeling or specifically the vocals? |
| smooth | smooth vocals, laid-back, polished | Does “smooth” describe the vocals, the pacing, or the finish? |
| heavy | hard-hitting, bass-heavy, dense | Does “heavy” mean impact, bass weight, or a dense arrangement? |
| spacey | dreamy, atmospheric, spacious | Does “spacey” describe the mood, the atmosphere, or the open mix? |
| moody | dark, melancholic, anxious | Is the mood dark, sad, or tense? |
| aggressive | hard-hitting, menacing, relentless | Does “aggressive” describe impact, threat, or nonstop intensity? |
| emotional | moving, emotionally resonant, vulnerable | Was it moving, personally resonant, or emotionally exposed? |
| deep | lyricism, thought-provoking, introspective | Does “deep” refer to the writing, the ideas, or the inward mood? |
| pretty | tender, ethereal, lush | Does “pretty” describe tenderness, an otherworldly mood, or a rich sound? |
| big | cinematic, wall of sound, anthemic | Does “big” mean cinematic scale, a massive sound, or an anthemic hook? |
| clean | polished, spacious, too polished | Is “clean” a polished strength, an open mix, or overly sterile? |
| weird | adventurous, psychedelic, genre-blending | Is “weird” creative risk, a psychedelic sound, or genre mixing? |
| hard | hard-hitting, menacing, bars | Does “hard” describe the impact, the attitude, or the writing? |

# Appendix A — Complete Reaction Tag Catalog

## Mood & Vibe

| Display | ID | Definition | Aliases | Polarity | SoundPrint / Avoidance | Role | Primary |
|---|---|---|---|---|---|---|---|
| anxious | `mood.anxious` | Creates unease, nervous motion, or emotional pressure. | tense, restless, on edge | neutral | Dimensions: mood, energy | tasteSignalOnly | Yes |
| bittersweet | `mood.bittersweet` | Blends pleasure and sadness without resolving fully into either. | happy-sad, sweet and sad, mixed emotions | mixed | Dimensions: mood | tasteSignalOnly | Yes |
| calm | `mood.calm` | Creates stillness, ease, or emotional quiet. | peaceful, serene, relaxing | neutral | Dimensions: mood, energy | tasteSignalOnly | Yes |
| carefree | `mood.carefree` | Feels loose, unburdened, and unconcerned with consequences. | free-spirited, no worries | positive | Dimensions: mood | tasteSignalOnly | No |
| cathartic | `mood.cathartic` | Provides emotional release through intensity, honesty, or resolution. | emotional release, cleansing, let it out | positive | Dimensions: mood, emotionalDirectness | tasteSignalOnly | Yes |
| celebratory | `mood.celebratory` | Feels built for a win, milestone, or shared celebration. | victory lap, celebration, champagne music | positive | Dimensions: mood, energy | tasteSignalOnly | Yes |
| comforting | `mood.comforting` | Feels reassuring, familiar, or emotionally safe. | cozy, reassuring, safe | positive | Dimensions: mood | tasteSignalOnly | Yes |
| confident | `mood.confident` | Projects assurance, control, and self-belief. | swagger, self-assured, bossed up, main character | positive | Dimensions: mood, energy | tasteSignalOnly | Yes |
| dark | `mood.dark` | Carries emotionally shadowed, serious, or unsettling subject matter. | bleak, shadowy, grim | neutral | Dimensions: mood | tasteSignalOnly | Yes |
| dreamy | `mood.dreamy` | Feels hazy, soft-focused, or suspended between waking and imagination. | hazy, dreamlike | neutral | Dimensions: mood, texturePreference | tasteSignalOnly | Yes |
| empowering | `mood.empowering` | Makes the listener feel capable, resilient, or stronger. | motivating, powerful, confidence boost | positive | Dimensions: mood | tasteSignalOnly | Yes |
| ethereal | `mood.ethereal` | Feels weightless, delicate, and almost otherworldly. | angelic, celestial, weightless | neutral | Dimensions: mood, texturePreference | tasteSignalOnly | Yes |
| euphoric | `mood.euphoric` | Creates an intense rush of joy, release, or emotional elevation. | ecstatic, blissful, pure euphoria | positive | Dimensions: mood, energy | tasteSignalOnly | Yes |
| feel-good | `mood.feel-good` | Light, positive, easy-to-enjoy emotional energy. | happy, good vibes, cheerful, positive | positive | Dimensions: mood | tasteSignalOnly | Yes |
| haunting | `mood.haunting` | Lingers through eerie beauty, grief, or unresolved emotional tension. | eerie, ghostly, lingering | neutral | Dimensions: mood, texturePreference | tasteSignalOnly | Yes |
| heartbroken | `mood.heartbroken` | Centers romantic loss, grief, or the aftermath of a breakup. | breakup music, brokenhearted, post-breakup | neutral | Dimensions: mood, emotionalDirectness | tasteSignalOnly | Yes |
| hype | `mood.hype` | Creates an excited, fired-up reaction that makes the listener feel ready for the moment. | turnt, hyped, fired up, lit | positive | Dimensions: mood, energy | tasteSignalOnly | Yes |
| intimate | `mood.intimate` | Feels private, close, and emotionally near to the performer. | close-up, personal, private | neutral | Dimensions: mood, emotionalDirectness | tasteSignalOnly | Yes |
| introspective | `mood.introspective` | Turns inward toward identity, motives, or personal conflict. | self-reflective, inward-looking, internal | neutral | Dimensions: mood, emotionalDirectness | tasteSignalOnly | Yes |
| lonely | `mood.lonely` | Evokes isolation, disconnection, or being emotionally alone. | isolated, solitary | neutral | Dimensions: mood | tasteSignalOnly | No |
| melancholic | `mood.melancholic` | Carries sustained sadness, reflection, or emotional heaviness. | melancholy, blue, sad but beautiful | neutral | Dimensions: mood | tasteSignalOnly | Yes |
| menacing | `mood.menacing` | Feels threatening, intimidating, or dangerous. | sinister, threatening, villainous | neutral | Dimensions: mood, energy | tasteSignalOnly | Yes |
| mysterious | `mood.mysterious` | Withholds clarity and creates curiosity, ambiguity, or intrigue. | enigmatic, cryptic, unknown | neutral | Dimensions: mood | tasteSignalOnly | Yes |
| nostalgic | `mood.nostalgic` | Pulls the listener toward a remembered time, place, or version of themselves. | nostalgia, throwback feeling, memory lane | neutral | Dimensions: mood, eraAffinity | tasteSignalOnly | Yes |
| playful | `mood.playful` | Uses humor, lightness, or mischievous energy. | fun, silly, cheeky | positive | Dimensions: mood | tasteSignalOnly | Yes |
| rebellious | `mood.rebellious` | Pushes against rules, expectations, or authority. | defiant, anti-establishment, fuck the rules | neutral | Dimensions: mood, energy | tasteSignalOnly | No |
| reflective | `mood.reflective` | Encourages thoughtful consideration of experience or memory. | thoughtful, contemplative, makes me reflect | neutral | Dimensions: mood | tasteSignalOnly | Yes |
| romantic | `mood.romantic` | Centers affection, longing, devotion, or idealized love. | love song energy, in love, romance | neutral | Dimensions: mood, emotionalDirectness | tasteSignalOnly | Yes |
| sensual | `mood.sensual` | Feels tactile, seductive, or physically expressive. | sexy, seductive, sultry | neutral | Dimensions: mood | tasteSignalOnly | Yes |
| soulful | `mood.soulful` | Feels deeply expressive, heartfelt, and emotionally lived-in. | heartfelt, deep feeling | positive | Dimensions: mood, emotionalDirectness | tasteSignalOnly | Yes |
| spiritual | `mood.spiritual` | Feels connected to faith, transcendence, ritual, or a larger meaning. | sacred, transcendent, devotional feeling | neutral | Dimensions: mood | tasteSignalOnly | No |
| tender | `mood.tender` | Expresses softness, care, or emotional gentleness. | gentle, soft-hearted, delicate feeling | neutral | Dimensions: mood, emotionalDirectness | tasteSignalOnly | Yes |
| triumphant | `mood.triumphant` | Feels victorious, overcoming, or earned after struggle. | victorious, winning, comeback music | positive | Dimensions: mood, energy | tasteSignalOnly | No |
| uplifting | `mood.uplifting` | Leaves the listener feeling encouraged, lighter, or more hopeful. | hopeful, inspiring, raises me up | positive | Dimensions: mood | tasteSignalOnly | Yes |
| vulnerable | `mood.vulnerable` | Feels emotionally exposed, honest, and unguarded. | open-hearted, unguarded, emotionally exposed | neutral | Dimensions: emotionalDirectness, mood | tasteSignalOnly | Yes |
| yearning | `mood.yearning` | Expresses unresolved desire, longing, or reaching for something absent. | longing, aching, pining | neutral | Dimensions: mood, emotionalDirectness | tasteSignalOnly | Yes |

## Energy & Movement

| Display | ID | Definition | Aliases | Polarity | SoundPrint / Avoidance | Role | Primary |
|---|---|---|---|---|---|---|---|
| bouncy | `energy.bouncy` | Has a springy, buoyant rhythmic feel. | bounce, springy, rubbery groove | neutral | Dimensions: energy | tasteSignalOnly | Yes |
| danceable | `energy.danceable` | Naturally invites physical movement or dancing. | makes me dance, dance floor, moveable | neutral | Dimensions: energy | tasteSignalOnly | Yes |
| explosive | `energy.explosive` | Builds or erupts into sudden, overwhelming intensity. | erupts, blows up, bursting | neutral | Dimensions: energy | tasteSignalOnly | No |
| funky | `energy.funky` | Uses syncopation, rhythmic tension, or pocket-driven movement associated with funk. | funky groove, syncopated, funked up | neutral | Dimensions: energy | tasteSignalOnly | Yes |
| groovy | `energy.groovy` | Locks into an easy, satisfying rhythmic pocket. | in the pocket, smooth groove, groove-heavy | neutral | Dimensions: energy | tasteSignalOnly | Yes |
| hard-hitting | `energy.hard-hitting` | Lands with physical force through drums, bass, delivery, or impact. | hits hard, heavy impact, punchy | neutral | Dimensions: energy, productionStyle | tasteSignalOnly | Yes |
| head-nodding | `energy.head-nodding` | Has a beat or pocket that invites a steady head nod. | head nod, neck snap, beat knocks | neutral | Dimensions: energy | tasteSignalOnly | Yes |
| high-energy | `energy.high-energy` | Maintains a fast, forceful, or highly activated level of energy. | energetic, amped, high energy | neutral | Dimensions: energy | tasteSignalOnly | Yes |
| laid-back | `energy.laid-back` | Moves with relaxed pacing and little urgency. | unhurried | neutral | Dimensions: energy | tasteSignalOnly | Yes |
| meditative | `energy.meditative` | Uses repetition, space, or restraint to encourage focused stillness. | zen, trance-like, centering | neutral | Dimensions: energy, mood | tasteSignalOnly | No |
| mellow | `energy.mellow` | Keeps its intensity soft, smooth, and restrained. | low-key, soft energy, easy listening | neutral | Dimensions: energy | tasteSignalOnly | Yes |
| mosh-ready | `energy.mosh-ready` | Feels suited to a pit, crowd surge, or aggressive live release. | mosh pit, pit music, crowd killer | neutral | Dimensions: energy | tasteSignalOnly | No |
| propulsive | `energy.propulsive` | Creates constant forward motion that keeps pulling the listener ahead. | driving rhythm, forward motion, urgent momentum | neutral | Dimensions: energy | tasteSignalOnly | Yes |
| relentless | `energy.relentless` | Sustains pressure or intensity with very little release. | nonstop, unrelenting, no breathing room | neutral | Dimensions: energy | tasteSignalOnly | No |
| slow burn | `energy.slow-burn` | Develops gradually and rewards patience rather than immediate impact. | builds slowly, patient, gradual | neutral | Dimensions: energy, tracklistConsistency | tasteSignalOnly | Yes |
| upbeat | `energy.upbeat` | Moves with a lively tempo and bright rhythmic feel. | lively, brisk, up-tempo | neutral | Dimensions: energy | tasteSignalOnly | Yes |

## Sonic Character

| Display | ID | Definition | Aliases | Polarity | SoundPrint / Avoidance | Role | Primary |
|---|---|---|---|---|---|---|---|
| acoustic | `sonic.acoustic` | Leans on unamplified or naturally resonant instruments and a stripped-back sound. | unplugged, acoustic sound, natural instruments | neutral | Dimensions: productionStyle, texturePreference | tasteSignalOnly | Yes |
| airy | `sonic.airy` | Feels light, breathable, and open in the upper frequencies or arrangement. | lightweight, breathy, open-air | neutral | Dimensions: texturePreference | tasteSignalOnly | Yes |
| atmospheric | `sonic.atmospheric` | Prioritizes environment, mood, and sonic space over direct impact. | ambient feeling, moody atmosphere, atmosphere | neutral | Dimensions: texturePreference, mood | tasteSignalOnly | Yes |
| bass-heavy | `sonic.bass-heavy` | Places low-end weight and bass presence at the center of the sound. | big bass, heavy bass, low-end heavy | neutral | Dimensions: productionStyle, texturePreference | tasteSignalOnly | Yes |
| bright production | `sonic.bright-production` | Emphasizes clear, vivid, or sparkling upper-frequency energy. | bright sound, shimmering, sparkly production | neutral | Dimensions: productionStyle, texturePreference | tasteSignalOnly | No |
| cinematic | `sonic.cinematic` | Feels large-scale, scene-setting, or suited to visual storytelling. | movie-like, soundtrack energy, epic | neutral | Dimensions: instrumentalRichness, mood | tasteSignalOnly | Yes |
| cold production | `sonic.cold-production` | Uses stark, icy, metallic, or emotionally detached tonal character. | icy production, frosty sound, glacial production | neutral | Dimensions: productionStyle, texturePreference | tasteSignalOnly | Yes |
| dark production | `sonic.dark-production` | Uses low-lit, shadowy, or ominous sonic choices independent of lyrical mood. | dark beat, shadowy production, ominous production | neutral | Dimensions: productionStyle, texturePreference | tasteSignalOnly | Yes |
| dense | `sonic.dense` | Packs many sounds or musical ideas into a limited amount of space. | packed, busy mix, thick | neutral | Dimensions: instrumentalRichness, texturePreference | tasteSignalOnly | No |
| distorted | `sonic.distorted` | Uses clipping, saturation, fuzz, or deliberate sonic breakup. | fuzzy, overdriven, blown out | neutral | Dimensions: texturePreference, productionStyle | tasteSignalOnly | Yes |
| drum-forward | `sonic.drum-forward` | Makes drums or percussion the most prominent part of the arrangement. | drum heavy, drums upfront, percussion-led | neutral | Dimensions: productionStyle, instrumentalRichness | tasteSignalOnly | Yes |
| futuristic | `sonic.futuristic` | Feels technologically forward, unfamiliar, or ahead of current conventions. | future-facing, sci-fi, next-level sound | neutral | Dimensions: experimentation, productionStyle | tasteSignalOnly | Yes |
| genre-blending | `sonic.genre-blending` | Combines recognizable elements from multiple styles into one sound. | genre-bending, fusion, cross-genre | neutral | Dimensions: genreOpenness, experimentation | tasteSignalOnly | Yes |
| gritty | `sonic.gritty` | Uses rough, dirty, or abrasive texture without becoming fully distorted. | grimy, dirty sound, dusty | neutral | Dimensions: texturePreference, productionStyle | tasteSignalOnly | Yes |
| guitar-driven | `sonic.guitar-driven` | Builds the track or album primarily around guitar parts. | guitar heavy, guitar-led, riff-driven | neutral | Dimensions: instrumentalRichness | tasteSignalOnly | Yes |
| horn-driven | `sonic.horn-driven` | Centers brass or woodwind parts in the arrangement. | horn-heavy, brass-heavy, sax-forward | neutral | Dimensions: instrumentalRichness | tasteSignalOnly | No |
| immersive | `sonic.immersive` | Surrounds the listener with a convincing, absorbing sonic environment. | enveloping, pulls me in, surrounding | positive | Dimensions: texturePreference, instrumentalRichness | tasteSignalOnly | Yes |
| industrial | `sonic.industrial` | Uses mechanical, metallic, or factory-like texture and rhythm. | mechanical, metallic, factory sound | neutral | Dimensions: texturePreference, productionStyle | tasteSignalOnly | No |
| layered | `sonic.layered` | Rewards attention through multiple interacting sonic or musical layers. | many layers, stacked, detailed layers | neutral | Dimensions: instrumentalRichness, texturePreference | tasteSignalOnly | Yes |
| live-sounding | `sonic.live-sounding` | Feels captured as a performance in a room rather than assembled entirely in production. | live feel, room sound, band in a room | neutral | Dimensions: productionStyle, instrumentalRichness | tasteSignalOnly | No |
| lo-fi | `sonic.lo-fi` | Embraces limited fidelity, noise, or home-recorded texture as part of the aesthetic. | lo fi, low fidelity, bedroom-recorded | neutral | Dimensions: productionStyle, texturePreference | tasteSignalOnly | Yes |
| lush | `sonic.lush` | Feels rich, full, and sensuously arranged. | rich sound, full-bodied, plush | positive | Dimensions: instrumentalRichness, texturePreference | tasteSignalOnly | Yes |
| maximalist | `sonic.maximalist` | Pursues abundance, excess, or many simultaneous ideas and textures. | over-the-top, huge arrangement, everything at once | neutral | Dimensions: instrumentalRichness, experimentation | tasteSignalOnly | No |
| minimal | `sonic.minimal` | Uses a deliberately limited palette, arrangement, or number of elements. | stripped-back, sparse, bare | neutral | Dimensions: productionStyle, texturePreference | tasteSignalOnly | Yes |
| orchestral | `sonic.orchestral` | Uses large-scale arranged instrumentation with symphonic breadth. | symphonic, full orchestra, orchestra | neutral | Dimensions: instrumentalRichness | tasteSignalOnly | Yes |
| organic | `sonic.organic` | Feels natural, human, and physically performed rather than heavily synthetic. | natural sound, human feel, earthy | neutral | Dimensions: productionStyle, texturePreference | tasteSignalOnly | No |
| percussion-heavy | `sonic.percussion-heavy` | Uses layered or prominent percussion beyond a basic drum-kit role. | rhythm-heavy, percussive, lots of percussion | neutral | Dimensions: instrumentalRichness, energy | tasteSignalOnly | No |
| piano-led | `sonic.piano-led` | Uses piano as a central melodic or harmonic voice. | piano-driven, piano heavy, keys-led | neutral | Dimensions: instrumentalRichness | tasteSignalOnly | No |
| polished | `sonic.polished` | Feels carefully finished, controlled, and professionally refined. | slick, well-produced | neutral | Dimensions: productionStyle | tasteSignalOnly | Yes |
| psychedelic | `sonic.psychedelic` | Uses altered, swirling, disorienting, or perception-shifting sonic effects. | trippy, mind-bending, acid-soaked | neutral | Dimensions: experimentation, texturePreference | tasteSignalOnly | Yes |
| raw production | `sonic.raw-production` | Preserves rough edges, immediacy, or an intentionally unrefined recording character. | rough production, unpolished, demo-like | neutral | Dimensions: productionStyle, texturePreference | tasteSignalOnly | Yes |
| retro | `sonic.retro` | Intentionally evokes the sound or production language of an earlier era. | throwback sound, vintage, old-school sound | neutral | Dimensions: eraAffinity, productionStyle | tasteSignalOnly | Yes |
| sample-heavy | `sonic.sample-heavy` | Builds much of its identity from prominent or layered samples. | sample-driven, lots of samples, chopped samples | neutral | Dimensions: productionStyle, experimentation | tasteSignalOnly | Yes |
| spacious | `sonic.spacious` | Leaves audible room between elements and creates a wide sense of space. | wide open, lots of space, open mix | neutral | Dimensions: texturePreference, productionStyle | tasteSignalOnly | Yes |
| string-led | `sonic.string-led` | Uses bowed or arranged strings as a defining part of the sound. | string-heavy, strings upfront, orchestral strings | neutral | Dimensions: instrumentalRichness | tasteSignalOnly | No |
| synth-heavy | `sonic.synth-heavy` | Relies strongly on synthesizers for melody, harmony, or texture. | synth-driven, lots of synths, synthy | neutral | Dimensions: productionStyle, texturePreference | tasteSignalOnly | Yes |
| textured | `sonic.textured` | Uses distinctive surfaces, timbres, or sonic grain as a major appeal. | tactile, sonic texture, grainy | neutral | Dimensions: texturePreference | tasteSignalOnly | Yes |
| wall of sound | `sonic.wall-of-sound` | Creates a large, blended mass of sound with few empty spaces. | huge wall, massive sound, sonic wall | neutral | Dimensions: texturePreference, productionStyle | tasteSignalOnly | No |
| warm production | `sonic.warm-production` | Uses rounded, rich, or softly saturated tonal character. | warm sounding, analog warmth, warm mix | neutral | Dimensions: productionStyle, texturePreference | tasteSignalOnly | Yes |

## Craft & Performance

| Display | ID | Definition | Aliases | Polarity | SoundPrint / Avoidance | Role | Primary |
|---|---|---|---|---|---|---|---|
| adventurous | `craft.adventurous` | Takes creative risks and avoids predictable choices. | bold choices, risk-taking, daring | positive | Dimensions: experimentation, genreOpenness | tasteSignalOnly | Yes |
| ambitious | `craft.ambitious` | Attempts a large, difficult, or unusually expansive creative goal. | big swing, aims high, bold vision | neutral | Dimensions: experimentation | tasteSignalOnly | Yes |
| anthemic | `craft.anthemic` | Feels built for collective singing, large emotion, or crowd-scale release. | stadium-ready, singalong, big anthem | positive | Dimensions: energy, replayability | tasteSignalOnly | Yes |
| artist chemistry | `craft.artist-chemistry` | Multiple performers interact naturally and make each other better. | duo chemistry, great chemistry, collaboration works | positive | Dimensions: vocalFocus | tasteSignalOnly | Yes |
| bars | `craft.bars` | The rap writing stands out for sharp lines, punchlines, or sustained lyrical skill. | pen game, rap writing, spitting, lyrical | positive | Dimensions: lyricFocus | tasteSignalOnly | Yes |
| bassline | `craft.bassline` | The bass part is especially memorable, musical, or groove-defining. | bass line, great bass, bass groove | positive | Dimensions: instrumentalRichness, energy | tasteSignalOnly | Yes |
| cadence | `craft.cadence` | The rhythmic shape and phrasing of the vocal performance are especially effective. | rhythmic phrasing, cadences, pocket | positive | Dimensions: vocalFocus, energy | tasteSignalOnly | No |
| catchy | `craft.catchy` | Melodies, rhythms, or phrases stick quickly and return easily to mind. | ear-catching, sticks in my head, infectious | positive | Dimensions: replayability | tasteSignalOnly | Yes |
| charisma | `craft.charisma` | The performer’s personality and presence make the material more compelling. | star power, presence, personality | positive | Dimensions: vocalFocus | tasteSignalOnly | Yes |
| cinematic arc | `craft.cinematic-arc` | The album develops with a large-scale sense of progression and payoff. | album arc, narrative arc, journey | positive | Dimensions: tracklistConsistency, instrumentalRichness | tasteSignalOnly | No |
| cohesive | `craft.cohesive` | The album’s sound, themes, and sequencing feel intentionally connected. | cohesion, unified, all fits together | positive | Dimensions: tracklistConsistency | tasteSignalOnly | Yes |
| concept album | `craft.concept-album` | Uses a sustained narrative, theme, world, or formal idea across the project. | conceptual album, album concept, themed album | neutral | Dimensions: experimentation, tracklistConsistency | tasteSignalOnly | No |
| conceptual writing | `craft.conceptual-writing` | Organizes the writing around a sustained idea, perspective, or thematic device. | strong concept, thematic writing, concept-driven | positive | Dimensions: lyricFocus, experimentation | tasteSignalOnly | No |
| concise | `craft.concise` | Says what it needs to without overstaying or overexplaining. | tight, lean, no wasted time | positive | Dimensions: tracklistConsistency | tasteSignalOnly | Yes |
| confessional writing | `craft.confessional-writing` | The writing presents private experience with unusual honesty or specificity. | diary-like, personal writing, confessional | positive | Dimensions: lyricFocus, emotionalDirectness | tasteSignalOnly | No |
| consistent | `craft.consistent` | Maintains a reliable quality level across most or all of the tracklist. | steady quality, consistent tracklist, no major dips | positive | Dimensions: tracklistConsistency | tasteSignalOnly | Yes |
| deep cuts | `craft.deep-cuts` | Non-single album tracks contain some of the strongest or most rewarding material. | album cuts, hidden gems, non-singles | positive | Dimensions: tracklistConsistency, replayability | tasteSignalOnly | Yes |
| delivery | `craft.delivery` | The performer’s emphasis, tone, timing, and presence elevate the material. | vocal delivery, rap delivery, performance | positive | Dimensions: vocalFocus, lyricFocus | tasteSignalOnly | Yes |
| drumming | `craft.drumming` | The drum performance, programming, or rhythmic detail stands out. | great drums, drum work, percussion | positive | Dimensions: instrumentalRichness, energy | tasteSignalOnly | Yes |
| dynamic | `craft.dynamic` | Uses meaningful shifts in volume, intensity, arrangement, or emotion. | great dynamics, contrast, rises and falls | positive | Dimensions: energy, instrumentalRichness | tasteSignalOnly | Yes |
| expansive | `craft.expansive` | Develops a broad musical world, scale, or range of ideas. | wide-ranging, big world, large scope | neutral | Dimensions: instrumentalRichness, experimentation | tasteSignalOnly | No |
| flows | `craft.flows` | The rapper’s rhythmic patterns and movement across beats stand out. | flow, switches flows, rap flow | positive | Dimensions: lyricFocus, energy | tasteSignalOnly | Yes |
| focused | `craft.focused` | Maintains a clear purpose and avoids unnecessary detours. | disciplined, tight vision, clear direction | positive | Dimensions: tracklistConsistency | tasteSignalOnly | Yes |
| great features | `craft.great-features` | Guest appearances consistently add value to the songs. | features, guest verses, cameos | positive | Dimensions: vocalFocus | tasteSignalOnly | Yes |
| guitar work | `craft.guitar-work` | The guitar playing, riffs, tone, or arrangement is a major strength. | great guitar, riffs, guitar playing | positive | Dimensions: instrumentalRichness | tasteSignalOnly | Yes |
| harmonies | `craft.harmonies` | Layered or interacting vocal parts are a defining strength. | vocal harmonies, stacked vocals, beautiful harmonies | positive | Dimensions: vocalFocus, instrumentalRichness | tasteSignalOnly | Yes |
| hooks | `craft.hooks` | The repeated melodic or lyrical phrases are a major strength. | great hooks, hooky, chorus game | positive | Dimensions: replayability | tasteSignalOnly | Yes |
| lyricism | `craft.lyricism` | The words reward close attention through meaning, imagery, or craft. | lyrics, strong writing, lyrical depth | positive | Dimensions: lyricFocus | tasteSignalOnly | Yes |
| melodic delivery | `craft.melodic-delivery` | The vocal performance moves fluidly between singing, rapping, or tuneful phrasing. | sing-rap, melodic rap, sung delivery | positive | Dimensions: vocalFocus, replayability | tasteSignalOnly | Yes |
| memorable chorus | `craft.memorable-chorus` | One or more choruses stand out as especially lasting or effective. | big chorus, great chorus, chorus sticks | positive | Dimensions: replayability | tasteSignalOnly | No |
| musicianship | `craft.musicianship` | The instrumental skill, interaction, or performance technique stands out. | playing, instrumental skill, musical chops | positive | Dimensions: instrumentalRichness | tasteSignalOnly | Yes |
| piano work | `craft.piano-work` | The piano or keyboard playing is a major musical strength. | great piano, keys, keyboard work | positive | Dimensions: instrumentalRichness | tasteSignalOnly | No |
| poetic writing | `craft.poetic-writing` | The language uses imagery, metaphor, rhythm, or ambiguity in a literary way. | poetic, beautiful writing, literary | positive | Dimensions: lyricFocus | tasteSignalOnly | No |
| powerhouse vocals | `craft.powerhouse-vocals` | The singer delivers exceptional force, range, projection, or technical command. | big vocals, belting, vocal powerhouse | positive | Dimensions: vocalFocus | tasteSignalOnly | No |
| producer chemistry | `craft.producer-chemistry` | The artist and production choices feel especially well matched. | artist-producer chemistry, beats fit, production partnership | positive | Dimensions: productionStyle | tasteSignalOnly | No |
| quotable | `craft.quotable` | Contains lines or phrases the listener wants to remember, repeat, or share. | caption-worthy, memorable lines, one-liners | positive | Dimensions: lyricFocus, replayability | tasteSignalOnly | Yes |
| raw vocals | `craft.raw-vocals` | The voice preserves strain, imperfection, or emotional immediacy. | unpolished vocals, rough vocals, emotionally raw singing | positive | Dimensions: vocalFocus, emotionalDirectness | tasteSignalOnly | No |
| smooth vocals | `craft.smooth-vocals` | The voice moves with ease, polish, and little audible strain. | silky vocals, effortless vocals, smooth singing | positive | Dimensions: vocalFocus | tasteSignalOnly | Yes |
| socially conscious | `craft.socially-conscious` | Engages directly with social, political, cultural, or community concerns. | political, conscious, message-driven | neutral | Dimensions: lyricFocus | tasteSignalOnly | No |
| solos | `craft.solos` | Instrumental solo sections provide a major highlight. | great solos, soloing, instrumental breaks | positive | Dimensions: instrumentalRichness | tasteSignalOnly | No |
| soulful vocals | `craft.soulful-vocals` | The vocal performance communicates depth, feeling, and lived-in expression. | emotional vocals, heartfelt singing | positive | Dimensions: vocalFocus, emotionalDirectness | tasteSignalOnly | Yes |
| standout singles | `craft.standout-singles` | The major singles or obvious centerpiece tracks deliver strongly. | great singles, big tracks, hits | positive | Dimensions: replayability | tasteSignalOnly | No |
| storytelling | `craft.storytelling` | The writing builds scenes, characters, events, or a clear narrative. | narrative, story-driven, paints a picture | positive | Dimensions: lyricFocus | tasteSignalOnly | Yes |
| strong closer | `craft.strong-closer` | The final track resolves or completes the album effectively. | great outro, ending track, finishes strong | positive | Dimensions: tracklistConsistency | tasteSignalOnly | No |
| strong melodies | `craft.strong-melodies` | The melodic writing carries the songs and remains memorable. | melodic, great melodies, melody-first | positive | Dimensions: replayability | tasteSignalOnly | Yes |
| strong opener | `craft.strong-opener` | The opening track establishes the album effectively and creates immediate interest. | great intro, opening track, starts strong | positive | Dimensions: tracklistConsistency | tasteSignalOnly | No |
| strong vocals | `craft.strong-vocals` | The vocal performance is a clear strength in control, expression, or presence. | vocals, great singing, vocal performance | positive | Dimensions: vocalFocus | tasteSignalOnly | Yes |
| technical rapping | `craft.technical-rapping` | The rap performance emphasizes precision, complexity, breath control, or difficult patterns. | technical bars, complex flows, rap technique | positive | Dimensions: lyricFocus | tasteSignalOnly | No |
| well-sequenced | `craft.well-sequenced` | The track order creates satisfying pacing, contrast, and progression. | great sequencing, flows well, track order | positive | Dimensions: tracklistConsistency | tasteSignalOnly | Yes |
| witty | `craft.witty` | The writing or performance uses clever humor, timing, or verbal play. | funny, clever, sharp humor | positive | Dimensions: lyricFocus | tasteSignalOnly | No |
| wordplay | `craft.wordplay` | Uses puns, double meanings, internal connections, or verbal technique. | double entendres, puns, clever bars | positive | Dimensions: lyricFocus | tasteSignalOnly | No |

## Listening Context

| Display | ID | Definition | Aliases | Polarity | SoundPrint / Avoidance | Role | Primary |
|---|---|---|---|---|---|---|---|
| background listening | `context.background-listening` | Works without demanding full attention throughout. | background music, passive listening, in the background | neutral | — | displayOnly | Yes |
| cleaning | `context.cleaning` | Fits chores through movement, energy, or easy replay. | chores, housework, Sunday cleaning | neutral | — | displayOnly | Yes |
| club | `context.club` | Fits a nightclub, dance floor, or high-volume late-night setting. | dance club, rave, nightclub | neutral | — | displayOnly | Yes |
| commute | `context.commute` | Fits routine travel to work, school, or another daily destination. | commuting, train ride, morning commute | neutral | — | displayOnly | No |
| cooking | `context.cooking` | Fits meal preparation through rhythm, warmth, or background presence. | kitchen music, making dinner, chef mode | neutral | — | displayOnly | Yes |
| cookout | `context.cookout` | Fits an outdoor gathering, barbecue, or relaxed group hang. | bbq, barbecue, backyard | neutral | — | displayOnly | No |
| creative work | `context.creative-work` | Supports visual, musical, design, or open-ended creative activity. | making art, designing, creating | neutral | — | displayOnly | No |
| cycling | `context.cycling` | Fits indoor or outdoor cycling through steady movement or pace. | bike ride, biking, spin class | neutral | — | displayOnly | No |
| date night | `context.date-night` | Fits romantic or intimate time with another person. | romantic evening, dinner date, with someone | neutral | — | displayOnly | Yes |
| driving | `context.driving` | Fits general time in the car, whether active or relaxed. | car music, in the car, windows down | neutral | — | displayOnly | Yes |
| flying | `context.flying` | Fits airports, flights, or reflective travel time. | plane music, airport, in-flight | neutral | — | displayOnly | No |
| focus | `context.focus` | Supports concentration, deep work, or attention-heavy tasks. | concentration, deep work, lock in | neutral | — | displayOnly | Yes |
| getting ready | `context.getting-ready` | Fits dressing, grooming, or preparing to leave the house. | GRWM, before going out, getting dressed | neutral | — | displayOnly | Yes |
| group listening | `context.group-listening` | Works well as a shared listen with friends or other people. | with friends, shared listen, play for people | neutral | — | displayOnly | No |
| gym | `context.gym` | Fits strength training, workouts, or high-effort exercise. | workout, lifting, training | neutral | — | displayOnly | Yes |
| hanging out | `context.hanging-out` | Fits casual, low-pressure time with friends or family. | chilling with friends, kickback, casual hang | neutral | — | displayOnly | Yes |
| headphones | `context.headphones` | Rewards close, private, or detail-focused headphone listening. | headphone album, with headphones, close listening | neutral | — | displayOnly | Yes |
| hosting | `context.hosting` | Works while entertaining guests without demanding constant attention. | having people over, dinner party, host music | neutral | — | displayOnly | No |
| late night | `context.late-night` | Fits quiet, reflective, or atmospheric listening after dark. | midnight, nighttime, after hours | neutral | — | displayOnly | Yes |
| morning | `context.morning` | Fits starting the day through energy, calm, or routine. | wake-up music, early morning, start the day | neutral | — | displayOnly | Yes |
| night drive | `context.night-drive` | Fits driving after dark through atmosphere, focus, or mood. | late-night drive, midnight drive, driving at night | neutral | — | displayOnly | Yes |
| party | `context.party` | Fits an energetic social gathering where music drives the room. | house party, party music, function | neutral | — | displayOnly | Yes |
| pregame | `context.pregame` | Fits getting ready and building energy before going out. | pre-game, before the party, getting hype | neutral | — | displayOnly | Yes |
| rainy day | `context.rainy-day` | Fits rain, overcast weather, or inward-looking time indoors. | rain music, stormy day, overcast | neutral | — | displayOnly | Yes |
| reading | `context.reading` | Complements reading through steadiness, atmosphere, or restraint. | book music, reading soundtrack, with a book | neutral | — | displayOnly | No |
| road trip | `context.road-trip` | Fits long-distance travel and extended shared listening. | roadtrip, long drive, travel music | neutral | — | displayOnly | Yes |
| running | `context.running` | Fits a run through pace, momentum, or sustained energy. | jogging, run playlist, 5k | neutral | — | displayOnly | Yes |
| sleep | `context.sleep` | Supports winding down, resting, or falling asleep. | bedtime, sleep music, wind down | neutral | — | displayOnly | No |
| solo listening | `context.solo-listening` | Feels best experienced privately or without conversation. | by myself, private listen | neutral | — | displayOnly | No |
| speakers | `context.speakers` | Feels especially effective played openly through a room or sound system. | big speakers, room-filling, play it loud | neutral | — | displayOnly | No |
| studying | `context.studying` | Supports sustained study without repeatedly breaking concentration. | study music, homework, schoolwork | neutral | — | displayOnly | Yes |
| summer | `context.summer` | Fits warm-weather listening, seasonal memories, or summer routines. | summer music, hot weather, summer vibes | neutral | — | displayOnly | Yes |
| sunset | `context.sunset` | Fits the transition into evening through warmth, reflection, or atmosphere. | golden hour, dusk, sunset drive | neutral | — | displayOnly | Yes |
| walking | `context.walking` | Fits a walk where the listener wants rhythm without overwhelming intensity. | walk, strolling, hot girl walk | neutral | — | displayOnly | No |
| winter | `context.winter` | Fits cold-weather listening, indoor reflection, or winter atmosphere. | winter music, cold weather, snow day | neutral | — | displayOnly | No |
| work | `context.work` | Fits general work time without becoming too distracting. | working, office, workday | neutral | — | displayOnly | No |
| writing | `context.writing` | Supports journaling, drafting, or other language-focused creative work. | journaling, creative writing, drafting | neutral | — | displayOnly | No |

## Personal Reaction

| Display | ID | Definition | Aliases | Polarity | SoundPrint / Avoidance | Role | Primary |
|---|---|---|---|---|---|---|---|
| album of the year | `reaction.album-of-the-year` | Feels like a top-tier release within the listener’s current year of listening. | AOTY, best album this year, year-end favorite | positive | Dimensions: replayability | tasteSignalOnly | No |
| artist breakthrough | `reaction.artist-breakthrough` | Feels like a meaningful creative step forward for the artist. | leveled up, career high, breakout | positive | Dimensions: experimentation | tasteSignalOnly | No |
| better with time | `reaction.better-with-time` | Has continued improving after the initial listening period. | aging well, keeps getting better, better later | positive | Dimensions: replayability | tasteSignalOnly | No |
| clicked immediately | `reaction.clicked-immediately` | The album made sense and connected on the first listen. | instant click, got it right away, immediate | positive | Dimensions: replayability | tasteSignalOnly | Yes |
| comfort album | `reaction.comfort-album` | Feels emotionally familiar, safe, or dependable enough to return to for comfort. | comfort listen, safe album, always there | positive | Dimensions: mood, replayability | tasteSignalOnly | Yes |
| distinctive | `reaction.distinctive` | Has an identity that is easy to recognize and difficult to confuse with other work. | unique, recognizable, stands out | positive | Dimensions: experimentation, texturePreference | tasteSignalOnly | Yes |
| emotionally resonant | `reaction.emotionally-resonant` | Connected strongly to the listener’s emotions or lived experience. | hit home, resonated, felt personal | positive | Dimensions: mood, emotionalDirectness | tasteSignalOnly | Yes |
| grower | `reaction.grower` | Improved meaningfully as the listener spent more time with it. | grew on me, slow grower, took time | positive | Dimensions: replayability | tasteSignalOnly | Yes |
| hidden gem | `reaction.hidden-gem` | Feels underappreciated relative to the listener’s enjoyment of it. | underrated, slept on, overlooked | positive | Dimensions: replayability | tasteSignalOnly | No |
| instant favorite | `reaction.instant-favorite` | Connected strongly enough on first or early listens to feel immediately special. | immediate favorite, love at first listen, new favorite | positive | Dimensions: replayability | tasteSignalOnly | Yes |
| lost its shine | `reaction.lost-its-shine` | Initially impressed but became less compelling after repeated listening. | wore off, didn't age well, faded | negative | Avoidance: lowReplayValue | avoidanceSignal | No |
| memorable | `reaction.memorable` | Leaves a clear lasting impression after the listen ends. | stays with me, hard to forget, lasting | positive | Dimensions: replayability | tasteSignalOnly | Yes |
| mood booster | `reaction.mood-booster` | Reliably improves the listener’s mood. | pick-me-up, cheers me up, instant mood lift | positive | Dimensions: mood, replayability | tasteSignalOnly | Yes |
| moving | `reaction.moving` | Provoked a strong emotional response without requiring a specific mood. | touching, made me feel | positive | Dimensions: mood, emotionalDirectness | tasteSignalOnly | Yes |
| needs more listens | `reaction.needs-more-listens` | The listener is not ready to make a settled judgment yet. | need more time, not sure yet, another listen | mixed | Dimensions: replayability | tasteSignalOnly | Yes |
| no skips | `reaction.no-skips` | The listener currently wants to hear the entire tracklist without skipping. | zero skips, front to back, not a single skip | positive | Dimensions: tracklistConsistency, replayability | tasteSignalOnly | Yes |
| on repeat | `reaction.on-repeat` | The listener is actively returning to the album or key songs repeatedly. | repeat, in rotation, can't stop playing | positive | Dimensions: replayability | tasteSignalOnly | Yes |
| personal favorite | `reaction.personal-favorite` | Holds special value to this listener beyond a general quality judgment. | one of my favorites, special to me, personal classic | positive | Dimensions: replayability | tasteSignalOnly | No |
| replayable | `reaction.replayable` | Feels likely to reward repeated listening. | replay value, will replay, run it back | positive | Dimensions: replayability | tasteSignalOnly | Yes |
| thought-provoking | `reaction.thought-provoking` | Continued generating questions, ideas, or reflection after listening. | made me think, stuck with me, provocative | positive | Dimensions: lyricFocus, experimentation | tasteSignalOnly | Yes |
| timeless | `reaction.timeless` | Feels durable beyond a specific trend, moment, or release cycle. | won't age, evergreen, built to last | positive | Dimensions: eraAffinity, replayability | tasteSignalOnly | Yes |
| unexpected | `reaction.unexpected` | Surprised the listener in style, quality, direction, or emotional effect. | surprising, didn't expect this, caught me off guard | positive | Dimensions: experimentation | tasteSignalOnly | Yes |

## Friction & Critique

| Display | ID | Definition | Aliases | Polarity | SoundPrint / Avoidance | Role | Primary |
|---|---|---|---|---|---|---|---|
| awkward features | `critique.awkward-features` | Guest appearances interrupt the songs or feel poorly matched. | bad features, features don't fit, weak guest verses | negative | — | displayOnly | Yes |
| back-loaded | `critique.back-loaded` | The project takes too long to reach its strongest material. | slow first half, gets good late, best songs last | negative | Avoidance: skipHeavyAlbums | avoidanceSignal | No |
| bloated | `critique.bloated` | The project contains more material than its strongest ideas can support. | overstuffed, too much filler, trim the tracklist | negative | Avoidance: fillerSensitivity | avoidanceSignal | Yes |
| boring | `critique.boring` | The listen fails to sustain attention or curiosity. | dull, tedious, uninteresting | negative | Avoidance: lowReplayValue | avoidanceSignal | Yes |
| dated production | `critique.dated-production` | The production feels tied to an era in a way that weakens the current listen. | aged badly, sounds outdated, old in a bad way | negative | — | displayOnly | No |
| derivative | `critique.derivative` | The project relies too heavily on recognizable ideas from other artists or styles. | copycat, too similar, unoriginal | negative | — | displayOnly | No |
| didn't click | `critique.didnt-click` | The album has not made sense or connected for the listener at this point. | did not click, not clicking, never connected | negative | Avoidance: moodMismatch | avoidanceSignal | Yes |
| emotionally distant | `critique.emotionally-distant` | The material feels difficult to emotionally enter or connect with. | cold emotionally, detached, no emotional connection | negative | Avoidance: moodMismatch | avoidanceSignal | Yes |
| exhausting | `critique.exhausting` | The project’s intensity, density, length, or repetition becomes tiring. | fatiguing, too much, draining | negative | Avoidance: fillerSensitivity | avoidanceSignal | No |
| filler | `critique.filler` | Some tracks feel included without adding enough value to the project. | filler tracks, dead weight, padding | negative | Avoidance: fillerSensitivity | avoidanceSignal | Yes |
| flat delivery | `critique.flat-delivery` | The vocal or rap performance lacks emphasis, character, or emotional variation. | monotone, lifeless delivery, no presence | negative | — | displayOnly | Yes |
| flat production | `critique.flat-production` | The production lacks depth, movement, contrast, or impact. | lifeless production, boring production, production has no depth | negative | Avoidance: energyWithoutPayoff | avoidanceSignal | Yes |
| forgettable | `critique.forgettable` | The project leaves little reason or desire to return after it ends. | unmemorable, didn't stick, fades away | negative | Avoidance: lowReplayValue | avoidanceSignal | Yes |
| forgettable lyrics | `critique.forgettable-lyrics` | The words leave little lasting impression after the music ends. | unmemorable lyrics, lyrics don't stick, bland lyrics | negative | Avoidance: weakWriting | avoidanceSignal | Yes |
| front-loaded | `critique.front-loaded` | The strongest material appears early and the project declines afterward. | best songs first, falls off, strong first half | negative | Avoidance: skipHeavyAlbums | avoidanceSignal | No |
| generic | `critique.generic` | The project lacks enough distinctive identity or perspective. | basic, cookie-cutter, nothing unique | negative | — | displayOnly | Yes |
| hard to connect | `critique.hard-to-connect` | The listener understands the intent but cannot form a personal connection. | can't connect, doesn't resonate, not for me | negative | Avoidance: moodMismatch | avoidanceSignal | Yes |
| harsh mix | `critique.harsh-mix` | The sound is fatiguing or abrasive in an unintended way. | piercing mix, too sharp, ear fatigue | negative | — | displayOnly | No |
| inaccessible | `critique.inaccessible` | The album’s choices make entry unusually difficult for this listener. | hard to get into, impenetrable, difficult listen | negative | — | displayOnly | No |
| inconsistent | `critique.inconsistent` | The album does not maintain a reliable standard, sound, or level of focus. | all over the place, inconsistent tracklist, quality varies | negative | Avoidance: skipHeavyAlbums | avoidanceSignal | Yes |
| lacks energy | `critique.lacks-energy` | The project feels less active, forceful, or animated than the listener wants. | low energy, no energy, flat energy | negative | Avoidance: energyWithoutPayoff | avoidanceSignal | Yes |
| missed potential | `critique.missed-potential` | The ingredients suggest a stronger result than the finished project delivers. | wasted potential, could have been better, almost there | negative | Avoidance: energyWithoutPayoff | avoidanceSignal | Yes |
| muddy mix | `critique.muddy-mix` | Elements blur together and lack useful clarity or separation. | muddy, unclear mix, everything blends | negative | — | displayOnly | Yes |
| one-note | `critique.one-note` | The project stays in one mode without enough contrast or progression. | same mood throughout, no variety, one dimensional | negative | Avoidance: fillerSensitivity | avoidanceSignal | Yes |
| overlong | `critique.overlong` | The runtime feels longer than the material justifies. | too long, drags on, longer than needed | negative | Avoidance: fillerSensitivity | avoidanceSignal | Yes |
| overproduced | `critique.overproduced` | The production feels excessively polished, layered, or controlled. | too produced, overly polished, too much production | negative | Avoidance: sterileProduction | avoidanceSignal | Yes |
| poor chemistry | `critique.poor-chemistry` | Performers or collaborators do not sound naturally connected. | no chemistry, collab doesn't work, mismatched artists | negative | — | displayOnly | No |
| poor sequencing | `critique.poor-sequencing` | The track order weakens pacing, transitions, or the album’s overall arc. | bad sequencing, track order is off, doesn't flow | negative | Avoidance: skipHeavyAlbums | avoidanceSignal | Yes |
| predictable | `critique.predictable` | The songs or album repeatedly follow expected paths without useful surprise. | saw it coming, formulaic, obvious | negative | — | displayOnly | Yes |
| repetitive | `critique.repetitive` | Ideas, structures, or sounds repeat without enough development or variation. | samey, too repetitive, keeps repeating | negative | Avoidance: fillerSensitivity | avoidanceSignal | Yes |
| skip-heavy | `critique.skip-heavy` | The listener wants to skip a substantial portion of the tracklist. | too many skips, lots of skips, skip city | negative | Avoidance: skipHeavyAlbums | avoidanceSignal | Yes |
| too many features | `critique.too-many-features` | Guest appearances crowd out the main artist or weaken the project’s identity. | feature overload, too many guests, crowded features | negative | — | displayOnly | No |
| too polished | `critique.too-polished` | The clean finish removes character, tension, or human texture. | sterile, clinical, too clean | negative | Avoidance: sterileProduction | avoidanceSignal | Yes |
| too safe | `critique.too-safe` | The project avoids risk in a way that limits its personality or impact. | plays it safe, risk-free, conservative | negative | — | displayOnly | Yes |
| too short | `critique.too-short` | The project ends before its ideas feel fully developed or satisfying. | ends too soon, not enough, too brief | negative | — | displayOnly | No |
| underdeveloped | `critique.underdeveloped` | Strong ideas appear but are not explored or completed enough. | half-baked, not fully realized, needed more | negative | Avoidance: energyWithoutPayoff | avoidanceSignal | Yes |
| underproduced | `critique.underproduced` | The ideas feel insufficiently developed, arranged, recorded, or finished. | not produced enough, unfinished production, thin production | negative | — | displayOnly | No |
| uneven | `critique.uneven` | The project has meaningful highs but noticeable dips in quality or execution. | up and down, mixed quality, inconsistent quality | negative | Avoidance: skipHeavyAlbums | avoidanceSignal | Yes |
| unfinished | `critique.unfinished` | The album or songs feel incomplete in writing, structure, performance, or production. | incomplete, demo quality, not finished | negative | Avoidance: energyWithoutPayoff | avoidanceSignal | No |
| weak hooks | `critique.weak-hooks` | The repeated melodic or lyrical sections fail to land or stay memorable. | bad hooks, hooks don't hit, weak choruses | negative | Avoidance: weakWriting | avoidanceSignal | Yes |
| weak vocals | `critique.weak-vocals` | The vocal performance feels limited, unconvincing, or poorly suited to the material. | bad vocals, singing is weak, vocal issues | negative | — | displayOnly | No |
| weak writing | `critique.weak-writing` | The lyrical ideas or execution feel thin, lazy, or insufficiently developed. | bad writing, lazy writing, thin lyrics | negative | Avoidance: weakWriting | avoidanceSignal | Yes |

# Appendix B — Complete Genre & Style Catalog

## Hip-Hop & Rap

| Display | ID | Parent | Aliases |
|---|---|---|---|
| abstract hip-hop | `genre.abstract-hip-hop` | hip-hop | abstract rap |
| alternative hip-hop | `genre.alternative-hip-hop` | hip-hop | alternative rap |
| boom bap | `genre.boom-bap` | hip-hop | boom-bap |
| cloud rap | `genre.cloud-rap` | hip-hop | — |
| conscious hip-hop | `genre.conscious-hip-hop` | hip-hop | conscious rap |
| drill | `genre.drill` | hip-hop | uk drill, chicago drill, brooklyn drill |
| experimental hip-hop | `genre.experimental-hip-hop` | hip-hop | experimental rap |
| gangsta rap | `genre.gangsta-rap` | hip-hop | gangster rap |
| grime | `genre.grime` | hip-hop | — |
| hip-hop | `genre.hip-hop` | — | hip hop, rap, hip-hop/rap |
| horrorcore | `genre.horrorcore` | hip-hop | — |
| jazz rap | `genre.jazz-rap` | hip-hop | — |
| lo-fi hip-hop | `genre.lo-fi-hip-hop` | hip-hop | lofi hip hop, chillhop |
| melodic rap | `genre.melodic-rap` | hip-hop | sing-rap |
| southern hip-hop | `genre.southern-hip-hop` | hip-hop | southern rap |
| trap | `genre.trap` | hip-hop | — |

## R&B, Soul & Funk

| Display | ID | Parent | Aliases |
|---|---|---|---|
| alternative r&b | `genre.alternative-rnb` | r&b | alt r&b |
| blue-eyed soul | `genre.blue-eyed-soul` | soul | blue eyed soul |
| contemporary r&b | `genre.contemporary-rnb` | r&b | modern r&b |
| funk | `genre.funk` | — | — |
| gospel soul | `genre.gospel-soul` | soul | — |
| motown | `genre.motown` | soul | motown sound |
| neo-soul | `genre.neo-soul` | r&b | neo soul |
| new jack swing | `genre.new-jack-swing` | r&b | — |
| p-funk | `genre.p-funk` | funk | parliament-funkadelic |
| psychedelic soul | `genre.psychedelic-soul` | soul | — |
| quiet storm | `genre.quiet-storm` | r&b | — |
| r&b | `genre.rnb` | — | rnb, rhythm and blues, r&b/soul |
| soul | `genre.soul` | — | — |
| southern soul | `genre.southern-soul` | soul | — |

## Pop

| Display | ID | Parent | Aliases |
|---|---|---|---|
| alternative pop | `genre.alt-pop` | pop | alt pop |
| art pop | `genre.art-pop` | pop | — |
| bedroom pop | `genre.bedroom-pop` | pop | — |
| bubblegum pop | `genre.bubblegum-pop` | pop | — |
| chamber pop | `genre.chamber-pop` | pop | — |
| children's music | `genre.childrens-music` | — | kids music, children |
| dance-pop | `genre.dance-pop` | pop | dance pop |
| dream pop | `genre.dream-pop` | pop | — |
| easy listening | `genre.easy-listening` | — | — |
| electropop | `genre.electropop` | pop | electro pop |
| holiday | `genre.holiday` | — | christmas, seasonal |
| hyperpop | `genre.hyperpop` | pop | — |
| indie pop | `genre.indie-pop` | pop | — |
| pop | `genre.pop` | — | — |
| pop rock | `genre.pop-rock` | pop | — |
| power pop | `genre.power-pop` | pop | — |
| sophisti-pop | `genre.sophisti-pop` | pop | sophisti pop |
| synth-pop | `genre.synth-pop` | pop | synthpop |
| teen pop | `genre.teen-pop` | pop | — |

## Rock

| Display | ID | Parent | Aliases |
|---|---|---|---|
| alternative | `genre.alternative` | rock | alternative music |
| alternative rock | `genre.alternative-rock` | rock | alt rock |
| britpop | `genre.britpop` | rock | — |
| classic rock | `genre.classic-rock` | rock | — |
| garage rock | `genre.garage-rock` | rock | — |
| glam rock | `genre.glam-rock` | rock | — |
| grunge | `genre.grunge` | rock | — |
| hard rock | `genre.hard-rock` | rock | — |
| heartland rock | `genre.heartland-rock` | rock | — |
| indie rock | `genre.indie-rock` | rock | — |
| krautrock | `genre.krautrock` | rock | — |
| math rock | `genre.math-rock` | rock | — |
| noise rock | `genre.noise-rock` | rock | — |
| post-rock | `genre.post-rock` | rock | — |
| progressive rock | `genre.progressive-rock` | rock | prog rock |
| psychedelic rock | `genre.psychedelic-rock` | rock | psych rock |
| rock | `genre.rock` | — | — |
| shoegaze | `genre.shoegaze` | rock | — |
| soft rock | `genre.soft-rock` | rock | — |
| southern rock | `genre.southern-rock` | rock | — |
| surf rock | `genre.surf-rock` | rock | — |

## Punk, Hardcore & Metal

| Display | ID | Parent | Aliases |
|---|---|---|---|
| black metal | `genre.black-metal` | metal | — |
| death metal | `genre.death-metal` | metal | — |
| deathcore | `genre.deathcore` | metal | — |
| doom metal | `genre.doom-metal` | metal | — |
| emo | `genre.emo` | — | — |
| folk metal | `genre.folk-metal` | metal | — |
| gothic metal | `genre.gothic-metal` | metal | — |
| hardcore punk | `genre.hardcore-punk` | punk | hardcore |
| heavy metal | `genre.heavy-metal` | metal | — |
| industrial metal | `genre.industrial-metal` | metal | — |
| metal | `genre.metal` | — | — |
| metalcore | `genre.metalcore` | metal | — |
| nu metal | `genre.nu-metal` | metal | nu-metal |
| pop punk | `genre.pop-punk` | punk | — |
| post-hardcore | `genre.post-hardcore` | hardcore punk | — |
| post-punk | `genre.post-punk` | punk | — |
| power metal | `genre.power-metal` | metal | — |
| progressive metal | `genre.progressive-metal` | metal | prog metal |
| punk | `genre.punk` | — | punk rock |
| screamo | `genre.screamo` | emo | — |
| sludge metal | `genre.sludge-metal` | metal | — |
| thrash metal | `genre.thrash-metal` | metal | — |

## Electronic & Dance

| Display | ID | Parent | Aliases |
|---|---|---|---|
| acid house | `genre.acid-house` | house | — |
| afro house | `genre.afro-house` | house | afro-house |
| bass music | `genre.bass-music` | electronic | — |
| breakbeat | `genre.breakbeat` | electronic | breaks |
| deep house | `genre.deep-house` | house | — |
| detroit techno | `genre.detroit-techno` | techno | — |
| disco | `genre.disco` | — | — |
| downtempo | `genre.downtempo` | electronic | — |
| drum and bass | `genre.drum-and-bass` | electronic | dnb, d&b |
| dubstep | `genre.dubstep` | electronic | — |
| edm | `genre.edm` | electronic | electronic dance music |
| electro | `genre.electro` | electronic | — |
| electroclash | `genre.electroclash` | electronic | — |
| electronic | `genre.electronic` | — | dance |
| footwork | `genre.footwork` | electronic | — |
| french house | `genre.french-house` | house | — |
| future bass | `genre.future-bass` | electronic | — |
| gabber | `genre.gabber` | electronic | hardcore techno |
| hardstyle | `genre.hardstyle` | electronic | — |
| house | `genre.house` | electronic | — |
| idm | `genre.idm` | electronic | intelligent dance music |
| jungle | `genre.jungle` | drum and bass | — |
| minimal techno | `genre.minimal-techno` | techno | — |
| nu-disco | `genre.nu-disco` | disco | nu disco |
| progressive house | `genre.progressive-house` | house | — |
| progressive trance | `genre.progressive-trance` | trance | — |
| psytrance | `genre.psytrance` | trance | psychedelic trance |
| synthwave | `genre.synthwave` | electronic | retrowave |
| tech house | `genre.tech-house` | house | — |
| techno | `genre.techno` | electronic | — |
| trance | `genre.trance` | electronic | — |
| trip-hop | `genre.trip-hop` | downtempo | trip hop |
| uk garage | `genre.uk-garage` | electronic | 2-step, 2 step garage |

## Jazz & Blues

| Display | ID | Parent | Aliases |
|---|---|---|---|
| bebop | `genre.bebop` | jazz | — |
| big band | `genre.big-band` | jazz | — |
| blues | `genre.blues` | — | — |
| blues rock | `genre.blues-rock` | blues | — |
| chicago blues | `genre.chicago-blues` | blues | — |
| cool jazz | `genre.cool-jazz` | jazz | — |
| delta blues | `genre.delta-blues` | blues | — |
| electric blues | `genre.electric-blues` | blues | — |
| free jazz | `genre.free-jazz` | jazz | — |
| hard bop | `genre.hard-bop` | jazz | — |
| jazz | `genre.jazz` | — | — |
| jazz fusion | `genre.jazz-fusion` | jazz | fusion jazz |
| jazz-funk | `genre.jazz-funk` | jazz | jazz funk |
| modal jazz | `genre.modal-jazz` | jazz | — |
| smooth jazz | `genre.smooth-jazz` | jazz | — |
| spiritual jazz | `genre.spiritual-jazz` | jazz | — |
| swing | `genre.swing` | jazz | — |
| vocal jazz | `genre.vocal-jazz` | jazz | — |

## Country, Folk & Americana

| Display | ID | Parent | Aliases |
|---|---|---|---|
| acoustic folk | `genre.acoustic-folk` | folk | — |
| alt-country | `genre.alt-country` | country | alternative country |
| americana | `genre.americana` | — | — |
| bluegrass | `genre.bluegrass` | — | — |
| contemporary country | `genre.contemporary-country` | country | — |
| country | `genre.country` | — | — |
| country pop | `genre.country-pop` | country | — |
| cowboy country | `genre.cowboy-country` | country | western country |
| folk | `genre.folk` | — | — |
| folk rock | `genre.folk-rock` | folk | — |
| honky-tonk | `genre.honky-tonk` | country | honky tonk |
| indie folk | `genre.indie-folk` | folk | — |
| outlaw country | `genre.outlaw-country` | country | — |
| roots rock | `genre.roots-rock` | rock | — |
| singer-songwriter | `genre.singer-songwriter` | — | singer songwriter, singer/songwriter |
| traditional folk | `genre.traditional-folk` | folk | — |
| western swing | `genre.western-swing` | country | — |

## Caribbean

| Display | ID | Parent | Aliases |
|---|---|---|---|
| calypso | `genre.calypso` | — | — |
| dancehall | `genre.dancehall` | — | — |
| dub | `genre.dub` | reggae | — |
| kompa | `genre.kompa` | — | compas |
| lovers rock | `genre.lovers-rock` | reggae | — |
| mento | `genre.mento` | — | — |
| reggae | `genre.reggae` | — | — |
| reggae fusion | `genre.reggae-fusion` | reggae | — |
| roots reggae | `genre.roots-reggae` | reggae | — |
| soca | `genre.soca` | — | — |
| zouk | `genre.zouk` | — | — |

## African

| Display | ID | Parent | Aliases |
|---|---|---|---|
| African gospel | `genre.african-gospel` | — | — |
| afro-fusion | `genre.afro-fusion` | — | afrofusion |
| Afro-soul | `genre.afro-soul` | — | afrosoul |
| Afrobeat | `genre.afrobeat` | — | fela-style afrobeat |
| afrobeats | `genre.afrobeats` | — | afrobeats pop |
| afropop | `genre.afropop` | — | afro-pop |
| alté | `genre.alte` | — | alte |
| amapiano | `genre.amapiano` | — | — |
| coupé-décalé | `genre.coupe-decale` | — | coupe decale |
| Ethio-jazz | `genre.ethio-jazz` | — | ethiopian jazz |
| gqom | `genre.gqom` | — | — |
| highlife | `genre.highlife` | — | — |
| kwaito | `genre.kwaito` | — | — |
| mbalax | `genre.mbalax` | — | — |
| mbaqanga | `genre.mbaqanga` | — | — |
| soukous | `genre.soukous` | — | congolese rumba |

## Latin

| Display | ID | Parent | Aliases |
|---|---|---|---|
| Afro-Cuban | `genre.afro-cuban` | — | afro cuban |
| bachata | `genre.bachata` | — | — |
| banda | `genre.banda` | música mexicana | — |
| bolero | `genre.bolero` | — | — |
| corridos | `genre.corridos` | música mexicana | corrido |
| corridos tumbados | `genre.corridos-tumbados` | corridos | tumbados |
| cumbia | `genre.cumbia` | — | — |
| dembow | `genre.dembow` | — | — |
| Latin alternative | `genre.latin-alternative` | — | alternativo latino |
| Latin pop | `genre.latin-pop` | — | pop latino |
| Latin trap | `genre.latin-trap` | — | trap latino |
| mariachi | `genre.mariachi` | música mexicana | — |
| merengue | `genre.merengue` | — | — |
| música mexicana | `genre.musica-mexicana` | — | musica mexicana, música mexicana |
| norteño | `genre.norteno` | música mexicana | norteno |
| reggaeton | `genre.reggaeton` | — | — |
| regional Mexican | `genre.regional-mexican` | música mexicana | regional mexicano |
| salsa | `genre.salsa` | — | — |
| son cubano | `genre.son-cubano` | — | cuban son |
| tango | `genre.tango` | — | — |
| Tejano | `genre.tejano` | — | — |
| vallenato | `genre.vallenato` | — | — |

## Brazilian

| Display | ID | Parent | Aliases |
|---|---|---|---|
| axé | `genre.axé` | — | axe |
| bossa nova | `genre.bossa-nova` | — | — |
| Brazilian funk | `genre.brazilian-funk` | — | funk carioca, baile funk |
| Brazilian jazz | `genre.brazilian-jazz` | — | — |
| Brazilian rock | `genre.brazilian-rock` | — | — |
| choro | `genre.choro` | — | — |
| forró | `genre.forro` | — | forro |
| MPB | `genre.mpb` | — | música popular brasileira, musica popular brasileira |
| pagode | `genre.pagode` | — | — |
| samba | `genre.samba` | — | — |
| sertanejo | `genre.sertanejo` | — | — |
| tropicália | `genre.tropicalia` | — | tropicalia |

## South Asian

| Display | ID | Parent | Aliases |
|---|---|---|---|
| Bengali modern | `genre.bengali-modern` | — | adhunik |
| bhajan | `genre.bhajan` | — | — |
| bhangra | `genre.bhangra` | — | — |
| Bollywood | `genre.bollywood` | — | hindi film music |
| Carnatic classical | `genre.carnatic-classical` | Indian classical | south indian classical |
| desi hip-hop | `genre.desi-hip-hop` | — | desi rap |
| ghazal | `genre.ghazal` | — | — |
| Hindustani classical | `genre.hindustani-classical` | Indian classical | north indian classical |
| Indian classical | `genre.indian-classical` | — | — |
| Indian film music | `genre.indian-film-music` | — | filmi |
| Indian indie | `genre.indian-indie` | — | — |
| Indipop | `genre.indipop` | — | Indian pop |
| Malayalam film music | `genre.malayalam-film-music` | Indian film music | — |
| Pakistani pop | `genre.pakistani-pop` | — | — |
| Punjabi pop | `genre.punjabi-pop` | — | — |
| qawwali | `genre.qawwali` | — | — |
| Sri Lankan pop | `genre.sri-lankan-pop` | — | — |
| Sufi music | `genre.sufi-music` | — | sufi |
| Tamil film music | `genre.tamil-film-music` | Indian film music | kollywood |
| Telugu film music | `genre.telugu-film-music` | Indian film music | tollywood |

## East Asian

| Display | ID | Parent | Aliases |
|---|---|---|---|
| anisong | `genre.anisong` | — | anime songs |
| C-pop | `genre.c-pop` | — | chinese pop |
| Cantopop | `genre.cantopop` | — | cantonese pop |
| Chinese hip-hop | `genre.chinese-hip-hop` | — | chinese rap |
| city pop | `genre.city-pop` | — | japanese city pop |
| enka | `genre.enka` | — | — |
| J-pop | `genre.j-pop` | — | jpop |
| J-rock | `genre.j-rock` | — | japanese rock |
| Japanese hip-hop | `genre.japanese-hip-hop` | — | j-rap |
| Japanese jazz | `genre.japanese-jazz` | — | — |
| K-hip-hop | `genre.k-hip-hop` | — | korean hip-hop, k-rap |
| K-indie | `genre.k-indie` | — | korean indie |
| K-pop | `genre.k-pop` | — | kpop |
| K-R&B | `genre.k-rnb` | — | korean r&b, k-rnb |
| Korean ballad | `genre.korean-ballad` | — | k-ballad |
| Mandopop | `genre.mandopop` | — | mandarin pop |
| Shibuya-kei | `genre.shibuya-kei` | — | shibuya kei |
| Taiwanese pop | `genre.taiwanese-pop` | — | — |
| visual kei | `genre.visual-kei` | — | — |
| Vocaloid | `genre.vocaloid` | — | — |

## Middle Eastern & North African

| Display | ID | Parent | Aliases |
|---|---|---|---|
| Anatolian rock | `genre.anatolian-rock` | — | — |
| Arabic classical | `genre.arabic-classical` | — | — |
| Arabic hip-hop | `genre.arabic-hip-hop` | — | arab rap |
| Arabic pop | `genre.arabic-pop` | — | — |
| dabke | `genre.dabke` | — | — |
| Gnawa | `genre.gnawa` | — | — |
| Khaliji | `genre.khaliji` | — | khaleeji |
| mahraganat | `genre.mahraganat` | — | electro shaabi |
| Middle Eastern electronic | `genre.middle-eastern-electronic` | — | — |
| Mizrahi | `genre.mizrahi` | — | mizrahi music |
| Persian classical | `genre.persian-classical` | — | iranian classical |
| Persian pop | `genre.persian-pop` | — | iranian pop |
| raï | `genre.rai` | — | rai |
| shaabi | `genre.shaabi` | — | — |
| Turkish folk | `genre.turkish-folk` | — | — |
| Turkish pop | `genre.turkish-pop` | — | — |

## Classical

| Display | ID | Parent | Aliases |
|---|---|---|---|
| avant-garde classical | `genre.avant-garde-classical` | classical | — |
| Baroque | `genre.baroque` | classical | — |
| chamber music | `genre.chamber-music` | classical | — |
| choral | `genre.choral` | — | choir |
| classical | `genre.classical` | — | — |
| Classical period | `genre.classical-period` | classical | — |
| contemporary classical | `genre.contemporary-classical` | classical | — |
| early music | `genre.early-music` | classical | — |
| minimalist classical | `genre.minimalist-classical` | classical | minimalism |
| modern classical | `genre.modern-classical` | classical | — |
| neoclassical | `genre.neoclassical` | classical | neo-classical |
| opera | `genre.opera` | — | — |
| orchestral | `genre.orchestral` | classical | — |
| piano solo | `genre.piano-solo` | classical | solo piano |
| Romantic classical | `genre.romantic-classical` | classical | romantic era |
| string quartet | `genre.string-quartet` | chamber music | — |

## Ambient, New Age & Experimental

| Display | ID | Parent | Aliases |
|---|---|---|---|
| ambient | `genre.ambient` | — | — |
| avant-garde | `genre.avant-garde` | — | avant garde |
| dark ambient | `genre.dark-ambient` | ambient | — |
| drone | `genre.drone` | — | — |
| electroacoustic | `genre.electroacoustic` | — | — |
| experimental | `genre.experimental` | — | — |
| free improvisation | `genre.free-improvisation` | — | — |
| harsh noise | `genre.harsh-noise` | noise | — |
| lowercase | `genre.lowercase` | — | — |
| musique concrète | `genre.musique-concrete` | — | musique concrete |
| new age | `genre.new-age` | — | — |
| noise | `genre.noise` | — | — |
| onkyo | `genre.onkyo` | — | — |
| plunderphonics | `genre.plunderphonics` | — | — |
| sound art | `genre.sound-art` | — | — |
| vaporwave | `genre.vaporwave` | — | — |

## Soundtrack & Stage

| Display | ID | Parent | Aliases |
|---|---|---|---|
| anime soundtrack | `genre.anime-soundtrack` | soundtrack | — |
| cast recording | `genre.cast-recording` | musical theatre | original cast recording |
| film score | `genre.film-score` | soundtrack | movie score |
| incidental music | `genre.incidental-music` | soundtrack | — |
| library music | `genre.library-music` | — | — |
| musical theatre | `genre.musical-theatre` | — | musical theater |
| soundtrack | `genre.soundtrack` | — | original score |
| television score | `genre.television-score` | soundtrack | tv score |
| video game music | `genre.video-game-music` | soundtrack | game soundtrack, vgm |

## Spiritual & Religious

| Display | ID | Parent | Aliases |
|---|---|---|---|
| Buddhist chant | `genre.buddhist-chant` | — | — |
| chant | `genre.chant` | — | — |
| contemporary Christian | `genre.contemporary-christian` | — | ccm, christian |
| contemporary gospel | `genre.contemporary-gospel` | gospel | — |
| devotional | `genre.devotional` | — | — |
| gospel | `genre.gospel` | — | — |
| Jewish liturgical | `genre.jewish-liturgical` | — | — |
| kirtan | `genre.kirtan` | — | — |
| nasheed | `genre.islamic-nasheed` | — | islamic devotional |
| sacred choral | `genre.sacred-choral` | — | — |
| southern gospel | `genre.southern-gospel` | gospel | — |
| worship | `genre.worship` | — | praise and worship |

## Global & Traditional

| Display | ID | Parent | Aliases |
|---|---|---|---|
| Andean folk | `genre.andean-folk` | — | — |
| Balkan folk | `genre.balkan-folk` | — | — |
| Celtic folk | `genre.celtic-folk` | — | celtic |
| Chinese traditional | `genre.chinese-traditional` | — | — |
| comedy | `genre.comedy` | — | comedy album |
| fado | `genre.fado` | — | — |
| Filipino pop | `genre.filipino-pop` | — | opm, p-pop |
| flamenco | `genre.flamenco` | — | — |
| gamelan | `genre.gamelan` | — | — |
| global | `genre.global` | — | worldwide, world music |
| Hawaiian | `genre.hawaiian` | — | — |
| Indonesian pop | `genre.indonesian-pop` | — | — |
| Japanese traditional | `genre.japanese-traditional` | — | — |
| karaoke | `genre.karaoke` | — | — |
| klezmer | `genre.klezmer` | — | — |
| Korean traditional | `genre.korean-traditional` | — | gugak |
| Mongolian folk | `genre.mongolian-folk` | — | — |
| poetry | `genre.poetry` | — | poetry reading |
| Polynesian | `genre.polynesian` | — | — |
| Romani music | `genre.romani-music` | — | gypsy music |
| spoken word | `genre.spoken-word` | — | spoken-word |
| taiko | `genre.taiko` | — | — |
| Thai pop | `genre.thai-pop` | — | t-pop |
| Tuvan throat singing | `genre.tuvan-throat-singing` | — | throat singing |
| Vietnamese pop | `genre.vietnamese-pop` | — | v-pop |

# Appendix C — Machine-readable files

- `Listend/ListendShared/Resources/Taxonomy/Listend_Reaction_Tags_v1.json`
- `Listend/ListendShared/Resources/Taxonomy/Listend_Genre_Styles_v1.json`
- `Listend/ListendShared/Resources/Taxonomy/Listend_Ambiguous_Aliases_v1.json`
- `docs/Listend_Taxonomy_Validation_Report_v1.txt`

These files are the source of truth for implementation. The Markdown appendix is generated for human review.
