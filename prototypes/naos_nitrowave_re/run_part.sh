#!/bin/sh
# run_part.sh N VBLS -- boot NITROWAV.ST in Hatari, at VBL 1400 patch the menu's
# key test into "jmp F<N> handler" (TEXT loads at $AA9A under TOS 1.62), record
# every frame (frameskip 0) to hatari/partN.avi and split it into pN/.
set -e
cd "$(dirname "$0")"
N=$1
VBLS=$2
case $N in 1) T='$b6 $04' ;; 2) T='$b6 $0e' ;; 3) T='$b6 $18' ;; esac
mkdir -p dbg "p$N"
printf 'b VBL = 1400 :once :file %s/dbg/jmp%s.ini\n' "$PWD" "$N" > "dbg/part$N.ini"
printf 'w $AFD6 $4e $f9 $00 $00 %s\nc\n' "$T" > "dbg/jmp$N.ini"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy hatari --machine st --memsize 1 \
  --tos /home/matt/projects/MJJ/bin/hatari/TOS/tos162fr.img --disk-a NITROWAV.ST \
  --protect-floppy on --borders on --fast-boot on --fast-forward on --frameskips 0 \
  --confirm-quit off --alert-level fatal --parse "dbg/part$N.ini" \
  --avirecord --avi-vcodec png --avi-file "hatari/part$N.avi" --run-vbls "$VBLS" \
  --log-file "hatari/part$N.log" > "dbg/part$N.out" 2>&1 || true
python3 avi_frames.py "hatari/part$N.avi" "p$N/f" 1 1400 "$VBLS"
