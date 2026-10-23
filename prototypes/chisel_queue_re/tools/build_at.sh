#!/bin/bash
# system.rv32 of main at given commits (detached in the main-fw worktree): build_at.sh <sha>...
set -e
W=/home/matt/projects/ZigMachine/.claude/worktrees/main-fw
O=/home/matt/projects/ZigMachine/prototypes/chisel_queue_re/audio_bisect
mkdir -p $O; cd $W
for c in "$@"; do
  git checkout -q --detach $c
  (cd fpga && make memmap >/dev/null 2>&1 && make ZM_AUDIO=snd ZM_FPU=1 build/hcycles/split/board_snd_fpu/sys.bin > $O/build_$c.log 2>&1)
  mkdir -p $O/$c
  (cd fpga && uv run python -c "
import sys; sys.path.insert(0,'tools'); from pathlib import Path; import glass_shelf as g
g.stage_system(Path('$O/$c'), Path('build/hcycles/split/board_snd_fpu/sys.bin'), g.CSR_MAP)")
  md5sum $O/$c/system.rv32
done
git checkout -q --detach a9a032eb
