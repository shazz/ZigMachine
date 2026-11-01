#!/bin/bash
# On the card's lm8 boot: for each bisect firmware, bind its system.rv32 over /tmp/zm and trace
# rno_natrium + union_l16 (40 s, 10 s windows). RAM only, the card is never written.
#   bisect_board.sh <name>=<system.rv32> ...
set -e
T=/home/matt/projects/ZigMachine/prototypes/chisel_queue_re
cd $T
for arg in "$@"; do
  name=${arg%%=*}; sys=${arg#*=}
  mkdir -p bisect/run_$name
  timeout 300 uv run --with pyserial python tools/arm_shelf.py "$sys" system.rv32 | grep -E "md5|table" | tail -2
  for c in rno_natrium union_l16; do
    timeout 200 uv run --with pyserial python tools/fps_trace.py demo-$c.zmd 40 10 > bisect/run_$name/trace_$c.txt
    echo "$name $(tail -1 bisect/run_$name/trace_$c.txt)"
  done
done
