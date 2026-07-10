# iOS 26 / iOS 27 FoundationModels Strategy Handoff

## Purpose

This document is a self-contained handoff for deciding the forward strategy for Listend's Apple Intelligence / FoundationModels integration across iOS 26 and iOS 27.

The core issue: Listend was developed and tested on an iOS 27 device / SDK surface, but the app needs to ship to users on iOS 26. Apple Intelligence is intended to remain part of the product on iOS 26. The previous implementation used newer FoundationModels structured-output convenience APIs that caused a TestFlight crash on iOS 26. The current implementation avoids those APIs and uses iOS 26-safe text responses plus local JSON decoding and validation.

## Current Repo State

- Repo: `/Users/shaunakkulkarni/Developer/listend-ios`
- App: Listend
- Current branch observed: `main`
- Worktree observed clean after the latest FoundationModels commits.
- Deployment target in `Listend/Listend.xcodeproj/project.pbxproj`: `IPHONEOS_DEPLOYMENT_TARGET = 26.4`
- Recent relevant commits:
  - `37b6198 Improve FoundationModels JSON decoding for SoundPrint`
  - `38e3637 Switch FoundationModels flows to text responses`

## User Goal

Listend should:

1. Ship before the public launch of iOS 27 without App Review rejecting it for depending on iOS 27.
2. Keep the full Apple Intelligence-powered feature set for supported iOS 26 users.
3. Avoid the TestFlight crash caused by referencing iOS 27-only FoundationModels structured-output symbols.
4. Avoid regressing SoundPrint, Journal Assist, or tag suggestion behavior.

## Original Crash / Root Cause

A TestFlight crash on iOS 26.5 pointed at a missing FoundationModels guided structured-output symbol:

```text
_$s16FoundationModels9GenerablePAAE20promptRepresentationAA6PromptVvg
```

The likely root cause was that the app binary referenced newer guided structured-output FoundationModels APIs, including patterns like:

- `@Generable`
- `@Guide`
- `respond(to:generating:)`
- guided schema / generation schema APIs
- `promptRepresentation`

The important lesson: runtime `#available` checks may not be enough if the binary still contains symbol references that the iOS 26 runtime loader cannot resolve. For an iOS 26-compatible shipping binary, these guided APIs must not be compiled into the app target unless there is a proven weak-linking / separate-target strategy.

## Current Fix

The code now uses plain FoundationModels text responses on iOS 26-safe APIs, then decodes structured data locally.

### Main Changed Files

- `Listend/Listend/Services/SoundPrint/FoundationModelsSoundPrintProvider.swift`
- `Listend/Listend/Services/JournalAssist/FoundationModelsJournalAssistService.swift`
- `Listend/Listend/Services/TagSuggestion/FoundationModelsTagSuggestionProvider.swift`
- `Listend/ListendTests/ListendTests.swift`

### SoundPrint Current Behavior

`FoundationModelsSoundPrintProvider` now keeps FoundationModels in the loop for the important SoundPrint paths while avoiding guided structured output:

- `analyzeSentiment(input:)`
  - Calls a plain text FoundationModels response.
  - Prompts the model to return JSON shaped like:

    ```json
    {"score": 0.72, "confidence": 0.81}
    ```

  - Decodes with `FoundationModelsSoundPrintValidator.decodedSentiment(from:)`.
  - Validates/clamps with existing sentiment validation.

- `extractTasteSignals(input:)`
  - Calls a plain text FoundationModels response.
  - Reuses existing SoundPrint taste extraction prompts.
  - Asks for JSON shaped like:

    ```json
    {
      "sentiment": {"score": 0.8, "confidence": 0.7},
      "positiveSignals": [
        {
          "dimensionKey": "energy",
          "label": "Energy Bias",
          "summary": "The log rewards intense momentum.",
          "strength": 0.9,
          "confidence": 0.8,
          "evidenceSnippet": "intimate vocals with replay value"
        }
      ],
      "avoidanceSignals": [
        {
          "signalKey": "skipHeavyAlbums",
          "label": "Skip-Heavy Albums",
          "summary": "The log calls out weaker tracks.",
          "strength": 0.4,
          "confidence": 0.6,
          "evidenceSnippet": "skipped/weaker tracks"
        }
      ]
    }
    ```

  - Decodes with `FoundationModelsSoundPrintValidator.decodedTasteExtractionPayload(from:)`.
  - Validates with the existing `validatedTasteExtraction(payload:input:)` path.
  - Restores the previous retry behavior: if taste extraction produces no positive signals for non-negative sentiment, retry once before failing/falling back.

### Journal Assist Current Behavior

`FoundationModelsJournalAssistService` uses plain text FoundationModels responses and local validation for:

- generated journal drafts
- tag suggestions

The recent change only adjusted logging text from "guided schema" to generic "decoded" wording. The unsafe guided API path is not used.

### Tag Suggestions Current Behavior

`FoundationModelsTagSuggestionProvider` uses plain text FoundationModels responses and local validation. The recent change only adjusted logging text from "guided schema" to generic "decoded" wording. The unsafe guided API path is not used.

## Current Feature Inventory

These user-facing Apple Intelligence / AI-adjacent features should remain available when FoundationModels is available on a supported iOS 26 device:

1. SoundPrint sentiment analysis
2. SoundPrint taste signal extraction
3. SoundPrint persona generation
4. SoundPrint compact summary generation
5. Journal Assist draft generation
6. Journal Assist tag suggestions
7. Tag suggestions while logging

The current iOS 26-safe implementation is intended to preserve all of these. The implementation no longer gets the developer convenience of guided structured output, but the product behavior should remain.

## Fallback Architecture

The app intentionally has fallback providers. Do not remove them just because they look repetitive.

Known relevant behavior:

- `SoundPrintProviderFactory.makeProvider(preferAppleIntelligence:isUITesting:isSimulator:)` can route production devices through:

  ```swift
  FallbackSoundPrintProvider(
      primary: FoundationModelsSoundPrintProvider(),
      fallback: MockSoundPrintProvider()
  )
  ```

- `MockSoundPrintProvider` is historically named and misleading. It is not only a test double. It also acts as the deterministic local fallback provider.
- UI tests, simulators, or users who disable Apple Intelligence can use the local fallback path.
- Successful FoundationModels persona output should be labeled as `.foundationModels` / "Apple Intelligence".
- Local fallback output should be labeled as `.localFallback` / "Local fallback".
- `.unavailable` should remain a runtime/UI state, not the normal persisted source for successful personas.

## Why Guided Structured Output Is Still Dangerous

The desired developer ergonomics of the old iOS 27-style path were:

- typed generated payloads
- less manual JSON parsing
- schema-guided model output
- compile-time-ish structure around generated responses

But the current shipping constraint matters more:

- The app targets iOS 26.4.
- TestFlight crash evidence showed an unresolved guided structured-output symbol on iOS 26.5.
- A normal runtime OS check is not enough if the loader sees an unavailable symbol in the binary.

Therefore, the safe production rule is:

> Do not compile `@Generable`, `@Guide`, `respond(to:generating:)`, `GenerationSchema`, `DynamicGenerationSchema`, or `promptRepresentation` references into the iOS 26 shipping app target until proven safe by binary inspection and real-device TestFlight validation.

## Verification Already Run

These checks were run after the iOS 26-safe changes:

### Focused FoundationModels Regression Tests

```bash
xcodebuild test \
  -project Listend/Listend.xcodeproj \
  -scheme Listend \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ListendTests/ListendTests/foundationModelsSentimentDecodesFencedJSON \
  -only-testing:ListendTests/ListendTests/foundationModelsSentimentDecodesJSONWithExtraText \
  -only-testing:ListendTests/ListendTests/foundationModelsTasteExtractionDecodesFencedJSON \
  -only-testing:ListendTests/ListendTests/foundationModelsTasteValidationCreatesNoPositiveEvidenceFromNegativeSentiment
```

Result:

```text
** TEST SUCCEEDED **
```

### Full Unit Suite

```bash
xcodebuild test \
  -project Listend/Listend.xcodeproj \
  -scheme Listend \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ListendTests/ListendTests
```

Result:

```text
** TEST SUCCEEDED **
```

### Whitespace / Patch Check

```bash
git diff --check
```

Result: clean.

### Source Scan For Unsafe Guided APIs

```bash
rg -n "FOUNDATION_MODELS_GUIDED_GENERATION|@Generable|@Guide|Generable|respond\(to:.*generating|DynamicGenerationSchema|GenerationSchema|promptRepresentation|guided schema" \
  Listend/Listend Listend/ListendTests \
  -g '*.swift'
```

Result: no hits.

### Release Simulator Build

```bash
xcodebuild \
  -project Listend/Listend.xcodeproj \
  -scheme Listend \
  -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Result:

```text
** BUILD SUCCEEDED **
```

### Release Binary Symbol Scan

```bash
nm -u /Users/shaunakkulkarni/Library/Developer/Xcode/DerivedData/Listend-eciuphmcmhujfnfchwkvdbpfbfdk/Build/Products/Release-iphonesimulator/Listend.app/Listend \
  | rg "Generable|promptRepresentation|generatedContent|GenerationSchema|respond.*generating"
```

Result: no hits.

## Remaining Unknowns

These cannot be fully proven by simulator unit tests:

1. Exact live FoundationModels output quality on a real iOS 26 device.
2. Whether the text-response JSON prompts are as reliable as the old guided structured-output APIs under real model behavior.
3. Whether App Review/TestFlight device matrix catches any additional FoundationModels linkage issue in archive/device builds.
4. Whether the app should keep any iOS 27-only guided implementation in source for later, and if so, how to prevent it from entering the iOS 26 shipping binary.

## Strategy Options

### Option A: Keep Text + JSON As The Single Production Path

This is the current safest approach.

Pros:

- One FoundationModels production path.
- No iOS 27-only guided symbols in the shipping target.
- Keeps Apple Intelligence features on iOS 26.
- Simpler App Review story.
- Less branching and fewer ways to regress fallback behavior.

Cons:

- Manual JSON decoding and validation are less convenient.
- Model may occasionally return malformed JSON.
- Prompt quality matters more.

Recommended if the goal is to ship soon on iOS 26.

### Option B: Keep Guided APIs In Source Only Behind A Build Flag

Possible shape:

```swift
#if FOUNDATION_MODELS_GUIDED_GENERATION
// iOS 27 experimental guided implementation here.
#endif
```

Rules if this option is used:

- The flag must be off for App Store/TestFlight iOS 26 builds.
- CI or a local release check must scan source and binary output.
- The guided code should not live in the default app target unless binary inspection proves it is not linked.

Pros:

- Preserves a future iOS 27 implementation for later.
- Lets development compare guided vs text behavior.

Cons:

- Easy to accidentally compile into the shipping binary.
- More code paths to test.
- More App Review risk before iOS 27 is public.

Recommended only after the iOS 26 release path is stable.

### Option C: Separate iOS 27 Experiment Target / Branch

Keep the iOS 27 guided implementation outside the shipping app target, either in:

- a separate experimental target,
- a branch,
- or a non-shipping Swift package/module not linked by the app target.

Pros:

- Reduces accidental symbol leakage.
- Keeps production app boring.

Cons:

- More maintenance overhead.
- Feature parity must be manually tracked.

Recommended if guided APIs are worth preserving for future iOS 27 work but should not risk the current release.

### Option D: Drop FoundationModels For iOS 26 And Use Local Fallback Only

This is not aligned with the product goal.

Pros:

- Lowest crash risk.

Cons:

- Regresses Apple Intelligence functionality for iOS 26 users.
- Not acceptable if Apple Intelligence is part of the intended iOS 26 feature set.

Not recommended unless real-device testing proves FoundationModels itself is unstable on iOS 26.

## Recommended Forward Strategy

Recommended default:

1. Ship iOS 26 with the current text-response + JSON decoding FoundationModels implementation.
2. Keep the deterministic local fallback providers.
3. Add one TestFlight pass on a real iOS 26 device focused on:
   - SoundPrint sentiment after saving logs
   - SoundPrint taste extraction after enough logs
   - persona generation and source badge
   - compact summary
   - Journal Assist draft generation
   - Journal Assist tag suggestions
   - normal tag suggestions
4. Keep guided structured-output APIs out of the shipping target until after iOS 27 is public or a separate build strategy is proven safe.
5. If iOS 27 guided output is still desired, preserve it in a separate non-shipping branch/target and compare outputs later.

## Suggested Questions For Another LLM

Use this prompt:

```text
You are reviewing an iOS app that targets iOS 26.4 and uses Apple Intelligence / FoundationModels. It previously used newer iOS 27-style guided structured-output APIs and crashed on TestFlight iOS 26.5 with a missing symbol: _$s16FoundationModels9GenerablePAAE20promptRepresentationAA6PromptVvg.

The app has now switched to plain FoundationModels text responses plus local JSON decoding and validation. The goal is to keep full Apple Intelligence functionality on iOS 26 without shipping iOS 27-only symbols.

Please review the strategy in this document and recommend the safest forward architecture. Focus on:

1. Whether text-response + JSON decoding is the right production path for iOS 26.
2. Whether any guided iOS 27 implementation can safely remain in source, and under what build/target conditions.
3. What release checks should be mandatory before TestFlight/App Review.
4. What real-device iOS 26 tests are needed to prove no user-facing functionality regression.
5. Any Swift/Xcode linking or availability pitfalls that could still cause dyld crashes.
```

## Files Another LLM Should Inspect

Start here:

- `Listend/Listend/Services/SoundPrint/FoundationModelsSoundPrintProvider.swift`
- `Listend/Listend/Services/SoundPrint/FallbackSoundPrintProvider.swift`
- `Listend/Listend/Services/SoundPrint/MockSoundPrintProvider.swift`
- `Listend/Listend/Services/SoundPrint/SoundPrintProviderEnvironment.swift`
- `Listend/Listend/Services/SoundPrint/SoundPrintSettings.swift`
- `Listend/Listend/Services/SoundPrint/SoundPrintProfileBuilder.swift`
- `Listend/Listend/Services/JournalAssist/FoundationModelsJournalAssistService.swift`
- `Listend/Listend/Services/TagSuggestion/FoundationModelsTagSuggestionProvider.swift`
- `Listend/ListendTests/ListendTests.swift`
- `Listend/Listend.xcodeproj/project.pbxproj`

## Mandatory Checks Before Shipping

Run these before any new TestFlight build.

First the source scan (`scripts/check-foundationmodels-symbols.sh` is the canonical version of this check and exits non-zero on any hit):

```bash
scripts/check-foundationmodels-symbols.sh
```

Equivalent manual command:

```bash
rg -n "FOUNDATION_MODELS_GUIDED_GENERATION|@Generable|@Guide|Generable|respond\(to:.*generating|streamResponse\(to:.*generating|DynamicGenerationSchema|GenerationSchema|promptRepresentation|GeneratedContent|guided schema" \
  Listend/Listend Listend/ListendTests \
  -g '*.swift'
```

```bash
xcodebuild test \
  -project Listend/Listend.xcodeproj \
  -scheme Listend \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ListendTests/ListendTests
```

```bash
xcodebuild \
  -project Listend/Listend.xcodeproj \
  -scheme Listend \
  -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Then scan the built binary for guided symbols:

```bash
nm -u /path/to/Listend.app/Listend \
  | rg "Generable|promptRepresentation|generatedContent|GenerationSchema|respond.*generating"
```

For archive/device builds, perform the same kind of symbol scan on the actual product that will be uploaded.

## Real-Device TestFlight Checklist

On an iOS 26 device with Apple Intelligence available:

- Install a fresh TestFlight build.
- Open app without launch crash.
- Enable/prefer Apple Intelligence if the app exposes that setting.
- Confirm creating individual logs still works (logging must never be blocked by AI failure).
- Create enough album logs to trigger SoundPrint profile generation.
- Confirm SoundPrint persona appears.
- Confirm the compact summary appears.
- Confirm the source badge says "Apple Intelligence" for FoundationModels output.
- Confirm profile copy does not show internal labels like `energy`, `tracklistConsistency`, `skipHeavyAlbums`, or schema-ish field names.
- Confirm positive reviews like "not a single skip" do not create a "what you tend to reject" skip-heavy claim.
- Confirm Journal Assist can generate a draft.
- Confirm Journal Assist can suggest tags.
- Confirm normal tag suggestions work.
- Disable Apple Intelligence preference if available and confirm local fallback still works.
- Capture any FoundationModels failures and confirm fallback preserves existing profile data instead of deleting it.

On an iOS 27 device:

- Repeat the same user-facing tests.
- Do not require iOS 27-only behavior for the shipping build.

## Bottom Line

The current safest shipping position is:

- Keep Apple Intelligence features on iOS 26 through plain FoundationModels text responses.
- Parse and validate JSON locally.
- Keep fallback providers.
- Do not compile guided structured-output APIs into the shipping iOS 26 app.
- Treat any future iOS 27 guided implementation as experimental until binary scans and real-device testing prove it cannot regress iOS 26 compatibility.
