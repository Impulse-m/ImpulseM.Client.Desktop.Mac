#!/bin/sh
#
# Initialises the git submodules that the macOS app and its native frameworks
# are built from. Every checkout is listed explicitly and nothing recurses:
# the nested submodules that needed a recursive checkout belonged to the
# removed native calls stack and the Rust mtproto engine, which are no longer
# part of the build.
#
# Usage:
#   sh scripts/ci-submodules.sh
#
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

log() {
    printf '\n==> %s\n' "$*"
}

log "Initialising top-level submodules"
git submodule update --init -- \
    submodules/Sparkle \
    submodules/libprisma \
    submodules/regex \
    submodules/rlottie \
    submodules/tlottie \
    submodules/telegram-ios

log "Initialising the telegram-ios submodules the native frameworks are built from"
git -C submodules/telegram-ios submodule update --init -- \
    third-party/td/td \
    third-party/dav1d/dav1d \
    third-party/wallet-engine/wallet-engine

log "Verifying that every required checkout is populated"
for REQUIRED_PATH in \
    submodules/Sparkle \
    submodules/libprisma \
    submodules/regex/include/boost/regex.hpp \
    submodules/rlottie \
    submodules/tlottie \
    submodules/telegram-ios \
    submodules/telegram-ios/third-party/td/td \
    submodules/telegram-ios/third-party/dav1d/dav1d \
    submodules/telegram-ios/third-party/wallet-engine/wallet-engine
do
    if [ -z "$(ls -A "$REQUIRED_PATH" 2>/dev/null)" ]; then
        echo "error: $REQUIRED_PATH is empty after submodule initialisation" >&2
        exit 1
    fi
    echo "ok: $REQUIRED_PATH"
done

log "Submodules ready"
