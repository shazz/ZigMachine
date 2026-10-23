#!/bin/bash
# Full-SoC postmortem on the CURRENT tree, via the repo's own flow of record.
#
#   bash review/tools/synth_full.sh
#
# 1. regenerates the flat gateware from the CURRENT sources (soc.zigmachine_soc, target z7)
# 2. copies build/board_main/gateware/platform_z7.tcl — the run-every-build Tcl (same part,
#    directives, reports) — with ONLY the platform_z7.v path retargeted to the regenerated
#    file, plus the matching XDC and netlist into /tmp/opencode/rev/pletdir
# 3. runs it in project mode (synth -> opt -> place, ExtraTimingOpt -> route + phys_opt,
#    write_bitstream) and leaves its own reports there:
#    platform_z7_{timing_synth,timing,utilization*,route_status,drc,power}.rpt + *_synth/place/route.dcp
set -e
export PATH=/opt/vivado/2026.1/Vivado/bin:$PATH LD_LIBRARY_PATH=$HOME/.local/lib/vivado-compat
FPGA=/home/matt/projects/ZigMachine/fpga
RW=/tmp/opencode/rev
cd "$FPGA"
mkdir -p "$FPGA/build/review" "$RW/pletdir"
rm -rf "$FPGA/build/review/soc"
mkdir -p "$FPGA/build/review/soc"
echo "> LiteX flat gateware gen (see $RW/eln.log)"
uv run --with meson --with ninja python -m soc.zigmachine_soc --target z7 \
  --out "$FPGA/build/review/soc" > "$RW/eln.log" 2>&1
G="$FPGA/build/review/soc/gateware"
[ -f "$G/platform_z7.v" ] || { tail -40 "$RW/eln.log"; exit 1; }
rm -rf "$RW/pletdir"; mkdir -p "$RW/pletdir"
cp "$G/platform_z7.v" "$RW/pletdir/"
sed 's#build/board_main/gateware/platform_z7.v#build/review/soc/gateware/platform_z7.v#' \
  build/board_main/gateware/platform_z7.tcl > "$RW/pletdir/platform_z7.tcl"
cp build/board_main/gateware/platform_z7.xdc "$RW/pletdir/"
cd "$RW/pletdir" && vivado -mode batch -source platform_z7.tcl -log vivado.log -journal vivado.jou >/dev/null 2>&1
test -s platform_z7_route_status.rpt
echo "soc plet done -> $RW/pletdir"
