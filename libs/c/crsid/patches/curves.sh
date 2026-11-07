#!/bin/sh
# Regenerate patches/SID_FilterCurves.h: cRSID's own tools/curvegen.c with its output rate set to
# zm_sid.h's ZM_SID_RATE (22050) instead of 44100. Run on a host with a C compiler and libm, then
# commit the result: the build copies it, it does not run curvegen.
#   libs/c/crsid/patches/curves.sh
set -eu
D=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
sed 's/samplerate=44100/samplerate=22050/' "$D/upstream/tools/curvegen.c" >"$T/curvegen.c"
cc -O2 -I"$D/upstream/tools" -o "$T/curvegen" "$T/curvegen.c" -lm
"$T/curvegen" "$D/patches/SID_FilterCurves.h" >/dev/null
