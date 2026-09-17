# Your Listend launch checklist

Use this for the candidate identified in Launch_Readiness.md. Check the version/build in Profile → Settings before testing. Leave a box unchecked if it was not actually tested. Simulator, unit-test, and archive results do not substitute for these checks.

## 1. Protect and check your existing journal — do this first

- [ ] Before updating, record your current version/build and log count. Choose three existing entries and note their ratings, reactions, review, favorite/skip tracks, and standout moment. Record the current SoundPrint if present.
- [ ] Make an ordinary device backup if you rely on this journal. Do not delete Listend or reset its data to test an upgrade.
- [ ] Install the candidate over the existing app. It opens without a hang and shows your original logs. Existing users are not forced through onboarding.
- [ ] Compare the three entries and SoundPrint with the before-update notes. Close/reopen Listend and check again.

If anything disappears or the app freezes, stop and report the device/iOS version, previous and new app build, approximate launch time, and exact behavior. Keep the installation and its data intact for diagnosis.

## 2. First-session experience — use a separate fresh installation

Use another device or a fresh installation that has no journal to preserve. Replaying the introduction on your main phone tests replay only; it does not certify fresh-install permissions.

- [ ] Introduction is understandable, Skip/Later works, and reopening does not restart completed onboarding.
- [ ] Simply viewing onboarding does not show the Music permission prompt. Tapping Connect does.
- [ ] Decline Music access. You can dismiss onboarding and use the journal; unavailable music features explain their state. Verify the limited catalog fallback does not look like a successful live Apple Music search.
- [ ] Save an album with a rating and reactions. Saving finishes without waiting for intelligence services. The entry appears in Home/Logs after reopening.
- [ ] Save five personal album choices. Progress reaches five and offers Create My Reflection.

## 3. Apple Music and sharing — live iPhone checks

- [ ] Enable Music access in system Settings, return to Listend, and confirm Settings updates its status.
- [ ] Search for a known album, open it, select favorite/skip tracks, and save. Verify title, artist, artwork, and track ordering against Apple Music.
- [ ] Recently Played loads plausible albums for your account. Refresh and selection work.
- [ ] If a preview is offered, listen and verify it matches the selected album. A missing preview has a usable unavailable state.
- [ ] Share an album from Apple Music → Listend, save a rating/reaction, then open the main app and find the saved entry.
- [ ] Repeat with the app already open, and try an unavailable/invalid link. Recovery/manual entry is understandable and does not save incorrect album identity.
- [ ] Revoke Music access and return to Listend. Existing entries remain usable and optional features fail clearly.

## 4. SoundPrint and Today's Pick — judge actual usefulness

- [ ] Create a reflection after five logs on an Apple Intelligence-capable device. Read it: does it accurately reflect your notes, including dislikes, without inventing opinions?
- [ ] Turn off preferred Apple Intelligence in SoundPrint Settings or test an unsupported/unavailable device. The local fallback works and its source is understandable.
- [ ] Generate Today's Pick. Record approximate time to result; report any extended/stuck loading. Read its evidence against your actual source logs.
- [ ] The recommendation is relevant enough to consider and preferably unfamiliar. Freshness wording matches the checks performed; already-known albums are not falsely presented as guaranteed new.
- [ ] Try Already Know, dismissal, and another feedback action. Check that you can continue and that the saved feedback makes sense.
- [ ] Add five more logs and explicitly update SoundPrint. The represented log count updates and remains correct after relaunch.
- [ ] Edit/delete a test log and verify diary totals and reflection/update state remain coherent.

## 5. Reliability and accessibility

- [ ] Enable airplane mode: open existing logs, edit/save one, relaunch, and check persistence. Reconnect and recover optional features.
- [ ] Background/reopen the app during a search and during reflection/recommendation work. It remains usable and does not duplicate saved logs.
- [ ] At your largest useful text size, onboarding, save/cancel, reactions, reflection, and feedback controls stay reachable.
- [ ] With VoiceOver, navigate and save a test log; verify rating/reaction selections and loading/error states are understandable.
- [ ] With Reduce Motion enabled, the main flows remain comfortable and understandable.
- [ ] On an iPad, check portrait/landscape navigation, log editor, reaction sheet, and reflection. If no physical iPad is available, record that gap instead of claiming full device acceptance.

## 6. Decisions required for public release

- [ ] Choose the public support email/contact method and stable HTTPS support/privacy URLs. These are explicitly outstanding decisions.
- [ ] Review Privacy_Policy_Draft.md, add contact/effective date, and arrange publication. Have Codex add the final URL in General Settings and App Store Connect, then verify both links on-device.
- [ ] Review Store_Materials.md and captured screenshots. Approve accurate copy, supported-device scope, public price, initial territories, and copyright.
- [ ] Confirm content rights for catalog artwork/metadata/previews and complete the age-rating questionnaire based on what the app actually exposes.
- [ ] Verify the private App Review contact in App Store Connect and publish accurate App Privacy answers.

## 7. Small beta and public go/no-go

- [ ] Approve the external tester group/list and candidate once the device checks above pass. An existing external public link is configured; confirm its scope before sharing it. No new tester invitations should be inferred from this checklist.
- [ ] Get at least five testers through five logs → SoundPrint → Today's Pick, and at least three to return on another day. Collect observations for five to seven days; a smaller sample is a conscious owner decision, not completed evidence.
- [ ] Send Codex the issues and approve fixes/defer decisions. Any replacement candidate needs its changed behavior revalidated; data-loss/crash fixes require a fresh upgrade check.
- [ ] Approve the exact final build, screenshots, and metadata for App Review submission. Public release remains manual.
- [ ] After approval, authorize public release, install from the App Store, smoke-test, and inspect initial feedback/crashes during the first 48 hours.

## Report a result

Copy this for any failure or uncertain behavior:

```text
Candidate version/build:
Device and iOS:
Fresh install or upgrade from:
Apple Music permission / Apple Intelligence setting:
Checklist item:
Steps:
Expected:
Actual:
Reproduces every time or intermittently:
Screenshot or approximate time (optional):
```

Do not send private journal content unless needed and you are comfortable sharing it. Describe the mismatch in your own words where possible.
