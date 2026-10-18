#!/bin/sh
# Build the carts and the ROM WITH function names (zig build -Dnames=true) into
# zig-out/perf-names/docs, for apps/frame_cost.mjs and apps/perf_audit.mjs: release carts
# are stripped, so without this twin their reports say f123 instead of a function name.
# The twin is used only while its code is byte-identical to docs/ (apps/perf/names.mjs),
# so rerun this after a rebuild. It is a full zig build: run it under the build lock,
#   prototypes/_gate_logs/gate_lock.sh tools/perf_names.sh
set -e
cd "$(dirname "$0")/.."
mkdir -p zig-out/perf-names
zig build -Drelease=true -Dwasm -Dnames=true -p zig-out/perf-names/zig-out
echo "perf names: $(ls zig-out/perf-names/docs/*.wasm | wc -l) modules in zig-out/perf-names/docs"
