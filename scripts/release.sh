#!/bin/zsh
# Free release (no paid Apple Developer account): universal Release build, ad-hoc signed, zipped.
#
#   scripts/release.sh            → build/Glink.zip (+ SHA-256)
#
# Upload build/Glink.zip to a GitHub Release. People who download it open it once via
# System Settings → Privacy & Security → Open Anyway (see README).
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Glink/Resources/Info.plist)

echo "› Running tests…"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi
swift test >/dev/null
(cd Packages/MCPShieldCore && swift test >/dev/null)

echo "› Building Glink $VERSION (universal, Release, ad-hoc signed)…"
UNIVERSAL=1 scripts/build-app.sh

echo "› Zipping…"
rm -f build/Glink.zip
ditto -c -k --sequesterRsrc --keepParent build/Glink.app build/Glink.zip
shasum -a 256 build/Glink.zip | tee build/Glink.zip.sha256

echo "✓ build/Glink.zip ($(du -h build/Glink.zip | cut -f1))"
echo "  Publish: gh release create v$VERSION build/Glink.zip --title \"Glink $VERSION\" --notes-file CHANGELOG.md"
