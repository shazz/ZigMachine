#!/bin/sh
# ref6.sh RE_DIR OUT_DIR: the F3 run. DUNE_AUTO.ST in Hatari at REAL speed (keys land by the wall
# clock, ../keys.sh), one AVI frame a VBL, with sound: Space in the main part, Space on the title
# once SingSong plays, F3 in the menu, then F4, F5, F6, F3 in the sound screen, Space back to
# the menu. Scancodes: 57 Space, 61 F3, 62 F4, 63 F5, 64 F6.
re=$1; out=$2
fifo="$out/ref6.fifo"
rm -f "$fifo" "$out/ref6.avi"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 900 hatari --machine st --memsize 1 \
  --tos "$re/hatari/tos102fr.img" --disk-a "$re/DUNE_AUTO.ST" --protect-floppy on \
  --borders on --fast-boot on --fast-forward off --frameskips 0 --confirm-quit off \
  --alert-level fatal --sound 44100 --cmd-fifo "$fifo" --avirecord --avi-vcodec png \
  --avi-file "$out/ref6.avi" --run-vbls 8000 --log-file "$out/ref6.log" > "$out/ref6.out" 2>&1 &
pid=$!
while [ ! -p "$fifo" ]; do sleep 0.2; done
sh "$re/keys.sh" "$fifo" "42:57 68:57 88:61 102:62 114:63 126:64 138:61 150:57"
wait $pid
tail -3 "$out/ref6.log"
