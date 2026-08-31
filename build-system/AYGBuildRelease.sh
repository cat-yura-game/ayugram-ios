#!/bin/bash
# AYG: build a release-signed AyuGram IPA, with progress visible while it runs.
#
#   Usage: build-system/AYGBuildRelease.sh adhoc|appstore [extra Make.py args...]
#
# adhoc    — signed with the Ad Hoc profiles, installs straight onto a device
#            registered on the team (currently only the iPhone 15,
#            00008120-000965642292201E). This is the one to use for testing.
# appstore — signed for App Store submission. Cannot be installed directly;
#            it only goes up through TestFlight / App Store Connect.
#
# Both use the distribution certificate (V7N7DGXYAF) whose private key is in
# the login keychain, and the profiles under build-input/codesigning-*/.
#
# Do NOT pipe this through grep to "keep it quiet" — that hides bazel's
# `[N / TOTAL] <action>` progress line, which is the only way to see where a
# 20-minute build actually is.

set -uo pipefail
cd "$(dirname "$0")/.."

VARIANT="${1:-}"
case "$VARIANT" in
    adhoc)
        CONFIG="build-system/AYGAdHocConfiguration.json"
        CODESIGNING="build-input/codesigning-adhoc"
        ;;
    appstore)
        CONFIG="build-system/AYGAppStoreConfiguration.json"
        CODESIGNING="build-input/codesigning-appstore"
        ;;
    *)
        echo "usage: $0 adhoc|appstore [extra Make.py args...]" >&2
        exit 2
        ;;
esac
shift

if grep -q "REPLACE_WITH_OWN_API" "$CONFIG"; then
    echo "ERROR: $CONFIG still carries placeholder api_id/api_hash." >&2
    echo "       Get a real pair from my.telegram.org before building for a device:" >&2
    echo "       Telegram's public test pair (api_id 8) gets real accounts banned." >&2
    exit 1
fi

LOG="${AYG_BUILD_LOG:-/tmp/ayg-build-release.log}"
BUILD_NUMBER="${AYG_BUILD_NUMBER:-1}"

echo "variant    : $VARIANT"
echo "config     : $CONFIG"
echo "codesigning: $CODESIGNING"
echo "log        : $LOG"
BAZEL_LOG="$(ls -t /private/var/tmp/_bazel_"$(whoami)"/*/command.log 2>/dev/null | head -1)"
[ -n "$BAZEL_LOG" ] && echo "bazel log  : $BAZEL_LOG"
echo

python3 build-system/Make/Make.py --overrideXcodeVersion \
    --cacheDir ~/telegram-bazel-cache \
    build \
    --configurationPath "$CONFIG" \
    --codesigningInformationPath "$CODESIGNING" \
    --buildNumber="$BUILD_NUMBER" --configuration=release_arm64 \
    "$@" 2>&1 | tee "$LOG"

status=${pipestatus[1]:-${PIPESTATUS[1]}}
echo
if [ "$status" = "0" ]; then
    echo "BUILD OK — bazel-bin/Telegram/Telegram.ipa"
else
    echo "BUILD FAILED (exit $status) — errors:"
    grep -E "^ERROR:|error: " "$LOG" | head -20
fi
exit "$status"
