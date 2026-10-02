#!/bin/sh
# run_hatari.sh NAME VBLS "SECS:SCANCODE ..." [extra hatari args]: boot SNYD_90.ST headless (ST,
# TOS 1.02, borders on, real time so key offsets mean something), record $OUT/NAME.avi and
# press the keys into its --cmd-fifo (scancodes decimal: 57 space, 59..64 F1..F6).
# RE = the dir holding SNYD_90.ST (MAIN's untracked prototypes/snyd90_re), OUT = output dir.
here=$(cd "$(dirname "$0")" && pwd)
RE=${RE:-/home/matt/projects/ZigMachine/prototypes/snyd90_re}
TOS=${TOS:-/home/matt/projects/ZigMachine/prototypes/dune_gen4_re/hatari/tos102fr.img}
OUT=${OUT:-$RE/hatari}
name=$1; vbls=$2; keys=$3; shift 3
fifo=$OUT/$name.fifo
rm -f "$OUT/$name.avi" "$fifo"
"$here/keys.sh" "$fifo" "$keys" &
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 1200 hatari --machine st --memsize 1 \
  --tos "$TOS" --disk-a "$RE/SNYD_90.ST" --protect-floppy on --borders on \
  --fast-boot on --confirm-quit off --alert-level fatal --sound off --cmd-fifo "$fifo" \
  --avirecord --avi-vcodec png --avi-file "$OUT/$name.avi" --run-vbls "$vbls" \
  --log-file "$OUT/$name.log" "$@" > "$OUT/$name.out" 2>&1
rm -f "$fifo"
python3 "$here/avi2png.py" "$OUT/$name.avi" "$OUT/$name" "${STEP:-25}"
