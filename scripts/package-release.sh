#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
APP_PATH="$PROJECT_ROOT/dist/RestFlow.app"
codesign --verify --deep --strict "$APP_PATH"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
ARCH=$(uname -m)
ARCHIVE="RestFlow-$VERSION-$ARCH.app.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$PROJECT_ROOT/dist/$ARCHIVE"
cd "$PROJECT_ROOT/dist"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
echo "$PROJECT_ROOT/dist/$ARCHIVE"
