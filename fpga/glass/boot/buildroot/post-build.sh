#!/bin/sh
# Buildroot post-build: put the glass program into the rootfs. It is a static
# Zig binary built outside Buildroot (fpga/glass), so no toolchain is shared:
#   (cd fpga/glass && zig build -Dtarget=arm-linux-musleabihf -Dcpu=cortex_a9 \
#        -Doptimize=ReleaseSafe --prefix zig-out/arm)
set -e
GLASS="$BR2_EXTERNAL_ZIGMACHINE_PATH/../../zig-out/arm/bin/glass"
if [ ! -x "$GLASS" ]; then
    echo "post-build: $GLASS is missing: build the ARM glass first (see this script)" >&2
    exit 1
fi
install -D -m 0755 "$GLASS" "$TARGET_DIR/usr/bin/glass"
# Buildroot's strip pass ran before this script, so the raw zig-out binary
# (debug_info, symtab: 3.4 MB) would reach the rootfs unstripped (0.5 MB stripped).
# Post-build scripts get HOST_DIR, not TARGET_CROSS: the toolchain's own strip.
STRIP=$(ls "$HOST_DIR"/bin/*-buildroot-linux-*-strip | head -n 1)
"$STRIP" "$TARGET_DIR/usr/bin/glass"
# The stock multi_v7 module tree is 31 MB of a 37 MB rootfs and nothing loads it:
# everything the glass needs is =y in linux.fragment. (CONFIG_MODULES=n is not
# the fix: Kconfig then turns every =m into =y, and the zImage grew 11.9 -> 18.3 MB.)
rm -rf "$TARGET_DIR/lib/modules"
# Wi-Fi firmware: linux-firmware's BCM43XXX set is ~20 chips; the board's dongle is the
# BCM43143 (fpga/docs/PREREQUISITES.md). Keep only the files named in WIFI_FW_KEEP (one
# basename a word, under brcm/); add another dongle's file there.
WIFI_FW_KEEP="brcmfmac43143.bin"
if [ -d "$TARGET_DIR/lib/firmware/brcm" ]; then
    for f in "$TARGET_DIR"/lib/firmware/brcm/*; do
        case " $WIFI_FW_KEEP " in *" $(basename "$f") "*) ;; *) rm -rf "$f" ;; esac
    done
fi
