# Listend SoundPrint Listening Reflection

**Document type:** Product requirements

**Status:** Draft for implementation handoff

**Version:** 1.0

**Date:** July 28, 2026

**Product:** Listend for iOS

**Feature area:** SoundPrint, Profile, Home, Foundation Models

**Priority:** High

**Target:** iOS 26.4+

**Companion technical specification:** `docs/Listend_SoundPrint_Reflection_TechSpec.md`

---

## 1. Product decision

Listend will keep SoundPrint as a recognizable AI feature powered by Apple
Foundation Models.

SoundPrint will no longer be presented primarily as a continuously generated
persona or a separate technical profile. It will become an **earned listening
reflection**: a concise, evidence-backed observation about what the listener has
been rewarding, rejecting, or returning to in the albums they actually logged.

The user-facing hierarchy is:

1. **Reaction-first logging** captures the listener's own opinion.
2. **Your Taste So Far** reports deterministic facts from their history.
3. **SoundPrint Reflection** uses Apple Intelligence to synthesize those facts
   into a useful, human-readable observation.
4. **Today's Pick** may consume the same taste evidence, but recommendation
   changes are outside this version.

The intended user reaction is:

> Listend noticed something meaningful in my journal.

The intended user reaction is not:

> Listend generated an AI personality for me.

---

## 2. Executive summary

After a listener has logged five albums, Listend will invite them to create
their first SoundPrint Reflection. Generation happens only after an explicit
user action.

On a supported physical device, Listend will prefer Apple Foundation Models.
The generated reflection must be grounded in the listener's ratings, selected
reactions, written thoughts, and optional track highlights. The reflection will
be displayed beside deterministic receipts from the same source logs so the
listener can see why Listend reached that conclusion.

The current reflection remains stable while the listener adds a few more logs.
An update becomes available after five additional logs, or sooner when an older
log used by the reflection is edited or deleted. A failed update must not erase
or replace the last valid reflection.

The feature remains usable without Apple Intelligence through Listend's
existing deterministic local fallback, but the interface must identify the
actual generator honestly.

---

## 3. Background

### 3.1 Current product state

Listend currently has:

- A reaction-first logging flow
- Optional written thoughts and Journal Assist
- Canonical reaction tags with direct SoundPrint mappings
- Locally persisted ratings, reviews, tags, and track highlights
- Deterministic `Your Taste So Far` statistics
- SoundPrint taste dimensions, avoidance signals, and evidence receipts
- A SoundPrint persona and compact summary
- Apple Intelligence and local-fallback generation paths
- Generator-source and persona-tone badges
- SoundPrint surfaces on Home and Profile

### 3.2 Current problem

The existing SoundPrint surface feels tacked on because:

- It asks the listener to care about a generated identity rather than helping
  them reflect on their own listening.
- It is presented as a product destination before it has earned enough evidence.
- Persona language can feel broad even when the underlying evidence is specific.
- Technical controls, generator badges, tones, dimensions, and summaries compete
  for attention.
- Automatic regeneration makes each output feel disposable instead of earned.
- The connection between logging and the generated payoff is not always obvious.

The problem is product framing and interaction design, not the presence of AI.

---

## 4. Product hypothesis

If SoundPrint:

- waits until the listener has enough history,
- generates only when the listener asks,
- makes a modest observation rather than defining the listener,
- names concrete evidence from their own logs, and
- stays stable until enough new information exists,

then it will feel like a meaningful payoff to journaling rather than a separate
AI feature attached to the app.

---

## 5. Goals

### 5.1 Primary goals

- Keep an explicit, high-quality Apple Foundation Models feature in Listend.
- Make SoundPrint feel like the payoff to logging, not a competing core loop.
- Ground every generated claim in the listener's stored data.
- Give the reflection a clear unlock and refresh cadence.
- Preserve user trust by showing the source logs behind the synthesis.
- Keep logging, Profile, and existing reflections available when generation
  fails.
- Preserve deterministic local fallback behavior.

### 5.2 Secondary goals

- Make reaction-first logs materially improve SoundPrint output.
- Reduce generic persona-style language.
- Reduce visual and conceptual duplication between `Your Taste So Far` and
  SoundPrint.
- Make the Apple Intelligence contribution understandable without turning the
  screen into a technical diagnostic.
- Create a clean foundation for later monthly, seasonal, or shareable recaps.

---

## 6. Non-goals

This version will not:

- Remove Foundation Models or hide that Apple Intelligence generated an output.
- Generate a reflection after every saved log.
- Make AI generation part of the Save path.
- Replace, rewrite, or auto-save the user's own review.
- Require reviews, reactions, or track highlights.
- Add a server, account, network model, or analytics SDK.
- Add a SoundPrint archive or historical timeline.
- Add monthly or yearly recap scheduling.
- Add sharing or image export.
- Add conversational follow-up chat with SoundPrint.
- Add new SoundPrint dimensions.
- Redesign Today's Pick ranking or catalog candidate selection.
- Add Foundation Models to the Share extension.
- Add a required SwiftData migration.
- Introduce iOS 27 guided structured-generation APIs.
- Rename every internal `Persona` or `SoundPrintProfile` type in the first pass.

---

## 7. Product principles

### 7.1 The listener supplies the truth

Ratings, reactions, written thoughts, and track notes are the evidence.
Foundation Models may synthesize that evidence but may not invent new facts.

### 7.2 SoundPrint observes; it does not define

Copy should describe patterns visible **so far**. It must avoid permanent identity
claims, personality typing, or horoscope-style certainty.

### 7.3 The output must earn its space

SoundPrint appears as a generated artifact only after enough logs exist. Before
then, it is a quiet progress state in Profile, not a promotional Home module.

### 7.4 Generation is intentional

The user explicitly creates or updates a reflection. SoundPrint processing must
not silently replace the artifact after every log.

### 7.5 Receipts are part of the feature

Evidence is not relegated to debugging or disclosure copy. The screen should
show which albums, reactions, or review excerpts support the reflection.

### 7.6 AI failure is non-destructive

Saving a log never waits for AI. Failed generation keeps the last valid
reflection and all existing journal data intact.

### 7.7 Generator identity is honest

An Apple Intelligence result is labeled `Apple Intelligence`. A deterministic
fallback result is labeled `Local fallback`. The app must not imply that a local
fallback was generated by Foundation Models.

---

## 8. Terminology and user-facing naming

### 8.1 Feature name

Use **SoundPrint** as the feature brand.

### 8.2 Artifact name

Use **SoundPrint Reflection** for the generated artifact and destination title.

### 8.3 Avoid in primary user-facing copy

- Persona
- AI profile
- Taste identity
- How AI sees you
- Personality
- Engine
- Model output

Internal type and property names may retain `Persona` for compatibility in this
version.

### 8.4 Recommended supporting copy

- `A reflection on what your listening journal is revealing.`
- `Built privately from your ratings, reactions, and notes.`
- `Based on 5 logs`
- `3 new logs since this reflection`
- `Your SoundPrint is ready for an update`

---

## 9. Relationship to adjacent features

### 9.1 Reaction-first logging

The logging flow remains:

> Rate → choose reactions → optionally write a thought → save

Canonical reactions are explicit user-authored evidence and should be preferred
over loose keyword matches when SoundPrint creates taste signals.

SoundPrint must not make reactions required.

### 9.2 Journal Assist

Journal Assist remains the immediate, optional Foundation Models utility inside
logging. It helps the listener express a thought using only information they
supplied.

This project must preserve:

- Explicit `Help me write` invocation
- Editable drafts
- User confirmation before applying a draft
- Reaction grounding
- Deterministic fallback
- Save availability regardless of Journal Assist state

No Journal Assist redesign is required for the first SoundPrint Reflection
implementation.

### 9.3 Your Taste So Far

`Your Taste So Far` remains deterministic and available from the first log. It
answers factual questions such as:

- How many albums have I logged?
- What are my highest-rated albums?
- Which reactions or tags appear most often?
- How do my ratings distribute?

SoundPrint Reflection must not duplicate those cards. It should synthesize a
meaningful relationship among those facts and the listener's language.

### 9.4 Today's Pick

Today's Pick may continue consuming persisted SoundPrint dimensions, avoidance
signals, and receipts. This version must not change its eligibility, ranking,
active-pick behavior, or MusicKit query construction.

---

## 10. Eligibility and cadence

### 10.1 First reflection

- The first SoundPrint Reflection becomes eligible at **5 saved logs**.
- The threshold reuses the existing
  `SoundPrintProfileThresholds.personaMinimumLogCount`.
- Before five logs, Profile shows progress toward the first reflection.
- Before a reflection exists, Home shows no SoundPrint reflection card.

### 10.2 Generation

- Reaching five logs does not automatically generate the artifact.
- Profile presents an explicit `Create my SoundPrint` action.
- Selecting the action starts generation.
- The action remains cancelable through normal view/task cancellation.

### 10.3 Update cadence

- A normal update becomes available after **5 new logs** beyond the log count
  used for the current reflection.
- The current reflection remains readable while it is not yet eligible for an
  update.
- The UI may report the number of new logs since generation.
- The feature must not imply that new logs are ignored; it should explain that
  the next reflection is still forming.

### 10.4 History changes

An update should become available before the normal five-log interval when:

- A log that predates the reflection is edited.
- The total log count drops below the count used for the reflection.
- The app otherwise knows that a supporting log was deleted.

If the total history falls below five logs, the generated artifact must not be
shown as a current reflection.

### 10.5 No archive in v1

Generating an update replaces the current stored artifact after the new output
passes validation. Historical SoundPrint versions are not retained in this
release.

---

## 11. User experience requirements

### 11.1 Profile: collecting state

With zero logs:

- Show a quiet SoundPrint section in Profile.
- Explain that logging starts building the evidence.
- Do not show a generator preference, tone selector, or technical status as the
  main content.

With one through four logs:

- Show progress, for example `3 of 5 logs`.
- Explain that ratings and reactions make the first reflection more specific.
- Do not place a locked SoundPrint module on Home.

### 11.2 Profile: ready state

At five or more logs with no valid reflection:

- Show `Your first SoundPrint is ready`.
- Show a one-sentence explanation of what will be used.
- Provide `Create my SoundPrint`.
- Do not require a review or reaction in every log.
- Do not start generation until the button is selected.

### 11.3 Generating state

While generation is active:

- Disable duplicate generation actions.
- Show calm progress copy such as `Reading your latest logs…`.
- Keep Profile navigation functional.
- Do not clear an existing reflection.
- If the task is canceled, return to the prior stable state.

### 11.4 Current reflection

The SoundPrint Reflection destination must show:

- Title: `SoundPrint Reflection`
- The generated reflection text
- Generation date
- `Based on N logs`
- Actual generator source
- A short privacy note
- At least one visible evidence section when usable evidence exists
- A status for new logs accumulated since generation

The generated prose should be the visual lead. Internal dimension names,
confidence scores, and raw model output must not be the lead.

### 11.5 Evidence presentation

Evidence should be presented in reader-facing language such as:

- `What you're rewarding`
- `What tends to lose you`
- `From your logs`

Evidence may include:

- Album and artist
- Rating
- Selected reactions
- A short review excerpt
- Favorite or weaker track information

Evidence must come from stored logs. The model must not fabricate receipts.

The interface must not show:

- Raw UUIDs
- Internal keys such as `tracklistConsistency`
- Confidence decimals
- Prompt text
- Parser output

### 11.6 Home

Home may show one compact SoundPrint Reflection card only when a valid reflection
already exists.

The card should include:

- `SoundPrint Reflection`
- One short excerpt or headline
- The generator source when known
- A clear path to Profile

The card must not include:

- Persona tone controls
- A list of all dimensions
- Generation settings
- A locked or empty promotional state

### 11.7 Update available

When eligible:

- Keep the current reflection visible.
- Show `Your SoundPrint is ready for an update`.
- Explain why, for example `5 new logs since your last reflection`.
- Provide `Update my SoundPrint`.
- Replace the current artifact only after the new result is valid.

### 11.8 Generation failure

If no reflection exists:

- Show a concise error and a retry action.
- Explain Apple Intelligence availability when it is the cause.
- Keep deterministic taste data and logging available.

If a reflection already exists:

- Keep the current reflection visible.
- Show a non-destructive update failure message.
- Allow retry.

Error copy should not expose Foundation Models error enums or implementation
details.

---

## 12. Foundation Models requirements

### 12.1 Primary path

On an eligible physical device with the preference enabled, generation must use
Apple Foundation Models through Listend's existing `LanguageModelSession`
plain-text response path.

### 12.2 Output behavior

The reflection must:

- Address the listener directly.
- Use one or two short paragraphs.
- Stay under 90 words.
- Make no more than three substantive claims.
- Name at least one concrete album, artist, reaction, or short review phrase.
- Explain a relationship, tension, or pattern rather than listing statistics.
- Use modest qualifiers such as `so far`, `in these logs`, or `lately` when
  evidence is limited.
- Avoid printing internal SoundPrint labels.
- Avoid generic AI or music-publication language.
- Avoid inventing album facts, lyrics, production details, or listening habits.
- Avoid diagnosing personality or mood.
- Avoid claiming repeated behavior unless the logs support repetition.

### 12.3 Model input

Model input may include:

- Total log count
- Average rating
- A bounded set of recent and representative logs
- Album title and artist
- Rating
- Canonical reaction display names
- User-authored custom tags
- Short review excerpts
- Favorite or weaker tracks
- Standout moments
- Deterministically derived taste and avoidance summaries

Model input must not include:

- Unrelated local data
- Apple Music account history that the user did not log
- Hidden contact, location, or account information
- Entire unbounded journal history

### 12.4 Local validation

Every generated output must pass local validation before persistence. Validation
must reject:

- Empty or malformed output
- Output above the length limit
- Internal analysis keys
- Banned generic phrases
- Unsupported certainty
- Claims with no grounding signal
- Prompt or protocol leakage

### 12.5 Runtime compatibility

The shipping target must use:

```swift
let session = LanguageModelSession(instructions: instructions)
let response = try await session.respond(to: prompt)
```

The shipping target must not reference:

- `@Generable`
- `@Guide`
- `GenerationSchema`
- `DynamicGenerationSchema`
- `respond(to:generating:)`
- Other guided structured-output symbols that can cause iOS 26 dyld failures

Runtime `#available` checks alone are not an acceptable safeguard.

### 12.6 Fallback

- Simulator and UI tests use deterministic mock/local output.
- Unsupported devices use the existing local fallback.
- Primary generation failure may use the existing local fallback.
- The resulting artifact must store and display the actual generation source.
- A fallback must not silently overwrite a valid Apple Intelligence reflection
  during a background save operation.

---

## 13. Settings requirements

The Apple Intelligence preference remains available, but it should not dominate
Profile.

Requirements:

- Keep the `Prefer Apple Intelligence` preference.
- Show current availability and last successful generator.
- Keep technical availability details in the settings destination.
- Remove persona-tone selection from the primary SoundPrint experience.
- New reflections use the balanced Listend voice.
- Existing stored tone values remain readable for compatibility.
- Changing the Apple Intelligence preference does not automatically replace the
  current reflection.
- When Apple Intelligence becomes available after a local fallback, the user may
  explicitly request the next eligible update with Apple Intelligence.

---

## 14. Privacy and trust

- Generation occurs on-device when Foundation Models is used.
- No SoundPrint content is sent to a Listend server.
- The detail screen should state that the reflection is built privately from
  the listener's Listend logs.
- Evidence receipts must link only to local stored logs.
- Deleting a log removes it from future generation inputs.
- Editing a log must not silently rewrite the current artifact.
- A generated reflection must never overwrite the user's own review text.

Recommended copy:

> Generated privately on your device from your Listend journal.

For local fallback:

> Built locally from your Listend journal.

---

## 15. Accessibility

- All generation and update controls have stable accessibility identifiers.
- Progress is exposed as a value, for example `3 of 5 logs`.
- Generator-source badges have meaningful labels without relying on color.
- Loading state is announced without repeating continuously.
- Error messages are reachable by VoiceOver.
- Evidence disclosures expose expanded/collapsed state.
- Dynamic Type must not truncate the generated reflection.
- The screen must work without motion-dependent meaning.
- Button labels must remain specific: `Create my SoundPrint`,
  `Update my SoundPrint`, and `Try again`.

---

## 16. Acceptance criteria

### 16.1 Eligibility

- With 0 logs, Profile shows a SoundPrint introduction and no Home card.
- With 1–4 logs, Profile shows accurate progress toward five.
- With 5+ logs and no artifact, Profile shows `Create my SoundPrint`.
- Reaching five logs does not automatically invoke full SoundPrint Reflection
  generation; the existing post-save sentiment path may continue independently.

### 16.2 Generation

- Selecting `Create my SoundPrint` invokes the configured SoundPrint provider.
- A valid Foundation Models result persists with source
  `Apple Intelligence`.
- A deterministic fallback persists with source `Local fallback`.
- Duplicate generation taps are prevented.
- Canceling generation does not persist partial output.
- Generation failure does not affect saved logs.

### 16.3 Reflection content

- The primary output is framed as a reflection, not a persona.
- The output is at most 90 words.
- The output contains at least one validated grounding signal.
- Internal dimension and avoidance keys do not appear.
- At least one local evidence receipt is visible when evidence exists.
- The screen shows generation date and `Based on N logs`.

### 16.4 Cadence

- Saving one to four additional logs does not replace the current reflection.
- At five additional logs, an update action appears.
- Editing or deleting supporting history makes an update available.
- The current reflection remains visible until a replacement validates.
- Successful generation resets the update count.

### 16.5 Surfaces

- Home shows no locked or empty SoundPrint promotion.
- Home shows one compact card after a valid reflection exists.
- Profile has one primary SoundPrint entry rather than separate persona,
  profile, and settings promotions.
- Generator settings remain reachable without dominating Profile.
- Persona-tone controls and badges are absent from the primary experience.

### 16.6 Compatibility

- Existing `SoundPrintPersona` records continue to load.
- Existing logs require no migration.
- Existing `Your Taste So Far` behavior remains intact.
- Existing Journal Assist behavior remains intact.
- Existing Today's Pick behavior remains intact.
- Simulator and UI tests do not require Apple Intelligence.
- The Release binary contains no guided-generation symbols.

---

## 17. Success signals

Formal analytics instrumentation is outside this version. Beta feedback should
evaluate:

- Whether listeners understand why SoundPrint reached its observation
- Whether the visible receipts increase trust
- Whether the reflection feels specific rather than generic
- Whether listeners intentionally return after an update becomes available
- Whether the SoundPrint card feels connected to logging
- Whether listeners can distinguish deterministic statistics from AI synthesis
- Whether Foundation Models output is materially better than the local fallback

The central qualitative question is:

> Does this feel like Listend reflecting your journal back to you, or like an AI
> feature added beside the journal?

---

## 18. Rollout

### Phase 1 — Reframe the current artifact

- Change user-facing persona language to reflection language.
- Consolidate Profile's SoundPrint entry.
- Remove persona-tone UI from the primary experience.
- Keep existing persistence and provider protocols.
- Preserve generator-source disclosure and evidence receipts.

### Phase 2 — Intentional generation cadence

- Stop full reflection regeneration on every save.
- Add collecting, ready, generating, current, and update-available states.
- Add five-log refresh cadence.
- Preserve the last valid artifact on failure.

### Phase 3 — Prompt and validation tuning

- Update Foundation Models instructions for reflection framing.
- Enforce the 90-word and grounding contract.
- Validate on a physical iOS 26 device.
- Compare Foundation Models and local-fallback specificity.

### Deferred

- Historical reflection archive
- Monthly or seasonal recaps
- Shareable cards
- A `What's changing` comparison
- Foundation Models recommendation explanations
- Internal model/type renaming

---

## 19. Coding-agent handoff

Before editing code, the implementation agent must:

1. Read this document and
   `docs/Listend_SoundPrint_Reflection_TechSpec.md`.
2. Inspect the current implementations named in the technical specification.
3. Check `git status` and preserve unrelated local changes.
4. Briefly summarize the current SoundPrint generation and persistence path.
5. Implement only the requested rollout phase.
6. Keep the SwiftData schema migration-free for this version.
7. Preserve the iOS 26-safe Foundation Models text path.
8. Add focused tests for changed behavior.
9. Run the Foundation Models source/symbol checks for any provider or prompt
   change.
10. Report changed files, tests, build result, and unresolved real-device
    validation.

Default implementation instruction:

> Implement the smallest behavior-preserving change that satisfies the selected
> phase. Do not create a second AI insight system, rewrite unrelated logging or
> recommendation code, or reintroduce guided Foundation Models APIs.
