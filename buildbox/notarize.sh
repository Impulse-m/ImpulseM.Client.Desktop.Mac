#!/bin/sh
set -eu

# Signs, notarizes and staples a release build of the app bundle.
# Usage: sh buildbox/notarize.sh <path to ImpulseM.app>
#
# Secrets come from the CI secret store as environment variables only:
#   IMPULSEM_DEVELOPER_ID_IDENTITY  name of the Developer ID Application identity in the job keychain
#   IMPULSEM_NOTARY_PROFILE         notarytool keychain profile that the job creates from its secrets
# Optional, not a secret:
#   IMPULSEM_APP_ENTITLEMENTS       entitlements plist of the app (Team ID already substituted), used for the app
#                                   and its main executable. CI builds are unsigned, so the bundle carries none.
# When either secret is missing the script exits 0 and the app stays unsigned, so builds without secrets never fail.
# A signing error, or a notarization that is not accepted, exits non-zero.

APP="${1:-}"
IDENTITY="${IMPULSEM_DEVELOPER_ID_IDENTITY:-}"
NOTARY_PROFILE="${IMPULSEM_NOTARY_PROFILE:-}"
APP_ENTITLEMENTS="${IMPULSEM_APP_ENTITLEMENTS:-}"

if [ -z "$APP" ]; then
    echo "usage: sh buildbox/notarize.sh <path to ImpulseM.app>" >&2
    exit 2
fi

if [ ! -d "$APP" ]; then
    echo "error: $APP is not an app bundle" >&2
    exit 2
fi

if [ -z "$IDENTITY" ] || [ -z "$NOTARY_PROFILE" ]; then
    echo "notarize: the signing secrets are not present, $APP stays unsigned"
    exit 0
fi

if [ -n "$APP_ENTITLEMENTS" ] && [ ! -f "$APP_ENTITLEMENTS" ]; then
    echo "error: IMPULSEM_APP_ENTITLEMENTS $APP_ENTITLEMENTS is not a file" >&2
    exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

sign_component() {
    component="$1"
    source_entitlements="${2:-}"
    entitlements="$WORK/entitlements.plist"
    rm -f "$entitlements"
    if [ -n "$source_entitlements" ]; then
        cp "$source_entitlements" "$entitlements"
    else
        codesign -d --entitlements :- "$component" > "$entitlements" 2>/dev/null || true
    fi
    if [ -s "$entitlements" ]; then
        codesign --force --options runtime --timestamp --entitlements "$entitlements" --sign "$IDENTITY" "$component"
    else
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$component"
    fi
}

# Nested code is signed first, inside out: Mach-O files, then the bundles deepest first, then the app.
# Every regular file is checked, so non-executable dylibs are signed too. The main executable in Contents/MacOS
# gets the app entitlements, because its own signature is what the sandbox and hardened runtime read.
find "$APP/Contents" -type f -print > "$WORK/files.txt"
while IFS= read -r candidate; do
    if file -b "$candidate" | grep -q 'Mach-O'; then
        case "$candidate" in
            "$APP/Contents/MacOS/"*)
                sign_component "$candidate" "$APP_ENTITLEMENTS"
                ;;
            *)
                sign_component "$candidate"
                ;;
        esac
    fi
done < "$WORK/files.txt"

find "$APP/Contents" -depth \( -name '*.xpc' -o -name '*.appex' -o -name '*.framework' -o -name '*.app' \) -print > "$WORK/bundles.txt"
while IFS= read -r bundle; do
    sign_component "$bundle"
done < "$WORK/bundles.txt"

sign_component "$APP" "$APP_ENTITLEMENTS"
codesign --verify --deep --strict --verbose=2 "$APP"

ARCHIVE="$WORK/ImpulseM-notarization.zip"
ditto -c -k --keepParent "$APP" "$ARCHIVE"

SUBMISSION="$WORK/submission.json"
if ! xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$SUBMISSION"; then
    echo "error: notarytool submit failed for $APP" >&2
    cat "$SUBMISSION" >&2 || true
    exit 1
fi

STATUS="$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1])).get("status", ""))' "$SUBMISSION")"
SUBMISSION_ID="$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1])).get("id", ""))' "$SUBMISSION")"
if [ "$STATUS" != "Accepted" ]; then
    echo "error: notarization of $APP finished with status '$STATUS' (submission $SUBMISSION_ID)" >&2
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    exit 1
fi

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
echo "notarize: $APP is signed, notarized and stapled"
