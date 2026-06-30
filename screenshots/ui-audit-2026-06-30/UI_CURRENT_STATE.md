# Listend UI Current State

This document summarizes the current UI flows captured in `screenshots/ui-audit-2026-06-30`. It is intended as a handoff for a future UI redesign agent. The screenshots were taken on an iPhone 17 simulator using UI-testing mock data.

## App Structure

Listend is a tab-based iOS app with four primary tabs:

- **Home**: dashboard, recent activity, recently played albums, and Today's Pick entry point.
- **Logs**: history of saved album diary entries.
- **Search**: album search and album detail entry point.
- **Profile**: listening stats and SoundPrint status.

The current UI is mostly native SwiftUI: `TabView`, `NavigationStack`, `List`, `Form`, sheets, section headers, system icons, and standard toolbar buttons. The visual language is quiet and diary-like, with grouped backgrounds, compact cards, serif branding in the home header, and understated system controls.

## Primary User Flows

### 1. Empty App Start

Relevant screenshots:

- `01-home-empty.jpg`
- `02-logs-empty.png`
- `03-search-empty.png`
- `04-profile-empty.png`

On a fresh local store, Home opens with:

- A branded header: “Listend” and the tagline “A quiet place for the albums that stayed with you.”
- Two stats: total logs and average rating.
- A primary **Add Log** button.
- A **Recently Played** module with a load CTA.
- No Today’s Pick module yet, because there is no qualifying positive log.

Logs shows a centered empty state: “No Logs Yet.” Search shows a centered “Search Albums” prompt. Profile shows stats with zero logs, no ratings, no tags, and a SoundPrint pending message.

### 2. Search And Album Detail

Relevant screenshots:

- `05-search-results.png`
- `06-album-detail-sos.png`
- `09-album-detail-already-logged.png`

Search uses a native searchable navigation view. With a query, results appear as a list of album rows:

- Artwork thumbnail
- Album title
- Artist
- Year and genre metadata

Selecting an album opens album detail. Album detail currently presents:

- Artwork/title/artist/year/genre
- Preview button
- **Log this album** CTA

After the album has a saved log, the CTA becomes an **Already logged** state. This is a useful state to preserve in redesign: it communicates completion directly on the album page.

### 3. Add Log / Edit Log

Relevant screenshots:

- `07-new-log-editor-top.png`
- `08-new-log-editor-track-highlights.png`
- `15-edit-log-editor.png`

The log editor is presented as a sheet with a `Form` and top toolbar:

- Cancel on the left
- Save on the right
- Title changes between “New Log” and “Edit Log”

Main sections:

- **Album**: compact selected-album summary.
- **Rating**: custom star rating control using half-star steps.
- **Review**: multiline text field.
- **Journal Assist**: three action rows.
- **Tags**: comma-separated text field with suggested tag buttons.
- **Track Highlights**: disclosure row that expands optional fields.

Track Highlights expands in place and contains:

- Favorite tracks comma-separated field.
- Less favorite tracks comma-separated field.
- Standout moment short text field.
- Footer text: “Optional album-level notes. No song logging required.”

The current editor is practical and dense, but because it is a native `Form`, the hierarchy can feel utilitarian. A redesign could preserve the data model while giving the logging moment a more expressive diary feel.

### 4. Journal Assist

Relevant screenshots:

- `20-journal-assist-help-write.png`
- `21-journal-assist-draft-review.png`
- `22-journal-assist-suggest-tags.png`

Journal Assist appears as a medium/large sheet over the log editor. The three modes share the same base layout:

- Navigation title for the mode.
- Done toolbar button.
- Reflection prompt fields.
- Quick Notes editor.
- Mode-specific action buttons.
- Result sections when draft/tag output exists.

Modes:

- **Help Me Write**: can generate a draft or suggest tags.
- **Draft Review**: focused on generating review text.
- **Suggest Tags**: focused on tag suggestions.

The current screenshots show the top prompt-heavy state. Redesign opportunity: clarify that this is an optional helper, reduce visual density, and make generated outputs feel more clearly actionable.

### 5. Saved Log Surfaces

Relevant screenshots:

- `10-home-populated.png`
- `13-logs-populated.png`
- `14-log-detail.png`
- `16-delete-log-confirmation.png`

After saving a log, Home updates to show:

- Total logs and average rating.
- Today’s Pick module.
- Recently Played module.
- Latest Log preview.

Logs becomes a scrollable list of recent log cards/rows. Each row shows:

- Album artwork
- Album/artist
- Rating
- Date
- Review snippet
- Favorite tracks when present

Log detail is a native list with sections:

- Album summary
- Log metadata
- Review
- Tags
- Track Highlights
- Delete Log action

Delete confirmation is a compact bottom sheet with destructive primary button and Cancel.

### 6. Today's Pick

Relevant screenshots:

- `11-todays-pick-empty.png`
- `12-todays-pick-active.png`

Today's Pick only appears once there is at least one qualifying positive log.

Initial state:

- “No Active Pick”
- Explains that the user can generate one pick backed by their logs.
- **Find Today’s Pick** button.

Active state:

- Recommended album artwork/title/artist/year/genre.
- Match confidence and freshness disclosure.
- Explanation text tying the pick to the source log.
- Preview button.
- Receipt/evidence row.
- Feedback actions: Like, Dismiss, Save for Later, Listened.

This is one of the richer flows in the app and likely deserves a more designed treatment than a plain list/card stack.

### 7. Choose Album

Relevant screenshots:

- `18-choose-album-recent.png`
- `19-choose-album-search-results.png`

The Add Log flow starts with a **Choose Album** sheet when no album is preselected.

Current structure:

- Cancel toolbar button.
- Recently Played section, with refresh action once loaded.
- Search section with native searchable field.
- Recent/search rows use the same album row pattern as Search.

The sheet can show both recently played albums and search results. Logged recent albums are marked as logged in the underlying Home/recently played surface.

## Current Visual Patterns

- **Navigation**: tab bar plus per-tab navigation stacks.
- **Surfaces**: grouped backgrounds, cards/modules on Home, native list/form rows elsewhere.
- **Typography**: Home uses a serif large title for brand; most other screens use standard SwiftUI title/headline/subheadline hierarchy.
- **Buttons**: mostly text + system icon labels; primary actions are usually bordered/prominent or row-style buttons.
- **Data density**: compact and scannable, especially in lists and forms.
- **Empty states**: `ContentUnavailableView` style with system icons and short explanatory copy.
- **Artwork**: small square album thumbnails on search/log rows; larger artwork appears on detail/recommendation surfaces.

## Redesign Notes For Another Agent

- Preserve the four-tab information architecture unless intentionally rethinking the whole app.
- Preserve core flows: search album, log album, view/edit/delete log, generate Today's Pick, inspect Profile/SoundPrint status.
- Preserve current data concepts: rating, review, tags, favorite tracks, less favorite tracks, standout moment, Journal Assist, Today’s Pick receipts.
- Keep local-first diary feel. The app should feel personal and reflective, not like a streaming service clone.
- Consider making Home and Today’s Pick the most visually distinctive areas; they carry the product personality.
- Consider making the log editor feel more like a writing surface while keeping controls efficient.
- Preserve empty states, loading/error states, already-logged states, and destructive confirmation states.
- The current app is mostly native and accessible; any redesign should keep clear labels, touch targets, predictable navigation, and readable contrast.

## Screenshot Index

1. `01-home-empty.jpg` - Home empty dashboard
2. `02-logs-empty.png` - Logs empty state
3. `03-search-empty.png` - Search empty state
4. `04-profile-empty.png` - Profile empty state
5. `05-search-results.png` - Search results
6. `06-album-detail-sos.png` - Album detail before logging
7. `07-new-log-editor-top.png` - New log editor top
8. `08-new-log-editor-track-highlights.png` - New log editor with track highlights expanded
9. `09-album-detail-already-logged.png` - Album detail after logging
10. `10-home-populated.png` - Home with log and Today’s Pick module
11. `11-todays-pick-empty.png` - Today’s Pick before generation
12. `12-todays-pick-active.png` - Active Today’s Pick
13. `13-logs-populated.png` - Logs list with saved entry
14. `14-log-detail.png` - Log detail
15. `15-edit-log-editor.png` - Edit log editor
16. `16-delete-log-confirmation.png` - Delete confirmation sheet
17. `17-profile-populated.png` - Profile after one log
18. `18-choose-album-recent.png` - Choose Album recent albums
19. `19-choose-album-search-results.png` - Choose Album search results
20. `20-journal-assist-help-write.png` - Journal Assist help-write mode
21. `21-journal-assist-draft-review.png` - Journal Assist draft-review mode
22. `22-journal-assist-suggest-tags.png` - Journal Assist tag-suggestion mode
