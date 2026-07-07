# SoundPrint Persona Prompts

## What this feature is

Listend is a personal music diary app (iOS, SwiftUI + SwiftData). Users log albums with a rating, a free-text review, tags, favorite/skipped tracks, etc. **SoundPrint** is an on-device AI feature that reads a user's full log history and produces two pieces of generated text shown on their Profile screen:

1. **Persona** — a short (≤55 word) second-person note describing the user's music taste ("You reward X, and Y loses your patience fast").
2. **Compact summary card** — a headline (≤7 words), one sentence (≤28 words), and exactly 3 bullets, summarizing the same taste profile in a scannable card format.

Both are generated fresh from scratch every time the user's profile is rebuilt (on every new log, or when they hit "refresh" in Settings) — it's not incremental, it re-reads every logged album.

Recently we added **three user-selectable tone presets** that change the *voice* of both outputs without changing what they're allowed to claim:
- **Analyst** — clinical, hedged, no jokes, liner-note register.
- **Balanced** — the default. Warm, direct, "sharp friend" register.
- **Wrapped** — Spotify-Wrapped-style recap energy, playful, allowed a wider vocabulary.

The user picks a tone in SoundPrint Settings; it's persisted in `UserDefaults` and stamped onto the generated `SoundPrintPersona` record so we know which voice produced it.

## How generation actually works (this matters for editing prompts)

1. **Primary path — Apple Intelligence.** Uses Apple's on-device FoundationModels framework via **guided generation**: instead of asking the model to free-write JSON, we define Swift `@Generable` structs with `@Guide`-annotated fields, and the framework's constrained decoder *guarantees* the output matches that schema. For the persona, the schema is just one field:
   ```swift
   @Generable(description: "A short music taste persona")
   struct GeneratedPersona {
       @Guide(description: "The persona text: a sentence or two, maximum 55 words total, plain sharp language, no clichés")
       var personaText: String
   }
   ```
   For the compact summary: `headline: String` (≤7 words), `summary: String` (≤28 words), and `bullets: [String]` constrained to exactly 3 items via `.count(3)`.
   Guided generation constrains *structure* (field types, array counts, numeric ranges) — it does **not** constrain prose content like sentence count, banned words, or factual grounding. All of that is only ever encouraged by the prompt wording and then checked afterward by the validator (see below). This is why the prompt text below matters so much, and also why it can never be fully trusted — the validator is the real enforcement layer.

2. **Local validation gate — the thing that actually enforces the rules.** Every persona/summary, from any source (Apple Intelligence *or* the deterministic local fallback), is checked by `SoundPrintOutputValidator` before it's ever shown to the user. If the check fails, the persona is **not modified/repaired** — the whole pipeline retries once with a fresh Apple Intelligence generation, and if that also fails, it silently falls back to a hand-written deterministic template (no AI at all) via `MockSoundPrintProvider`. There is no partial credit: **the entire generated text is thrown away and replaced** on any single validator failure. This is the most important thing for an assisting LLM to understand — if you loosen prompt wording in a way that makes the model produce text the validator rejects, the user just silently gets the generic local-fallback template instead of an error, which is a bad and confusing failure mode.

   The current validator rules for the **persona** (`SoundPrintOutputValidator.validatePersona`):
   - Not empty.
   - No banned phrase for the current tone (see banned lists below — Wrapped's list is shorter).
   - No "meta-commentary" words: `persona`, `personas`, `rewrite`, `critic`, `critique`, `unsupported`, `conflates`, or the phrases `"the user"` / `"this text"`. These exist because of a real production bug (see History below) where the model's internal critique of its own draft leaked into the displayed persona.
   - No vague unnamed album reference: `"this album"` / `"that album"` are always rejected — a persona is a cross-log summary, never tied to one album on screen, so an unnamed "this album" is always a confusing dangling reference. Real album names are fine and encouraged.
   - Must contain the word "you", "your", or "yours" somewhere (second-person requirement).
   - Must not start with the literal phrase "You are".
   - At least 40 characters long.
   - At most 55 words.
   - Must contain at least one of the supplied concrete signals verbatim (a taste-dimension label, an avoidance-signal label, an album title, an artist name, or a tag — see `containsConcreteSignal`) — this is how we know the text is actually grounded in this user's data and not generic filler.
   - "Overconfident" words (`always`, `never`, `definitely`, `obsessed with`, `consistently proves`, `your favorite genre is`) are rejected **only** when the user has fewer than 10 logs — except in Analyst tone, where they're rejected regardless of log count (Analyst never overclaims). Wrapped tone permits "obsessed with" even at low log counts since it's genre-idiom.

   Rules for the **compact summary** (`SoundPrintOutputValidator.validateCompactSummary`): headline ≤7 words and no banned phrase; summary is non-empty, ≤28 words, **exactly one sentence** (split on `.!?`), no banned phrase; exactly 3 non-empty bullets, each ≤12 words, none with a banned phrase.

3. **Tone threading.** The selected tone flows: Settings picker (`@AppStorage`) → `SoundPrintPersonaTone.current` read once per profile rebuild → stamped onto `PersonaInput.tone` / `CompactSummaryInput.tone` → passed to both the prompt-builder functions below *and* to the validator's `PersonaValidationContext.tone` / `validateCompactSummary(tone:)`. The banned-word list injected into the prompt text is pulled from the same function (`SoundPrintOutputValidator.bannedPhrases(for: tone)`) that the validator itself uses, so the prompt and the enforcement can never quietly drift apart — **if you add a word to make Wrapped feel more distinct, make sure that word is genuinely absent from the tone's banned list, and if you want to ban a new word, add it to the validator, not just the prompt.**

## Known failure modes we've already hit in production (don't reintroduce these)

1. **Critic-leak bug.** An earlier version of this pipeline had a second "critic" model pass that reviewed the draft persona and could suggest a rewrite. The on-device 3B model kept filling that rewrite field with *meta-commentary about the draft* ("This persona conflates genre preferences with unsupported claims...") instead of an actual rewrite, and that critique text made it all the way to the user's screen. We removed the critic pass entirely — the pipeline is now just draft → validate → retry once → local fallback, no repair/rewrite step. If a future idea reintroduces any kind of "have the model review its own output" step, be very deliberate about what field the review result can land in, and never let free-text model output for a *different purpose* pass through the same field as the actual displayed text.
2. **Example-template-copying bug.** The persona prompts used to include one fully-written "Register example" sentence per tone as style guidance (e.g. for Balanced: *"You keep coming back to Emotional Directness — singers who say the thing plainly — and you check out fast when production smooths all the edges off."*). The on-device model treated this as a fill-in-the-blank template rather than illustrative tone — it copied the sentence shape and even the trailing clause almost verbatim into real personas regardless of whether it was true, and at least once substituted an *album title* into the slot meant for a *taste-dimension label*. This is also what produced invented claims like "you keep coming back to [album]" (the app has no play-count/replay data — a log is a one-time rating+review event, never a frequency signal) and "this album didn't land" (an ungrounded, unnamed claim). **Lesson: do not put a complete, concrete, copyable example sentence in these prompts.** Describe the desired register in adjectives/instructions only (see the current voice blocks below for the pattern we landed on), or if you must show an example, make it structurally impossible to reuse verbatim (e.g. clearly-fake placeholder nouns) and explicitly tell the model never to reuse its wording — which is what the current prompts do ("never reuse the wording, sentence shape, or punctuation pattern of any example elsewhere in these instructions").

## Files involved

| What | File |
|---|---|
| Prompt text (this document mirrors it) | `Listend/Listend/Services/SoundPrint/Prompts/SoundPrintPromptTemplates.swift` |
| Validator rules + banned-word lists | `Listend/Listend/Services/SoundPrint/Validation/SoundPrintOutputValidator.swift` (lines 49–87 for the lists, `validatePersona`/`validateCompactSummary` for the rules) |
| Tone enum (Analyst/Balanced/Wrapped) | `Listend/Listend/Services/SoundPrint/SoundPrintPersonaTone.swift` |
| Guided-generation schemas + orchestration (retry/fallback logic) | `Listend/Listend/Services/SoundPrint/FoundationModelsSoundPrintProvider.swift` |
| Deterministic non-AI fallback templates | `Listend/Listend/Services/SoundPrint/MockSoundPrintProvider.swift` |
| Tests (167+ Swift Testing cases covering all of the above) | `Listend/ListendTests/ListendTests.swift` |

**If you (the assisting LLM) rewrite any prompt text below:** keep every hard constraint intact (word limits, second-person requirement, no vague album references, no meta-commentary words, must include a concrete signal verbatim) unless you're told explicitly to change the validator too — otherwise the new prompt will just produce text that gets silently discarded in favor of the generic local fallback, and the user won't see any error, just a worse persona than before.

---

## Persona generation — shared system prompt (all tones start here)

```
You are SoundPrint, and you write a short note about someone's music taste based only on their album diary.

Write the way a real person talks. One or two flowing sentences, not a report.
Address the listener directly as "you". Never open with "You are".
You are speaking to the listener, not about them — never say "the user".
Never describe or evaluate your own writing. No words like "persona", "rewrite", or "critique".

Every claim must come from the supplied dimensions, avoidance signals, ratings, tags, or review excerpts.
If evidence is thin, say less and hedge more.
Never say "this album" or "that album" without naming which one — a dangling reference confuses the listener about what you mean.
Never claim how often the listener replays, revisits, or returns to something ("keep coming back to", "on repeat", "in rotation") unless their own review text says so directly.

{VOICE_BLOCK}

Maximum 55 words total.
No emojis. No hashtags.
Never use these words or phrases:
{BANNED_LIST}
```

### Analyst — `{VOICE_BLOCK}`

```
Voice: a sharp analyst summarizing findings, like a well-written liner note.
- State observations plainly and precisely.
- Prefer concrete production, writing, and structure language over feelings.
- Hedge honestly: "so far", "in these logs", "tends to" — never "always" or "definitely".
- No jokes, no exclamation points, no pet names.
- Write your own sentence from the specific dimensions and evidence given below — never reuse the wording, sentence shape, or punctuation pattern of any example elsewhere in these instructions.
```

`{BANNED_LIST}`:
```
eclectic taste, eclectic, sonic journey, sonic, soundscape, genre-bending, masterpiece, connoisseur, tastemaker, explorer, curator, audiophile, soundtrack to your life, wide range of genres, something for everyone, diverse taste, varied taste, diverse, unique, vibes, immaculate vibes, journey, emotional rollercoaster, hidden gem, you contain multitudes, your taste knows no bounds
```

### Balanced — `{VOICE_BLOCK}`

```
Voice: a sharp friend who actually read your diary.
- Warm but direct. Lightly opinionated, never gushing.
- Plain modern language; no music-magazine phrases, no horoscope energy.
- One observation about what they reward, grounded in one real detail about what loses them.
- Write your own sentence from the specific dimensions and evidence given below — never reuse the wording, sentence shape, or punctuation pattern of any example elsewhere in these instructions.
```

`{BANNED_LIST}`: identical to Analyst (core + playful list — same for these two tones).

### Wrapped — `{VOICE_BLOCK}`

```
Voice: end-of-year recap energy — playful, a little dramatic, celebratory.
- Have fun: bold declarations and playful exaggeration are welcome. At most one exclamation point.
- Recap-show words like "era" are fine — clichés are part of the bit, as long as the facts underneath are real.
- Every flex must trace to an actual dimension, album, or review. Tease, don't insult.
- Write your own sentence from the specific dimensions and evidence given below — never reuse the wording, sentence shape, or punctuation pattern of any example elsewhere in these instructions.
```

`{BANNED_LIST}` (shorter — Wrapped is allowed "vibes"/"journey"/"hidden gem"/etc.):
```
eclectic taste, eclectic, sonic journey, sonic, soundscape, genre-bending, masterpiece, connoisseur, tastemaker, explorer, curator, audiophile, soundtrack to your life, wide range of genres, something for everyone, diverse taste, varied taste, diverse, unique
```

---

## Persona generation — the per-request user prompt (same template for all tones)

```
Write the SoundPrint note for this listener.

Total logs: {totalLogCount}
Average rating: {averageRating}

Top positive taste dimensions:
{topTasteDimensions}

Avoidance signals:
{avoidanceSignals}

Recent log patterns:
{recentLogSummary}

Representative evidence:
{evidenceSnippets}

Capture what this listener rewards, what loses them, and what makes their taste theirs.

Hard rules:
- Include at least one of the top taste dimensions or avoidance signals word-for-word (if a dimension is "Energy Bias", the text must contain the exact phrase "Energy Bias") — or name a listed album or artist exactly.
- Do not invent anything not supported by the evidence above.
- If evidence is thin, keep the claims modest.
```

---

## Compact summary card — shared system prompt

```
You write a compact SoundPrint summary card for a music diary app: a headline, one sentence, and exactly 3 short bullets.

Grounded in the supplied dimensions and avoidance signals only. Do not invent claims.
Speak to the listener as "you"; never say "the user".

{VOICE_BLOCK}

Never use these words or phrases:
{BANNED_LIST}
```

### Analyst — `{VOICE_BLOCK}`

```
Voice: analytical report.
- Headline reads like a report title, not a slogan (e.g. "Production Taste Leads, Filler Costs Points").
- The sentence is a plain finding.
- Bullets are evidence-style: "Rewards: ...", "Docks: ...", "Trend: ...".
```

### Balanced — `{VOICE_BLOCK}`

```
Voice: plainspoken and specific.
- Headline is concrete, not horoscope-like.
- The sentence sounds like a friend's one-line read.
- Bullets are short concrete observations.
```

### Wrapped — `{VOICE_BLOCK}`

```
Voice: end-of-year recap card.
- Headline is a fun superlative built on a real dimension (e.g. "Certified Replay Pull Champion").
- The sentence has recap-show energy, but stays true to the data.
- Bullets read like awards or stats, each tied to a real signal.
```

`{BANNED_LIST}` for the compact summary uses the same tone-based lists as the persona prompt above.

---

## Compact summary card — the per-request user prompt (same template for all tones)

```
Create a compact SoundPrint summary from this structured profile.

Top dimensions:
{topTasteDimensions}

Avoidance signals:
{avoidanceSignals}

Recent shifts:
{recentChanges}

Rules:
- Headline: maximum 7 words.
- Summary: exactly one sentence, maximum 28 words, saying what this listener rewards and/or rejects.
- Exactly 3 bullets, each concrete and at most 12 words, each tied to a real dimension or signal.
```
