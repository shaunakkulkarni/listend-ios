# Listend launch plan: TestFlight first, then App Store

Status: proposed execution plan. User confirmed TestFlight beta before App Store release. Creating this document does not start implementation or distribution.

## Launch objective and scope

Ship the existing Listend experience: select an album, save ratings/reactions/notes, reach five logs, create a useful SoundPrint reflection, and discover an album through Today's Pick. Existing journals must survive upgrades, and optional Apple services must not prevent saving logs.

Planning target: a beta candidate within roughly five focused working days, followed by five to seven days of small-group use and a short stabilization pass before App Store submission. Reestimate after the baseline audit. These are working targets, not verified effort estimates or promises of Apple's processing/review time.

Freeze feature scope during this cycle. Defer cloud sync, accounts/social features, collections, major redesigns, a recommendation engine rewrite, a large evaluation harness, and general import/export. Reconsider export only if the storage audit reveals an actual launch-blocking recovery problem. Fix failures in the existing experience and anything required for an accurate, reviewable release.

## Starting evidence

- The preceding status audit verified local and live GitHub main at `f2e6d75`, the August 10 activation/taste-loop merge, with no open PRs or issues.
- Six existing uncommitted files contain cleanup edits. Preserve them; determine their intended disposition before incorporating them into release work.
- Historical verification passed the app/Share-extension build and 9/9 activation UI tests. It reported two Today's Pick unit failures, a stale SoundPrint UI assertion, and order/orientation-sensitive screenshot tests. This is not a fresh test result.
- The project currently declares version 1.5, build 4, iOS 26.4, and both iPhone and iPad. Actual uploaded/released versions have not been checked.
- `.asc/config.json` has no app ID. This does not prove that App Store Connect authentication, an app record, or prior builds are absent.
- No `PrivacyInfo.xcprivacy` was found in the repository. Audit required-reason API use and the final archive to determine the necessary declarations.
- General Settings has privacy explanation text; a published privacy policy and its in-app link still need verification/preparation.
- Production catalog setup uses a mock-backed fallback. Check whether fallback results and unavailable states are accurate and understandable to a release user.

## Milestone 1: establish the release baseline

Target: first working session; complete before changing product behavior.

- [ ] Record HEAD, working-tree diff, Xcode/SDK version, available simulator destinations, and production scheme/configuration.
- [ ] Inspect the six cleanup edits and propose whether to include them as a separate reviewed commit or leave them outside the release changes. Do not discard them.
- [ ] Build the production app and Share extension; run the unit suite once to establish the current baseline.
- [ ] Run focused UI coverage for onboarding, save/edit/delete, reflection creation/update, and Today's Pick. Investigate screenshot instability separately from functional regressions.
- [ ] Reproduce and classify the two historical recommendation failures and stale reflection assertion. Fix actual defects or obsolete expectations based on intended behavior; do not weaken assertions merely to pass.
- [ ] Read App Store Connect state: existing app, versions/builds, beta groups, signing/capabilities, and account readiness. Reuse existing records and version history.
- [ ] Audit the privacy manifest/API requirements, MusicKit and App Group setup, policy/support links, and production fallback behavior.
- [ ] Confirm the supported device/OS scope. Default to preserving the current iPhone+iPad scope and testing both; changing it requires an explicit product decision informed by existing distribution history.

Deliverable: a short launch-blocker list with severity, reproduction, likely fix, owner, and evidence. Record each result against its commit and environment. Reestimate the remaining work at this gate.

## Milestone 2: stabilize and verify the core loop

Target: next two to three working days, depending on Milestone 1 findings.

- [ ] Resolve launch crashes/hangs, storage problems, incorrect recommendation evidence, permission dead ends, and indefinite loading states.
- [ ] Make the current unit and functional UI suites pass. Keep any proven screenshot-only instability documented separately with equivalent visual inspection; it cannot mask a functional failure.
- [ ] On an existing physical iPhone installation, record representative saved data, install the candidate over it, and verify logs, reactions, tracks, and reflections remain intact. Do not delete the existing app to make an upgrade pass.
- [ ] Test a fresh installation on a separate device or test environment: onboarding, explicit Connect/Later, first log, five logs, reflection creation, and next reflection update after five additional logs.
- [ ] Test denied/revoked Music access and return from system Settings; unavailable network/services; unavailable Apple Intelligence; preview failure; and relaunch persistence.
- [ ] Validate Share-extension save and visibility in the main app, editing/deleting logs, and favorite/skip track persistence.
- [ ] Verify live Today's Pick returns a result or recoverable state, explains it using real evidence, states only completed freshness checks, and handles feedback. Exercise several contrasting listening histories; record relevance, novelty, and explanation issues without building a large new framework.
- [ ] Check a small iPhone layout, large text, VoiceOver on the core loop, Reduce Motion, and iPad portrait/landscape if iPad support is retained. Clearly label simulator checks versus physical-device checks.

Beta-entry gate: no known reproducible crash, data-loss path, blocked save, permission trap, or endless core-flow loading; required automated tests pass; physical iPhone upgrade and live-service checks pass; retained device families have usable layouts.

## Milestone 3: deliver a small TestFlight beta

Target: around working day five if the preceding gates pass.

- [ ] Use the production scheme and a version/build compatible with verified App Store Connect history. Validate the signed app and extension, entitlements, privacy declarations, and archive contents.
- [ ] Prepare beta description, feedback contact, review information, known limitations, and concise What to Test instructions.
- [ ] Upload the reviewed candidate after distribution authorization; confirm processing succeeds and resolve compliance prompts accurately.
- [ ] Smoke-test the actual TestFlight-installed build, including an upgrade from the previous candidate when applicable.
- [ ] Start with the owner/internal testing, then a proposed group of 5–10 external testers after any required TestFlight review. The owner supplies/approves the tester list and invitations.

Tester assignment: use personal album choices, save five logs, create a reflection, try Today's Pick and feedback, close/reopen the app, and return on another day to log again. Ask what felt confusing, whether the reflection was specific, and whether the pick was unfamiliar and worth trying. Gather feedback through TestFlight and direct voluntary reports; new analytics instrumentation is not required.

## Milestone 4: prepare App Store materials during the beta

This work can overlap the tester observation period; it does not require parallel agents.

- [ ] Prepare accurate name/subtitle/description/keywords and screenshots of the frozen build for supported device families. Refresh screenshots after visible release changes.
- [ ] Publish a truthful privacy policy and support/contact page; make the privacy policy accessible in the app. Complete App Privacy answers based on actual data flows, including Apple integrations and any SDKs.
- [ ] Resolve age rating, content-rights declarations, encryption/export questions, pricing, availability, and app-review contact information based on the actual app and owner's choices.
- [ ] Explain the five-log SoundPrint threshold, explicit generation, Apple Music behavior, Share extension, and AI/local fallback in reviewer notes. Provide reproducible steps without special undocumented reviewer-only behavior.
- [ ] Run App Store readiness validation against the exact app/version/build; inspect items the API cannot fully verify in App Store Connect.

Owner decisions needed before publishing: price/business model, initial territories, support contact/public URLs, final store copy, and release timing. Prepare concrete proposals and materials before asking for final approval.

## Milestone 5: close the beta and submit

Proposed exit criteria after five to seven days of use:

- At least five testers complete the five-log → reflection → pick flow; at least three return on a later day and save again. These are usability gates, not statistical proof of retention or recommendation quality.
- All reported launch-blocking issues are fixed and verified on the final candidate. No unresolved reproducible crash, data loss, core-flow blocker, or materially false recommendation explanation.
- Every lower-severity issue has an explicit fix/defer decision; cosmetic preferences do not continually expand scope.
- Final candidate passes focused regression checks, upgrade preservation, and a TestFlight installation smoke test. Tests from an older candidate do not certify changed code.
- Metadata, policy/support URLs, screenshots, and review information match the final build.

Prepare the exact version/build and submission summary for owner approval, then submit to App Review. Prefer manual public release so approval and publication remain separate decisions. After approval, verify the store listing and release the approved build when authorized. Smoke-test the public installation and review crash/feedback reports over the first 48 hours; any scheduled monitoring is a separate action.

## Ownership and immediate next session

Codex: baseline diagnosis, narrow fixes once implementation is authorized, automated verification, draft release materials, and evidence tracking. Owner: physical interaction/listening judgments, testers and feedback, business choices, and publication authorization. Device automation may assist but does not replace human acceptance of those behaviors.

Start with Milestone 1. Its definition of done is a current baseline and a ranked, bounded blocker list—not a new feature. No app implementation, build, upload, invitation, or submission was performed while writing this plan.

## Release references

- [Apple TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview): external testing may require beta review.
- [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers): beta review and external distribution workflow.
- [Apple App Review](https://developer.apple.com/app-store/review/): completeness, support, and privacy-policy preparation.
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/): verify applicable requirements against the final app.
- [App Privacy details](https://developer.apple.com/app-store/app-privacy-details/): accurate disclosures and public privacy-policy URL.
