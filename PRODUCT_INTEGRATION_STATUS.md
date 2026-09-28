# Product integration acceptance status

Date: 5 September 2026. This is an engineering checkpoint, not a release approval.

## Physical devices

| Check | Verified state |
| --- | --- |
| iPhone works | Yes, existing build 20, per user report |
| Apple Watch installs | Yes, existing build 20, per user report |
| Apple Watch launches | Yes, existing build 20, per user report |
| New sprint installed | No |
| New sprint VoiceOver acceptance | Not yet tested |
| Known-good free deployment preserved | Yes, local tag, IPA and private manifest retained |

No package was installed over the working devices during this sprint. The
production profiles and established signing/installation scripts were not
modified. The Windows reference application was not modified.

## Source implementation

| Area | Implementation | Acceptance |
| --- | --- | --- |
| Today | Upcoming activities and attention, no recent history | Not physically tested |
| Track | Structured training, match and tournament setup | Not physically tested |
| Live | Active training/tournament and post-training feedback | Not physically tested |
| Recent | Completed activity and details handoff | Not physically tested |
| Score | Dedicated scorer, named teams, undo/save/hear/tie-break/finish | Not physically tested |
| Players and partners | Stable IDs, mini profiles, native selection | Not physically tested |
| Coaches | Separate lightweight records, optional player link | Not physically tested |
| Venues and locations | Reusable records and historical name preservation | Not physically tested |
| Tournaments | Templates separate from occurrences and date ranges | Not physically tested |
| Summaries | Shared singles/doubles/training/tournament formatting | New Swift tests not run |
| Sync | Queued stable-ID updates, revision/time reconciliation and receipt status | Physical two-way acceptance incomplete |
| Health training | Mockable coordinator and gated HealthKit client | Free probe profile authorized; workout not tested |
| Complication/Smart Stack | WidgetKit source and shared snapshot/deep links | Not provisioned, built or installed |
| Motion | User-labeled sample models only | No collection or classifier |
| Live Activities | Architecture documented | Deferred |

Watch page audit: Today answers what is next; Track opens activity setup; Live
contains non-score active activity controls; Recent contains completed history;
Score owns point scoring. Today may link to an active activity but does not
duplicate its point or finish controls. The Live completion summary is immediate
feedback, not a second history list.

## Checks actually run

- Eight Python deployment/streaming-protocol regression tests passed.
- Read-only preflight accepted both signed components in the known-good build 20
  IPA and confirmed unexpired profiles containing the required devices.
- The same preflight rejected an older broken IPA with a parent signed-slot-3
  content mismatch. That broken IPA was not installed.
- Local tree-sitter parsing found no Swift syntax errors. This is not a Swift
  compiler, an SDK availability check or a substitute for Xcode tests.
- A separate test App ID obtained a free HealthKit-authorized Watch profile from
  Apple. The registered Watch is included. The production App ID/profile was
  untouched. This is not proof of a saved or recorded Health workout.

The new Swift unit/UI tests have not run. No native Watch UI automation target
has yet been added. Source-level page/deep-link tests do not test watchOS focus.

## Cloud build gate

The configured GitHub repository is public. The security review rejected source
publication, and explicit user approval for uploading source/tests is pending.
No alternative upload route has been used. A cloud build and device deployment
cannot truthfully be claimed before that gate is resolved.

Keep the private checkpoint tag local. The development branch starts at the
previous remote source commit, excluding the later private device-report commit.
Review the exact outgoing file list before any authorized push.

## Remaining engineering work

- Compile all stages with Xcode and fix any type, SDK, project or UI-test errors.
- Add/run native Watch UI tests, in addition to shared model tests on iPhone.
- Complete notification/App Intent record-level routing acceptance; some existing
  routes select the relevant area and still require choosing a record.
- Exercise concurrent edits, app restarts and disconnected updates end to end.
  The existing wire dates have whole-second precision; equal-revision edits in
  the same second use the incoming-record tie rule. No deletion tombstone
  protocol has been added, so delete-versus-offline-edit conflicts need work.
- Complete Health workout recovery after process termination and interruption
  testing. A timeout can preserve tennis tracking, but a Health save that finishes
  after timeout may require later reconciliation with its workout identifier.
- Provision an App Group and separate widget App ID/profile, validate extension
  entitlements and implement/verify a three-component signing stage. The existing
  two-profile signer is not declared widget-ready.
- Verify actual metrics, Watch/iPhone data equality, WidgetKit refresh and stale
  content, and complication activation on a compatible physical Watch face.
- Check accessibility focus on the automatic match-winning point, every Picker,
  every Cancel/delete flow, headings, large text and VoiceOver swipe order.

Critical VoiceOver blockers cannot yet be ruled out. Physical acceptance is a
release blocker, not an optional follow-up.

## Physical acceptance matrix

All rows below are pending for the new candidate.

| Device/workflow | Required result |
| --- | --- |
| iPhone setup | Add/edit/delete player, partner, coach, venue and template; Name only required for mini profile |
| iPhone entry | One set default; exactly one set row; deciding set only when needed; correct doubles score |
| iPhone dates | Tournament start/end accessible; full date range; five-minute scheduling; duration hours/minutes |
| iPhone summaries | Current/next/recent/attention; all doubles names; coach and participants; missing score explicit |
| Watch navigation | Five distinct pages, accessible headings and no redundant primary rotor action |
| Watch scoring | Both teams, stable point focus, undo including transitions, exact save/resume and finish |
| Watch training | Saved pickers, Other/Needs Details, consent or decline, actual start/finish, available metrics only |
| Phone to Watch | Start/finish a phone-created training record using the original UUID |
| Watch to phone | New training arrives once with context, duration, workout ID and Needs Details state |
| Cross-device match | Score a phone-created doubles match on Watch; exact score and four names return to phone |
| Offline/restart | Changes survive either app restarting; no duplicates or older snapshot erasure |
| Health stage | Permission denied fallback, granted workout, clean finish, Health app workout and UUID linkage |
| Widget stage | Appears on face/Smart Stack; meaningful VoiceOver label; fresh/stale state; correct destination |

For each capability stage: build, preflight, back up, install, query installed
state, launch and perform VoiceOver/data acceptance. Stop at the first regression
and use the preserved known-good package. Never move the Watch app to PlugIns.
