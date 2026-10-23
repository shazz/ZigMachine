#!/bin/bash
# main a9a032eb's firmware with N bytes of dead code added to bmain.c (.text): a layout-only change.
set -e
W=/home/matt/projects/ZigMachine/.claude/worktrees/main-fw
O=/home/matt/projects/ZigMachine/prototypes/chisel_queue_re/bisect
cd $W && git checkout -q --detach a9a032eb
for n in "$@"; do
  git checkout -q -- fpga/cycles/bmain.c
  python3 - "$n" <<'PY'
import sys
n = int(sys.argv[1]); p = "fpga/cycles/bmain.c"; s = open(p).read()
pad = ("/* BISECT TEST ONLY: %d bytes of dead code, to move the image layout. */\n"
       "volatile int zm_layout_never;\n"
       "__attribute__((noinline)) void zm_layout_pad(void) { __asm__ volatile(\".fill %d, 4, 0x00000013\"); }\n") % (n, n // 4)
s = s.replace("static void frame(", pad + "static void frame(", 1)
s = s.replace("int main(void) {", "int main(void) {\n    if (zm_layout_never) zm_layout_pad();", 1)
open(p, "w").write(s)
PY
  (cd fpga && make ZM_AUDIO=snd ZM_FPU=1 build/hcycles/split/board_snd_fpu/sys.bin > $O/build_pad$n.log 2>&1)
  mkdir -p $O/pad$n
  (cd fpga && uv run python -c "
import sys; sys.path.insert(0,'tools'); from pathlib import Path; import glass_shelf as g
g.stage_system(Path('$O/pad$n'), Path('build/hcycles/split/board_snd_fpu/sys.bin'), g.CSR_MAP)")
  md5sum $O/pad$n/system.rv32
done
git checkout -q -- fpga/cycles/bmain.c
