#!/bin/zsh
# Packages build/Maclip.app into build/Maclip.dmg, a disk image with
# the app and a shortcut to /Applications so it can be installed by dragging.
#
#   ./make-dmg.sh                 package the existing build (runs ./build.sh only if there is none)
#   REBUILD=1 ./make-dmg.sh       rebuild the app first
#   SIGN_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE=notary ./make-dmg.sh
#                                 rebuild, sign app and DMG with your Developer ID, notarize
#                                 with Apple and staple the ticket, so it opens on other Macs
#                                 without Gatekeeper warnings (see README, "Sharing the app").
set -euo pipefail
cd "${0:A:h}"

APP="build/Maclip.app"
DMG="build/Maclip.dmg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)"

if [[ -n "${REBUILD:-}" || -n "${SIGN_IDENTITY:-}" || ! -d "$APP" ]]; then
  ./build.sh
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -quiet -volname "Maclip $VERSION" -srcfolder "$STAGING" \
  -fs HFS+ -format UDZO -ov "$DMG"

if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  if [[ -z "${SIGN_IDENTITY:-}" || "$SIGN_IDENTITY" != Developer\ ID\ Application* ]]; then
    echo "error: notarization needs SIGN_IDENTITY=\"Developer ID Application: ...\"" >&2
    exit 1
  fi
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

hdiutil verify -quiet "$DMG"
echo "Created $PWD/$DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
