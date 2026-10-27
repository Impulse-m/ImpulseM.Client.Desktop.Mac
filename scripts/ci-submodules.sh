#!/bin/sh
#
# Initialises the git submodules that the macOS app and its native frameworks read.
#
# A recursive submodule update fails on the private upstream repositories
# (third-party/twidget, third-party/widget-sandbox) and on nested submodules
# with relative URLs. Every checkout is therefore listed explicitly. The two
# private repositories are not listed and are never initialised: no app target,
# Swift package or framework build step references them.
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
    submodules/libprisma \
    submodules/libtgvoip \
    submodules/rlottie \
    submodules/tgcalls \
    submodules/tlottie \
    submodules/telegram-ios

log "Initialising top-level submodules that need their own nested submodules"
git submodule update --init --recursive -- \
    submodules/Sparkle \
    submodules/tg_owt

log "Initialising the telegram-ios submodules the native frameworks are built from"
git -C submodules/telegram-ios submodule update --init -- \
    third-party/td/td \
    third-party/dav1d/dav1d \
    third-party/wallet-engine/wallet-engine \
    third-party/mtproto-engine

log "Verifying that every required checkout is populated"
for REQUIRED_PATH in \
    submodules/libprisma \
    submodules/libtgvoip \
    submodules/rlottie \
    submodules/tgcalls \
    submodules/tlottie \
    submodules/telegram-ios \
    submodules/Sparkle \
    submodules/tg_owt \
    submodules/telegram-ios/third-party/td/td \
    submodules/telegram-ios/third-party/dav1d/dav1d \
    submodules/telegram-ios/third-party/wallet-engine/wallet-engine \
    submodules/telegram-ios/third-party/mtproto-engine
do
    if [ -z "$(ls -A "$REQUIRED_PATH" 2>/dev/null)" ]; then
        echo "error: $REQUIRED_PATH is empty after submodule initialisation" >&2
        exit 1
    fi
    echo "ok: $REQUIRED_PATH"
done

log "Submodules ready"
