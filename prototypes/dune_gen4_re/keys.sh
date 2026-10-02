#!/bin/sh
# keys.sh FIFO "SECS:SCANCODE ..." : press keys into a running hatari --cmd-fifo at
# wall-clock offsets (seconds after start). Scancodes are decimal (57 space, 59 F1, 60 F2, 61 F3).
fifo=$1; shift
t0=$(date +%s)
for ev in $1; do
  at=${ev%%:*}; code=${ev##*:}
  while [ $(( $(date +%s) - t0 )) -lt "$at" ]; do sleep 1; done
  [ -p "$fifo" ] || exit 0
  echo "hatari-event keydown $code" > "$fifo"
  sleep 0.3
  echo "hatari-event keyup $code" > "$fifo"
done
