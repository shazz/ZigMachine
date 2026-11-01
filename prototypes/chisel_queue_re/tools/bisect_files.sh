#!/bin/bash
# Variants of bisect/7740706e with some files put back to main a9a032eb's: name:file,file ...
set -e
W=/home/matt/projects/ZigMachine/.claude/worktrees/main-fw
O=/home/matt/projects/ZigMachine/prototypes/chisel_queue_re/bisect
cd $W
for arg in "$@"; do
  name=${arg%%:*}; files=${arg#*:}
  git checkout -q --detach bisect/7740706e
  for f in ${files//,/ }; do git checkout a9a032eb -- "$f"; done
  (cd fpga && make ZM_AUDIO=snd ZM_FPU=1 build/hcycles/split/board_snd_fpu/sys.bin > $O/build_$name.log 2>&1)
  mkdir -p $O/$name
  (cd fpga && uv run python -c "
import sys; sys.path.insert(0,'tools'); from pathlib import Path; import glass_shelf as g
g.stage_system(Path('$O/$name'), Path('build/hcycles/split/board_snd_fpu/sys.bin'), g.CSR_MAP)")
  md5sum $O/$name/system.rv32
  git checkout -q -- . && git checkout -q --detach bisect/7740706e
done
git checkout -q --detach a9a032eb
