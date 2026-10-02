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
