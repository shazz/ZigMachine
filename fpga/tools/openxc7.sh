#!/usr/bin/env bash
# openXC7 (yosys + nextpnr-xilinx + Project X-Ray) in Docker, for the Z7-Lite's
# XC7Z010-1CLG400. Nothing is installed on the host: the image is built from
# docker/openxc7/ (pinned), and the repo is mounted at its own path so every
# path LiteX writes into a build script is valid on both sides.
#
#   openxc7.sh image                 build the image (once; tagged by its recipe's hash)
#   openxc7.sh db                    copy the pinned prjxray-db zynq7/ to .tools/prjxray-db/
#   openxc7.sh chipdb                nextpnr chipdb for xc7z010 -> .tools/chipdb/ (heavy, once)
#   openxc7.sh toolchain             all three
#   openxc7.sh bit TOP OUT XDC V...  synth -> pnr -> fasm -> frames -> OUT/TOP.bit
#   openxc7.sh run CMD...            any command in the container, cwd preserved
#
# OPENXC7_MEM caps every container's memory (default 8g: the box is shared).
set -euo pipefail

FPGA="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$FPGA/.." && pwd)"
RECIPE="$FPGA/docker/openxc7"
TAG="$(cat "$RECIPE/Dockerfile" "$RECIPE/entry.sh" "$RECIPE/flake.nix" "$RECIPE/flake.lock" | sha256sum | cut -c1-12)"
IMAGE="zm-openxc7:$TAG"
MEM="${OPENXC7_MEM:-8g}"
PART=xc7z010clg400-1
DBPART=xc7z010clg400  # LiteX and openXC7.mk look up $CHIPDB/$DBPART.bin
export CHIPDB="$FPGA/.tools/chipdb"
export PRJXRAY_DB_DIR="$FPGA/.tools/prjxray-db"
# The chipdb built from the pins above (docker/openxc7/chipdb.sha256).
CHIPDB_SHA_FILE="$RECIPE/chipdb.sha256"

die() { echo "openxc7: $*" >&2; exit 1; }

image() {
    command -v docker >/dev/null || die "docker not found"
    docker image inspect "$IMAGE" >/dev/null 2>&1 && return 0
    echo "openxc7: building $IMAGE (nix build of the pinned tools, ~15 min once)"
    docker build --memory "$MEM" -t "$IMAGE" "$RECIPE"
}

run() {  # run CMD...: in the container, as the caller, repo at its own path
    image
    docker run --rm --memory "$MEM" --user "$(id -u):$(id -g)" \
        -v "$ROOT:$ROOT" -w "$PWD" \
        -e CHIPDB \
        "$IMAGE" "$@"
}

db() {
    [ -f "$PRJXRAY_DB_DIR/zynq7/$PART/part.yaml" ] && return 0
    mkdir -p "$PRJXRAY_DB_DIR"
    # Inside, the image's env sets PRJXRAY_DB_DIR to its own (nix store) copy.
    run bash -c 'cp -r "$PRJXRAY_DB_DIR/zynq7" "$1/" && chmod -R u+w "$1/zynq7"' _ "$PRJXRAY_DB_DIR"
    [ -f "$PRJXRAY_DB_DIR/zynq7/$PART/part.yaml" ] || die "prjxray-db has no $PART"
}

chipdb() {
    local bin="$CHIPDB/chipdb-xc7z010.bin"
    db
    if [ ! -f "$bin" ]; then
        mkdir -p "$CHIPDB"
        echo "openxc7: generating the xc7z010 chipdb (memory capped at $MEM)"
        run bash -c 'set -euo pipefail
            python3 "$XILINX_GEN" --xray "$1/zynq7" --device xc7z010 --bba "$2/xc7z010.bba"
            bbasm -l "$2/xc7z010.bba" "$2/chipdb-xc7z010.bin.tmp"
            rm -f "$2/xc7z010.bba"; mv "$2/chipdb-xc7z010.bin.tmp" "$2/chipdb-xc7z010.bin"' \
            _ "$PRJXRAY_DB_DIR" "$CHIPDB"
    fi
    ln -sf chipdb-xc7z010.bin "$CHIPDB/$DBPART.bin"
    if [ -f "$CHIPDB_SHA_FILE" ]; then
        (cd "$CHIPDB" && sha256sum -c --quiet "$CHIPDB_SHA_FILE") \
            || die "chipdb differs from $CHIPDB_SHA_FILE (different pins?)"
    else
        (cd "$CHIPDB" && sha256sum chipdb-xc7z010.bin) > "$CHIPDB_SHA_FILE"
        echo "openxc7: recorded $(cat "$CHIPDB_SHA_FILE")"
    fi
}

xdc_for() {  # xdc_for BOARD_XDC TOP_V: the board's lines for the top's ports only
    local ports
    ports=$(grep -oE '^\s*(input|output|inout)\s+(wire|reg)?\s*(\[[^]]*\])?\s*\w+' "$2" \
        | awk '{print $NF}' | paste -sd'|')
    [ -n "$ports" ] || die "no ports found in $2"
    grep -E "get_ports\s+\{?\s*($ports)(\[[0-9]+\])?\s*\}?\s*\]" "$1"
}

bit() {  # bit TOP OUT XDC VERILOG...
    local top=$1 out=$2 xdc=$3; shift 3
    [ -f "$CHIPDB/$DBPART.bin" ] || chipdb
    mkdir -p "$out"
    run bash -c 'set -euo pipefail
        top=$1 out=$2 xdc=$3 part=$4 chipdb=$5 db=$6; shift 6
        cd "$out"
        yosys -q -l synth.log -p "read_verilog -sv $*; synth_xilinx -flatten -abc9 -arch xc7 -top $top; tee -o utilization.txt stat; write_json $top.json"
        nextpnr-xilinx --chipdb "$chipdb" --xdc "$xdc" --json "$top.json" \
            --write "${top}_routed.json" --fasm "$top.fasm" --report report.json --log pnr.log
        fasm2frames --part "$part" --db-root "$db/zynq7" "$top.fasm" > "$top.frames"
        xc7frames2bit --part_file "$db/zynq7/$part/part.yaml" --part_name "$part" \
            --frm_file "$top.frames" --output_file "$top.bit"' \
        _ "$top" "$out" "$xdc" "$PART" "$CHIPDB/$DBPART.bin" "$PRJXRAY_DB_DIR" "$@"
    echo "openxc7: $out/$top.bit"
}

cmd=${1:-}; shift || true
case "$cmd" in
    image) image ;;
    db) db ;;
    chipdb) chipdb ;;
    toolchain) image; db; chipdb ;;
    bit) [ $# -ge 4 ] || die "usage: bit TOP OUT XDC VERILOG..."; bit "$@" ;;
    xdc) xdc_for "$@" ;;
    run) run "$@" ;;
    *) sed -n '2,14p' "$0"; exit 2 ;;
esac
