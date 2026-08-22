#!/usr/bin/env bash
# --------------------------------------------------------------------------
# Seal guard — fails if any OPEN code (apps/ or zigos/) imports SEALED machine
# source (hw/) directly. Open code may reach the machine ONLY through the
# published SDK headers, and only via the Zig named modules wired in build.zig
# ("hardware", "audio_hw"), never a path into hw/.
#
# The named-module setup already makes hw/ unreachable by relative import from
# apps//zigos/ (different module roots), so this is a defence-in-depth check for
# CI and for anyone tempted to add a cross-root module the wrong way.
# --------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."

# Any @import whose path dips into hw/ machine source (not the sdk headers, which
# are reached as named modules) is forbidden in the open tree.
violations=$(grep -rnE '@import\("([^"]*/)?(hw/|\.\./hw/|machine_video|machine_audio)' apps zigos 2>/dev/null || true)
# Also forbid importing the sealed chip/render source by filename.
violations+=$(grep -rnE '@import\("([^"]*/)?(video\.zig|audio/engine\.zig|audio/ym\.zig)"\)' apps zigos 2>/dev/null || true)

if [ -n "$violations" ]; then
    echo "SEAL VIOLATION: open code (apps/ or zigos/) imports sealed hw/ source:" >&2
    echo "$violations" >&2
    echo "" >&2
    echo "Open code must use the named modules ('hardware', 'audio_hw', 'zigos', 'players')," >&2
    echo "which resolve only to hw/sdk/ headers — never hw/ machine source." >&2
    exit 1
fi

echo "seal OK — no open->hw/ source imports."
