#!/usr/bin/env bash
# osd_uboot_demo.sh [STEP...]: drive the OSD test bitstream (make -C fpga osd-test,
# build/osd_test/osd_test_top.bit) from the U-Boot prompt, through tools/uboot.sh.
# Steps 0..4 by default; name some to run only those. PAUSE=1 waits for Enter
# after each step, else it sleeps HOLD seconds (default 4) so the screen can be seen.
#
# Before: zeST's BOOT.BIN booted to `Zynq>` (Ctrl-C stops the autoboot), and
#   openFPGALoader -c digilent_hs2 fpga/build/osd_test/osd_test_top.bit
# loaded the PL. NEVER touch 0x43C0xxxx with the PL unconfigured: nothing
# answers GP0 and the ARM hangs until a reset. Use md.l / mw.l only (single
# 32-bit beats); the block does not take bursts.
#
# What the monitor shows (tests/tb/osd_test_tb.cpp checks each frame in CXXRTL;
# make -C fpga osd-test-sim draws them as build/osd_test/osd_<n>_*.png):
#   at load  osd_1_poweron.png: the colour-bar pattern, and over its middle (x 144..655,
#            y 172..427) a 512x256 black box with white 16x16 text: an inverse title bar
#            "ZIGMACHINE OSD TEST", "THE PL WROTE THIS AT POWER-ON", the font's 256 glyphs
#            (rows 0x00-1F and 0x80-9F are blank in the ST system font), "GP0 43C00000
#            ID 5A4D474C", "WAITING FOR THE ARM (U-BOOT)", an inverse bar "MICROPHASE
#            Z7-LITE  XC7Z010". PL_LED2 lit (PLL locked).
#   step 0   the PS-PL level shifters checked (and enabled if off); screen unchanged
#   step 1   the ID read; screen unchanged; PL_LED1 flips once per GP0 word
#   step 2   osd_2_message.png: rows 13-14 now " HELLO FROM THE ARM" and " TIME hh:mm:ss"
#            (the host's time when the step ran); the rest of the banner unchanged
#   step 3   osd_3_off.png: the box gone, the bare test pattern, for HOLD seconds;
#            then the box back, exactly as in step 2
#   step 4   osd_4_colours.png: yellow text on a blue box; the two inverse bars become
#            blue text on yellow
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GAP="${GAP:-0.6}"
HOLD="${HOLD:-4}"
BASE=0x43c00000           # glass/src/map.zig GP0_BASE
TEXT=0x43c01000           # + OFF_OSD_TEXT: one character a word, 32 x 16, row-major

die() { echo "osd_uboot_demo: $*" >&2; exit 1; }

# Send U-Boot commands; the reply goes to stdout. WAIT covers every GAP.
ub() { WAIT="$(awk -v n=$# -v g="$GAP" 'BEGIN { print int(n * g + 3) }')" GAP="$GAP" "$HERE/uboot.sh" "$@"; }

hold() {
    echo ">>> EXPECT: $*"
    if [ "${PAUSE:-0}" = 1 ]; then read -r -p "    Enter for the next step " _; else sleep "$HOLD"; fi
}

# The commands that write `text` into row `row`: the row cleared to spaces
# (mw.l's count is hex: 0x20 words), then one word a character, PER_LINE (4) to a
# console line: ~70 characters, so a paste at 921600 baud stays near the PS
# UART's 64-byte receive FIFO while U-Boot echoes it.
row_cmds() {
    local row=$1 text=$2 addr i line="" n=0
    addr=$((TEXT + 4 * row * 32))
    printf 'mw.l %x 20 20\n' "$addr"
    for ((i = 0; i < ${#text} && i < 32; i++)); do
        line+="$(printf 'mw.l %x %x;' $((addr + 4 * i)) "'${text:i:1}")"
        if ((++n == ${PER_LINE:-4})); then echo "${line%;}"; line=""; n=0; fi
    done
    [ -z "$line" ] || echo "${line%;}"
}

# The value md.l prints for one word, lower-case hex.
word_at() { ub "md.l $1 1" | awk -v a="${1#0x}:" 'tolower($1) == a { print tolower($2) }' | tail -1; }

step0() {
    echo "== step 0: the PS-PL level shifters (SLCR LVL_SHFTR_EN, 0xF8000900)"
    local lvl
    lvl="$(word_at 0xf8000900)"
    echo "LVL_SHFTR_EN = ${lvl:-<no answer>}"
    [ -n "$lvl" ] || die "no reply from U-Boot: is it at the Zynq> prompt?"
    if [ "$lvl" != 0000000f ]; then
        echo "enabling them (SLCR unlock, then LVL_SHFTR_EN = 0xF, as ps7_post_config does)"
        ub "mw.l f8000008 df0d" "mw.l f8000900 f"
        lvl="$(word_at 0xf8000900)"
        [ "$lvl" = 0000000f ] || die "LVL_SHFTR_EN still $lvl: GP0 would hang, stopping"
    fi
    hold "screen unchanged (the power-on banner)"
}

step1() {
    echo "== step 1: read the block: ID, VERSION, CTRL, STATUS; SCRATCH written and read back"
    ub "md.l 43c00000 4" "mw.l 43c00034 c0ffee42" "md.l 43c00034 1"
    # Expect: 43c00000: 5a4d474c 00010200 00000002 00000000   ZMGL ...   43c00034: c0ffee42
    # (VERSION 00010100 on an osd-test bitstream built before AUDIO_VOL, 2026-10-03)
    [ "$(word_at "$BASE")" = 5a4d474c ] || die "ID is not 0x5A4D474C: GP0 or the bitstream is not there"
    hold "screen unchanged; ID 5a4d474c, VERSION 00010200 (00010100 before AUDIO_VOL), CTRL 00000002 (OSD on), SCRATCH c0ffee42"
}

step2() {
    local now
    now="$(date +%H:%M:%S)"
    echo "== step 2: a message from the ARM, rows 13 and 14"
    mapfile -t cmds < <(row_cmds 13 " HELLO FROM THE ARM"; row_cmds 14 " TIME $now")
    ub "${cmds[@]}" > /dev/null
    hold "rows 13-14 of the box read ' HELLO FROM THE ARM' and ' TIME $now', white on black"
}

step3() {
    echo "== step 3: the OSD off (CTRL = 0), then on again (CTRL = CTRL_OSD = 2)"
    ub "mw.l 43c00008 0" "md.l 43c00008 1"
    hold "the box gone: only the colour bars, the bouncing orange box and the ramps"
    ub "mw.l 43c00008 2" "md.l 43c00008 1"
    hold "the box back, as after step 2 (CTRL reads 00000002)"
}

step4() {
    echo "== step 4: colours: OSD_FG = 0xFFFF00 (yellow), OSD_BG = 0x0000AA (blue)"
    ub "mw.l 43c0002c ffff00" "mw.l 43c00030 aa" "md.l 43c0002c 2"
    hold "yellow text on a blue box; the title and bottom bars blue on yellow (reads 00ffff00 000000aa)"
}

steps=("$@")
[ ${#steps[@]} -gt 0 ] || steps=(0 1 2 3 4)
for s in "${steps[@]}"; do
    case "$s" in
        0 | 1 | 2 | 3 | 4) "step$s" ;;
        *) die "no step $s (0..4)" ;;
    esac
done
