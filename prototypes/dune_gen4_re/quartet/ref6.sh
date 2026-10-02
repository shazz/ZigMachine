#!/bin/sh
# ref6.sh RE_DIR OUT_DIR: the F3 run. DUNE_AUTO.ST in Hatari, one AVI frame a VBL, with sound;
# keys land at emulated VBLs (keys_vbl.py, counting the AVI's frames): Space in the main part, Space on the title
# once SingSong plays, F3 in the menu, then F4, F5, F6, F3 in the sound screen, Space back to
# the menu. Scancodes: 57 Space, 61 F3, 62 F4, 63 F5, 64 F6.
re=$1; out=$2
fifo="$out/ref6.fifo"
rm -f "$fifo" "$out/ref6.avi"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 1800 hatari --machine st --memsize 1 \
  --tos "$re/hatari/tos102fr.img" --disk-a "$re/DUNE_AUTO.ST" --protect-floppy on \
  --borders on --fast-boot on --fast-forward on --frameskips 0 --confirm-quit off \
  --alert-level fatal --sound 44100 --cmd-fifo "$fifo" --avirecord --avi-vcodec png \
  --avi-file "$out/ref6.avi" --run-vbls 6600 --log-file "$out/ref6.log" > "$out/ref6.out" 2>&1 &
pid=$!
while [ ! -p "$fifo" ]; do sleep 0.2; done
python3 "$(dirname "$0")/keys_vbl.py" "$fifo" "$out/ref6.avi" \
  "1751:57 2951:57 3800:61 4300:62 4700:63 5100:64 5500:61 5900:57"
wait $pid
tail -3 "$out/ref6.log"
