#!/usr/bin/env bash
#
# Roll back a Quarry Amore release.
#
# Default action: unpublish the release on Amore and delete the matching GitHub
# release + tag. The old R2 Sparkle feeds are then refreshed from Amore so
# existing users do not keep seeing the rolled-back release.
#
# Usage:
#   scripts/rollback-release.sh <version>
#   scripts/rollback-release.sh --latest
#   scripts/rollback-release.sh 0.1.0 --delete
#   scripts/rollback-release.sh 0.1.0 --keep-github
#   scripts/rollback-release.sh --latest --yes

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="doc.pluk"
GITHUB_RELEASE_REPO="ribban-co/Quarry"
AMORE_APPCAST_URL="${AMORE_APPCAST_URL:-https://releases.pluk.sh/v1/apps/doc.pluk/appcast.xml}"
R2_CONFIG_FILE="$PROJECT_ROOT/private/r2-config"

VERSION=""
USE_LATEST=false
DELETE=false
KEEP_GH=false
YES=false
SKIP_R2=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --latest) USE_LATEST=true; shift ;;
        --delete) DELETE=true; shift ;;
        --keep-github) KEEP_GH=true; shift ;;
        --skip-r2) SKIP_R2=true; shift ;;
        --yes|-y) YES=true; shift ;;
        -h|--help) sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# //;s/^#//'; exit 0 ;;
        -*) echo "unknown flag: $1" >&2; exit 2 ;;
        *) VERSION="$1"; shift ;;
    esac
done

amore_bin() {
    if command -v amore >/dev/null 2>&1; then command -v amore
    elif [[ -x /usr/local/bin/amore ]]; then echo /usr/local/bin/amore
    else echo "error: amore CLI not found" >&2; return 1
    fi
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

    rm -f "$appcast_path"
    echo "  ok refreshed legacy Sparkle appcasts from Amore"
}

AMORE="$(amore_bin)"
if ! "$AMORE" whoami >/dev/null 2>&1; then
    echo "x amore not logged in - run: amore login" >&2
    exit 1
fi

LIST="$("$AMORE" releases list --bundle-id "$BUNDLE_ID" 2>&1)"
ROWS="$(echo "$LIST" | grep -E '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-' | sed 's/[│├┤]//g')"

if [[ -z "$ROWS" ]]; then
    echo "x no releases found for $BUNDLE_ID" >&2
    exit 1
fi

if $USE_LATEST; then
    ROW="$(echo "$ROWS" | head -1)"
    VERSION="$(echo "$ROW" | awk '{print $2}')"
fi

if [[ -z "$VERSION" ]]; then
    echo "error: pass a version or --latest" >&2
    exit 2
fi

ROW="$(echo "$ROWS" | awk -v v="$VERSION" '$2 == v {print; exit}')"
if [[ -z "$ROW" ]]; then
    echo "x no release found for version $VERSION" >&2
    echo "$LIST"
    exit 1
fi

BUILD="$(echo "$ROW" | awk '{print $3}')"
STATUS="$(echo "$ROW" | awk '{print $4}')"
TAG="v$VERSION"

echo "Target: $VERSION (build $BUILD), currently $STATUS"
if $DELETE; then
    echo "Action: permanently delete from Amore"
else
    echo "Action: unpublish from Amore"
fi
if ! $KEEP_GH; then
    echo "Action: delete GitHub release + tag $TAG"
fi
if ! $SKIP_R2; then
    echo "Action: refresh legacy R2 appcast URLs"
fi
echo

if ! $YES; then
    read -rp "Continue? [y/N] " ans
    case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "aborted"; exit 1 ;; esac
fi

if $DELETE; then
    "$AMORE" releases delete "$VERSION" --bundle-id "$BUNDLE_ID" --yes
else
    "$AMORE" releases update "$VERSION" --bundle-id "$BUNDLE_ID" --published false
fi

if ! $KEEP_GH; then
    if command -v gh >/dev/null 2>&1; then
        if gh release view "$TAG" --repo "$GITHUB_RELEASE_REPO" >/dev/null 2>&1; then
            gh release delete "$TAG" --repo "$GITHUB_RELEASE_REPO" --yes --cleanup-tag 2>/dev/null \
                || gh release delete "$TAG" --repo "$GITHUB_RELEASE_REPO" --yes
        else
            echo "  ! no GitHub release for $TAG in $GITHUB_RELEASE_REPO"
        fi
        if git rev-parse "$TAG" >/dev/null 2>&1; then
            git tag -d "$TAG" >/dev/null
            git push "https://github.com/$GITHUB_RELEASE_REPO.git" ":refs/tags/$TAG" >/dev/null 2>&1 || true
        fi
    else
        echo "  ! skipping GitHub cleanup (gh CLI missing)"
    fi
fi

sync_legacy_appcasts

echo "Rolled back $VERSION (build $BUILD)"
if ! $DELETE; then
    echo "To re-publish: amore releases update $VERSION --bundle-id $BUNDLE_ID --published true"
fi
