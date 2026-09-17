# Listend release materials

Draft for owner review. Description, keywords, and subtitle have been staged in App Store Connect; nothing has been submitted or publicly released. Legal, pricing, territory, and privacy declarations remain unchanged. Target app: 6767377515, bundle `com.shaunakkulkarni.Listend`. Keep marketing version 1.5; the existing iOS App Store draft has been aligned to 1.5 with manual release. Existing macOS draft is outside this iOS launch.

## App Store copy

Name: Listend - Personal Album Diary

Subtitle: A journal for your music taste

Keywords: music,journal,ratings,reviews,listening,records,reactions,discovery,collection,reflection

Description:

Remember the albums that stayed with you—and why.

Listend is a personal album diary for your ratings, reactions, and listening notes. Keep a record of the music you love, the tracks you return to, and the moments that make an album worth another listen.

LOG YOUR LISTENING
Find an album, give it a rating, and add as much detail as you like. Choose reactions, write a review, and save favorite tracks, skips, or a standout moment. Revisit and edit your entries as your opinions change.

SEE YOUR SOUNDPRINT
After five logs, create a SoundPrint reflection from your journal. Explore patterns in what you enjoy, supported by your own listening history. Create an updated reflection after five more logs.

FIND YOUR NEXT LISTEN
Today's Pick suggests one album at a time, with context from your journal. Give feedback to help shape what comes next. Apple Music can provide catalog connections and checks against your library and recent listening; availability and coverage vary.

LOG FROM APPLE MUSIC
Use the Share extension to save an album from an Apple Music link, or browse your recently played albums when access is available.

YOUR JOURNAL, ON YOUR DEVICE
Listend stores your journal locally. SoundPrint can use on-device Apple Intelligence when supported and available, with a local fallback. Optional music and intelligence features do not need to finish before a log is saved.

Apple Music features require access to Apple services. Apple Intelligence availability depends on your device and settings. Listend does not currently offer its own account, cloud sync, or journal export.

## TestFlight What to Test

This candidate focuses on launch reliability and the first listening-journal experience.

1. If you already use Listend, install this update without deleting the app. Confirm your existing logs, reactions, and track notes remain intact.
2. On a fresh install, try onboarding and the Apple Music Connect/Later paths. Save five albums with your own ratings and reactions, then create your first SoundPrint.
3. Try Today's Pick, read its explanation and source logs, and give feedback. Tell us whether the pick was unfamiliar and interesting.
4. Edit and delete a test log, share an album from Apple Music into Listend, then close and reopen the app to confirm your changes persist.
5. Add five more logs and update SoundPrint. Return on another day and save another album.

Please report crashes, missing data, stuck loading, confusing permissions, inaccurate explanations, and layouts that hide controls. Include your device/iOS version, app build, steps, and expected behavior. Use TestFlight's feedback option; avoid sharing personal journal text unless you choose to.

Known limitations: journal data is local, there is no Listend sync/export, Apple Music history checks are best-effort, and unavailable Apple services use limited local fallbacks. Simulator tests do not validate live Apple Music or Apple Intelligence quality.

## App Review notes

Listend is a local personal album diary. No Listend login is required and there are no in-app purchases in this candidate.

Start with onboarding, optionally connect Apple Music, and add a log from album search or recently played albums. A rating is required; reactions, notes, favorite/skip tracks, and standout moments are optional. Saved entries can be edited/deleted in Logs.

SoundPrint requires five saved logs. At that point Home/Profile offers an explicit Create action. After creating the reflection and adding five further logs, Profile offers Update. This is intentional generation, not an automatic response on every save. On supported devices it may use Apple's on-device Foundation Models; a local fallback is available. See Profile → Settings → SoundPrint Settings for availability/preferences.

Today's Pick becomes available with sufficient journal history. It presents a single recommendation with explanations and feedback actions. Apple Music catalog, relationship, library, recent-play, and preview features depend on Apple service access. Freshness checks do not represent a complete Apple listening-history audit.

For the Share extension, share an album URL from Apple Music, select Listend, add a rating, and save. Open the main app to view the saved entry. If album lookup is unavailable, the extension supports manual album details.

## Owner decisions and missing fields

- Public support contact and support URL: owner has explicitly left undecided.
- Public privacy-policy hosting and the final in-app URL: undecided. See Privacy_Policy_Draft.md.
- Price and initial territories: confirm. Proposed starting point is a free beta; that does not decide the public app's price.
- Proposed primary category: Music; optional secondary category: Lifestyle. Confirm before publishing.
- Content rights: uses Apple Music catalog metadata/artwork and previews. Confirm the applicable rights; do not accept the validator's generic suggestion to declare no third-party content.
- Age-rating questionnaire: assess accessible album titles, artwork, explicit metadata, previews, private user notes, and generated reflections. Do not set every content category to None without review.
- App Review contact: an existing beta-review contact is populated in App Store Connect and can be reviewed there; do not put private phone/email values in this repository.
- Copyright: proposed `2026 Shaunak Kulkarni`; confirm owner attribution.
- App Privacy: proposed no developer collection/tracking based on the inspected code. Confirm against the final archive and Apple service behavior before publishing the declaration.
- Public launch: manual release after review approval and the validation checklist passes.

## Screenshot brief

Capture the final build, using only fictional/sample journal entries: Home with progress or a reflection; log editor with reactions; Logs; SoundPrint reflection; Today's Pick with its evidence. Show the actual interface and preserve visible fallback/provenance labels. Capture iPhone and iPad if both remain supported. Screenshots generated from test fixtures are draft assets until visually approved; do not claim that simulator-generated reflections prove the on-device model experience.

## Sources

- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [TestFlight external testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers)
