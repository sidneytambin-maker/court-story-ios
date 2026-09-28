# Court Story Build 32

The TestFlight record was renamed before the installed apps. Build 31 still used the former visible name and TT artwork. Build 32 completes that branding change without renaming the app's permanent bundle IDs, App Group, widget kinds, URL scheme, persistence keys or library file locations.

Both platform icons now show a high-contrast CS tennis-ball monogram. The full system display name and spoken Home Screen name are Court Story on iPhone and Apple Watch; the complication extension has the same full name. CS is not an accessibility label.

Updated surfaces include onboarding, Siri descriptions and responses, Calendar and Health permission explanations, Watch connectivity status, new Calendar-event notes, private-backup export names and messages, offline privacy information, the public privacy page and TestFlight copy. Removed company attribution from the app's privacy policy. Existing user records, previously exported files and past Calendar notes are not destructively rewritten.

Source regression tests reject retired visible branding, pin the approved icon hash and protect stable storage and sync identifiers. Archive and signed-IPA checks reject shortened or stale app names in any component, old permission copy and old branding in compiled executables. Apple's native asset inspection checks both compiled icon catalogues before upload.

## Verified Publication

- Source: `572f5c5cbfe1da312d84f7309fc04d014d181d67` on `codex/testflight-beta`.
- Full validation and upload: [GitHub Actions run 34650550238](https://github.com/sidneytambin-maker/tennis-tracker-ios/actions/runs/34650550238), all four jobs successful.
- Tests: 98 packaging regressions, 192 native unit tests, 28 iPhone interface tests and 25 Watch interface tests passed, 343 in total.
- Two fresh iPhone installations and two fresh Watch installations contained no personal records. The two iPhone libraries had distinct identities.
- The downloaded archive and the exported signed IPA both report Court Story as the full display and bundle name for all three components, version 0.1.0 (32).
- Apple's native asset inspection verified opaque 1024-square sRGB icons in both exported app catalogues. All three exported signatures and embedded distribution profiles passed verification, followed by Apple's package validation and successful upload.
- Apple build `5f898a12-8c42-4140-9b10-bab1f0ed60b4` processed as `VALID`, with export compliance resolved and internal state `IN_BETA_TESTING`.
- Build 32 and its updated testing notes are assigned to the existing Owner Verification internal group. Automatic build notification is enabled.
- Apple's email, "Court Story 0.1.0 (32) for iOS is now available to test.", was confirmed in the owner's inbox at 22:24:59 UTC on 11 September 2026. It identifies the update as ready for iOS and watchOS. The original invitation was already accepted, so a replacement invitation was unnecessary.
- The live TestFlight description and public privacy page now use Court Story. The public privacy page was checked successfully and contains no retired visible name or company attribution.

## External Access, 12 September 2026

- Apple approved the first external beta, build 31. The already validated, fully renamed build 32 was then added to Community Beta and submitted for external testing during Sidney's active request for the same joining-link access as Galleonaire.
- Build `5f898a12-8c42-4140-9b10-bab1f0ed60b4` now has review state `APPROVED` and external state `IN_BETA_TESTING`, read back from Apple after submission. Internal owner access remains unchanged.
- The existing Court Story public invitation link is enabled, with an enforced limit of 100 testers. No external testers were present before the limit was applied.
- Apple's live joining page returned HTTP 200, identified itself as Join the Court Story beta, offered Start Testing, and did not report that the beta was full, expired or unavailable.
- Sent "Your Court Story TestFlight download link" to the verified owner email. The response confirmed both SENT and INBOX. The email points to the external joining link and identifies build 32, including the new artwork and full spoken app name.
- The joining link was delivered only to Sidney, who can share it with chosen testers. It is not copied into this public repository; retrieve it from the Community Beta group's App Store Connect record when needed.
- No tester accounts were deleted, no Apple Account settings were changed, and Galleonaire's access was not modified by this action. No new binary or rebuild was necessary.

## Remaining Device Checks

The build is available in the owner's TestFlight account. Automatic installation depends on the device's TestFlight settings and Apple's delivery timing; physical installation, Home Screen VoiceOver speech and post-update Watch sync have not been observed for build 32. The test notes explicitly request the full spoken name and preservation of existing records. No app deletion or data reset is required for this rename.

Both builds 31 and 32 have Apple's external beta approval. The public joining route can now deliver the current build 32; select that build, not the older build 31, when checking Court Story's updated branding. This is TestFlight beta availability, not a public App Store release.
