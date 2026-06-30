# Listend UI Redesign Direction

Date: 2026-06-30
Source: `screenshots/ui-audit-2026-06-30/` (current-state audit, 22 screenshots + `UI_CURRENT_STATE.md`)
Scope: visual + interaction direction for a SwiftUI redesign. This is a spec for implementation in Xcode, not code.

## Note on how this was produced

This direction was written using the design-critique discipline from an anti-slop *web* frontend skill (the kind of checklist that catches "AI Purple," generic three-card grids, Inter-everywhere, etc.), translated to native iOS terms. It does **not** prescribe React/Tailwind/Motion — none of that applies here. Everything below assumes SwiftUI, the HIG, and SF Symbols / custom iOS components.

## Diagnosis: what's actually wrong today

The current app is not badly built — it's just **undifferentiated**. Every screen reads as "default SwiftUI components, lightly arranged":

- **System blue (`Color.accentColor` default) is the only accent**, used for buttons, links, icons, the active tab, star fills when rated, and `Play preview` text. It's doing every job a brand color would do, and it's the one color guaranteed to make an app look unfinished, because every untouched SwiftUI tutorial uses it too.
- **One card style everywhere**: white rounded-rect floating on `systemGroupedBackground` gray. Home stats, Today's Pick, album detail, the log editor, search rows — all the same card. Nothing tells you which screen you're on except the nav title.
- **Two competing display faces fighting for "brand"**: the serif "Listend" wordmark in the Home header card, and bold system sans for every other large title ("Profile," "Album," "New Log"). Pick one. Right now it reads like the serif was a logo asset dropped in, not a typographic system.
- **The diary concept is asserted in copy, not felt in design.** "A quiet place for the albums that stayed with you" sits inside a UIKit-default card with a system-blue pill button under it. Nothing about the visual language says diary, paper, ritual, or personal — it says "form with rounded corners."
- **Today's Pick — the most interesting screen in the app, the one actual differentiator — looks identical to every other list-of-cards screen.** Match confidence, the "because you liked..." reasoning, the receipts trail: this is the product's personality and it's currently presented with zero visual distinction from the Profile stats list.
- **Journal Assist is a sheet-on-a-sheet with the same Form chrome**, which makes an AI-assist feature feel like more paperwork rather than a moment of help.

The fix is not "add color and call it done." It's: build a real type and color system, give each screen's *job* a distinct visual treatment, and let Today's Pick and the log editor carry the personality the rest of the app borrows from.

## Direction: Warm Editorial Diary

Reference points worth looking at directly in the App Store, not for literal copying but for how they handle restraint + warmth: **Day One** (journaling, paper-adjacent warmth, serif/sans pairing done with intent), **Letterboxd** (rating + tagging + personal-taste data treated as content, not form fields), **Apple Music** (artwork-forward, confident large type, generous whitespace around metadata).

### Color system

Drop system blue as the accent entirely. One accent, used consistently:

- **Ink** — near-black warm gray for primary text and headlines. Not pure `#000000`. Something like `#1C1A17` (warm near-black) in light mode, `#F2EFE9` in dark.
- **Paper** — the base background. Warm off-white, not `systemGroupedBackground` cool gray. Light mode: something like `#F7F4EE`. Dark mode: a warm near-black surface, not pure OLED black (`#15130F`-ish), so cards can still read as "paper" against it.
- **Accent — pick one and lock it across every screen:**
  - A muted **clay/terracotta** (e.g. `#B3522F`-ish) reads "warm, personal, analog" and ties to the diary concept without falling into the banned beige+brass+oxblood cliché combo as long as you keep the rest of the palette restrained and don't pair it with brass or warm-paper-everywhere. Use it alone against ink/paper neutrals.
  - Alternative if you want something a little more modern-music-app: a deep **ink-blue** (e.g. `#2C3E50`-adjacent) — cooler, more "midnight listening" than "craft journal," still distinct from system blue.
  - Whichever you pick, it is the **only** saturated color in the app: rating stars when filled, primary CTA fill, active tab icon, links, the Today's Pick confidence indicator. Nothing else gets color. Tags, badges, and secondary icons stay ink/gray.
- **Star ratings**: currently plain SF Symbol stars in system blue when filled. Switch fill color to the accent; keep the five-star control but consider a slightly more tactile custom shape (hand-drawn-adjacent, not a generic SF Symbol) since rating is the single most "diary verdict" gesture in the app.

### Typography system

Two faces, each with one job — not "serif in the hero, sans everywhere else by accident."

- **Display serif** for moments that are the *subject* of the screen: the album title on Album Detail, the recommended album title on Today's Pick, the "New Log / Edit Log" title, the Home wordmark. This is where the diary/editorial feel lives. A warm literary serif (something like Source Serif, Lora, or a licensed equivalent — avoid Fraunces/Instrument-style trendy display serifs; this needs to read "Day One," not "Awwwards portfolio").
- **System sans (SF Pro, default Dynamic Type)** for everything functional: nav titles that aren't the subject (Profile, Logs, Search), body copy, metadata rows, button labels, tab bar, form labels. Don't fight Dynamic Type or accessibility sizing — SF Pro at system sizes stays correct automatically; the serif is reserved for specific named moments above so it never has to carry dense paragraphs.
- Stop using bold system sans as a faux-display face (the "Profile" / "Album" / "New Log" large titles today are just bold SF Pro at title size — fine for "Profile" and "Logs," wrong for "New Log"/"Edit Log," which should use the serif since the log itself is the diary entry).

### Surface & card system

- **Retire the single floating-white-card-on-gray pattern as the default for everything.** Reserve true elevated cards (white/paper surface, soft shadow) for *content that is genuinely a discrete object*: an album, a log entry, a Today's Pick recommendation.
- For **groupings of metadata or actions** (Stats rows, Receipts, Reflection Prompts, Tags), use flat dividers (`Divider()` / hairline `border-t` between rows) directly on the paper background instead of a second nested white card. Right now Profile nests "Stats" inside a white card inside a gray background — that's a card-in-a-card with no elevation purpose. Flatten it.
- **One corner radius scale, used consistently**: e.g., 20pt for primary content cards (album art container, Today's Pick card), 14pt for buttons/pills, 0 (flat, divider-separated) for in-card list rows. Today the radius is fairly consistent already — keep that discipline, just apply it on top of the new surface rules above.

### Per-screen direction

**Home** — This is the daily-open screen; it should feel like opening a journal, not a dashboard. Replace the stats-in-a-card-in-a-card pattern: serif "Listend" wordmark + tagline stay, but drop them onto the paper background directly (no card), with the two stats (Logs / Average) as plain large serif numerals with sans labels underneath, no pill backgrounds. "Add Log" becomes the one true accent-filled CTA on the screen — currently it's visually tied with "Load Recently Played," which is also full accent-blue; demote Recently Played's CTA to an outlined/ghost button so there's a clear single primary action per screen (per CTA-intent discipline: one obviously-primary action, not two competing blue pills).

**Today's Pick** — Give this the most distinct treatment in the app since it's the product's actual differentiator. Recommended album: large artwork (currently small/generic placeholder square — use real artwork at a meaningfully bigger size, art-directed like an "exhibit," not a list thumbnail), serif title, match confidence shown as a simple accent-colored numeral/percentage rather than the current plain gray text, and the "Because you liked X..." reasoning line set in a slightly distinguished style (italic or a quote-like treatment) since it's the most personal, written-feeling content in the app. Receipts and feedback actions (Like / Dismiss / Save for Later / Listened) move from a plain divided list to icon-forward chips or a horizontal row — four stacked link-style rows reads like a settings menu, not feedback on a recommendation that the app is proud of.

**Album Detail / Search** — Search results list and album detail card are functionally fine; mainly inherit the new type/color system. The big opportunity here is **artwork**: replace the generic placeholder square (circle-in-square icon) with either real Apple Music artwork or, when unavailable, a textured/tinted placeholder using the accent color rather than flat system gray, so even un-loaded artwork feels designed rather than broken.

**Log Editor (New/Edit Log)** — This is the writing surface and deserves the most "diary" feel. Concretely:
- "New Log" / "Edit Log" title in the display serif.
- Review `TextEditor` should look like a page, not a form field: more generous padding, no visible field border/background distinct from the page (or a very subtle one), placeholder copy ("What did this album leave with you?") in a lighter ink, not gray-on-white-card.
- Rating control: accent-colored stars (see Color section).
- Journal Assist: currently three blue link rows inside a white card — restyle as a single distinguished module (e.g., a soft accent-tinted background panel, not white) so it reads as "the app's assistant," distinct from regular data-entry rows. Icons should be consistent stroke weight from one icon family (currently mixed pencil/bubble/tag SF Symbols — fine if all default SF Symbols, just confirm consistent weight).
- Track Highlights stays a disclosure group; fine as-is functionally.

**Journal Assist sheet** — Reduce visual density per the existing audit note. Reflection Prompts as four stacked placeholder fields reads as more form-filling, which undercuts "assist." Consider presenting prompts as tappable suggestion chips that insert into Quick Notes on tap, rather than four more text fields to fill in.

**Logs list / Log Detail** — Inherits card + type system. Log rows (artwork + title/artist + rating + date + review snippet) are already a reasonable "diary entry" pattern — mainly needs the artwork-size and serif-for-title treatment from Album Detail.

**Profile** — Lowest-personality screen by design (it's a stats screen), but flatten the nested-card pattern (see Surface section) and use the accent for the rating numeral and any future SoundPrint persona badge once that ships.

**Delete confirmation** — Keep as a native compact destructive sheet; this is correct iOS pattern, just apply the type/color system (destructive button stays system red per HIG convention — don't reskin destructive actions with the brand accent).

### States to preserve (per current audit)

Empty states, "already logged" state, loading/error states, and destructive confirmation all need to be re-skinned in the new system, not redesigned structurally — they already do their job. Empty states specifically: keep the icon + short copy pattern, but use SF Symbols rendered in the accent color (not flat system gray) so even "nothing here yet" feels like the app, not a placeholder.

### Things to explicitly NOT do

- Don't add gradients, glassmorphism, or any "premium AI app" surface treatment — this is a quiet, personal, paper-like app, and that's a legitimate, well-validated direction (Day One has shipped this for a decade). Resist the pull toward glossy/cinematic.
- Don't introduce a second accent color "for variety." One accent, every screen, no exceptions — that consistency is what currently most undermines the app.
- Don't reach for the beige+brass+oxblood "craft/artisan" palette cliché. Warm paper + ink + one clay/terracotta or ink-blue accent is enough; don't add a second warm metallic tone on top.
- Don't change the four-tab IA, the data model (rating/review/tags/favorite tracks/standout moment), or existing flows. This is a visual and surface-level redesign of an already-sound structure.

## Suggested next step

Hand this doc to whoever (or whichever agent) implements the SwiftUI changes, screen by screen, starting with **Home** and **Today's Pick** since they carry the most product personality and will validate the new color/type system fastest before rolling it out app-wide.
