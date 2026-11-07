#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
CONFIGURATION="${CONFIGURATION:-release}"
swift build -c "$CONFIGURATION" --product RestFlow
BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP_PATH="$PROJECT_ROOT/dist/RestFlow.app"
# Recreate generated output so repeated builds cannot retain old resources.
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$APP_PATH/Contents/Frameworks"
cp "$BIN_PATH/RestFlow" "$APP_PATH/Contents/MacOS/RestFlow"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
cp Resources/Lottie-LICENSE.txt LICENSE THIRD_PARTY_NOTICES.md "$APP_PATH/Contents/Resources/"

# SwiftPM links the official prebuilt framework; the app must carry its own copy.
LOTTIE_FRAMEWORK="$(find .build/artifacts -type d -path '*/macos-arm64_x86_64/Lottie.framework' -print -quit)"
if [[ -z "$LOTTIE_FRAMEWORK" ]]; then
    echo "Could not locate the macOS Lottie framework." >&2
    exit 1
fi
ditto "$LOTTIE_FRAMEWORK" "$APP_PATH/Contents/Frameworks/Lottie.framework"

# The icon is drawn with AppKit, without requiring Xcode or external image tools.
swift scripts/make-icon.swift "$PROJECT_ROOT/dist/AppIcon.iconset"
iconutil -c icns dist/AppIcon.iconset -o "$APP_PATH/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP_PATH/Contents/Frameworks/Lottie.framework"
codesign --force --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
echo "Built: $APP_PATH"
