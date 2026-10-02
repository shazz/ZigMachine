#!/usr/bin/env bash
# Fetches the MicroPhase Z7-Lite 7010 board files into
# boards/microphase_z7_7010/, pinned to commits and checksummed. None of it is
# committed: MicroPhase's XDC says "Publication of this design is not authorized
# without written consent", and the rest is third-party (see that board's README).
#
#   board.xdc                 MicroPhase's Z7_LITE.xdc (identical pin map in 3 public
#                             copies; every HDMI pin re-derived from the schematic)
#   vendor/Z7-LITE_R11.pdf    schematic        vendor/…Reference_Manual.md
#   vendor/xc7z010clg400pkg.txt  Xilinx package pinout (pin function -> ball)
#   vendor/zest/…             zeST (GPL-3): its Z7-Lite XDC and the Vivado PS7 config
#   vendor/zest-bin/…/z7lite_7010/boot.bin  zeST's prebuilt FSBL+U-Boot for the 7010:
#                             a working PS7 init (DDR3, clocks, MIO) without Vivado
set -euo pipefail

FPGA="$(cd "$(dirname "$0")/.." && pwd)"
BOARD="$FPGA/boards/microphase_z7_7010"
V="$BOARD/vendor"
mkdir -p "$V/zest/xdc" "$V/zest/vivado" "$V/zest-bin"

GH=https://raw.githubusercontent.com
LEE=$GH/leecurrent04/MicroPhase-Z7-Lite-Board/d87ba6145563e50900b5e387691277036c755957/board_files/Z7-Lite_7010/1.0
MPH=$GH/MicroPhase/fpga-docs/05189b9f0ebb74bbb59b9365c5a2d01ac2a8b265
ZEST=https://codeberg.org/zerkman/zest/raw/commit/057e6e45a6c7782179c7b8d19ae1e2a911578440
ZBIN=zeST-20260518.tar.xz

get() {  # get <url> <dest> <sha256>
    local url=$1 dest=$2 sha=$3
    [ -f "$dest" ] || curl -fsSL -A "Mozilla/5.0" -o "$dest" "$url"
    if ! echo "$sha  $dest" | sha256sum -c --quiet -; then
        echo "fetch_board: checksum mismatch for $dest (deleted, re-run to retry)" >&2
        rm -f "$dest"
        exit 1
    fi
}

get "$LEE/Z7_LITE.xdc" "$V/Z7_LITE.xdc" e977e1f79510a4d3585fd7cfb74a711fe02666d8a60a9a12da271c2e03adfa3c
get "$MPH/schematic/Z7-LITE_R11.pdf" "$V/Z7-LITE_R11.pdf" 7e6c992efc270e7884f4c9517f0966b43084a5621b0695bb6c37710de6d6e5ea
get "$MPH/source/DEV_BOARD/Z7-LITE/Z7-Lite_Reference_Manual.md" "$V/Z7-Lite_Reference_Manual.md" \
    eb12c24f0864f273cc120452a121f16253b94582f7d80aeeaf8e5f58f80460c9
get https://www.xilinx.com/content/dam/xilinx/support/packagefiles/z7packages/xc7z010clg400pkg.txt \
    "$V/xc7z010clg400pkg.txt" c40e04844e7144e0318a7fa8904f028c9699ffc153ca6f3170d04f025012cf68
get "$ZEST/xdc/z7lite.xdc" "$V/zest/xdc/z7lite.xdc" 006543fbe4d7ad6310869a96e49d0607f14926b3dec3ad80ba97594097d24f69
get "$ZEST/vivado/zest_z7lite.tcl" "$V/zest/vivado/zest_z7lite.tcl" \
    a87548d00e8110eb789747361cb7a1be9ab175aebec566d5019c19953740c9de
get "$ZEST/LICENSE" "$V/zest/LICENSE" 3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986
get "https://zest.sector1.fr/download/$ZBIN" "$V/zest-bin/$ZBIN" \
    bdc1081ba9b57a56b94ebf51dac7c59e2cadc0c8a9af922a1936408c2bfacc60
tar xJf "$V/zest-bin/$ZBIN" -C "$V/zest-bin" zeST-20260518/boards/z7lite_7010/boot.bin

cp "$V/Z7_LITE.xdc" "$BOARD/board.xdc"
echo "fetch_board: board.xdc + vendor/ ready in $BOARD"
