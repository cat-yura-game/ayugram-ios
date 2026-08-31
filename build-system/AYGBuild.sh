#!/bin/bash
# AYG: build AyuGram for the simulator, with progress visible while it runs.
#
#   Usage: build-system/AYGBuild.sh [extra Make.py args...]
#
# Do NOT pipe this through grep to "keep it quiet" — that hides bazel's
# `[N / TOTAL] <action>` progress line, which is the only way to see where a
# 20-minute build actually is. The full output goes to the log named below, and
# bazel additionally keeps its own copy at <output_base>/command.log, which is
# what a progress watcher should tail.

set -uo pipefail
cd "$(dirname "$0")/.."

LOG="${AYG_BUILD_LOG:-/tmp/ayg-build.log}"

echo "log        : $LOG"
BAZEL_LOG="$(ls -t /private/var/tmp/_bazel_"$(whoami)"/*/command.log 2>/dev/null | head -1)"
[ -n "$BAZEL_LOG" ] && echo "bazel log  : $BAZEL_LOG"
echo

python3 build-system/Make/Make.py --overrideXcodeVersion \
    --cacheDir ~/telegram-bazel-cache \
    build \
    --configurationPath build-system/AYGDevelopmentConfiguration.json \
    --codesigningInformationPath build-system/fake-codesigning \
    --buildNumber=1 --configuration=debug_sim_arm64 \
    "$@" 2>&1 | tee "$LOG"

status=${pipestatus[1]:-${PIPESTATUS[1]}}
echo
if [ "$status" = "0" ]; then
    echo "BUILD OK"
else
    echo "BUILD FAILED (exit $status) — errors:"
    grep -E "^ERROR:|error: " "$LOG" | head -20
fi
exit "$status"
