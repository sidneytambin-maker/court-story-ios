# TestFlight Metadata

The App Store Connect record is registered as **Court Story**, using `com.inclusophy.tennistracker`. Build 33 addresses corrected training duration, Watch workout start, streamlined entry, dashboard hierarchy and separate tournament outcomes. Bundle identifiers and library storage remain unchanged.

Build 32 is the previous approved external beta. Build 33 must pass new native tests, visual review, archive and signed-IPA checks, independent clean-install privacy checks and Apple's processing/review before its availability is reported. The existing Owner Verification and Community Beta groups are retained. This is not an App Store release submission.

## Beta Description

Court Story is a tennis activity, match and training companion for iPhone and Apple Watch, designed around accessible, independent use.

Record singles and doubles matches, training sessions and tournaments. Save player profiles, regular doubles partners, multiple coaches, venues and reusable tennis details. Log completed match results or score a match live, including one-set and multi-set formats and tie-break results. Link matches to training and tournaments without entering the same details twice.

The personalised dashboard brings together results, training focus, upcoming tennis, goals and achievements. Accessible summaries accompany visual charts and progress displays. Notification reminders open the relevant activity or reflection area, and optional tennis sounds can be previewed and selected in Settings.

The Apple Watch companion supports quick access to upcoming activity, training tracking, recent records and live scoring. Edit, complete and delete supported records using visible controls and VoiceOver actions. Watch-face complications provide several tennis summaries and shortcuts. Your iPhone and its paired Watch exchange your tennis library; there is no shared community database.

Health integration is optional. When you explicitly enable a Health workout on Apple Watch and grant Apple's permissions, supported workout measurements can accompany your training record. You can use Court Story without Health access.

New testers start with an empty personal library and an accessible setup flow. This beta is intended to test accessibility, scoring, reliability, synchronisation, notifications, Health integration and general usability before a wider release.

## What to Test

Please use Court Story naturally on iPhone and Apple Watch. Test with VoiceOver, without VoiceOver, or both, according to your normal preferences.

- Correct a recorded training duration on either device. Verify the editor, Training list, Dashboard, weekly complication and shared summary agree after saving, reopening and synchronising. Original Health measurements remain unchanged and are identified separately.
- Start scheduled training from Watch Overview with Health workout saving already allowed. There should be a single Start Session action, without the routine with/without Health choice. The app must only report Health recording after it has started. Check live measurements and the saved Health workout on your physical Watch.
- If Health cannot start, confirm a clear retry or explicit Start Without Health choice. Cancelling must not create an active session. Check pause, interruption, ending and recovery without duplicate records or invented measurements.
- Tournament stage and final position: choose Round robin, a group stage or a placement play-off, separately choose a final position from 1st through 16th, and verify both survive editing and phone/Watch sync.
- Tournament VoiceOver actions: Mark Tournament Complete, then Mark Tournament Entered. Check the spoken confirmation, visible status and sync, without losing stage or final position.
- Basic mode: quick entry and a compact Dashboard, with optional details available when requested. Standard mode retains guided detail. Advanced professional metrics and coach-summary sharing belong to Power mode only.
- Power mode coach summary: choose included sections, inspect the preview and use the system share sheet. Nothing is sent automatically. Health measurements and personal names are not included in the default summary.
- Updating an existing installation: your records, saved people and venues, preferences and Watch connection remain available. Do not delete the app to change its name.
- First-time setup: your own profile, optional classification and handedness, match defaults, optional people and places, and skipping permissions.
- Empty first installation: no other person's records, coaches, venues, goals or workout information should appear.
- Saved players, regular doubles partners, coaches, venues and locations throughout every relevant picker.
- Training with multiple coaches and players, more than one focus, duration including seconds, completion, reflection, editing and deletion.
- Singles and doubles entry order, one-set and multi-set formats, tied games and tie-break result pickers.
- Match lists: populated status headings only, earliest date/time first regardless of entry order. Choose a match round in any mode; check spoken time and venue.
- Live scoring, undo, saving progress, resuming, and clearly ending an activity on Watch.
- Tournament dates, linked scheduled/completed match counts, and optional links to matches and training.
- Dashboard result categories, Monday-to-Sunday summaries, training focus, goals, achievements and direct links to relevant editors.
- Notifications that open the exact activity or reflection, and the five selectable tennis sounds without excessive playback or interference with speech.
- Watch Overview, Track, Live, Recent and Score, including the Menu button, VoiceOver actions, empty states and complications.
- Two-way sync, including edits made while the other device is temporarily unreachable. Reopen both apps to confirm the final result.
- Optional Health workouts, denied permissions, accurate measured summaries and no invented measurements.
- Text contrast, larger text, visual charts and all three themes, as well as VoiceOver labels, values, hints, focus and reading order.

For a bug report, include what you were trying to do, what happened, what you expected, iPhone or Watch, whether VoiceOver was enabled, and the version/build. Do not attach a private backup or other people's personal details to public feedback.

## Contact and Access

Use the verified Apple Developer account email for TestFlight feedback/contact fields only. It is intentionally not copied into this public source document. External availability requires Apple's beta review approval. Internal owner access does not imply that a build is approved for external testers.
