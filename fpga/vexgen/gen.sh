#!/usr/bin/env bash
# Generate VexRiscv netlists with other cache geometries (CYCLES.md "Memory path"),
# with the JDK + sbt that `ZM_VEXGEN=1 tools/setup.sh` puts in fpga/.tools/.
#
#   vexgen/gen.sh I16w2D4:16384:2:4096:1 [<name>:<i$ bytes>:<i$ ways>:<d$ bytes>:<d$ ways> ...]
#
# Writes build/vexgen/VexRiscv_<name>.v for each spec; one sbt session for all.
set -euo pipefail
FPGA="$(cd "$(dirname "$0")/.." && pwd)"
T="$FPGA/.tools"
[ -x "$T/jdk/bin/java" ] && [ -x "$T/sbt/bin/sbt" ] || { echo "vexgen: run ZM_VEXGEN=1 tools/setup.sh" >&2; exit 2; }
export JAVA_HOME="$T/jdk" PATH="$T/jdk/bin:$T/sbt/bin:$PATH" COURSIER_CACHE="$T/coursier"
export SBT_OPTS="-Dsbt.global.base=$T/sbt-home -Dsbt.ivy.home=$T/ivy2 -Dsbt.boot.directory=$T/sbt-boot"
out="$FPGA/build/vexgen"
mkdir -p "$out"
cmds=()
for spec in "$@"; do
    IFS=: read -r name isz iways dsz dways <<<"$spec"
    cmds+=("runMain zm.GenZm --iCacheSize $isz --iWays $iways --dCacheSize $dsz --dWays $dways --outputFile VexRiscv_$name --targetDirectory $out")
done
cd "$FPGA/vexgen" && sbt -batch "${cmds[@]}"
