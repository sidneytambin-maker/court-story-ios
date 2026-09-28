# Court Story for iPhone and Apple Watch

Native SwiftUI Court Story, developed on Windows and built with the existing
free GitHub Actions macOS workflow. The Windows TennisTracker application is a
read-only functional reference. Never modify it as part of this project.

## Verified deployment baseline

The user confirmed that build 20 installs and launches on the physical Apple
Watch. The iPhone build also works. Preserve this achievement independently of
new product work.

- Local known-good tag: `watch-physical-launch-working`, commit `1aa386e`.
- Known-good signed artifact: `builds/TennisTracker-development-signed-build20-33925361373.ipa`.
- Watch location: `Payload/TennisTracker.app/Watch/TennisTrackerWatchApp.app`.
- Single-target Watch metadata: `WKApplication=true`, no `WKWatchKitApp`.
- Separate free iPhone and Watch profiles, including the correct physical devices.
- Watch-first, parent-last signing with zsign 1.1.2 multiple-profile support.
- Direct Watch developer installation over the established streaming connection.

See [WATCH_INSTALLATION.md](WATCH_INSTALLATION.md) for the repeatable installation,
refresh, verification and regression-recovery process. Icon visibility, an
iPhone installation, compilation and physical Watch launch are different checks.

The local checkpoint also has a private deployment manifest with exact bundle
identifiers, entitlements, profiles, device registration and signing-script
hashes. It and the known-good tag's private historical report must stay local.
Do not publish certificates, passwords, Apple session data, device identifiers,
personal tennis records, provisioning profiles, IPAs or private reports.

## Product integration candidate

The `codex/product-integration` branch contains source changes, not a new
physically accepted release. Stage one was committed as `1c66b63`; subsequent
local refinements and capability preparation build on it.

Implemented in source:

- Reusable player mini profiles, regular doubles partners, coaches, venues,
  locations and tournament templates with stable IDs.
- Tennis Setup management on iPhone; the same records populate Watch pickers.
- B1, B2, B3, B4, B5, Sighted and Not known classification labels.
- Per-player default match format and automatic one-set/deciding-set result rows.
- Native pickers for finite choices, five-minute scheduling and hours/minutes
  training duration.
- Shared singles, doubles, training and tournament summaries; all four doubles
  players remain explicit and tournaments retain their full date range.
- Five Watch destinations: Today, Track, Live, Recent and Score.
- Actual training start/finish times, practice results separate from competitive
  matches, saved scoring progress, undo history and secondary custom actions.
- Queued Watch changes retained until acknowledged by the phone; shared
  revision/time reconciliation and protection for active records.
- Accurate distinction between pairing, installation, live reachability, queued
  delivery and confirmed receipt.

These changes still require Xcode compilation, Swift unit/UI tests, physical
VoiceOver acceptance and cross-device tests. They are not described as working
on the physical devices until that evidence exists.

## Capability stages

| Stage | Configuration | Build | Release gate |
| --- | --- | --- | --- |
| Core | `project.yml` | 21 | Existing profiles, package preflight, install and launch |
| Health | `project-health.yml` | 22 | Authorized Health profile, user consent, actual workout tests |
| Widgets | `project-widgets.yml` | 23 | Authorized App Group and extension profile, nested signing and physical complication tests |

Automatic pushes build Core only. The cloud workflow's manual `stage` input
selects Core, Health or Widgets for compilation; it never installs a device.
Never advance physical deployment to the next stage before the previous one
passes launch and acceptance testing.

Health has a shared mockable coordinator, a Watch HealthKit tennis-workout
client, contextual opt-in, permission-denied fallback, actual metrics only and
clean finish/error handling. A separate free test App ID obtained an Apple-issued
HealthKit profile that includes the registered Watch. Production profiles were
not altered. This proves provisioning, not workout execution or Health saving.

The WidgetKit candidate supports accessory complications/Smart Stack presentation,
shared snapshot data, stale-state wording and destination-specific links.
Its App Group setting is a compile-only placeholder, not a provisioned group.
A production App Group, extension profile and validated three-component signing
stage are still required. Do not use the two-profile signer as though that
extension were already supported.

Live Activities are deferred until the core, Health and complication deployment
stages are accepted. Their proposed data source is the same stable match or
training ID, with an ActivityKit view derived from shared summary state. Start,
update and end follow the source activity; no second match database is needed.
No Live Activity extension or entitlement has been added.

Experimental motion support is limited to timestamped sample and user-labeled
session models. No sensor collection, stroke detection, classifier or accuracy
claim is implemented.

## Build and verification

The existing remote is a **public** GitHub repository:
`https://github.com/sidneytambin-maker/tennis-tracker-ios`.

Public source upload was stopped pending explicit user approval. No new sprint
build or physical installation has occurred. Do not bypass that publication
approval using another upload mechanism.

After authorized source publication, use the existing workflow. Tests are
release-blocking; do not ignore failed tests or install a merely syntax-checked
candidate.

Local checks:

```powershell
python -m unittest discover -s Scripts -p 'test_*.py' -v
python Scripts/deployment_preflight.py --candidate <signed-ipa> --baseline <known-good-signed-ipa> --repo . --openssl <openssl-path>
```

The preflight preserves architecture and bundle identity, verifies signed
content, checks profile expiry/device authorization and rejects unapproved
capability additions. It does not replace Apple's device trust checks.

Before physical installation, back up application data and keep the known-good
IPA and profiles available. Never refresh profiles by modifying Apple's signed
profile bytes; use the established legitimate provisioning workflow.

## Acceptance tracking

See [PRODUCT_INTEGRATION_STATUS.md](PRODUCT_INTEGRATION_STATUS.md) for verified
checks, remaining engineering work and the physical acceptance matrix.
Accessibility is release-blocking. Native controls, labels and automated
accessibility audits do not by themselves prove independent VoiceOver use.

## Primary guidance

- [Apple SwiftUI accessibility](https://developer.apple.com/documentation/swiftui/view-accessibility)
- [Apple accessible SwiftUI guidance](https://developer.apple.com/videos/play/wwdc2021/10009/)
- [Apple WatchConnectivity reachability](https://developer.apple.com/documentation/watchconnectivity/wcsession/isreachable)
- [Apple workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions)
- [Apple watchOS capability support](https://developer.apple.com/help/account/reference/supported-capabilities-watchos/)
- [Apple WidgetKit complications](https://developer.apple.com/documentation/widgetkit/creating-accessory-widgets-and-watch-complications)
