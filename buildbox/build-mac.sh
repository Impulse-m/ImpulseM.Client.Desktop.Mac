#!/bin/sh
set -e


BUILD_CONFIGURATION=$1

PWDPATH=$PWD

CPPATH="${TELEGRAM_BUILD_ROOT:-$HOME}/build-${BUILD_CONFIGURATION}"
PROJECT="${CPPATH}/telegrammacos"


sh "$PWDPATH/scripts/time-step.sh" source-sync \
    sh "$PWDPATH/buildbox/sync-source.sh" "$PWDPATH" "$PROJECT"

cd "$PROJECT"
cd ..
files_to_remove=$(ls -A | grep -v telegrammacos || true)
if [ -n "$files_to_remove" ]; then
    rm -r $files_to_remove
else
    echo "No files to remove."
fi

rm -r telegrammacos.xcarchive || true

cd telegrammacos


BUILD_LOG_DIR="${CI_BUILD_LOG_DIR:-$CPPATH}"
mkdir -p "$BUILD_LOG_DIR"
FRAMEWORK_LOG="$BUILD_LOG_DIR/frameworks.log"
if ! sh scripts/time-step.sh frameworks sh "scripts/configure_frameworks.sh" > "$FRAMEWORK_LOG" 2>&1; then
    tail -80 "$FRAMEWORK_LOG"
    exit 1
fi
grep -E '^(framework-stamp:|build-timing:)' "$FRAMEWORK_LOG" || true
if ! cmp -s "configurations/${BUILD_CONFIGURATION}.xcconfig" "Telegram-Mac/Release.xcconfig"; then
    cp "configurations/${BUILD_CONFIGURATION}.xcconfig" "Telegram-Mac/Release.xcconfig"
fi

case "${BUILD_CONFIGURATION}" in
    Alpha) CHANNEL_CONDITION="ALPHA" ;;
    Beta) CHANNEL_CONDITION="BETA" ;;
    Stable) CHANNEL_CONDITION="STABLE" ;;
    AppStore|Appstore) CHANNEL_CONDITION="APP_STORE" ;;
    *) echo "Unknown build configuration: ${BUILD_CONFIGURATION}" >&2; exit 1 ;;
esac

set --
case "${TELEGRAM_COMPILATION_CACHE:-}" in
    YES|NO)
        set -- "COMPILATION_CACHE_ENABLE_CACHING=$TELEGRAM_COMPILATION_CACHE" \
            "COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES"
        ;;
    "") ;;
    *) echo "TELEGRAM_COMPILATION_CACHE must be YES or NO" >&2; exit 1 ;;
esac

XCODEBUILD_LOG="$BUILD_LOG_DIR/xcodebuild.log"
echo "Archiving, full log: ${XCODEBUILD_LOG}"
if ! sh scripts/time-step.sh archive xcodebuild archive -showBuildTimingSummary -workspace "Telegram-Mac.xcworkspace" \
-scheme Release \
-configuration Release \
-archivePath ./ \
COMPILER_INDEX_STORE_ENABLE=NO \
"SWIFT_ACTIVE_COMPILATION_CONDITIONS=\$(inherited) ${CHANNEL_CONDITION}" "$@" > "${XCODEBUILD_LOG}" 2>&1; then
    grep -E -A3 '(^|: )(fatal )?error: |^ld: [^w]|^Undefined symbols' "${XCODEBUILD_LOG}" | head -300 || true
    echo "..."
    tail -20 "${XCODEBUILD_LOG}"
    exit 1
fi
echo "Archive succeeded"
sed -n '/^Build Timing Summary/,$p' "$XCODEBUILD_LOG" | tail -60


cd ..

archive="./telegrammacos.xcarchive"
appname="ImpulseM.app"

rm -rf ${appname} ${appname}.dSYM ${appname}.DSYM.zip
cp -R "${archive}/Products/Applications/ImpulseM.app" ${appname}
cp -R "${archive}/dSYMs/ImpulseM.app.dSYM" ${appname}.dSYM


sh "$PWDPATH/scripts/time-step.sh" dsym-compression \
    ditto -c -k --sequesterRsrc --keepParent ${appname}.dSYM ${appname}.DSYM.zip

# Notarization changes the app (ticket staple), so it runs before the update archive is built.
# Without the signing secrets notarize.sh exits 0 and the app stays unsigned.
sh "$PWDPATH/buildbox/notarize.sh" "${appname}"

# Sparkle update archive and EdDSA signature. The signing key is a CI secret; without it the
# archive is still produced, unsigned, and the job does not fail. sign_update is taken from a
# pinned Sparkle release, because the vendored submodule predates --ed-key-file and --verify.
SPARKLE_VERSION="2.10.0"
SPARKLE_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
update_archive="${appname%.app}.zip"
update_signature="${update_archive}.sparkle.txt"

rm -f "${update_archive}" "${update_signature}"
sh "$PWDPATH/scripts/time-step.sh" update-archive \
    ditto -c -k --sequesterRsrc --keepParent "${appname}" "${update_archive}"

if [ -z "${IMPULSEM_SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    echo "sparkle: the EdDSA update key secret is not present, ${update_archive} stays unsigned"
else
    sparkle_dir="${CPPATH}/sparkle-${SPARKLE_VERSION}"
    sign_update="${sparkle_dir}/bin/sign_update"
    if [ ! -x "${sign_update}" ]; then
        mkdir -p "${sparkle_dir}"
        curl -fsSL -o "${sparkle_dir}/Sparkle.tar.xz" \
            "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
        echo "${SPARKLE_SHA256}  ${sparkle_dir}/Sparkle.tar.xz" | shasum -a 256 -c -
        tar -xJf "${sparkle_dir}/Sparkle.tar.xz" -C "${sparkle_dir}"
        if [ ! -x "${sign_update}" ]; then
            echo "error: ${sign_update} is missing from the pinned Sparkle ${SPARKLE_VERSION} archive" >&2
            exit 1
        fi
    fi

    # The key is read from standard input, so it never appears in the command line or the log.
    printf '%s\n' "${IMPULSEM_SPARKLE_ED_PRIVATE_KEY}" | "${sign_update}" --ed-key-file - "${update_archive}" > "${update_signature}"
    signature="$(sed -n 's/^sparkle:edSignature="\([^"]*\)".*/\1/p' "${update_signature}")"
    if [ -z "${signature}" ]; then
        echo "error: sign_update did not produce an EdDSA signature for ${update_archive}" >&2
        cat "${update_signature}" >&2
        exit 1
    fi
    printf '%s\n' "${IMPULSEM_SPARKLE_ED_PRIVATE_KEY}" | "${sign_update}" --ed-key-file - --verify "${update_archive}" "${signature}"
    cat "${update_signature}"
    echo "sparkle: ${update_archive} is signed and the EdDSA signature verifies"
fi
