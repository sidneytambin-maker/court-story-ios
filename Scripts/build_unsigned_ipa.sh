#!/bin/bash
set -euo pipefail

xcodebuild clean build \
  -project "TennisTrackeriOS.xcodeproj" \
  -scheme "TennisTracker" \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""

xcodebuild build \
  -project "TennisTrackeriOS.xcodeproj" \
  -target "TennisTrackerWatchApp" \
  -sdk watchos \
  -destination "generic/platform=watchOS" \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""

mkdir -p artifacts/Payload
APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/Build/Products/Release-iphoneos/TennisTracker.app" -type d | head -n 1)"
BUILT_WATCH_APP_PATH="$(find build "$HOME/Library/Developer/Xcode/DerivedData" -path "*/Release-watchos/TennisTrackerWatchApp.app" -type d 2>/dev/null | head -n 1)"

if [ -z "$APP_PATH" ]; then
  echo "Could not find the unsigned Tennis Tracker.app build output." >&2
  exit 1
fi

if [ -z "$BUILT_WATCH_APP_PATH" ]; then
  echo "Could not find the unsigned TennisTrackerWatchApp.app build output." >&2
  exit 1
fi

rm -rf "$APP_PATH/Watch" "$APP_PATH/PlugIns"
mkdir -p "$APP_PATH/Watch"
cp -R "$BUILT_WATCH_APP_PATH" "$APP_PATH/Watch/"

rm -rf artifacts/Payload/* artifacts/WatchKitSupport
cp -R "$APP_PATH" artifacts/Payload/

IPHONEOS_PLATFORM_PATH="$(xcrun --sdk iphoneos --show-sdk-platform-path)"
IPHONEOS_SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
WATCHKIT_SUPPORT_PATH=""
for candidate in \
  "$IPHONEOS_PLATFORM_PATH/Developer/Library/WatchKitSupport/WK" \
  "$IPHONEOS_SDK_PATH/Library/Application Support/WatchKit/WK"
do
  if [ -f "$candidate" ]; then
    WATCHKIT_SUPPORT_PATH="$candidate"
    break
  fi
done

if [ -n "$WATCHKIT_SUPPORT_PATH" ]; then
  mkdir -p artifacts/WatchKitSupport
  cp "$WATCHKIT_SUPPORT_PATH" artifacts/WatchKitSupport/WK
  echo "Embedded Xcode WatchKitSupport/WK into IPA artifact."
else
  DEVELOPER_PATH="$(xcode-select -p)"
  WATCHKIT_SUPPORT_PATH="$(find "$DEVELOPER_PATH" -path "*/WatchKitSupport/WK" -type f 2>/dev/null | head -n 1)"
  if [ -n "$WATCHKIT_SUPPORT_PATH" ]; then
    mkdir -p artifacts/WatchKitSupport
    cp "$WATCHKIT_SUPPORT_PATH" artifacts/WatchKitSupport/WK
    echo "Embedded Xcode WatchKitSupport/WK into IPA artifact from discovered Xcode path."
  else
    echo "Xcode WatchKitSupport/WK was not found in active Xcode." >&2
    echo "Checked:" >&2
    echo "- $IPHONEOS_PLATFORM_PATH/Developer/Library/WatchKitSupport/WK" >&2
    echo "- $IPHONEOS_SDK_PATH/Library/Application Support/WatchKit/WK" >&2
    echo "- any */WatchKitSupport/WK file under $DEVELOPER_PATH" >&2
    echo "Continuing because current Xcode runners no longer include this support payload." >&2
  fi
fi

WATCH_APP_PATH="artifacts/Payload/TennisTracker.app/Watch/TennisTrackerWatchApp.app"
if [ ! -d "$WATCH_APP_PATH" ]; then
  echo "Apple Watch companion app was not embedded at Payload/TennisTracker.app/Watch/TennisTrackerWatchApp.app." >&2
  echo "Found embedded app folders:" >&2
  find artifacts/Payload/TennisTracker.app -maxdepth 3 -type d \( -name "*.app" -o -name "Watch" -o -name "PlugIns" \) -print >&2
  exit 1
fi

(
  cd artifacts
  if [ -d WatchKitSupport ]; then
    /usr/bin/zip -qry TennisTracker-unsigned.ipa Payload WatchKitSupport
  else
    /usr/bin/zip -qry TennisTracker-unsigned.ipa Payload
  fi
)

cat > artifacts/build-summary.txt <<SUMMARY
Build artifact: TennisTracker-unsigned.ipa
Signing status: unsigned
Watch deployment status: Watch bundle compiled - physical signing not yet verified.
Intended next step: download on Windows, produce a signed package, then verify BOTH the iPhone app and embedded Watch app signatures/provisioning before installing.
Bundle identifier: com.inclusophy.tennistracker.dev
Embedded Watch app: Payload/TennisTracker.app/Watch/TennisTrackerWatchApp.app
SUMMARY
