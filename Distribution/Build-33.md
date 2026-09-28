# Court Story Build 33

## Scope

- One effective training duration across persisted records, phone/Watch reconciliation, summaries, statistics and complications. Explicit corrections take precedence over the original recording without changing Health measurements.
- Single scheduled-session start with confirmed Health lifecycle state, clear errors and explicit fallback. Read authorization is never inferred from HealthKit write authorization or missing samples.
- Compact, consistent dashboards, progressive optional entry details, normal semantic text sizes and preserved user-selected Dynamic Type.
- Advanced metrics and an optional preview-before-sharing coach summary restricted to Power mode.
- Separate tournament stage reached and optional finishing position 1st to 16th. Additional round-robin, group and placement play-off stages.
- State-dependent tournament completion actions, spoken confirmation and matching visible status on iPhone and Watch.
- Tournament lists hide empty status sections; match and tournament status text keeps strong contrast on the bright tennis background.
- Tournament summaries count linked scheduled, in-progress and completed matches separately; results describe completed matches only.
- Watch all-time match results use the full compact result history rather than the limited editable cache, preserving achievement rules and linked-practice deduplication.
- Watch recent focus summaries retain all recorded sessions in the displayed 30-day window, including sessions whose actual start differs from their scheduled date.
- Preserve native button and navigation behaviour on expandable details, match lists, tournament lists and Watch scoring choices while retaining concise summaries and custom actions.
- Status-based match lists with no empty headings, chronological date/time ordering independent of entry order, accessible match-round choices in every mode, and date/time/place in match summaries.

## Acceptance

Native unit, iPhone interface and Watch interface tests are required at the exact release revision. Inspect screenshots at normal and accessibility text sizes. Release containers must remain empty and distinct, and unsigned resources must pass the additional private-identifier audit locally. The final App Store export must preserve the existing phone, Watch and complication identities, profiles, HealthKit capability and native bundle layout.

Simulator tests do not establish real sensor acquisition, physical VoiceOver focus, paired-device delivery, haptics or Apple Health saving. These remain explicit physical acceptance checks for testers.

## Release Status

In development. Build 32 remains the last verified externally available beta until build 33 completes native validation, signing, upload, group assignment and Apple's actual approval.

The public build source is a clean, privacy-reviewed snapshot in `sidneytambin-maker/court-story-ios`. Previous development history is preserved privately rather than copied into the public repository. This changes neither the app's permanent identities nor its users' libraries.

## Technical References

- [Apple: Authorizing access to Health data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)
- [Apple: Building a workout app for Apple Watch](https://developer.apple.com/documentation/healthkit/building-a-workout-app-for-apple-watch)
- [Apple: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Apple: Accessibility child behaviour](https://developer.apple.com/documentation/swiftui/accessibilitychildbehavior/ignore)
- [GitHub: Standard hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
