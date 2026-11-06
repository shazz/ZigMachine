#!/bin/sh
# The "same pixels" proof for a klystrack UI change: every frame's picture hashed (run.mjs HASHES=) in each
# scenario, for two carts, compared frame by frame.
#   apps/ports/klystrack/hashes.sh <before.wasm> <after.wasm> [outdir=apps/ports/klystrack/build/hashes]
# From the repo root. Prints one line a scenario: "same" or the first frame that differs; exit 1 if any differs.
set -u
A=$1 B=$2 OUT=${3:-apps/ports/klystrack/build/hashes}
mkdir -p "$OUT"
F5=57349 ESC=57362 CTRL=57364 F3=57347 F2=57346
# right button held over the menu bar, the pointer moving every frame (as apps/klystrack_cost.mjs)
menu() { s="$1,150,100,0;$(($1 + 1)),150,100,4"; f=$(($1 + 2)); while [ $f -le $2 ]; do s="$s;$f,$((150 + f % 8 * 2)),$((100 + f % 5)),4"; f=$((f + 1)); done; echo "$s"; }
hover() { s=""; f=$1; while [ $f -le $2 ]; do s="$s;$f,$((60 + f % 50 * 4)),$((120 + f % 7 * 9)),0"; f=$((f + 1)); done; echo "${s#;}"; }
run() { # run <name> <frames> [VAR=value...]
    name=$1 frames=$2; shift 2
    for c in a b; do
        cart=$A; [ $c = b ] && cart=$B
        env "$@" CART="$cart" HASHES="$OUT/$name.$c" node apps/ports/klystrack/run.mjs "$frames" "$OUT/$name.$c." > "$OUT/$name.$c.log" 2>&1
    done
    if cmp -s "$OUT/$name.a" "$OUT/$name.b"; then echo "  same     $name ($frames frames)"
    else echo "  DIFFERS  $name: first at frame $(diff "$OUT/$name.a" "$OUT/$name.b" | head -1 | sed 's/[^0-9].*//')"; bad=1; fi
}
bad=0
run idle 200
run play 420 KEYS="30,$F5"
run menu 260 MOVES="$(menu 150 240)"
run play_menu 330 KEYS="30,$F5" MOVES="$(menu 200 300)"
run play_hover 260 KEYS="30,$F5" MOVES="$(hover 100 220)"
run dialog 160 KEYS="30,$CTRL;31,111;100,$ESC"
run keyjazz 220 KEYS="40,122;70,120;100,99"
run play_edit 260 KEYS="30,$F5;60,32;80,122;100,113;120,32"
run play_click 240 KEYS="30,$F5" CLICKS="120,60,140;160,200,150"
run play_tabs 300 KEYS="30,$F5;60,$F3;120,$F2;180,$F3"
run quit 120 KEYS="60,$ESC"
exit $bad
