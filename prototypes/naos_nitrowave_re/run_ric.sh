#!/bin/sh
# run_ric.sh F VBLS -- F1 with its "random" figure forced to F (0..3): boot,
# start F1 at VBL 1400, and when DEMO_RIC reads the video counter for its
# figure ($A44: d0 = counter, then lsr #1, and #3) set d0 = 2F. Saves
#   dumps/f1_pre.bin   RAM just before the choice ($A44, the same for all F)
#   dumps/f1_F.bin     RAM at the main loop's first pass ($D98)
# logs the VBL of the title ($894), the choice and the entry, and records
# every frame to hatari/ric_F.avi -> pF/ (frameskip 0).
set -e
cd "$(dirname "$0")"
F=$1
VBLS=$2
mkdir -p dbg dumps "r$F"
printf 'b VBL = 1400 :once :file %s/dbg/ricjmp.ini\n' "$PWD" > dbg/ric.ini
printf 'w $AFD6 $4e $f9 $00 $00 $b6 $04\nb pc = $894 :once :file %s/dbg/ric_title.ini\nb pc = $a44 :once :file %s/dbg/ric_pick.ini\nb pc = $d98 :once :file %s/dbg/ric_entry.ini\nc\n' "$PWD" "$PWD" "$PWD" > dbg/ricjmp.ini
printf 'e VBL\nc\n' > dbg/ric_title.ini
printf 'savebin %s/dumps/f1_pre.bin 0 $100000\nr d0=%d\ne VBL\nc\n' "$PWD" "$((2 * F))" > dbg/ric_pick.ini
printf 'savebin %s/dumps/f1_%s.bin 0 $100000\ne VBL\nc\n' "$PWD" "$F" > dbg/ric_entry.ini
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy hatari --machine st --memsize 1 \
  --tos /home/matt/projects/MJJ/bin/hatari/TOS/tos162fr.img --disk-a NITROWAV.ST \
  --protect-floppy on --borders on --fast-boot on --fast-forward on --frameskips 0 \
  --confirm-quit off --alert-level fatal --parse dbg/ric.ini \
  --avirecord --avi-vcodec png --avi-file "hatari/ric_$F.avi" --run-vbls "$VBLS" \
  > "dumps/f1_$F.log" 2>&1 || true
grep -E "^= .*dec|CPU=" "dumps/f1_$F.log" | head -12
python3 avi_frames.py "hatari/ric_$F.avi" "r$F/f" 1 1900 "$VBLS"
