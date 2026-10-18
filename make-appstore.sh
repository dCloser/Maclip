#!/bin/zsh
# Builds build/Maclip.pkg for uploading to the Mac App Store (with Transporter).
#
#   PROFILE=~/Downloads/Maclip_App_Store.provisionprofile BUILD_NUMBER=2 ./make-appstore.sh
#
# Needs, in your keychain: an "Apple Distribution" certificate and a "Mac Installer
# Distribution" certificate (named "3rd Party Mac Developer Installer: ..."), plus a Mac App
# Store provisioning profile for com.clipboard.Maclip. See README, "Mac App Store".
# Override the certificates with APP_IDENTITY / INSTALLER_IDENTITY if you have several.
set -euo pipefail
cd "${0:A:h}"

PROFILE="${PROFILE:-Support/Maclip_App_Store.provisionprofile}"
[[ -f "$PROFILE" ]] || { echo "error: provisioning profile not found: $PROFILE (set PROFILE=...)" >&2; exit 1; }

identity() {
  security find-identity -v ${2:-} 2>/dev/null | awk -F'"' -v p="$1" 'index($2, p) == 1 {print $2; exit}'
}
APP_IDENTITY="${APP_IDENTITY:-$(identity "Apple Distribution:" "-p codesigning")}"
[[ -z "$APP_IDENTITY" ]] && APP_IDENTITY="$(identity "3rd Party Mac Developer Application:" "-p codesigning")"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-$(identity "3rd Party Mac Developer Installer:")}"
[[ -n "$APP_IDENTITY" ]] || { echo "error: no Apple Distribution certificate in your keychain" >&2; exit 1; }
[[ -n "$INSTALLER_IDENTITY" ]] || { echo "error: no Mac Installer Distribution certificate in your keychain" >&2; exit 1; }

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Support/Info.plist)"
PROFILE_PLIST="$(mktemp)"
trap 'rm -f "$PROFILE_PLIST"' EXIT
security cms -D -i "$PROFILE" > "$PROFILE_PLIST"
TEAM_ID="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$PROFILE_PLIST")"
PROFILE_APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$PROFILE_PLIST")"
if [[ "$PROFILE_APP_ID" != "$TEAM_ID.$BUNDLE_ID" ]]; then
  echo "error: the profile is for $PROFILE_APP_ID, but the app is $TEAM_ID.$BUNDLE_ID" >&2
  exit 1
fi

# App Store builds need the app and team identifiers in their entitlements.
OUT="build/appstore"
mkdir -p "$OUT"
ENT="$OUT/Maclip-AppStore.entitlements"
cp Support/Maclip.entitlements "$ENT"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" "$ENT"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$ENT"

OUT_DIR="$OUT" SIGN_IDENTITY="$APP_IDENTITY" ENTITLEMENTS="$ENT" PROVISIONING_PROFILE="$PROFILE" ./build.sh

PKG="build/Maclip.pkg"
rm -f "$PKG"
productbuild --component "$OUT/Maclip.app" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"
pkgutil --check-signature "$PKG" | head -3

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$OUT/Maclip.app/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$OUT/Maclip.app/Contents/Info.plist")"
echo "Created $PWD/$PKG (version $VERSION, build $BUILD). Upload it with the Transporter app."
