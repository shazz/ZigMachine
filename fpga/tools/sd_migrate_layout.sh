#!/bin/sh
# Move a KESTREL SD card to the layout of 6 Nov 2026 (decisions.md; fpga/tools/sd_layout.py,
# fpga/glass/src/layout.zig). Runs ON THE BOARD (busybox sh), over the serial console or ssh:
#
#   sh sd_migrate_layout.sh [--dry-run] [--back] [CARD]       CARD: default /mnt/sd
#
#   /            the boot files stay: BOOT.BIN, u-boot.img, boot.scr, zImage, zigmachine.dtb,
#                rootfs.cpio.uboot, zigmachine.bit, uImage, rootfs.ub, zest*, uboot.env,
#                authorized_keys, and every copy of them (*.prev, NAME.<hash>)
#   zigmachine/  system.rv32, kos/, progs/, glass.cfg -> KESTREL/; everything else (shelf.txt,
#                the category folders) -> CARTS/
#   /<other>     every other file or folder at the root (rollback_*, an old `glass`, MANIFEST.txt)
#                -> KESTREL/rollback/ (an old glass must NOT become KESTREL/glass: S99glass would run it)
#   HD/          made, empty: KOS's C:
#
# mkdir and mv only: nothing is deleted or overwritten (a name already at the target is skipped and
# said). Run it again and it moves nothing. --back moves it all back (for the old rootfs, whose
# S99glass runs `glass run /mnt/sd/zigmachine`), then removes the folders it emptied (rmdir: an
# emptied folder only). /mnt/sd is remounted read-write for the moves and read-only after.
set -u
DRY=0 BACK=0 CARD=/mnt/sd
for a in "$@"; do
    case "$a" in
    --dry-run) DRY=1 ;;
    --back) BACK=1 ;;
    -*) echo "usage: $0 [--dry-run] [--back] [CARD]" >&2; exit 2 ;;
    *) CARD=$a ;;
    esac
done
[ -d "$CARD" ] || { echo "sd_migrate: no $CARD" >&2; exit 1; }
cd "$CARD" || exit 1
MOVED=0 SKIPPED=0

# mv_one SRC DEST_DIR: SRC (relative to CARD) into DEST_DIR, keeping its name, never over a name.
mv_one() {
    to="$2/$(basename "$1")"
    if [ -e "$to" ]; then
        echo "skip $1: $to is there already"; SKIPPED=$((SKIPPED + 1)); return
    fi
    echo "mv $1 $to"
    MOVED=$((MOVED + 1))
    [ "$DRY" = 1 ] && return
    mkdir -p "$2" && mv "$1" "$to" || { echo "sd_migrate: mv $1 failed" >&2; exit 1; }
}

is_boot() {
    case "$1" in
    BOOT.BIN* | boot.bin* | u-boot.img* | boot.scr* | zImage* | zigmachine.dtb* | zigmachine.bit* | \
        rootfs.cpio.uboot* | uImage* | rootfs.ub* | zest* | uboot.env* | authorized_keys* | *.prev | \
        "System Volume Information" | KESTREL | CARTS | HD | zigmachine) return 0 ;;
    esac
    return 1
}

is_system() {
    case "$1" in system.rv32* | kos | progs | glass.cfg*) return 0 ;; esac
    return 1
}

forward() {
    if [ -d zigmachine ]; then
        for f in zigmachine/*; do
            [ -e "$f" ] || continue
            n=$(basename "$f")
            if is_system "$n"; then
                mv_one "$f" KESTREL
            elif [ "$n" = glass ] || [ "${n#glass.}" != "$n" ]; then
                mv_one "$f" KESTREL/rollback # an old glass binary: never the override
            else
                mv_one "$f" CARTS
            fi
        done
    fi
    for f in *; do
        [ -e "$f" ] || continue
        is_boot "$f" || mv_one "$f" KESTREL/rollback
    done
    if [ ! -d HD ]; then
        echo "mkdir HD"
        [ "$DRY" = 1 ] || mkdir HD
    fi
}

back() {
    for f in KESTREL/*; do
        [ -e "$f" ] || continue
        case "$(basename "$f")" in
        rollback) ;;
        glass) [ -e glass.kestrel ] || { echo "mv $f glass.kestrel"; [ "$DRY" = 1 ] || mv "$f" glass.kestrel; } ;;
        *) mv_one "$f" zigmachine ;;
        esac
    done
    for f in KESTREL/rollback/* CARTS/*; do
        [ -e "$f" ] || continue
        case "$f" in KESTREL/*) mv_one "$f" . ;; *) mv_one "$f" zigmachine ;; esac
    done
    [ "$DRY" = 1 ] || rmdir KESTREL/rollback KESTREL CARTS 2>/dev/null
}

remount() {
    [ "$DRY" = 1 ] || [ "$CARD" != /mnt/sd ] || mount -o "remount,$1" /mnt/sd || { echo "sd_migrate: remount $1 failed" >&2; exit 1; }
}

remount rw
trap 'sync; remount ro' EXIT # read-only again whatever happens (a failed mv exits)
if [ "$BACK" = 1 ]; then back; else forward; fi
echo "sd_migrate: $MOVED moved, $SKIPPED skipped$([ "$DRY" = 1 ] && echo ' (dry run: nothing moved)')"
[ "$BACK" = 1 ] || [ "$DRY" = 1 ] || echo "sd_migrate: undo with: sh $0 --back${CARD:+ $CARD}"
