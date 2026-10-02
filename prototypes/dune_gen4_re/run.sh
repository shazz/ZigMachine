#!/bin/sh
# run.sh NAME VBLS [extra hatari args...]: boot DUNE_AUTO.ST headless on TOS 1.02 (the
# demo's keyboard handler jumps into TOS 1.02 at $FC29CE) and record hatari/NAME.avi.
cd "$(dirname "$0")" || exit 1
name=$1; vbls=$2; shift 2
rm -f "hatari/$name.avi" "hatari/$name.log"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 900 hatari --machine st --memsize 1 \
  --tos hatari/tos102fr.img --disk-a "${DISK:-DUNE_AUTO.ST}" --protect-floppy on --borders on \
  --fast-boot on --fast-forward on --confirm-quit off --alert-level fatal --sound off \
  --avirecord --avi-vcodec png --avi-file "hatari/$name.avi" --run-vbls "$vbls" \
  --log-file "hatari/$name.log" "$@" > "hatari/$name.out" 2>&1
tail -3 "hatari/$name.log"
python3 avi2png.py "hatari/$name.avi" "hatari/$name" "${STEP:-100}"
