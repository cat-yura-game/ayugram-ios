#!/bin/bash
# AYG: install a freshly built ayugram.app onto a simulator, keeping the login.
#
#   Usage: build-system/AYGInstallToSimulator.sh [device-udid-or-name]
#          defaults to the currently booted simulator.
#
# What actually matters here, measured on Xcode 26.6 / iOS 26.2:
#
#   * `simctl uninstall` DELETES the data container — that is what makes you log in
#     again. Never use it just to pick up a rebuild.
#   * `simctl install` KEEPS your data. It moves the data container to a new UUID
#     path but carries the contents across, and it is the only way Info.plist
#     changes (display name, icons, permissions text) reach SpringBoard/installd.
#   * Replacing the .app in place keeps the data container path AND the contents,
#     but installd never re-reads Info.plist, so metadata changes silently do not
#     show up. It is also the documented workaround for installd's hard-link cache
#     skipping an install when the build number has not changed.
#
# So: install normally, then verify the installed binary really is the fresh one,
# and only fall back to the in-place swap if it is not.

set -euo pipefail

BUNDLE_ID="ph.telegra.Telegraph"
DEVICE="${1:-}"

if [ -z "$DEVICE" ]; then
    DEVICE="$(xcrun simctl list devices booted -j \
        | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; a=[x for v in d.values() for x in v]; print(a[0]["udid"] if a else "")')"
    [ -n "$DEVICE" ] || { echo "No booted simulator, and none given. Boot one or pass a udid."; exit 1; }
fi

cd "$(dirname "$0")/.."

# `-L` is REQUIRED: bazel-out is a symlink, so a plain `find bazel-out` finds nothing.
SRC="$(find -L bazel-out -maxdepth 14 -path '*/Telegram_archive-root/Payload/ayugram.app' -type d | head -1)"
[ -n "$SRC" ] && [ -x "$SRC/ayugram" ] || {
    echo "No freshly built ayugram.app under bazel-out — build first."; exit 1; }

echo "device : $DEVICE"
echo "source : $SRC"

xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$DEVICE" "$SRC"

DEST="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" app)"
WANT="$(shasum -a 256 "$SRC/ayugram" | awk '{print $1}')"
GOT="$(shasum -a 256 "$DEST/ayugram" | awk '{print $1}')"

if [ "$WANT" != "$GOT" ]; then
    # installd kept a cached copy (same build number). Swap the bundle by hand.
    # Guarded on SRC above, so a failed copy cannot leave the device with no app.
    echo "installd served a stale binary — replacing the bundle in place"
    xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
    rm -rf "$DEST"
    cp -Rp "$SRC" "$DEST"
    echo "note: Info.plist changes (display name, icons) will NOT show until an install"
    echo "      that installd accepts — bump --buildNumber if you need them picked up."
else
    echo "installed binary matches the build"
fi

echo "data   : $(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)"
xcrun simctl launch "$DEVICE" "$BUNDLE_ID"
