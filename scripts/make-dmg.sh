#!/bin/zsh
# Packages build/Glink.app into a signed, notarized DMG and writes the Sparkle appcast.
#
# Requires an Apple Developer Program membership:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE="glink-notary"   # created once with:
#     xcrun notarytool store-credentials glink-notary --apple-id you@example.com --team-id TEAMID
#
#   SIGN_IDENTITY=… NOTARY_PROFILE=… scripts/make-dmg.sh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

UNIVERSAL=1 SIGN_IDENTITY="$SIGN_IDENTITY" scripts/build-app.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Glink/Resources/Info.plist)
DMG="$ROOT/build/Glink-$VERSION.dmg"
STAGING="$ROOT/build/dmg"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R build/Glink.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "› Creating DMG…"
hdiutil create -volname "Glink" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp -s "$SIGN_IDENTITY" "$DMG"

echo "› Notarizing (this can take a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

rm -rf "$STAGING"

# Sparkle appcast. generate_appcast signs the DMG with the EdDSA key in your login Keychain
# (created with: .build/artifacts/sparkle/Sparkle/bin/generate_keys --account glink).
echo "› Generating appcast…"
RELEASES="$ROOT/build/releases"
mkdir -p "$RELEASES"
cp "$DMG" "$RELEASES/"
"$ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" --account glink \
  --download-url-prefix "https://github.com/SaiPranav13188/Glink/releases/download/v$VERSION/" \
  "$RELEASES"

echo "✓ $DMG"
echo "✓ $RELEASES/appcast.xml"
echo
echo "Publish (uploads to GitHub; the feed URL in Info.plist reads the latest release's appcast.xml):"
echo "  gh release create v$VERSION \"$DMG\" \"$RELEASES/appcast.xml\" --repo SaiPranav13188/Glink --title \"Glink $VERSION\""
echo
echo "Before the next release, bump CFBundleShortVersionString and CFBundleVersion in Glink/Resources/Info.plist."
