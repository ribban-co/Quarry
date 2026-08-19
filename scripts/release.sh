#!/usr/bin/env bash
#
# Release Quarry via Amore, then mirror the Amore appcast to Pluk's legacy
# Sparkle URLs so existing installs keep receiving updates.
#
# Usage:
#   scripts/release.sh stable
#   scripts/release.sh beta 42
#   scripts/release.sh alpha 1
#   scripts/release.sh rc 1
#   scripts/release.sh --version 0.1.0 --build 302 stable
#   scripts/release.sh --draft beta 42
#   scripts/release.sh --skip-github stable
#   scripts/release.sh --skip-r2 beta 42
#
# Source of truth:
#   - quarry/version.xcconfig -> MARKETING_VERSION, CURRENT_PROJECT_VERSION
#   - CHANGELOG.md          -> release notes, heading: ## [X.Y.Z] - YYYY-MM-DD
#
# Important:
#   - The Xcode scheme is Collection.
#   - Pluk's installed apps check https://r2.pluk.sh/appcast.xml and
#     https://r2.pluk.sh/appcast-prerelease.xml. Do not strand those URLs.
#   - The existing Sparkle private key in private/sparkle_ed_private_key must
#     match SUPublicEDKey in quarry/Info.plist and must be the key imported into
#     Amore for bundle id doc.pluk.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_CONFIG="$PROJECT_ROOT/quarry/version.xcconfig"
CHANGELOG="$PROJECT_ROOT/CHANGELOG.md"
INFO_PLIST="$PROJECT_ROOT/quarry/Info.plist"
SPARKLE_PRIVATE_KEY="$PROJECT_ROOT/private/sparkle_ed_private_key"
SPARKLE_PUBLIC_KEY_FILE="$PROJECT_ROOT/quarry/sparkle-public-ed-key.txt"
R2_CONFIG_FILE="$PROJECT_ROOT/private/r2-config"
SENTRY_CONFIG_FILE="$PROJECT_ROOT/private/sentry-config"

APP_NAME="Quarry"
BUNDLE_ID="doc.pluk"
SCHEME="Collection"
GITHUB_RELEASE_REPO="ribban-co/Quarry"
LEGACY_STABLE_APPCAST_URL="https://r2.pluk.sh/appcast.xml"
LEGACY_PRERELEASE_APPCAST_URL="https://r2.pluk.sh/appcast-prerelease.xml"
AMORE_APPCAST_URL="${AMORE_APPCAST_URL:-https://releases.pluk.sh/v1/apps/doc.pluk/appcast.xml}"

VERSION_OVERRIDE=""
BUILD_OVERRIDE=""
RELEASE_TYPE=""
PRERELEASE_NUMBER=""
DRAFT_FLAG=""
SKIP_GH=false
SKIP_R2=false

usage() {
    sed -n '/^# Usage:/,/^# Important:/p' "$0" | sed 's/^# //;s/^#//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION_OVERRIDE="$2"; shift 2 ;;
        --build) BUILD_OVERRIDE="$2"; shift 2 ;;
        --draft) DRAFT_FLAG="--draft"; SKIP_GH=true; shift ;;
        --skip-github) SKIP_GH=true; shift ;;
        --skip-r2) SKIP_R2=true; shift ;;
        stable|beta|alpha|rc) RELEASE_TYPE="$1"; shift ;;
        -h|--help) usage; exit 0 ;;
        *)
            if [[ -n "$RELEASE_TYPE" && "$RELEASE_TYPE" != "stable" && -z "$PRERELEASE_NUMBER" ]]; then
                PRERELEASE_NUMBER="$1"
                shift
            else
                echo "Unknown option: $1" >&2
                usage
                exit 2
            fi
            ;;
    esac
done

if [[ -z "$RELEASE_TYPE" ]]; then
    echo "error: release type is required: stable, beta, alpha, or rc" >&2
    usage
    exit 2
fi

if [[ "$RELEASE_TYPE" != "stable" ]]; then
    if [[ -z "$PRERELEASE_NUMBER" ]]; then
        echo "error: $RELEASE_TYPE releases require a number, e.g. scripts/release.sh $RELEASE_TYPE 42" >&2
        exit 2
    fi
    if ! [[ "$PRERELEASE_NUMBER" =~ ^[0-9]+$ ]] || [[ "$PRERELEASE_NUMBER" -eq 0 ]]; then
        echo "error: prerelease number must be a positive integer" >&2
        exit 2
    fi
fi

amore_bin() {
    if command -v amore >/dev/null 2>&1; then command -v amore
    elif [[ -x /usr/local/bin/amore ]]; then echo /usr/local/bin/amore
    else echo "error: amore CLI not found" >&2; return 1
    fi
}

read_xcconfig() {
    grep "^$1" "$VERSION_CONFIG" | sed -E 's/^[A-Z_]+ *= *//'
}

write_xcconfig() {
    /usr/bin/sed -i '' -E "s|^$1 *=.*|$1 = $2|" "$VERSION_CONFIG"
}

extract_notes() {
    awk -v ver="$1" '
        $0 ~ "^## \\[" ver "\\]" { flag=1; next }
        flag && /^## \[/         { exit }
        flag                     { print }
    ' "$CHANGELOG" | awk 'NF{found=1} found' | sed -E '$ { /^[[:space:]]*$/d; }'
}

info_plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST" 2>/dev/null || true
}

require_clean_tree() {
    git update-index --refresh >/dev/null 2>&1 || true
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        echo "  x working tree is dirty - commit or stash first"
        git status --short
        exit 1
    fi
    echo "  ok working tree clean"
}

validate_sparkle_continuity() {
    echo "  - Sparkle continuity"

    local feed_url
    feed_url="$(info_plist_value SUFeedURL)"
    if [[ "$feed_url" != "$LEGACY_STABLE_APPCAST_URL" ]]; then
        echo "  x SUFeedURL changed: $feed_url"
        echo "    Keep $LEGACY_STABLE_APPCAST_URL so older update paths remain continuous."
        exit 1
    fi

    local plist_public_key file_public_key
    plist_public_key="$(info_plist_value SUPublicEDKey)"
    file_public_key="$(grep -E '^[A-Za-z0-9+/]+=*$' "$SPARKLE_PUBLIC_KEY_FILE" | tail -1 || true)"
    if [[ -z "$plist_public_key" || "$plist_public_key" != "$file_public_key" ]]; then
        echo "  x SUPublicEDKey does not match $SPARKLE_PUBLIC_KEY_FILE"
        exit 1
    fi

    if [[ ! -s "$SPARKLE_PRIVATE_KEY" ]]; then
        echo "  x missing Sparkle private key: $SPARKLE_PRIVATE_KEY"
        exit 1
    fi

    local signer
    signer="$(command -v sign_update || true)"
    if [[ -n "$signer" ]]; then
        local tmp
        tmp="$(mktemp)"
        printf 'quarry sparkle continuity check\n' > "$tmp"
        local signature
        if signature="$("$signer" "$tmp" -f "$SPARKLE_PRIVATE_KEY" -p 2>/dev/null)"; then
            local amore_for_verify
            amore_for_verify="$(amore_bin 2>/dev/null || true)"
            if [[ -n "$amore_for_verify" ]]; then
                if "$amore_for_verify" verify "$tmp" "$signature" "$plist_public_key" >/dev/null 2>&1; then
                    echo "  ok Sparkle private key matches SUPublicEDKey"
                else
                    rm -f "$tmp"
                    echo "  x Sparkle private key does not verify against SUPublicEDKey"
                    exit 1
                fi
            else
                echo "  ok Sparkle private key can sign updates"
            fi
        else
            rm -f "$tmp"
            echo "  x Sparkle private key could not sign with sign_update"
            exit 1
        fi
        rm -f "$tmp"
    else
        echo "  ! sign_update not found; checked key file presence only"
    fi
}

upload_dsyms() {
    local archive_path="$1"

    if [[ -f "$SENTRY_CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$SENTRY_CONFIG_FILE"
    fi

    if [[ -z "${SENTRY_AUTH_TOKEN:-}" || -z "${SENTRY_ORG:-}" || -z "${SENTRY_PROJECT:-}" ]]; then
        echo "  ! Sentry config missing; dSYM upload skipped"
        echo "    Crashes for this build will be unsymbolicated in Sentry."
        echo "    Add SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_PROJECT to $SENTRY_CONFIG_FILE"
        return
    fi

    if ! command -v sentry-cli >/dev/null 2>&1; then
        echo "  ! sentry-cli missing; dSYM upload skipped - brew install getsentry/tools/sentry-cli"
        return
    fi

    SENTRY_AUTH_TOKEN="$SENTRY_AUTH_TOKEN" sentry-cli debug-files upload \
        --org "$SENTRY_ORG" --project "$SENTRY_PROJECT" \
        "$archive_path/dSYMs"
    echo "  ok uploaded dSYMs to Sentry ($SENTRY_ORG/$SENTRY_PROJECT)"
}

sync_legacy_appcasts() {
    if $SKIP_R2; then
        echo "  ! skipped legacy R2 appcast sync"
        return
    fi

    if [[ -f "$R2_CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$R2_CONFIG_FILE"
    fi

    if [[ -z "${R2_ACCESS_KEY_ID:-}" || -z "${R2_SECRET_ACCESS_KEY:-}" || -z "${R2_ENDPOINT_URL:-}" || -z "${R2_BUCKET_NAME:-}" ]]; then
        echo "  ! R2 config missing; legacy appcast sync skipped"
        echo "    Existing users still need $LEGACY_STABLE_APPCAST_URL to serve the Amore feed."
        return
    fi

    if ! command -v aws >/dev/null 2>&1; then
        echo "  ! aws CLI missing; legacy appcast sync skipped"
        return
    fi

    local appcast_path
    appcast_path="$(mktemp)"
    curl -fsSL -o "$appcast_path" "$AMORE_APPCAST_URL"
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$appcast_path"
    fi

    export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
    export AWS_DEFAULT_REGION="auto"

    aws s3 cp "$appcast_path" "s3://$R2_BUCKET_NAME/appcast.xml" \
        --endpoint-url="$R2_ENDPOINT_URL" \
        --content-type="application/xml"
    aws s3 cp "$appcast_path" "s3://$R2_BUCKET_NAME/appcast-prerelease.xml" \
        --endpoint-url="$R2_ENDPOINT_URL" \
        --content-type="application/xml"

    echo "  ok synced legacy appcasts: $LEGACY_STABLE_APPCAST_URL and $LEGACY_PRERELEASE_APPCAST_URL"

    rm -f "$appcast_path"
}

current_marketing_version="$(read_xcconfig MARKETING_VERSION)"
current_build="$(read_xcconfig CURRENT_PROJECT_VERSION)"
base_version="${current_marketing_version%%-*}"

if [[ -n "$VERSION_OVERRIDE" ]]; then
    base_version="${VERSION_OVERRIDE%%-*}"
fi

if [[ "$RELEASE_TYPE" == "stable" ]]; then
    VERSION="${VERSION_OVERRIDE:-$base_version}"
else
    VERSION="$base_version-$RELEASE_TYPE.$PRERELEASE_NUMBER"
fi

if [[ -n "$BUILD_OVERRIDE" ]]; then
    BUILD="$BUILD_OVERRIDE"
elif [[ "$VERSION" != "$current_marketing_version" ]]; then
    BUILD=$((current_build + 1))
else
    BUILD="$current_build"
fi

if [[ -z "$VERSION" || -z "$BUILD" ]]; then
    echo "error: could not resolve version/build" >&2
    exit 1
fi

echo "Releasing $APP_NAME $VERSION (build $BUILD) via Amore"
echo
echo "Preflight"

require_clean_tree

if [[ "$(read_xcconfig PRODUCT_BUNDLE_IDENTIFIER)" != "$BUNDLE_ID" ]]; then
    echo "  x PRODUCT_BUNDLE_IDENTIFIER is not $BUNDLE_ID"
    exit 1
fi
echo "  ok bundle id $BUNDLE_ID"

validate_sparkle_continuity

if [[ ! -f "$CHANGELOG" ]] || ! grep -q "^## \[$VERSION\]" "$CHANGELOG"; then
    echo "  x no CHANGELOG.md entry for [$VERSION]"
    echo "    add a heading like: ## [$VERSION] - $(date +%Y-%m-%d)"
    exit 1
fi
echo "  ok CHANGELOG.md entry found"

AMORE="$(amore_bin)"
if ! "$AMORE" whoami >/dev/null 2>&1; then
    echo "  x amore not logged in - run: amore login"
    exit 1
fi
echo "  ok amore logged in"

if ! command -v jq >/dev/null 2>&1; then
    echo "  x jq not installed - brew install jq"
    exit 1
fi

if ! $SKIP_GH; then
    if ! command -v gh >/dev/null 2>&1; then
        echo "  x gh CLI not installed - brew install gh, or pass --skip-github"
        exit 1
    fi
    if ! gh auth status >/dev/null 2>&1; then
        echo "  x gh not authenticated - run: gh auth login"
        exit 1
    fi
    if ! gh repo view "$GITHUB_RELEASE_REPO" >/dev/null 2>&1; then
        echo "  x cannot access GitHub release repo $GITHUB_RELEASE_REPO"
        exit 1
    fi
    echo "  ok gh ready"
fi

echo
echo "Version"
if [[ "$current_marketing_version" != "$VERSION" || "$current_build" != "$BUILD" ]]; then
    echo "  updating quarry/version.xcconfig: $current_marketing_version ($current_build) -> $VERSION ($BUILD)"
    write_xcconfig MARKETING_VERSION "$VERSION"
    write_xcconfig CURRENT_PROJECT_VERSION "$BUILD"
    git add "$VERSION_CONFIG"
    git commit -m "Release $VERSION ($BUILD)" >/dev/null
    echo "  ok committed version bump"
else
    echo "  ok already at $VERSION ($BUILD)"
fi

NOTES="$(extract_notes "$VERSION")"
if [[ -z "$NOTES" ]]; then
    echo "error: empty CHANGELOG.md body for [$VERSION]" >&2
    exit 1
fi

echo
echo "Archive"
ARCHIVE_PATH="$(mktemp -d)/$APP_NAME.xcarchive"
xcodebuild -project "$PROJECT_ROOT/Quarry.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    archive
echo "  ok archived to $ARCHIVE_PATH"

echo
echo "Sentry dSYM upload"
upload_dsyms "$ARCHIVE_PATH"

AMORE_RELEASE_FLAGS=("$ARCHIVE_PATH" --release-notes "$NOTES" --format json)
if [[ "$RELEASE_TYPE" != "stable" ]]; then
    AMORE_RELEASE_FLAGS+=(--beta)
fi
if [[ -n "$DRAFT_FLAG" ]]; then
    AMORE_RELEASE_FLAGS+=("$DRAFT_FLAG")
fi

echo
echo "Amore release"
LOG="$(mktemp)"
"$AMORE" release "${AMORE_RELEASE_FLAGS[@]}" | tee "$LOG"

DMG_URL="$(sed -n '/^{/,$p' "$LOG" | jq -er '.release.downloadURL' 2>/dev/null || true)"
if [[ -z "$DMG_URL" ]]; then
    echo "x no .release.downloadURL in Amore JSON output (see $LOG)" >&2
    exit 1
fi
echo "  ok DMG: $DMG_URL"

echo
echo "Legacy Sparkle appcast sync"
sync_legacy_appcasts

if $SKIP_GH; then
    echo
    echo "Released $VERSION ($BUILD). GitHub step skipped."
    exit 0
fi

echo
echo "GitHub release"
DMG_PATH="$(mktemp -d)/Quarry-$VERSION.dmg"
curl -fsSL -o "$DMG_PATH" "$DMG_URL"

TAG="v$VERSION"
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "  ! tag $TAG already exists locally - reusing"
else
    git tag -a "$TAG" -m "Release $VERSION ($BUILD)"
fi
git push "https://github.com/$GITHUB_RELEASE_REPO.git" "$TAG"

if gh release view "$TAG" --repo "$GITHUB_RELEASE_REPO" >/dev/null 2>&1; then
    echo "  ! GitHub release $TAG exists - uploading DMG as new asset"
    gh release upload "$TAG" "$DMG_PATH" --repo "$GITHUB_RELEASE_REPO" --clobber
else
    if [[ "$RELEASE_TYPE" == "stable" ]]; then
        gh release create "$TAG" \
            --repo "$GITHUB_RELEASE_REPO" \
            --title "Quarry $VERSION" \
            --notes "$NOTES" \
            "$DMG_PATH"
    else
        gh release create "$TAG" \
            --repo "$GITHUB_RELEASE_REPO" \
            --title "Quarry $VERSION" \
            --notes "$NOTES" \
            --prerelease \
            "$DMG_PATH"
    fi
fi

echo
echo "Released $VERSION ($BUILD)"
echo "  GitHub: https://github.com/$GITHUB_RELEASE_REPO/releases/tag/$TAG"
echo "  Amore:  $DMG_URL"
echo "  Legacy: $LEGACY_STABLE_APPCAST_URL"
