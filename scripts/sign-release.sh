#!/bin/bash
set -euo pipefail
app="${1:?Usage: scripts/sign-release.sh /path/to/Clean.app}"
identity="${CLEAN_SIGN_IDENTITY:-Developer ID Application: ZHIPING XU (5N66S29EK2)}"
repo="$(cd "$(dirname "$0")/.." && pwd)"
sparkle="$app/Contents/Frameworks/Sparkle.framework"
# SPM embeds precompiled helpers. Sign each nested executable before its container.
for helper in XPCServices/Downloader.xpc XPCServices/Installer.xpc Autoupdate Updater.app; do
    codesign --force --sign "$identity" --options runtime --timestamp \
        --preserve-metadata=identifier,entitlements "$sparkle/Versions/Current/$helper"
done
codesign --force --sign "$identity" --options runtime --timestamp "$sparkle"
codesign --force --sign "$identity" --options runtime --timestamp \
    --entitlements "$repo/CleanMac/Clean.entitlements" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
