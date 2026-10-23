#!/bin/zsh
# Builds Glink.app into ./build.
#
#   scripts/build-app.sh                 # release build, ad-hoc signed
#   UNIVERSAL=1 scripts/build-app.sh     # arm64 + x86_64
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build-app.sh
#
# Ad-hoc signed builds work locally, but macOS ties the Accessibility permission to the
# signature, so you'll need to re-grant it after each rebuild. A Developer ID identity avoids that.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "› Building (release)…"
swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

APP="$ROOT/build/Glink.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/Glink" "$APP/Contents/MacOS/Glink"
cp "$ROOT/Glink/Resources/Info.plist" "$APP/Contents/Info.plist"

# Resource bundles from dependencies (KeyboardShortcuts' localized strings).
for bundle in "$BIN_DIR"/*.bundle(N); do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

# Sparkle.framework (the executable's rpath points at Contents/Frameworks).
mkdir -p "$APP/Contents/Frameworks"
SPARKLE_FW="$(find "$BIN_DIR" "$ROOT/.build/artifacts/sparkle" -name Sparkle.framework -type d -maxdepth 6 2>/dev/null | grep -v "ios\|tvos\|watchos\|xros" | head -1)"
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"

# Icon (regenerate with: swift scripts/make-icon.swift /tmp/AppIcon.iconset && iconutil -c icns …)
cp "$ROOT/Glink/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "› Signing…"
# Sign inside-out: Sparkle's helpers, the framework, then the app (Sparkle's recommended order).
IDENTITY="${SIGN_IDENTITY:--}"
SIGN_FLAGS=(--force -s "$IDENTITY")
[[ -n "${SIGN_IDENTITY:-}" ]] && SIGN_FLAGS+=(--options runtime --timestamp)
FW="$APP/Contents/Frameworks/Sparkle.framework"
for helper in "$FW"/Versions/B/XPCServices/*.xpc(N) "$FW/Versions/B/Autoupdate" "$FW/Versions/B/Updater.app"; do
  [[ -e "$helper" ]] && codesign "${SIGN_FLAGS[@]}" "$helper"
done
codesign "${SIGN_FLAGS[@]}" "$FW"
codesign "${SIGN_FLAGS[@]}" --entitlements "$ROOT/scripts/Glink.entitlements" "$APP"
codesign --verify --deep --strict "$APP"

echo "✓ Built $APP"
