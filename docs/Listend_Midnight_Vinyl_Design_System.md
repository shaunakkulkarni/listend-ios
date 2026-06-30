# Listend Design System — Midnight Vinyl

**Product:** Listend  
**Platform:** iOS  
**Implementation target:** SwiftUI + SwiftData  
**Design direction:** Midnight Vinyl  
**Purpose:** This document defines the reusable visual and interaction system for Listend. It is written so it can be handed to Codex, another coding agent, or a human iOS developer.

---

## 1. Design Thesis

Listend is a personal music diary. It should feel like opening a private record shelf at night: editorial, quiet, personal, and artwork-forward.

The UI should not feel like a default SwiftUI tutorial, an AI productivity app, or a generic music-streaming clone.

The core aesthetic is:

> Warm paper + deep navy accent + editorial serif + album-art focus.

The product experience should make logging music feel like a small ritual, while making SoundPrint and Tonight’s Pick feel like thoughtful reflections based on the user’s own listening history.

---

## 2. Design Principles

### 2.1 Quiet, not empty

Use generous spacing and simple layouts, but keep screens emotionally anchored with album art, serif titles, user review snippets, and evidence receipts.

### 2.2 One accent, used with restraint

The deep navy accent is the only brand color. It is used for primary actions, selected states, rating stars, active tabs, confidence bars, and small emphasis moments. It should not be used on every icon or every label.

### 2.3 Album art carries emotion

Album artwork should be larger and more central than in a normal list app. The artwork is the main visual content.

### 2.4 Cards are for objects, not layout

Use cards for albums, logs, recommendations, and persona quotes. Do not wrap every group of metadata in a white rounded rectangle.

### 2.5 SoundPrint must feel evidence-backed

Taste dimensions, recommendations, and persona language should always feel grounded in the user’s actual logs, ratings, tags, and review snippets.

### 2.6 Native iOS first

Use SwiftUI, SF Symbols, Dynamic Type, VoiceOver-friendly controls, native navigation, native sheets, and standard destructive patterns. Do not imitate web UI frameworks.

---

## 3. Color System

### 3.1 Light Mode Tokens

| Token | Hex | Use |
|---|---:|---|
| `ListendPaper` | `#F4F1EA` | Main app background |
| `ListendSurface` | `#FFFDF7` | Album cards, log cards, recommendation cards |
| `ListendInk` | `#171A1F` | Primary text |
| `ListendMutedInk` | `#6D7178` | Secondary text, metadata, timestamps |
| `ListendHairline` | `#DDD8CE` | Dividers, subtle borders |
| `ListendAccent` | `#243B53` | Primary CTA, active tab, stars, confidence bars |
| `ListendAccentSoft` | `#DDE7EF` | Soft panels, selected chips, Journal Assist background |
| `ListendDestructive` | System red | Delete/destructive actions only |

### 3.2 Dark Mode Tokens

| Token | Hex | Use |
|---|---:|---|
| `ListendPaper` | `#0F141A` | Main app background |
| `ListendSurface` | `#181F27` | Cards and elevated content |
| `ListendInk` | `#F3F0EA` | Primary text |
| `ListendMutedInk` | `#AEB5BE` | Secondary text |
| `ListendHairline` | `#2A333D` | Dividers and borders |
| `ListendAccent` | `#7FA7C7` | Accent in dark mode |
| `ListendAccentSoft` | `#1E3345` | Soft panels and selected states |
| `ListendDestructive` | System red | Delete/destructive actions only |

### 3.3 Color Usage Rules

Use `ListendAccent` for:

- Filled primary buttons
- Active tab icon and label
- Rating stars
- Tonight’s Pick match percentage
- SoundPrint confidence bars
- Selected chips
- Small inline emphasis

Do not use `ListendAccent` for:

- Every icon
- Every row label
- Body text
- Plain metadata
- Destructive actions
- Large decorative backgrounds

Use `ListendAccentSoft` for:

- Journal Assist panels
- Selected filter chips
- Gentle callout panels
- Empty-state icon circles

---

## 4. Typography System

Listend uses two typographic roles.

### 4.1 Display Serif

Use a warm editorial serif for emotional and subject-level moments.

Recommended options:

- Lora
- Source Serif
- New York, if using Apple system serif styling
- Another licensed serif that feels literary, not trendy

Use display serif for:

- `Listend` wordmark on Home
- Album titles on Album Detail
- Recommended album title on Tonight’s Pick
- `New Log` / `Edit Log` title
- Large stat numerals
- SoundPrint persona quote

Do not use display serif for:

- Dense body copy
- Form labels
- Buttons
- Tab labels
- Search results metadata

### 4.2 System Sans

Use SF Pro / SwiftUI system font for functional UI.

Use system sans for:

- Body copy
- Metadata
- Buttons
- Form labels
- Navigation titles
- Search fields
- Tab bar
- Tags
- Receipts

### 4.3 Type Scale

| Role | Suggested SwiftUI Style | Use |
|---|---|---|
| Wordmark | Custom serif, 40–44pt | Home title |
| Display Title | Custom serif, 30–34pt | Album Detail, New Log, Pick title |
| Display Stat | Custom serif, 32pt | Total logs, average rating |
| Section Title | `.headline` or 17–20pt semibold | Recent Logs, Receipts, Top Tags |
| Body | `.body` | Reviews, explanations |
| Metadata | `.subheadline` | Artist, year, genre |
| Caption | `.caption` | Dates, helper text, counts |
| Button | `.callout.weight(.semibold)` | Primary/secondary buttons |

---

## 5. Layout Tokens

### 5.1 Spacing

| Token | Value |
|---|---:|
| `ListendSpacing.xs` | 4 |
| `ListendSpacing.sm` | 8 |
| `ListendSpacing.md` | 12 |
| `ListendSpacing.lg` | 16 |
| `ListendSpacing.xl` | 24 |
| `ListendSpacing.xxl` | 32 |

### 5.2 Radius

| Token | Value | Use |
|---|---:|---|
| `ListendRadius.small` | 10 | Small chips, compact badges |
| `ListendRadius.medium` | 14 | Buttons, input fields |
| `ListendRadius.large` | 20 | Album/log/recommendation cards |
| `ListendRadius.artwork` | 16 | Album artwork |

### 5.3 Shadows

Use shadows sparingly. The app should feel like paper and record sleeves, not floating glass cards.

Recommended light mode card shadow:

```swift
.shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
```

Recommended dark mode card shadow:

```swift
.shadow(color: .black.opacity(0.20), radius: 12, x: 0, y: 4)
```

---

## 6. Surface System

### 6.1 Paper Background

Use on all primary screens.

```swift
Color.listendPaper.ignoresSafeArea()
```

### 6.2 Content Card

Use for discrete content objects:

- Album card
- Log entry card
- Recommendation card
- Persona card
- Journal Assist card

Style:

- Background: `ListendSurface`
- Radius: `ListendRadius.large`
- Optional subtle shadow
- Padding: 16–20pt

### 6.3 Flat Row Group

Use for metadata groups and lists where cards would feel heavy:

- Profile stats
- Taste dimensions
- Receipts
- Settings rows
- Top tags section

Style:

- No outer card by default
- Rows separated by `ListendHairline`
- Sits directly on `ListendPaper`

---

## 7. Component Library

### 7.1 `ListendPrimaryButton`

Use once per screen for the main action.

Examples:

- Add Log
- Log this album
- Save Log
- Use Draft

Style:

- Filled `ListendAccent`
- Text `ListendPaper` or white-like foreground
- Radius `ListendRadius.medium`
- Height 44–50pt
- Full width for major actions

### 7.2 `ListendSecondaryButton`

Use for supporting actions.

Examples:

- Load Recently Played
- Cancel
- View Receipts
- Regenerate

Style:

- Transparent or `ListendSurface`
- Border `ListendHairline`
- Text `ListendAccent`
- Radius `ListendRadius.medium`
- Same height as primary when paired

### 7.3 `AlbumArtworkView`

States:

1. Real artwork loaded
2. Loading state
3. Designed placeholder

Placeholder style:

- Background: `ListendAccentSoft`
- Foreground icon: `ListendAccent`
- SF Symbol: `music.note`, `record.circle`, or `opticaldisc`
- Radius: `ListendRadius.artwork`

### 7.4 `RatingStarsView`

Style:

- Filled stars: `ListendAccent`
- Empty stars: `ListendHairline`
- Supports half-star ratings if already implemented
- Large enough tap targets for editing

Display-only rows may use smaller stars.

### 7.5 `TagChip`

Style:

- Background: transparent or `ListendSurface`
- Border: `ListendHairline`
- Text: `ListendMutedInk`
- Radius: `ListendRadius.small`
- Horizontal padding: 10–12pt
- Vertical padding: 6pt

Selected chip:

- Background: `ListendAccentSoft`
- Border: transparent
- Text: `ListendAccent`

### 7.6 `LogEntryCard`

Content:

- Album artwork thumbnail
- Album title
- Artist
- Rating
- Date
- Review snippet
- Tags

Rules:

- Album title may use serif subtly, but keep row readability high.
- Review snippets should be short and human.
- Use cards because logs are diary objects.

### 7.7 `RecommendationCard`

Used on Tonight’s Pick.

Content:

- Large artwork
- Album title in display serif
- Artist
- Match percentage
- Explanation note
- Receipt preview
- Feedback actions

Rules:

- This should be the most distinctive card in the app.
- Do not make feedback actions look like a settings list.

### 7.8 `ReceiptRow`

Content:

- Source album artwork thumbnail
- Album title
- Rating
- Review/tag snippet
- Optional linked dimension

Style:

- Flat rows with dividers
- No heavy card unless embedded in recommendation card

### 7.9 `JournalAssistCard`

Style:

- Background: `ListendAccentSoft`
- Text: `ListendInk`
- Icon: `sparkles` or `pencil.and.scribble`
- Button: secondary or lightly filled accent

Copy:

> Stuck? Turn your notes into a sharper log.

Primary action:

> Help me write

### 7.10 `EmptyStateView`

Content:

- Accent-tinted icon
- Short title
- One sentence of helper text
- Optional primary CTA

Tone should be gentle, not error-like.

---

## 8. Screen Specifications

## 8.1 Home

### Purpose

Home is the daily-open screen. It should feel like opening a journal, not a dashboard.

### Layout

1. Serif `Listend` wordmark
2. Small tagline: `Albums that stayed.`
3. Two stat numerals: Logs and Avg Rating
4. Primary CTA: `+ Add Log`
5. Secondary CTA: `Load Recently Played` if present
6. Recent Logs section
7. Log cards

### Rules

- Do not wrap the wordmark/stats in a card.
- Use `ListendPaper` as the background.
- Make `+ Add Log` the only filled button.
- Recent log cards use `ListendSurface`.

### Empty State Copy

```text
No logs yet.
Start with an album you can’t stop thinking about.
```

CTA:

```text
Add your first log
```

---

## 8.2 Search

### Purpose

Search is functional and fast. It should be clean, not overly branded.

### Layout

1. Navigation title: Search
2. Search field
3. Recent search chips if available
4. Results list
5. Album rows

### Rules

- Use system sans for most of the screen.
- Album artwork should appear on every result.
- Use dividers or light cards, not heavy repeated cards.
- No system blue in search field focus or action states if reasonably controllable.

---

## 8.3 Album Detail

### Purpose

Album Detail confirms the album and provides the path to logging.

### Layout

1. Large album artwork
2. Serif album title
3. Artist
4. Year and genre
5. Primary CTA: `Log this album`
6. Already logged state if applicable

### Rules

- Use the album title as the emotional center.
- If already logged, do not hide that state. Show rating and `View your log` / `Edit Log`.

---

## 8.4 Log Editor

### Purpose

This is the core diary-writing ritual.

### Layout

1. Top bar: Cancel / Save
2. Serif title: New Log or Edit Log
3. Compact album summary
4. Rating stars
5. Review writing area
6. Tags
7. Journal Assist module
8. Optional Track Highlights disclosure

### Rules

- The review field should feel like a writing page, not a bordered enterprise form.
- Save is disabled until rating is selected.
- Rating stars use `ListendAccent`.
- Journal Assist uses `ListendAccentSoft`.

### Review Placeholder

```text
What did this album leave with you?
```

---

## 8.5 Journal Assist Sheet

### Purpose

Help the user write without turning the experience into more form-filling.

### Layout

1. Sheet title: Journal Assist
2. Helper copy
3. Quick Notes text area
4. Prompt chips
5. Draft output area
6. Primary CTA: Use Draft

### Prompt Chips

- What stood out?
- Best track?
- Mood?
- Skip?

### Rules

- Prompt chips should insert or shape notes.
- Avoid four stacked empty fields.
- AI should feel like writing help, not a separate product.

---

## 8.6 Tonight’s Pick

### Purpose

This is Listend’s signature feature. It should feel personal, confident, and receipt-backed.

### Layout

1. Title: Tonight’s Pick
2. Subtitle: One album. With receipts.
3. Large artwork
4. Serif album title
5. Artist
6. Accent match percentage
7. Personal explanation
8. Receipt rows
9. Feedback actions

### Feedback Actions

Use compact buttons/chips:

- Like
- Save
- Listened
- Dismiss

### Rules

- Large artwork is required.
- Match percentage uses `ListendAccent`.
- Explanation text should feel written, not generated.
- Receipts must reference real logs.

### Cold State Copy

```text
No pick yet.
Log a few more albums so Listend has something real to work from.
```

---

## 8.7 Profile

### Purpose

Profile shows stats and the user’s taste identity.

### Layout

1. Navigation title: Profile
2. Stats: Logs and Average Rating
3. SoundPrint Persona card
4. Top Tags chips
5. Taste Dimensions rows
6. Link to full SoundPrint Profile

### Rules

- Keep stats flat, not carded.
- Persona can be carded because it is content.
- Taste dimensions should be flat rows with confidence bars.

---

## 8.8 SoundPrint Profile

### Purpose

Show how Listend understands the user’s taste, backed by evidence.

### Layout

1. Title: SoundPrint
2. Subtitle: How Listend sees your taste so far.
3. Taste dimension sections
4. Summary
5. Confidence bar
6. Receipt row

### Rules

- Do not make it look like analytics software.
- Each dimension should include evidence.
- Negative logs should not appear as positive evidence.

---

## 8.9 Settings

### Purpose

Settings should be native, simple, and low-personality.

### Rules

- Use standard grouped rows where appropriate.
- Background should still use `ListendPaper`.
- Keep destructive actions system red.
- Do not over-style settings.

---

## 9. Interaction Patterns

### 9.1 Primary Action Discipline

Each screen should have one obvious primary action.

Examples:

| Screen | Primary Action |
|---|---|
| Home | Add Log |
| Album Detail | Log this album |
| Log Editor | Save Log |
| Journal Assist | Use Draft |
| Tonight’s Pick | Context-dependent; feedback actions should be balanced |

### 9.2 Cold Starts

Cold states should be honest and gentle.

SoundPrint:

```text
Your SoundPrint is still quiet.
Log a few more albums and patterns will start to show.
```

Tonight’s Pick:

```text
No pick yet.
Recommendations work better when Listend knows what you actually liked.
```

### 9.3 Microcopy Style

Use:

- “Log this album”
- “Albums that stayed.”
- “One album. With receipts.”
- “What did this album leave with you?”
- “Your SoundPrint is still quiet.”

Avoid:

- “Submit”
- “Analyze preference data”
- “AI-generated recommendation”
- “User feedback captured”

---

## 10. Accessibility Requirements

### 10.1 Dynamic Type

- Functional UI should use SwiftUI text styles where possible.
- Custom serif text must still scale.
- Do not hard-code tiny text for metadata that may become unreadable.

### 10.2 Contrast

- Verify all text/background pairs meet WCAG AA where possible.
- Especially test `ListendMutedInk` on `ListendPaper`.
- Do not rely on color alone for selected states.

### 10.3 Tap Targets

- Buttons and interactive chips should be at least 44pt high where practical.
- Rating stars should have generous tap areas.

### 10.4 VoiceOver

Album rows should read as:

```text
Blue Rev, Alvvays, 2022, Indie Rock. Button.
```

Rating control should read as:

```text
Your rating, 4 out of 5 stars.
```

Tonight’s Pick feedback actions should have clear labels:

```text
Like recommendation
Save recommendation for later
Mark recommendation as listened
Dismiss recommendation
```

---

## 11. SwiftUI Implementation Notes

### 11.1 Color Assets

Create named color assets with light and dark variants:

- `ListendPaper`
- `ListendSurface`
- `ListendInk`
- `ListendMutedInk`
- `ListendHairline`
- `ListendAccent`
- `ListendAccentSoft`

Then expose them:

```swift
extension Color {
    static let listendPaper = Color("ListendPaper")
    static let listendSurface = Color("ListendSurface")
    static let listendInk = Color("ListendInk")
    static let listendMutedInk = Color("ListendMutedInk")
    static let listendHairline = Color("ListendHairline")
    static let listendAccent = Color("ListendAccent")
    static let listendAccentSoft = Color("ListendAccentSoft")
}
```

### 11.2 Radius Tokens

```swift
enum ListendRadius {
    static let small: CGFloat = 10
    static let medium: CGFloat = 14
    static let large: CGFloat = 20
    static let artwork: CGFloat = 16
}
```

### 11.3 Spacing Tokens

```swift
enum ListendSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}
```

### 11.4 Typography Helper

If using a custom serif font:

```swift
enum ListendTypography {
    static func display(_ size: CGFloat) -> Font {
        .custom("Lora-SemiBold", size: size, relativeTo: .title)
    }

    static let wordmark = Font.custom("Lora-SemiBold", size: 42, relativeTo: .largeTitle)
    static let displayTitle = Font.custom("Lora-SemiBold", size: 32, relativeTo: .title)
    static let displayStat = Font.custom("Lora-SemiBold", size: 32, relativeTo: .title2)
}
```

If no custom font is available yet, use SwiftUI serif design as a fallback:

```swift
.font(.system(.largeTitle, design: .serif).weight(.semibold))
```

---

## 12. Codex Implementation Plan

### Phase A — Add Design Tokens

```markdown
We are implementing the Listend Midnight Vinyl design system.

Implement design tokens only.

Scope:
- Add named color assets with light/dark variants:
  - ListendPaper
  - ListendSurface
  - ListendInk
  - ListendMutedInk
  - ListendHairline
  - ListendAccent
  - ListendAccentSoft
- Add Color extensions for these assets.
- Add ListendSpacing constants.
- Add ListendRadius constants.
- Add a lightweight ListendTypography helper if appropriate.

Constraints:
- Do not redesign screens yet.
- Do not change navigation.
- Do not change models, services, repositories, or persistence.
- App must compile and run after changes.

Before coding:
1. Inspect the repo.
2. Summarize current state.
3. List files to create or modify.
4. Wait for approval.
```

### Phase B — Shared Components

```markdown
Implement shared UI components for the Listend Midnight Vinyl design system.

Scope:
- ListendPrimaryButton
- ListendSecondaryButton
- AlbumArtworkView
- RatingStarsView using ListendAccent
- TagChip
- TagChipRow
- EmptyStateView
- StatPairView
- ReceiptRow
- JournalAssistCard

Constraints:
- Use existing data models where needed.
- Do not redesign full screens yet.
- Do not change app architecture.
- Do not add MusicKit, Foundation Models, authentication, cloud sync, or social features.
- App must compile and run after changes.

Before coding:
1. Inspect existing components.
2. Reuse what exists where practical.
3. List files to create or modify.
4. Wait for approval.
```

### Phase C — Redesign Home

```markdown
Redesign the Home screen using the Listend Midnight Vinyl design system.

Scope:
- Use ListendPaper as the screen background.
- Remove generic card treatment around the header/stats.
- Use display serif styling for the Listend wordmark.
- Add tagline: Albums that stayed.
- Show total logs and average rating as large stat numerals.
- Make Add Log the only filled primary CTA.
- Make Load Recently Played a secondary/outline action if it exists.
- Use redesigned LogEntryCard for recent logs.
- Restyle empty state using EmptyStateView.

Constraints:
- Preserve existing SwiftData fetching and navigation behavior.
- Do not change models or services.
- App must compile and run after changes.

Before coding:
1. Inspect the current Home implementation.
2. Summarize what will change visually.
3. List files to modify.
4. Wait for approval.
```

### Phase D — Redesign Search and Album Detail

```markdown
Redesign Search and Album Detail using the Listend Midnight Vinyl design system.

Scope:
- Search screen uses ListendPaper background.
- Search results use artwork-forward album rows.
- Album artwork placeholders use ListendAccentSoft, not generic gray.
- Album Detail uses large artwork and display serif album title.
- Log this album uses ListendPrimaryButton.
- Already logged state is clearly visible with rating and View/Edit Log action.

Constraints:
- Preserve existing mock catalog and navigation behavior.
- Do not add MusicKit.
- Do not change models or services.
- App must compile and run after changes.

Before coding:
1. Inspect Search and Album Detail views.
2. List files to modify.
3. Wait for approval.
```

### Phase E — Redesign Log Editor and Journal Assist

```markdown
Redesign the Log Entry screen and Journal Assist module using the Listend Midnight Vinyl design system.

Scope:
- Use display serif styling for New Log/Edit Log.
- Rating stars use ListendAccent.
- Review TextEditor should feel like a writing page with generous padding.
- Tags use TagChip styling.
- Journal Assist uses ListendAccentSoft and should appear as a distinct help module.
- Journal Assist sheet uses prompt chips instead of feeling like a dense form where possible.

Constraints:
- Preserve existing save/edit/delete behavior.
- Preserve SoundPrint processing behavior.
- Do not add new AI dependencies.
- App must compile and run after changes.

Before coding:
1. Inspect current Log Entry and Journal Assist views.
2. Summarize visual changes.
3. List files to modify.
4. Wait for approval.
```

### Phase F — Redesign Tonight’s Pick

```markdown
Redesign Tonight’s Pick using the Listend Midnight Vinyl design system.

Scope:
- Make this the most visually distinctive screen.
- Use large album artwork.
- Use display serif styling for the recommended album title.
- Show match percentage in ListendAccent.
- Style explanation as a personal note.
- Show receipts using ReceiptRow.
- Style feedback actions as compact chips/buttons: Like, Save, Listened, Dismiss.
- Restyle cold/empty state.

Constraints:
- Preserve existing recommendation scoring and feedback logic.
- Do not change models or services unless strictly required for UI wiring.
- App must compile and run after changes.

Before coding:
1. Inspect current Tonight’s Pick implementation.
2. List files to modify.
3. Wait for approval.
```

### Phase G — Redesign Profile and SoundPrint

```markdown
Redesign Profile and SoundPrint screens using the Listend Midnight Vinyl design system.

Scope:
- Profile uses flat stats, not nested cards.
- Persona appears as a content card with display serif quote styling.
- Top tags use TagChip styling.
- Taste dimensions use flat rows with confidence bars in ListendAccent.
- SoundPrint Profile shows dimensions with summaries, confidence, and receipts.
- Negative logs should not appear as positive evidence in UI.

Constraints:
- Preserve existing SoundPrint logic.
- Do not change models or services unless needed for UI display.
- App must compile and run after changes.

Before coding:
1. Inspect Profile and SoundPrint views.
2. List files to modify.
3. Wait for approval.
```

---

## 13. Definition of Done

The design-system implementation is complete when:

- System blue is removed from brand moments.
- Midnight Vinyl tokens are used consistently.
- Home feels like a journal opening screen.
- Tonight’s Pick feels like the signature feature.
- Log Editor feels like writing, not form-filling.
- Album art is larger and visually important.
- Cards are reserved for albums, logs, recommendations, persona, and assist modules.
- Profile is flatter and less nested.
- SoundPrint feels evidence-backed, not dashboard-heavy.
- Empty states use branded copy and accent treatment.
- Dark mode is warm and usable.
- Dynamic Type and VoiceOver remain viable.
- The app compiles and preserves existing MVP behavior.
