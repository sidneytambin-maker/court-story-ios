# Court Story App Icon

Build 32 replaces the previous TT artwork with a CS tennis-ball monogram, using the built-in image-generation tool. The icon remains bright tennis yellow with a high-contrast deep-green tennis emblem. CS is visual artwork only: CFBundleDisplayName and CFBundleName are Court Story in full on iPhone, Apple Watch and the complication extension. Home Screen VoiceOver uses the full system app name, not letters inside the bitmap.

The source is CourtStoryIcon-source.png. The shipped iPhone and Watch PNGs are matching, opaque, 1024 by 1024, 8-bit RGB files. Apple's asset catalogues supply the native masks and renditions; no rounded-square or circular mask is baked in. The privacy website uses the same approved artwork. AppIcon-identity.json pins the reviewed bitmap hash so the old TT artwork cannot silently return.

The historical TennisTrackerIcon-source.png is retained only as an unshipped source reference. It is not in either app's asset catalogue or the public website.

## Generation Prompt

Edit the original icon: replace the central TT lettering with exactly CS, in bold slightly italic sports lettering. Preserve the bright electric tennis-yellow and near-black forest-green palette, tennis-ball seams and clean square composition. Keep essential artwork centred for the Watch's circular mask. No other words, third-party logos, watermark, frame, shadows or applied device mask. Deliver opaque square PNG artwork for Court Story on iPhone and Apple Watch.

The generated bitmap was normalized to 1024-square RGB for Apple's single-size asset workflow. Source and compiled-icon checks cover both apps. Full-name release checks reject CS or the retired app name as a system display name.

## Apple Guidance

- https://developer.apple.com/design/human-interface-guidelines/app-icons
- https://developer.apple.com/documentation/xcode/configuring-your-app-icon
