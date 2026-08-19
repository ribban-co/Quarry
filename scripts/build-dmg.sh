#!/usr/bin/env bash
#
# Build, sign, notarize and package Quarry as a distributable DMG.
#
# Usage:
#   scripts/build-dmg.sh                 # full pipeline (archive -> sign -> notarize -> dmg)
#   scripts/build-dmg.sh --skip-notarize # signed but un-notarized (recipients must right-click -> Open)
#   scripts/build-dmg.sh --version 0.1.0 --build 1
#
# One-time setup:
#   1. App Store Connect -> Users and Access -> Integrations -> App Store Connect API
#      Create a key with the "Developer" role, download the .p8 (one chance only).
#   2. Store it for notarytool:
#        xcrun notarytool store-credentials "quarry-notary" \
#          --key ~/private/AuthKey_XXXXXXXX.p8 --key-id XXXXXXXX --issuer <issuer-uuid>
#   3. Point this script at that profile with NOTARY_PROFILE, or accept the default below.
#
# Output: dist/Quarry-<version>.dmg  (signed, notarized, stapled)

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="Quarry"
SCHEME="Collection"
CONFIGURATION="Release"
TEAM_ID="6ECNB95892"
SIGN_IDENTITY="Developer ID Application: RIBBAN AB ($TEAM_ID)"
NOTARY_PROFILE="${NOTARY_PROFILE:-quarry-notary}"
VERSION_CONFIG="quarry/version.xcconfig"
EXPORT_OPTIONS="scripts/ExportOptions-developer-id.plist"
DIST_DIR="dist"

SKIP_NOTARIZE=false
VERSION_OVERRIDE=""
BUILD_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-notarize) SKIP_NOTARIZE=true; shift ;;
        --version) VERSION_OVERRIDE="$2"; shift 2 ;;
        --build) BUILD_OVERRIDE="$2"; shift 2 ;;
        -h|--help) sed -n '/^# Usage:/,/^# Output:/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    ok %s\n' "$1"; }
die()  { printf '    x  %s\n' "$1" >&2; exit 1; }

read_xcconfig() { grep "^$1" "$VERSION_CONFIG" | sed -E 's/^[A-Z_]+ *= *//' | tr -d ' '; }

# ---------------------------------------------------------------- preflight

step "Preflight"

security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY" \
    || die "signing identity not in keychain: $SIGN_IDENTITY"
ok "signing identity: $SIGN_IDENTITY"

[[ -f "$EXPORT_OPTIONS" ]] || die "missing $EXPORT_OPTIONS"

BUNDLE_ID="$(read_xcconfig PRODUCT_BUNDLE_IDENTIFIER)"
[[ -n "$BUNDLE_ID" ]] || die "could not read PRODUCT_BUNDLE_IDENTIFIER"
ok "bundle id: $BUNDLE_ID"

if [[ -n "$VERSION_OVERRIDE" ]]; then
    /usr/bin/sed -i '' -E "s|^MARKETING_VERSION *=.*|MARKETING_VERSION = $VERSION_OVERRIDE|" "$VERSION_CONFIG"
fi
if [[ -n "$BUILD_OVERRIDE" ]]; then
    /usr/bin/sed -i '' -E "s|^CURRENT_PROJECT_VERSION *=.*|CURRENT_PROJECT_VERSION = $BUILD_OVERRIDE|" "$VERSION_CONFIG"
fi

VERSION="$(read_xcconfig MARKETING_VERSION)"
BUILD="$(read_xcconfig CURRENT_PROJECT_VERSION)"
ok "version: $VERSION ($BUILD)"

if ! $SKIP_NOTARIZE; then
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || die "notarytool profile '$NOTARY_PROFILE' not found or invalid — see setup notes at the top of this script, or pass --skip-notarize"
    ok "notarytool profile: $NOTARY_PROFILE"
fi

# ---------------------------------------------------------------- archive

ARCHIVE_PATH="$DIST_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$DIST_DIR/export"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

step "Archiving $APP_NAME $VERSION ($BUILD)"
xcodebuild archive \
    -project Quarry.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates
[[ -d "$ARCHIVE_PATH" ]] || die "archive failed"
ok "archived: $ARCHIVE_PATH"

# ---------------------------------------------------------------- export + re-sign with Developer ID

step "Exporting with Developer ID"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_PATH" \
    -allowProvisioningUpdates
[[ -d "$APP_PATH" ]] || die "export produced no $APP_NAME.app"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
AUTHORITY="$(codesign -dvv "$APP_PATH" 2>&1 | grep '^Authority=' | head -1 | cut -d= -f2-)"
[[ "$AUTHORITY" == "$SIGN_IDENTITY" ]] || die "app signed by unexpected authority: $AUTHORITY"
ok "signed by: $AUTHORITY"
codesign -d --entitlements - --xml "$APP_PATH" >/dev/null 2>&1 && ok "entitlements intact"

# ---------------------------------------------------------------- notarize the app

if ! $SKIP_NOTARIZE; then
    step "Notarizing $APP_NAME.app"
    ZIP_PATH="$DIST_DIR/$APP_NAME-notarize.zip"
    /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    rm -f "$ZIP_PATH"
    xcrun stapler staple "$APP_PATH"
    ok "notarized and stapled"
fi

# ---------------------------------------------------------------- dmg

step "Building DMG"
STAGE="$(mktemp -d)"
/usr/bin/ditto "$APP_PATH" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "$DMG_PATH" >/dev/null
rm -rf "$STAGE"
ok "created: $DMG_PATH"

step "Signing DMG"
codesign --sign "$SIGN_IDENTITY" --timestamp --force "$DMG_PATH"
ok "signed"

if ! $SKIP_NOTARIZE; then
    step "Notarizing DMG"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    ok "notarized and stapled"
fi

# ---------------------------------------------------------------- verify

step "Verification"
xcrun stapler validate "$DMG_PATH" 2>&1 | tail -1 || true
spctl --assess --type open --context context:primary-signature -vv "$DMG_PATH" 2>&1 | sed 's/^/    /' || true
spctl --assess --type execute -vv "$APP_PATH" 2>&1 | sed 's/^/    /' || true

printf '\n\033[1m%s %s (%s) ready\033[0m\n' "$APP_NAME" "$VERSION" "$BUILD"
printf '  DMG: %s (%s)\n' "$DMG_PATH" "$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')"
if $SKIP_NOTARIZE; then
    printf '  Not notarized — recipients must right-click the app and choose Open.\n'
else
    printf '  Signed by RIBBAN AB, notarized and stapled. Opens cleanly on any Mac.\n'
fi
