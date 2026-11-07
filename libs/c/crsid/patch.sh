#!/bin/sh
# cRSID as KESTREL builds it: upstream/ (cRSID 1.58, unmodified) + patches/ -> <out-dir>, the tree
# the players compile (build.zig for machine-audio.wasm, fpga/cycles/audio.mk for BARD and the native
# host). Each sed patch must change its file. README.md says what each one does and why.
#   libs/c/crsid/patch.sh <out-dir>
set -eu
D=$(cd "$(dirname "$0")" && pwd)
O=$1
rm -rf "$O"
mkdir -p "$O"
cp -R "$D/upstream/." "$O/"
apply() {
    sed -f "$D/patches/$2" "$O/$1" >"$O/$1.new"
    if cmp -s "$O/$1" "$O/$1.new"; then
        echo "patch.sh: patches/$2 changed nothing in $1 (upstream moved?)" >&2
        exit 1
    fi
    mv "$O/$1.new" "$O/$1"
}
apply C64/C64_SIDrouting.c C64_SIDrouting.c.sed
apply C64/SID_OscWaves.c SID_OscWaves.c.sed
apply host/audio.c audio.c.sed
# The light engine's filter cutoff table for 22.05 kHz (patches/curves.sh made it with cRSID's curvegen).
cp "$D/patches/SID_FilterCurves.h" "$O/C64/SID_FilterCurves.h"
