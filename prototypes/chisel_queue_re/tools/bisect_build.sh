#!/bin/bash
# Build main a9a032eb + perf/chisel-async up to each commit's firmware (system.rv32), for the
# board A/B on lm8 (rno_natrium, union_l16). Conflicts are only decisions.md and binary disks: ours.
set -e
W=/home/matt/projects/ZigMachine/.claude/worktrees/main-fw
O=/home/matt/projects/ZigMachine/prototypes/chisel_queue_re/bisect
cd $W
for c in "$@"; do
  git checkout -q -B bisect/$c a9a032eb
  git merge -q --no-ff --no-commit $c >/dev/null 2>&1 || true
  for f in $(git diff --name-only --diff-filter=U); do git checkout --ours -- "$f"; git add "$f"; done
  git -c core.editor=true commit -q -m "bisect: main a9a032eb + perf/chisel-async $c (firmware A/B only)"
  (cd fpga && make memmap >/dev/null && make ZM_AUDIO=snd ZM_FPU=1 build/hcycles/split/board_snd_fpu/sys.bin > $O/build_$c.log 2>&1)
  mkdir -p $O/$c
  (cd fpga && uv run python -c "
import sys; sys.path.insert(0,'tools'); from pathlib import Path; import glass_shelf as g
print(g.stage_system(Path('$O/$c'), Path('build/hcycles/split/board_snd_fpu/sys.bin'), g.CSR_MAP))")
  md5sum $O/$c/system.rv32
done
git checkout -q --detach a9a032eb
