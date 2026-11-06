#!/usr/bin/env bash
# Plan A, the whole boot stack from source (docs/FPGA_GLASS.md, "Plan A"): our own BOOT.BIN
# (U-Boot SPL + u-boot.img), the kernel, its DTB and the rootfs with /usr/bin/glass.
#
#   fpga/glass/boot/build_planA.sh [--stage DIR [--stage-only]]
#
#   1. here: the ARM glass (zig) and ps7_init_gpl.c, read out of zeST's FSBL
#      (fpga/tools/ps7_from_bootbin.py; needs fpga/tools/fetch_board.sh once)
#   2. on BUILD_HOST (default omarchy; "local" = this machine), in BUILD_DIR (default br,
#      relative to its home): Buildroot $BR_VERSION with this external tree, ~1 h the first time
#   3. here: the images in fpga/build/planA/images; with --stage, a card dir (below) + md5s
#
# The card dir holds BOOT.BIN.ours (renamed so a copy onto the card does not replace
# zeST's BOOT.BIN by accident), u-boot.img, zImage, zigmachine.dtb, rootfs.cpio.uboot and
# boot.scr.planA (boot.cmd: plan A when a zImage is on the card) and zest.dtb (plan B's tree
# under our BOOT.BIN). Nothing touches a device.
# BR_DL_SEED=<dir>: a Buildroot dl/ to copy first (saves the downloads).
set -euo pipefail

BR_VERSION=2026.02.3
BR_SHA256=5a59e7501b0b4ec52c41f4bfa79412320e0b37eae5f719605a258e8d0c6fc7fb
HOST=${BUILD_HOST:-omarchy}
DIR=${BUILD_DIR:-br}
BOOT="$(cd "$(dirname "$0")" && pwd)"
FPGA="$(cd "$BOOT/../.." && pwd)"
GLASS="$FPGA/glass/zig-out/arm/bin/glass"
ZEST_BOOT=${ZEST_BOOT:-"$FPGA/boards/microphase_z7_7010/vendor/zest-bin/zeST-20260518/boards/z7lite_7010/boot.bin"}
IMAGES="$FPGA/build/planA/images"
STAGE=
[ "${1:-}" = "--stage" ] && STAGE=${2:?--stage needs a directory}

say() { echo "build_planA: $*" >&2; }

host_side() {  # the ARM glass and the PS7 init, built here
    (cd "$FPGA/glass" && zig build -Dtarget=arm-linux-musleabihf -Dcpu=cortex_a9 -Doptimize=ReleaseSafe \
        --prefix zig-out/arm)
    [ -f "$ZEST_BOOT" ] || { say "no zeST boot.bin: run fpga/tools/fetch_board.sh"; exit 1; }
    python3 "$FPGA/tools/ps7_from_bootbin.py" "$ZEST_BOOT" "$BOOT/uboot/ps7_init_gpl.c"
}

remote() { if [ "$HOST" = local ]; then (cd && bash -c "$1"); else ssh -o BatchMode=yes "$HOST" "$1"; fi; }
put() {  # put <src> <dest under DIR>
    if [ "$HOST" = local ]; then rsync -a "$1" "$HOME/$DIR/$2"; else rsync -a "$1" "$HOST:$DIR/$2"; fi
}
get() {  # get <src under DIR> <dest>
    if [ "$HOST" = local ]; then rsync -a "$HOME/$DIR/$1" "$2"; else rsync -a "$HOST:$DIR/$1" "$2"; fi
}

sync_tree() {  # the external tree as fpga/glass/boot + the glass, at the paths post-build.sh expects
    remote "mkdir -p $DIR/zm/fpga/glass/zig-out/arm/bin $DIR/dl $DIR/tools/bin"
    put "$BOOT/" zm/fpga/glass/boot/
    put "$GLASS" zm/fpga/glass/zig-out/arm/bin/glass
    [ -z "${BR_DL_SEED:-}" ] || put "$BR_DL_SEED/" dl/
    remote "command -v wget >/dev/null" || put "$BOOT/host-tools/wget" tools/bin/wget
    remote "PATH=\$HOME/$DIR/tools/bin:\$PATH command -v bc >/dev/null" \
        || { say "$HOST has no bc (the kernel build needs it): put one in ~/$DIR/tools/bin"; exit 1; }
}

buildroot() {  # Buildroot on the build host; it resumes where it stopped if run again
    remote "set -e; cd $DIR; export PATH=\$HOME/$DIR/tools/bin:\$PATH
        [ -d buildroot-$BR_VERSION ] || {
            [ -f buildroot-$BR_VERSION.tar.xz ] || curl -fsSL -o buildroot-$BR_VERSION.tar.xz \
                https://buildroot.org/downloads/buildroot-$BR_VERSION.tar.xz
            echo '$BR_SHA256  buildroot-$BR_VERSION.tar.xz' | sha256sum -c --quiet -
            tar xJf buildroot-$BR_VERSION.tar.xz; }
        make -C buildroot-$BR_VERSION O=\$HOME/$DIR/out BR2_DL_DIR=\$HOME/$DIR/dl \
            BR2_EXTERNAL=\$HOME/$DIR/zm/fpga/glass/boot/buildroot zigmachine_z7lite_defconfig >/dev/null
        make -C buildroot-$BR_VERSION O=\$HOME/$DIR/out BR2_DL_DIR=\$HOME/$DIR/dl > build.log 2>&1 \
            || { tail -40 build.log; exit 1; }
        # SPL without the board's PS7 init would boot with no DDR: refuse such an image.
        ls out/build/uboot-*/spl/board/xilinx/zynq/zynq-z7lite/ps7_init_gpl.o >/dev/null"
}

stage() {  # stage <dir>: the card files + md5s
    mkdir -p "$1"
    cp "$IMAGES/boot.bin" "$1/BOOT.BIN.ours"
    cp "$IMAGES/u-boot.img" "$IMAGES/zImage" "$IMAGES/rootfs.cpio.uboot" "$1/"
    cp "$IMAGES/zigmachine-z7lite.dtb" "$1/zigmachine.dtb"
    python3 "$FPGA/tools/uboot_script.py" "$BOOT/boot.cmd" "$1/boot.scr.planA"
    # zeST's DTB (its BOOT.BIN's partition loaded at 0x800000; GPL-3, zeST release 20260518):
    # plan B's bootm takes it from there, and our SPL does not put it there (RECOVERY.md).
    python3 - "$ZEST_BOOT" "$1/zest.dtb" <<'EOF'
import struct, sys
d = open(sys.argv[1], "rb").read()
pht = struct.unpack_from("<I", d, 0x9C)[0]
for i in range(16):
    words = struct.unpack_from("<16I", d, pht + 64 * i)
    at = words[5] * 4
    if words[3] == 0x800000 and d[at : at + 4] == bytes.fromhex("d00dfeed"):
        open(sys.argv[2], "wb").write(d[at : at + struct.unpack_from(">I", d, at + 4)[0]])
        break
else:
    sys.exit("no DTB partition at 0x800000 in " + sys.argv[1])
EOF
    (cd "$1" && md5sum BOOT.BIN.ours u-boot.img zImage zigmachine.dtb rootfs.cpio.uboot boot.scr.planA zest.dtb \
        > MD5SUMS)
    cat "$1/MD5SUMS"
}

if [ "${3:-}" = "--stage-only" ]; then stage "$STAGE"; exit 0; fi  # the images already in $IMAGES

host_side
sync_tree
say "Buildroot $BR_VERSION on $HOST:~/$DIR (log: ~/$DIR/build.log)"
buildroot
mkdir -p "$IMAGES"
get out/images/ "$IMAGES/"
say "images in $IMAGES"
[ -z "$STAGE" ] || stage "$STAGE"
