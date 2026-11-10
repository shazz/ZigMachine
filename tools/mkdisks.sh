#!/bin/sh
# Repack every ZigMachine .zmd disk image from the built wasm carts.
#
# WHY THIS EXISTS: the disks used to be build output with no recipe. They drifted
# a week behind the wasm and froze an import list that no longer matched the host,
# so every disk on the shelf failed to instantiate (4c00b19) — the metadata was
# only recoverable by reading the images back. Packing is now a command.
#
# Every disk below was verified against the descriptor of the image it replaces
# (title / author / date / bootability / FAT), so a repack is byte-faithful apart
# from the cart itself and the build date.
#
# Usage:  tools/mkdisks.sh [-f]     -f / --force: repack even if up to date
#         ZMD_DATE=YYYYMMDD tools/mkdisks.sh      pin the stamped date
#
# A disk is rewritten only when its CONTENT changes. Every image is packed again
# with the date the existing disk already carries; if that reproduces the disk
# byte for byte, it is left alone, so an unchanged disk keeps its bytes and date.
# Only a disk whose cart or files really changed is stamped with today's date.
# (This used to compare file timestamps, which a fresh checkout or worktree
# resets, so every build re-stamped all of them and dirtied every commit.)
set -e
cd "$(dirname "$0")/.."

OUT=docs
MK=tools/mkdisk.py
AUTHOR=ZigMachine
DATE=${ZMD_DATE:-$(date +%Y%m%d)}
FORCE=""
[ "$1" = "-f" ] || [ "$1" = "--force" ] && FORCE=1

# Wasm in docs/ that are NOT bootable carts and get no disk:
#   machine-*  sealed hardware      demo-audio  worklet module, not a cart
#   boot-*     v2 boot sectors      demo-c/rust polyglot demos (run via ?demo=)
#   *bootloader/audio  retired legacy monolith
SKIP="machine-video machine-audio demo-audio bootloader audio boot-novirus boot-replicants_emlyn boot-sdl demo-c demo-rust demo-tutorial_steps demo-c-tutorial_steps demo-rust-tutorial_steps"

packed=0; skipped=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# repack <out.zmd> <mkdisk args...>: write out only if its content changed.
repack() {
    out=$1; shift
    if [ -z "$FORCE" ] && [ -f "$out" ]; then
        trial="$TMP/$(basename "$out")"
        python3 "$MK" "$@" -o "$trial" --date "$DATE" --date-from "$out" > /dev/null
        if cmp -s "$trial" "$out"; then skipped=$((skipped+1)); return; fi
    fi
    python3 "$MK" "$@" -o "$out" --date "$DATE"
    packed=$((packed+1))
}

# Every cart goes on its disk ZX0-PACKED (about a tenth of the size; ST Replay's
# 1.6 MB of zero-filled RAM becomes 9 KB). The machine unpacks it when it loads
# the disk: sealed-loader.js hands the bytes to the ROM chip's romDepack. Packing
# is deterministic, so an unchanged cart still reproduces its disk byte for byte.
ZX0PACK=zig-out/bin/zx0pack
[ -x "$ZX0PACK" ] || { echo "mkdisks: $ZX0PACK is missing: run zig build first"; exit 1; }
# Packing every cart costs most of this script's time, and the same cart bytes
# always pack to the same bytes. So packed copies are cached (zig-out/, ignored)
# under the hash of the cart AND of the packer: a rebuilt zx0pack is a new key,
# never a stale hit. The disk is still rebuilt and compared byte for byte below.
ZX0CACHE=zig-out/zx0cache
mkdir -p "$ZX0CACHE"
PACKER_KEY=$(sha256sum "$ZX0PACK" | cut -c1-16)
packcart() { # packcart <cart.wasm> -> prints the packed copy's path
    dst="$ZX0CACHE/$PACKER_KEY-$(sha256sum "$1" | cut -c1-32).zx0"
    if [ ! -s "$dst" ]; then
        "$ZX0PACK" "$1" "$dst.$$" > /dev/null
        mv "$dst.$$" "$dst"
    fi
    echo "$dst"
}

pack() { # pack <out.zmd> <title> <cart.wasm> [extra mkdisk args...]
    out=$1 title=$2 cart=$3; shift 3
    if [ ! -f "$cart" ]; then echo "  -- $out: no $cart, skipped"; skipped=$((skipped+1)); return; fi
    repack "$out" "$(packcart "$cart")" --title "$title" --author "$AUTHOR" "$@"
}

# portdisk <tag> <cart.wasm> [--file ...]: a C program port's DATA disk (see the case below),
# carrying the shared "SDL" boot sector (docs/boot-sdl.wasm, apps/zig/boot/sdl.zig): a v2 disk whose
# descriptor names no cart, so the sector runs, then GEM follows (SysInfo's "No virus" pattern).
portdisk() {
    tag=$1 cart=$2; shift 2
    [ -f "$OUT/boot-sdl.wasm" ] || { echo "mkdisks: $OUT/boot-sdl.wasm is missing: run zig build first"; exit 1; }
    pack "$OUT/demo-$tag.zmd" "$tag" "$cart" --no-boot --boot-wasm "$OUT/boot-sdl.wasm" "$@"
}

# --- the menu ------------------------------------------------------------
pack "$OUT/demo.zmd" "ZigMachine Menu" "$OUT/demo.wasm"

# --- scene disks: one per demo-<tag>.wasm, title = tag ------------------
# A new scene gets a disk automatically — that is the point of deriving the list
# from the build output rather than hardcoding it here.
for w in "$OUT"/demo-*.wasm; do
    tag=$(basename "$w" .wasm); tag=${tag#demo-}
    case " $SKIP " in *" demo-$tag "*|*" $tag "*) continue;; esac
    # Polyglot carts (demo-c-*, demo-rust-*) run via ?demo=, not from a
    # floppy, and there is one per scene — so skip the whole family rather
    # than naming each new one in SKIP and finding out by a failed pack.
    # EXCEPT a polyglot cart the menu lists (its tag is in catalog.zig): the
    # menu and the +/- channels boot scenes from demo-<tag>.zmd, so it needs one.
    case "$tag" in
        c-*|rust-*) grep -q "\.tag = \"$tag\"" apps/zig/scenes/catalog.zig || continue ;;
    esac
    case "$tag" in
        # REPLICANTS / Emlyn Hughes is a FORMAT V2 disk: its block 0 is an
        # executable boot sector (the crew's note about the SPACE key), which
        # chainloads the cart. The boot program is the screen's own, so it is
        # named here next to the disk it belongs to.
        replicants_emlyn)
                   BOOTSEC="$OUT/boot-replicants_emlyn.wasm"
                   if [ -f "$BOOTSEC" ]; then
                       pack "$OUT/demo-$tag.zmd" "$tag" "$w" --boot-wasm "$BOOTSEC"
                   else
                       echo "  !! $BOOTSEC missing: demo-$tag packed WITHOUT its boot sector"
                       pack "$OUT/demo-$tag.zmd" "$tag" "$w"
                   fi ;;
        # ST Replay ships as a DATA disk: not executable, so the machine boots
        # GEM, which opens the app and reads its sample off the same disk.
        st_replay) pack "$OUT/demo-$tag.zmd" "$tag" "$w" --no-boot \
                        --file "SAMPLE.RAW=$OUT/music/smp1.raw" ;;
        # SysInfo is a GEM program the same way: its disk is a data disk, GEM opens
        # it and runs BOOT.WSM, and Q (request 4) quits back to the desktop. As a
        # bootable disk it had no OS to return to, which is why it could not quit
        # on the board.
        # It also carries the "No virus in ZigMachine" boot sector, as an ST data
        # disk carries an antivirus one: a v2 disk whose descriptor names NO cart,
        # so the sector runs, then GEM follows (docs/FLOPPY_DISK.md). And five
        # sound files its SOUND page reads off the disk and plays: an SNDH (YM
        # only), a SAP (POKEY), a second of signed 8-bit PCM (ST Replay's), an XM
        # (Drozerix's public-domain Keygen 9000) and a Hippel module (the musicdisk's
        # Thalion intro). Those two and the SNDH go on ZX0-packed (packcart: the
        # "ZX0!" container) as Matt's floppy is small (the SNDH saves 3 blocks);
        # the app depacks them as it reads them. And a klystrack song for the .kt
        # player on BARD: upstream's STARPORT2 example (MIT, apps/ports/klystrack/
        # LICENSE), unpacked: 1822 bytes, packing it saves nothing worth a block.
        # And a C64 tune for the .sid player (cRSID on BARD): HerMiniSID by Hermit, cRSID's own
        # test tune (379 bytes, unpacked), the one SID TEST ships.
        sysinfo)   BOOTSEC="$OUT/boot-novirus.wasm"
                   [ -f "$BOOTSEC" ] || { echo "mkdisks: $BOOTSEC is missing: run zig build first"; exit 1; }
                   pack "$OUT/demo-$tag.zmd" "$tag" "$w" --no-boot --boot-wasm "$BOOTSEC" \
                        --file "JINKS.SND=$(packcart "$OUT/music/Jinks.sndh")" \
                        --file "GAUNTLET.SAP=$OUT/music/Gauntlet.sap" \
                        --file "SAMPLE.RAW=$OUT/music/smp1_short.raw" \
                        --file "KEYGEN.XM=$(packcart "$OUT/music/keygen_9000.xm")" \
                        --file "THALION.HIP=$(packcart "$OUT/music/hippel/thalion_intro.hip")" \
                        --file "STARPORT.KT=$OUT/music/starport2.kt" \
                        --file "HERMINI.SID=$OUT/music/hermini.sid" ;;
        # NOTEPAD is a GEM program as ST Replay and SysInfo are: a DATA disk, GEM opens it, BOOT.WSM
        # is double-clicked, ^Q goes back to the desktop (request 4). Its files are on C: (KOS GEMDOS).
        notepad)   pack "$OUT/demo-$tag.zmd" "$tag" "$w" --no-boot ;;
        # GEMTEST too (docs/GEMTEST.md): a data disk, BOOT.WSM shows every GEM 5 component.
        gemtest)   pack "$OUT/demo-$tag.zmd" "$tag" "$w" --no-boot ;;
        # STNICCC 2000 streams its polygon data off the disk, 64 KB at a time.
        stniccc)   pack "$OUT/demo-$tag.zmd" "$tag" "$w" \
                        --file "SCENE1.BIN=apps/zig/assets/screens/stniccc/scene1.bin" ;;
        # The streaming demo carries the track it block-streams.
        stream)    pack "$OUT/demo-$tag.zmd" "$tag" "$w" \
                        --file "MICROMIX.RAW=$OUT/music/micromix30.raw" ;;
        # The C program ports (apps/ports) are GEM programs on DATA disks, as ST Replay and SysInfo:
        # the machine boots GEM over the disk, the FLOPPY window lists the program (BOOT.WSM) beside
        # its files, a double-click runs it (request 3) and its quit brings the desktop back (request
        # 4, apps/ports/kestrel_sdl2/src/kestrel_quit.c). The program reads its files off the same
        # disk (kestrel_wasi.c). portdisk adds the shared "SDL" boot sector (docs/boot-sdl.wasm: it
        # runs, then GEM follows, as SysInfo's "No virus" one). Their carts are committed prebuilt;
        # their files come from
        # apps/ports/<port>/, named one by one (a glob's order follows the locale, and the disk
        # must be the same bytes on every machine), with 8.3 names (GEM shows 12 at most).
        # pt2-clone: two public-domain modules for its DISK OP to load.
        pt2)       portdisk "$tag" "$w" \
                        --file "RONKEN.MOD=$OUT/music/ronken.mod" \
                        --file "HYBRID.MOD=$OUT/music/hybridglenz.mod" ;;
        # GrafX2: its default skin, font and ini (data/), and our own pictures (ownpics/).
        # Pictures ripped from other people's work never go on this disk. The skin and the font
        # keep GrafX2's own names: its skin and font pickers list files by their skin_/font_ prefix.
        grafx2)    P=apps/ports/grafx2
                   portdisk "$tag" "$w" \
                        --file "gfx2def.ini=$P/data/gfx2def.ini" --file "gfx2.gif=$P/data/gfx2.gif" \
                        --file "skin_DPaint.gif=$P/data/skin_DPaint.gif" \
                        --file "font_DPaint.gif=$P/data/font_DPaint.gif" \
                        --file "ZIGPLASM.PI1=$P/ownpics/ZIGPLASMA.PI1" --file "ZIGPLASM.NEO=$P/ownpics/ZIGPLASMA.NEO" \
                        --file "ZIGPLASM.GIF=$P/ownpics/ZIGPLASMA.GIF" --file "ZIGWAVES.PI1=$P/ownpics/ZIGWAVES.PI1" \
                        --file "ZIGWAVES.NEO=$P/ownpics/ZIGWAVES.NEO" --file "ZIGWAVES.GIF=$P/ownpics/ZIGWAVES.GIF" ;;
        # klystrack: the Default theme bundle and four upstream example songs (data/,
        # made by its `make data`); it opens STARPRT2.KT at boot (kestrel_main.c).
        klystrack) P=apps/ports/klystrack/data
                   portdisk "$tag" "$w" --file "Default=$P/Default" \
                        --file "STARPRT2.KT=$P/STARPORT2.KT" --file "CASTLEVA.KT=$P/CASTLEVANIA.KT" \
                        --file "OCEANLD3.KT=$P/OCEANLOADER3.KT" --file "DPINTRO.KT=$P/DPINTRO.KT" ;;
        # ChipNomad: three of upstream's example projects (songs/, MIT like the tracker), for its
        # PROJECT screen's Load.
        chipnomad) P=apps/ports/chipnomad/songs
                   portdisk "$tag" "$w" --file "MICROEGG.CNM=$P/MICROEGG.CNM" \
                        --file "MICROPIZ.CNM=$P/MICROPIZ.CNM" --file "WB7.CNM=$P/WB7.CNM" ;;
        # SID-Wizard: Hermit's own example song "Flash It Back" (upstream native/examples, WTF licence,
        # data/), which the cart opens at start (kestrel_sw_keysim.c); saves go to C: (README.md).
        sidwizard) portdisk "$tag" "$w" --file "FLASHBAK.SWM=apps/ports/sidwizard/data/FLASHBAK.SWM" ;;
        # SyncTERM (the spike): the mocked BBS's welcome screen, our own CP437 ANSI art (mkansi.py), which
        # the in-cart fake BBS sends when SyncTERM dials telnet://fakebbs.zig (kestrel_fakebbs.c).
        syncterm)  portdisk "$tag" "$w" --file "WELCOME.ANS=apps/ports/syncterm/data/BBS.ANS" --file "DIAL.TXT=apps/ports/syncterm/data/DIAL.TXT" ;;
        *)         pack "$OUT/demo-$tag.zmd" "$tag" "$w" ;;
    esac
done

# --- format v2: an EXECUTABLE wasm boot sector that chainloads the cart ---
if [ -f "$OUT/boot-novirus.wasm" ] && [ -f "$OUT/demo-fullscreen.wasm" ]; then
    repack "$OUT/test-v2.zmd" "$(packcart "$OUT/demo-fullscreen.wasm")" \
        --title "No Virus Test" --boot-wasm "$OUT/boot-novirus.wasm"
fi

echo "disks: $packed packed, $skipped up to date"
