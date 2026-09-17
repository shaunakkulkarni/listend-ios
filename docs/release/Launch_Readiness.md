# Listend launch readiness

Updated September 17, 2026. Candidate: version 1.5, build 7. Release order remains TestFlight beta, then App Store. This document records engineering evidence; it does not certify release acceptance.

## Included work

- Preserve the original journal if migration to the shared App Group store fails. Stage files before publication, publish the main store last, roll back partial publication, and remove orphaned sidecars on retry.
- Add migration regression coverage, privacy manifests for the app and Share extension, and an IPA metadata inspection script.
- Correct Today's Pick dimension-label capitalization and the receipt test fixture, and remove unused internal helpers.
- Update UI tests for iPad tab controls, current SoundPrint update wording, and manual track-entry keyboard handling. Add sample-data launch screenshot coverage.
- Keep the production and Sandbox app identities separate, with version 1.5/build 7 in both configurations.

## Verification

### September 17

- The current production scheme built successfully in Xcode. The development build was installed over the existing Listend app on the owner's iPhone Air and launched successfully.
- The owner reported that Recently Played resumed working. No Recently Played code change was made; the transient issue's cause remains unconfirmed.
- Fresh pre-merge verification on the iPhone 17 simulator with iOS 27.0 passed all 362 unit tests and four focused UI tests: existing-user onboarding bypass, reflection create/update, manual track-entry fallback, and launch screenshots.
- The focused launch screenshot test also passed on the iPad Pro 13-inch (M5) simulator with iOS 27.0, including tab navigation and landscape capture. Captured screenshots still require visual approval before use as store assets.
- The iPhone UI run's post-test simulator diagnostic collection stalled. Only that diagnostic subprocess was stopped; the test command then completed successfully. The four test results passed before diagnostic collection was stopped.
- The Foundation Models symbol guard, release JSON/privacy plist parsing, IPA script syntax, project-file validation, local documentation links, and `git diff --check` passed.
- Xcode emits Swift concurrency warnings in the existing code/tests. Passing this suite does not establish Swift 6 language-mode readiness.

### Historical September 9 evidence

The previous preparation session recorded 361 passing unit tests, a successful Release build/archive/export, and a passing IPA metadata inspection for version 1.5/build 7. These are historical results, not a fresh archive of the final merge.

Focused reflection and Settings UI tests passed in that session. iPad launch screenshot coverage remained unverified after an assertion correction and a timed-out rerun. Physical-device acceptance, upload of this candidate, and beta distribution were not completed in that session.

## Remaining release gates

- Complete the [owner validation checklist](Owner_Validation_Checklist.md), especially upgrade preservation, live MusicKit and Share-extension behavior, SoundPrint quality, recommendation usefulness, accessibility, and iPad layouts.
- Review final screenshots and [store materials](Store_Materials.md). Finalize support/privacy URLs, contact details, pricing, territories, content rights, age rating, and App Privacy declarations.
- Recheck App Store Connect and the exact candidate before authorizing upload, tester distribution, submission, or public release. Installing a development build through Xcode does not complete those steps.

## Supporting files

- [Launch plan](../Listend_Launch_Plan.md): original milestone plan; unchecked items are not a current automated test report.
- [Privacy policy draft](Privacy_Policy_Draft.md): unpublished preparation material.
- [App Store readiness snapshot](app-store-readiness.json): historical pre-staging validator output for version 1.0, including 35 blockers. It is not the current status of version 1.5.
- `metadata/version/1.5/en-US.json`: draft description and keywords; not evidence of submission.
- `scripts/verify-release-ipa.py`: checks archive metadata, bundled provisioning files, and privacy declarations. It does not validate signatures, distribution entitlements, or device behavior.
