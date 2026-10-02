#!/bin/sh
# hatari_rec.sh RE_DIR OUT_DIR NAME VBLS [extra hatari args]: boot RE_DIR/DUNE_AUTO.ST headless
# (TOS 1.02, as ../run.sh) WITH sound, recording OUT_DIR/NAME.avi (png video + 44.1 kHz PCM).
# avi_wav.py pulls the sound out of it.
re=$1; out=$2; name=$3; vbls=$4; shift 4
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 1800 hatari --machine st --memsize 1 \
  --tos "$re/hatari/tos102fr.img" --disk-a "$re/${DISK:-DUNE_AUTO.ST}" --protect-floppy on \
  --borders on --fast-boot on --fast-forward on --confirm-quit off --alert-level fatal \
  --sound 44100 --avirecord --avi-vcodec png --avi-file "$out/$name.avi" --run-vbls "$vbls" \
  --log-file "$out/$name.log" "$@" > "$out/$name.out" 2>&1
tail -3 "$out/$name.log"
