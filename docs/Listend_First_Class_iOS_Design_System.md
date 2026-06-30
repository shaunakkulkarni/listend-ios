# Listend First-Class iOS Design System

Date: 2026-06-30
Platform: iOS first, SwiftUI
Source inputs:
- `/Users/shaunakkulkarni/Documents/Listend_Midnight_Vinyl_Design_System.md`
- `docs/Listend_UI_Redesign_Direction.md`
- `screenshots/ui-audit-2026-06-30/`
- Current SwiftUI views in `Listend/Listend/Views`

## 1. Product Feel

Listend is a private music diary, not a streaming clone and not an AI dashboard. It should feel native, calm, and personal: Apple-level structure with album artwork and writing moments doing the emotional work.

The app should read as:

- Native iOS first.
- Artwork-forward.
- Personal and reflective.
- Quietly premium, not decorative.
- Receipt-backed when it recommends something.

The design mistake to avoid: replacing default SwiftUI blue cards with custom branded cards everywhere. First-class iOS apps usually feel first-class because they use system chrome well, reserve visual emphasis, and make the app's content feel valuable.

## 2. Design Principles

### Native Before Branded

Use `TabView`, `NavigationStack`, native sheets, `ContentUnavailableView`, toolbars, `searchable`, swipe/destructive patterns, Dynamic Type, SF Symbols, and system materials. Customize only where Listend's content needs identity.

### Artwork Is The Hero

Album art is the primary visual asset. Search rows can stay compact, but detail, Today's Pick, latest log, and recommendation surfaces should make art visible enough to carry mood.

### One Accent, Rarely Used

The accent is for primary action, selected state, rating fill, active tab, match confidence, and key links. It is not for every icon, every row label, or every decorative panel.

### Cards Are For Objects

Use cards for albums, logs, recommendations, persona summaries, and draft outputs. Do not use cards for every section, stat group, or metadata cluster.

### Glass Is Chrome, Not Wallpaper

Use Liquid Glass for interactive controls, floating action groups, tab/sidebar-adjacent chrome, and compact object surfaces on iOS 26+. Do not turn the whole app into layered frosted panels.

### The Diary Moment Gets Warmth

The log editor and Journal Assist should feel like writing, not filling out paperwork. Keep controls efficient, but let the review field and album context breathe.

## 3. Visual Tokens

Prefer semantic SwiftUI styles first. Add brand tokens only where they remove repeated magic values.

### Color

Use named colors with light and dark variants:

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `ListendBackground` | `#F7F4EE` | `#151411` | Main app background where a custom diary feel is useful |
| `ListendSurface` | `#FFFDF8` | `#1D1B17` | Object cards only |
| `ListendInk` | `#1C1A17` | `#F2EFE9` | Primary branded text when `primary` is not enough |
| `ListendSecondaryInk` | `#6F6A61` | `#BDB6AA` | Metadata and helper text |
| `ListendHairline` | `#DDD7CC` | `#343029` | Dividers, subtle borders |
| `ListendAccent` | `#A94F32` | `#D98563` | Primary action, ratings, active state, match confidence |
| `ListendAccentSoft` | `#F1DED5` | `#39231C` | Selected chips, Journal Assist, gentle empty-state icons |

Rules:

- Use `Color.accentColor` only after the asset is set to `ListendAccent`.
- Destructive actions stay system red.
- Keep inactive icons in `.secondary`, not accent.
- Use `.primary`, `.secondary`, `.tertiary`, `.background`, `.regularMaterial`, and `.thinMaterial` when they fit.

### Typography

Use two roles:

| Role | Font | Use |
| --- | --- | --- |
| Display serif | `.system(..., design: .serif)` or a bundled licensed serif later | App wordmark, album titles on detail, Today's Pick title, New/Edit Log title, persona quote |
| System sans | SwiftUI system text styles | Navigation, forms, metadata, rows, buttons, receipts, settings |

Rules:

- Do not use serif for dense body copy.
- Keep navigation titles system unless the title is the content subject.
- Use Dynamic Type text styles first. Avoid fixed-size typography except tightly controlled artwork/title compositions.

### Spacing And Radius

Keep the scale small:

```swift
enum ListendSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum ListendRadius {
    static let chip: CGFloat = 10
    static let control: CGFloat = 14
    static let card: CGFloat = 20
    static let artwork: CGFloat = 16
}
```

Use 8pt corners for small native/glass utility surfaces when that better matches iOS 26 chrome. Use 20pt only for real content objects.

## 4. Surface System

### Screen Background

Default: system background/grouped background where the native structure should win.

Use `ListendBackground` for Home, Today's Pick, Log Editor, and SoundPrint surfaces where the diary identity matters.

### Object Card

Use for:

- Album cards
- Log rows/cards
- Today's Pick recommendation
- Persona summary
- Generated Journal Assist draft

Style:

- `ListendSurface` or `.regularMaterial`
- Radius 16-20
- 16-20pt padding
- Hairline or very soft shadow, not both by default

### Flat Row Group

Use for:

- Receipts
- Profile stats
- Taste dimensions
- Settings-like actions
- Metadata rows

Style:

- No outer card unless the group itself is the object
- Native list rows or plain `VStack` with dividers
- Icons in `.secondary` unless action/selection requires accent

### Liquid Glass

Use only with availability checks:

```swift
if #available(iOS 26.0, *) {
    content
        .glassEffect(.regular.interactive(isInteractive), in: .rect(cornerRadius: 14))
} else {
    content
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
}
```

Rules:

- Wrap multiple nearby glass elements in `GlassEffectContainer`.
- Apply `.glassEffect` after layout and visual modifiers.
- Use `.interactive()` only for tappable/focusable elements.
- Use `.buttonStyle(.glass)` or `.buttonStyle(.glassProminent)` for iOS 26 actions.
- Use morphing IDs only for actual animated hierarchy changes.
- Fallbacks should use native material, not hand-rolled blur.

## 5. Core Components

### `AlbumArtworkView`

Required states:

- Loaded artwork.
- Loading.
- Designed placeholder.

Placeholder:

- `ListendAccentSoft` background.
- `opticaldisc`, `music.note`, or `record.circle` symbol.
- Accent foreground at reduced opacity.
- Same radius as real artwork.

Sizing:

- Search/log row: 48-64.
- Detail: 180-240 depending on viewport.
- Today's Pick: 220+ when possible.

### Primary Button

Use once per screen:

- Home: Add Log.
- Album Detail: Log this album.
- Log Editor: Save.
- Journal Assist: Use Draft.
- Today's Pick empty state: Find Today's Pick.

iOS 26:

- `.buttonStyle(.glassProminent)` for prominent actions.

Fallback:

- `.buttonStyle(.borderedProminent)`.
- Accent tint.

### Secondary Button

Use for supporting actions:

- Load Recently Played.
- Play Preview.
- Refresh.
- Regenerate.

iOS 26:

- `.buttonStyle(.glass)` for compact chrome.

Fallback:

- `.buttonStyle(.bordered)` or plain row button depending on context.

### Rating Control

- Filled stars: `ListendAccent`.
- Empty stars: `ListendHairline` or `.tertiary`.
- Editing target must remain easy to tap.
- Display-only rows can be compact.

### Tag Chip

- Default: subtle border or material, `.secondary` text.
- Selected/suggested: `ListendAccentSoft` background, accent text.
- Keep chips short. Wrap before shrinking text too far.

### Receipt Row

Receipts prove trust. Keep them readable:

- Source album title.
- Artist.
- Rating or tag evidence.
- One short quote/snippet.

Use rows, not oversized cards. The recommendation card is already the parent object.

### Journal Assist Module

This is a helper, not a second product.

- Use `ListendAccentSoft` or subtle material.
- Lead with `sparkles` or `square.and.pencil`.
- One line of copy.
- One primary entry action, then reveal modes.

Avoid three large blue row buttons stacked like Settings.

## 6. Screen Guidance

### Home

Goal: daily open, fast path to logging.

Keep:

- Four-tab structure.
- Recent logs.
- Recently Played.
- Today's Pick entry.
- SoundPrint teaser.

Change:

- Remove the big card around the wordmark/stats.
- Use serif `Listend` as page identity, directly on background.
- Show stats as flat large numerals, not pills.
- Make Add Log the only filled/prominent action.
- Demote Load Recently Played to secondary.
- Keep cards only for Today's Pick, SoundPrint summary, and latest log.

### Logs

Goal: diary history.

Use:

- Native list or scroll of object rows.
- Artwork, title, artist, rating, date, one snippet.
- Serif only for album title if it improves personality without hurting scan speed.

Do not:

- Add decorative cards around each metadata line.
- Hide edit/delete behind custom gestures only.

### Search

Goal: fast lookup.

Use:

- Native `.searchable`.
- Compact album rows.
- Artwork on every result.
- System title and system typography.

Keep this screen restrained. It is a utility path, not the brand showcase.

### Album Detail

Goal: confirm album and start a log.

Use:

- Large artwork.
- Serif album title.
- System metadata.
- Primary Log this album button.
- Clear Already Logged state with View/Edit Log.

Do not hide completion state. It is useful feedback.

### Log Editor

Goal: writing ritual with efficient controls.

Use:

- Sheet with native toolbar actions.
- Serif `New Log` / `Edit Log`.
- Album context object near top.
- Rating as a tactile control.
- Review field styled like a writing page.
- Tags as chips where possible.
- Track Highlights as a disclosure.

Avoid:

- Dense `Form` look for the whole surface.
- Multiple equal-weight assistant actions.
- Over-styled Save/Cancel that fights native sheet behavior.

### Journal Assist Sheet

Goal: unblock writing.

Use:

- One Quick Notes area.
- Prompt chips that insert or shape notes.
- Generated output as an object card.
- Use Draft as the primary action.
- Suggest Tags as chips.

Avoid:

- Four empty prompt fields before the user gets value.
- AI copy that sounds like a separate chatbot.

### Today's Pick

Goal: signature feature.

This is the most important redesign target.

Use:

- Large artwork.
- Serif album title.
- Accent match percentage.
- One personal explanation.
- Receipt rows beneath.
- Feedback actions as compact buttons/chips, not Settings rows.

Layout:

1. Header: "Today's Pick" and short subtitle.
2. Recommendation object with artwork/title/artist/confidence.
3. Explanation.
4. Receipts.
5. Feedback group: Like, Save, Listened, Dismiss.

Cold state:

```text
No pick yet.
Log a 4-star album and Listend can choose one with receipts.
```

### Profile And SoundPrint

Goal: taste identity and evidence.

Use:

- Native sections.
- Flat stats.
- Persona as an object card.
- Taste dimensions as rows with confidence bars.
- Receipts/evidence next to each meaningful claim.

Avoid analytics-dashboard styling. The user is reading themselves, not a report.

### Settings

Use native grouped settings. Low personality is correct here.

## 7. Interaction Rules

### One Primary Action Per Screen

If two buttons look equally important, one is wrong.

### Use Native Presentation State

- Prefer `.sheet(item:)` for selected models/modes.
- Keep sheet actions inside the sheet when possible.
- Avoid parallel booleans for mutually exclusive presentation.

### Use Scroll Instead Of Gesture State Machines

For reveal/collapse effects, derive progress from scroll position before adding custom gestures.

### Accessibility

Required:

- Dynamic Type works for all main text.
- Minimum 44pt interactive targets where practical.
- VoiceOver labels for artwork, ratings, recommendation feedback, and destructive actions.
- Do not rely on color alone for selected states.
- Destructive remains system red.

## 8. Implementation Notes

### Keep Existing Good Structure

The current app already has:

- `TabView` with four tabs.
- Per-tab `NavigationStack`.
- SwiftData queries scoped to views.
- Shared components like `AlbumArtworkView`, `StarRatingControl`, `AlbumPreviewControl`, and `EditorialSurface`.

Reuse those. Do not add a design framework.

### Token Pass

Small first diff:

1. Add color assets.
2. Add `Color` helpers.
3. Add radius/spacing constants only if repeated values remain.
4. Set app accent tint to `ListendAccent`.
5. Update `StarRatingControl` and artwork placeholder colors.

### Surface Pass

Then update shared components:

1. `EditorialSurface` should remain small and native.
2. Use Liquid Glass only on iOS 26+.
3. Add a plain object-card option and a flat-row option.
4. Do not make every section use `EditorialSurface`.

### Screen Pass Order

Implement in this order:

1. Home.
2. Today's Pick.
3. Log Editor and Journal Assist.
4. Album Detail and Search.
5. Logs.
6. Profile and SoundPrint.

Home and Today's Pick prove the system fastest.

## 9. Code Patterns

### Accent Setup

```swift
extension Color {
    static let listendBackground = Color("ListendBackground")
    static let listendSurface = Color("ListendSurface")
    static let listendInk = Color("ListendInk")
    static let listendSecondaryInk = Color("ListendSecondaryInk")
    static let listendHairline = Color("ListendHairline")
    static let listendAccent = Color("ListendAccent")
    static let listendAccentSoft = Color("ListendAccentSoft")
}
```

### Display Title

```swift
Text(album.title)
    .font(.system(.largeTitle, design: .serif).weight(.semibold))
    .foregroundStyle(.primary)
    .fixedSize(horizontal: false, vertical: true)
```

### Glass Action Group

```swift
@ViewBuilder
func listendActionGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    if #available(iOS 26.0, *) {
        GlassEffectContainer(spacing: 12) {
            content()
        }
    } else {
        content()
    }
}
```

### Object Card

```swift
struct ListendObjectCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.separator.opacity(0.25), lineWidth: 1)
            }
    }
}
```

## 10. Explicit Non-Goals

- No new navigation model.
- No new dependency.
- No custom blur implementation.
- No web-style design system with dozens of variants.
- No gradients/orbs/decorative backgrounds.
- No second accent color.
- No custom controls where native controls are already excellent.
- No macOS redesign until the iOS app direction is stable.

## 11. References

- Apple Liquid Glass overview: https://developer.apple.com/documentation/technologyoverviews/liquid-glass
- Apple SwiftUI documentation: https://developer.apple.com/documentation/swiftui
- Apple Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines
