#!/bin/zsh
# Builds Maclip.app into ./build (sandboxed, with its icon).
#
#   ./build.sh            release build, ad-hoc signed (fine for running on this Mac)
#   SIGN_IDENTITY="Developer ID Application: ..." ./build.sh
#                         sign with a real certificate instead, which keeps the
#                         Accessibility permission valid across rebuilds. Gatekeeper kills
#                         (and may trash) an app signed with a revoked certificate, so the
#                         script checks for that.
#   OUT_DIR=dir ENTITLEMENTS=path PROVISIONING_PROFILE=path BUILD_NUMBER=n ./build.sh
#                         another output folder, other entitlements, an embedded provisioning
#                         profile and a build number override (make-appstore.sh uses these).
set -euo pipefail
cd "${0:A:h}"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Maclip"

OUT_DIR="${OUT_DIR:-build}"
APP="$OUT_DIR/Maclip.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Maclip"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/container-migration.plist "$APP/Contents/Resources/"
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
if [[ -n "${PROVISIONING_PROFILE:-}" ]]; then
  cp "$PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
fi

# Compile the icon: produces Assets.car and AppIcon.icns in Resources.
xcrun actool Support/Assets.xcassets --compile "$APP/Contents/Resources" \
  --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
  --output-partial-info-plist "$OUT_DIR/actool-info.plist" --errors --warnings >/dev/null

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY" --options runtime
            --entitlements "${ENTITLEMENTS:-Support/Maclip.entitlements}")
# Notarization requires a secure timestamp; only Developer ID builds get notarized.
if [[ "$SIGN_IDENTITY" == Developer\ ID\ Application* ]]; then SIGN_FLAGS+=(--timestamp); fi
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --strict "$APP"
if [[ "$SIGN_IDENTITY" != "-" ]] && spctl --assess --type execute "$APP" 2>&1 | grep -q REVOKED; then
  echo "error: the certificate '$SIGN_IDENTITY' is revoked; macOS will refuse to run this app." >&2
  echo "Rebuild without SIGN_IDENTITY (ad-hoc) or with a valid certificate." >&2
  rm -rf "$APP"
  exit 1
fi

echo "Built $PWD/$APP (signed with: $SIGN_IDENTITY)"
echo "Run it with:  open \"$PWD/$APP\""
