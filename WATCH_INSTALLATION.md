# Verified free Watch installation

## Current known-good checkpoint

The user subsequently confirmed physical installation and launch of build 20.
The local tag `watch-physical-launch-working` points to `1aa386e`. Preserve
`builds/TennisTracker-development-signed-build20-33925361373.ipa` and its matching
unsigned artifact. The private checkpoint records the IPA hash, exact Info.plist
values, both entitlements/profiles, device registrations and signing-script
hashes. Do not upload that private manifest or its historical device report.

As checked on 5 September 2026, the current iPhone and Watch profiles expire on
11 September 2026. Refresh legitimately before expiry; do not edit profile bytes.
Keep the same registered devices and bundle identifiers. Never revoke a working
certificate as a speculative troubleshooting step.

New builds 21 (core), 22 (Health) and 23 (widgets) are staged source candidates,
not physically accepted replacements. The original working package and profiles
have not been modified. See `PRODUCT_INTEGRATION_STATUS.md`.

On 4 September 2026, Watch build 19 was installed successfully through
`com.apple.streaming_zip_conduit` using `PackageType=Developer` and
`AllowInstallLocalProvisioned=true`. The service reported `InstallComplete` at
100% and `DataComplete`. A subsequent Watch application query reported the app
present and `ProfileValidated=true`. Device logs confirmed a successful foreground
launch and VoiceOver navigation of Tennis Tracker's screens.

## Diagnosed cause

The normal iPhone-to-Watch installation path left a placeholder. The Watch log
reported `MIInstallerErrorDomain Code=111`: the app used a free provisioning
profile, but installation from that source was not allowed. The direct developer
streaming route accepted that same Watch app and profile.

Do not move the companion into `PlugIns`. Keep
`Payload/TennisTracker.app/Watch/TennisTrackerWatchApp.app`.
Keep `WKApplication` for this single-target Watch app, without `WKWatchKitApp`.

The accepted Watch profile lists the iOS platform family. Requiring a literal
`watchOS` entry incorrectly rejected this profile locally; physical installation
and launch confirmed acceptance. Never edit the Apple-signed profile itself.

## Repeatable update

1. Build the unsigned IPA using the existing GitHub workflow.
2. Use `Scripts/sign_nested_watch_ipa.ps1` with the existing iPhone and Watch
   profiles. It requires a zsign release with multiple-profile support (tested
   with 1.1.2), signs the Watch before its parent, and checks executable pages,
   XML/DER entitlement hashes, Info.plist, and CodeResources.
   Run `Scripts/deployment_preflight.py` against the known-good signed build 20
   before either installation. Inspect the actual IPA, not only build settings.
   Keep a current backup of application data and the known-good IPA available.
3. Install the signed iPhone IPA through the existing developer installation
   tool. Preserve its bundle identifier and data.
4. Install the embedded companion directly using the command below. A paired
   iPhone must be USB-connected and the Watch available. Developer Mode must be
   enabled on the Watch.

```powershell
python Scripts/watch_developer_install.py install --repo . --ipa <signed-ipa-path>
python Scripts/watch_developer_install.py status --repo .
```

The installer reads the already-created private Watch metadata from
`work/signing-assets/watch/bundle.json`. It does not log passwords or device IDs.
It uses the open-source go-ios zipconduit protocol with developer installation
options, preserving all bytes of the signed Watch bundle.

Sideloadly supplied the established free iPhone account/setup workflow. Its Done
status is not evidence that the Watch is installed or correctly signed. Do not
run another transformation over a validated nested package: any re-signing must
be followed by another full IPA preflight. Developer trust on iPhone and
Developer Mode on Watch are prerequisites, not replacements for device-specific
provisioning or the accepted direct developer installation route.

For profile refresh, reuse the cached legitimate developer session and existing
App IDs/devices/certificate where valid. Renew iPhone and Watch profiles
separately, confirm the relevant physical UDID appears in each signed profile,
then sign Watch before parent without subsequent nested file edits. Authentication
or physical trust interactions may require the user; do not expose credentials.

Health and widgets must not silently extend the working two-profile process.
Health requires both a profile grant and signed HealthKit entitlement. Widgets
add an independently provisioned extension and an authorized shared App Group.
The current widget configuration is compile-only preparation: its three-component
signing/install stage remains incomplete. Advance one physical capability at a
time, confirming the Watch still launches after each stage.

`verify_macho_seals.py` checks signed content integrity; it does not replace
Apple's certificate trust or device authorization checks. Installation success,
an installed-app query, launch, and real activity sync are separate checks.
An iPhone install or visible Watch icon is never evidence that all four passed.

## Prevented signing regression

The earlier Watch-last script refreshed the parent's CodeResources after signing.
That invalidated the parent's signed slot 3. Multiple-profile signing fixes the
ordering without any post-signature edits. The verifier rejects that old IPA and
accepts both signatures produced by the corrected script.

## Sync status

WatchConnectivity reachability means availability for live messages. It can be
false while the Watch app sleeps. Application context is queued for background
delivery after session activation. It is not a receipt or proof that records
have arrived. Confirm the actual Watch records and a Watch-created record on the
iPhone before claiming two-way sync is physically verified.

References:

- https://developer.apple.com/documentation/watchconnectivity/wcsession/isreachable
- https://developer.apple.com/documentation/watchconnectivity/wcsession/updateapplicationcontext(_:)
- https://developer.apple.com/documentation/xcode/using-the-latest-code-signature-format
- https://github.com/danielpaulus/go-ios/tree/main/ios/zipconduit
