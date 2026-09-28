# First TestFlight Release Gates

Target: version 0.1.0, build 32; team HT5X86Q4DD. App Store Connect listing: Court Story. Build 32 completes the Court Story rebrand across iPhone, Watch, complications and privacy information. The permanent iPhone, Watch and widget identifiers and required capabilities are registered. Apple Distribution credentials and three App Store profiles are verified; this does not establish that this build has passed native validation or upload.

## Build and Privacy

- Keep the known-good development deployment intact until TestFlight replacement succeeds physically.
- Run all packaging tests, iPhone unit/UI tests, Watch UI tests and release-container tests at the exact source commit.
- Archive with the TestFlight scheme using Xcode's native target dependencies. Do not move or rewrite nested bundles after signing.
- Require the phone app, Watch app under Watch/, and complication extension under that Watch app's PlugIns/ directory.
- Require matching versions, permanent identifiers, the correct Watch companion association and permanent App Group.
- Inspect final resources and executables for personal data, exports, test fixtures, temporary identifiers and simulator launch hooks. Also scan locally against the owner's private backup without sending that backup to CI.
- Verify Apple distribution signatures and profiles separately. An unsigned archive passing structural checks is not an installable TestFlight build.
- After exporting the IPA, extract an inspection copy without changing the signed files and run `python3 Scripts/verify_testflight_signing.py --app Payload/TennisTracker.app` on macOS. This checks all three signatures, App Store profile type, expiry, actual signing certificate, team, identities, entitlement grants, App Groups and Watch HealthKit. Apple processing remains a separate required gate.
- Require Apple processing success before enabling internal testing. Do not submit an App Store release.

## Private Owner Migration

1. Take fresh private backups from the development iPhone and Watch while no activity is running. Compare complete records by stable ID, catalogues, settings, deletion history and relationships.
2. Keep the original installation, original backup and original signing/deployment route unchanged.
3. Install the permanent TestFlight app alongside the development identity. Do not assume it can see the old app's private container.
4. Transfer only the owner's verified backup over the trusted USB connection to the new app's Documents folder, using Apple's file-sharing route. The app's live library remains in Application Support, outside Documents.
5. In the new installation, use Restore My Private Backup, review counts, then Restore My Backup. Restore is unavailable once a destination library is set up; it does not merge with or overwrite existing records.
6. Compare all restored fields and stable record IDs with the original private backup. Only the library transport identity, onboarding state and supported schema version should change.
7. Confirm the paired Watch receives the new owner's library, and verify complete records and two-way edits. The backup does not export or replace Apple's Health database.
8. Remove the temporary transferred backup only after verifying restore, retaining the private recovery copy. Do not include any backup in source control, CI artifacts, beta feedback or distributed app resources.

## Independent Tester Installation

- Separate installation containers must start with distinct library identities, no selected player, empty records and setup tables, no achievements and no workout summaries.
- Optional onboarding choices must remain optional. Do not request Health access during setup, and do not request notifications unless the user selects Allow Notifications.
- A finished setup with zero matches must stay finished across launches and updates.
- Corrupt, incomplete or newer-version libraries must not be silently replaced with an empty library.
- A new Watch library must not accept old queued edits, old receipts, old Health results, pinned notification records or delayed snapshots from a retired library.
- Do not add a reset-all feature until its phone, Watch, Health and complication cleanup is tested end to end.

## Apple Account Gates

The account holder must review required agreements and complete authentication/security confirmations. Register and verify permanent IDs/capabilities, create the App Store Connect app record, and configure secure distribution credentials. Never commit private keys or publish them in logs. Keep the verified feedback address in App Store Connect, not in public source.

## External TestFlight Availability

1. Complete the build/privacy, owner migration and independent clean-install checks above. Create an internal group before an external group.
2. Upload for App Store Connect distribution, not the Internal Only route, so the same validated build remains eligible for external testing.
3. Provide the beta description, What to Test and verified feedback/review contact details. Do not include owner records, backup attachments or invented contact information.
4. Add the validated build to an external group and submit the first build for TestFlight App Review. Resolve any review or export-compliance issues accurately.
5. Require Apple's external-testing approval before marking the beta available. Upload success or internal installation alone does not satisfy this step.
6. Enable the approved external build and a TestFlight invitation link, then verify that the link identifies the correct app and accepts testers. Do not send unsolicited invitations or publish an App Store release.
7. Verify the normal tester route includes the Watch companion without developer signing tools. Report any remaining physical-device acceptance checks explicitly.

Reference: [Apple external TestFlight requirements](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers).

## Encrypted Upload Configuration

The workflow's optional upload job is disabled on pushes. A manual run on the reviewed beta branch with `upload_to_testflight` enabled must first pass all three native validation jobs. It uses the `testflight` environment and serializes uploads without cancelling an in-progress upload.

Configure environment secrets only after Apple has created the permanent identities and App Store Connect record:

- `TENNIS_DISTRIBUTION_P12`: base64 Apple Distribution certificate and private key; `TENNIS_DISTRIBUTION_PASSWORD`: its password.
- `TENNIS_PHONE_PROFILE`, `TENNIS_WATCH_PROFILE`, `TENNIS_WIDGET_PROFILE`: base64 App Store distribution profiles for the exact three permanent IDs. The Watch profile must grant HealthKit and the permanent App Group; the widget profile must grant that group.
- `TENNIS_ASC_PRIVATE_KEY`: App Store Connect API private key text; `TENNIS_ASC_KEY_ID` and `TENNIS_ASC_ISSUER_ID`: the corresponding identifiers. Grant only the access needed for build upload, not account-wide administrative access merely for convenience.

The upload script uses an ephemeral keychain, filters signing secrets from child-process environments, cleans up its profiles/keychain, and does not publish signed packages, private keys or raw signing logs as public CI artifacts. It preserves build 32, validates the exported phone/Watch/widget signatures, asks Apple to validate the IPA, then uploads. It does not invite testers or submit an App Store release. This pipeline still requires a real native run before it can be considered verified.

## Privacy Policy

- The offline policy is available before setup and in iPhone Settings, About, Privacy Policy; on Watch it is in Menu, Privacy Policy.
- Publish only `docs/` to GitHub Pages and verify `https://sidneytambin-maker.github.io/court-story-ios/privacy.html` returns the current policy before saving that URL in App Store Connect's beta metadata.
- Keep the public policy and `TennisTrackerShared/TennisPrivacyPolicy.swift` consistent with actual storage, optional Health access, exports, deletion and TestFlight feedback handling.
- The policy does not replace physical migration, independent fresh-library checks or Apple's beta review.

References: [GitHub's macOS signing guidance](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications), [Apple build uploads](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

Reference: [Apple file sharing](https://developer.apple.com/documentation/bundleresources/information-property-list/uifilesharingenabled), [creating an App Store Connect record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/), [beta distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases), [provisioning profile checks](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles).
