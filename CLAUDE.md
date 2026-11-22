# ZigMachine: project rules for Claude sessions

The ZigMachine is an Atari-ST-inspired machine (wasm in the browser) and KESTREL, its FPGA console
(Zynq 7010). The detailed rules live in skills; read the one that matches the task FIRST. Worktree
agents don't get `.claude/` (it is gitignored), so read them by absolute path:

| Skill | Read it before |
|---|---|
| `/home/matt/projects/ZigMachine/.claude/skills/zm-screen-rules/SKILL.md` | any screen, port or cart: music (SNDH, not YM dumps), REAL rasters, float maths |
| `/home/matt/projects/ZigMachine/.claude/skills/kestrel-capabilities/SKILL.md` | anything that must run on the board: ZIGGY + FPU, ZM-X, BARD (mailbox, queue, jobs), ASTROLABE, CHISEL (AFFINE, MAP, QUEUE), FRESCO (alpha planes, true colour, hw fade, hw scroll, copper), memory, the frame budget |
| `/home/matt/projects/ZigMachine/.claude/skills/zm-gate/SKILL.md` | `./build.sh`, gates, merges, pushes, sims, new harnesses |
| `/home/matt/projects/ZigMachine/.claude/skills/{st-port,c64-port,codef-port,stos-port,board-cart}/SKILL.md` | porting from an ST / C64 / CODEF / STOS original; staging a cart on the SD card |

## The rules that apply everywhere (details in the skills)

- **Music**: SNDH via the 68000 player; a YM dump only when no SNDH exists (Matt, 2026-09-13).
- **Rasters**: colour bars are per-line register writes (copper / linepal / HBL), full width,
  never pixels (Matt, 2026-09-20).
- **Maths**: a port of an integer original stays integer (fixed point, tables, ZM-X); ZIGGY has an
  f32 FPU for KESTREL-native designs; f64 is soft-float, never per frame (Matt, 2026-10-11, 11-14).
- **Board speed**: enabled planes are the big cost (~0.59 Mc each); 60 fps is lost at ~1.75-2.1 Mc
  a frame; draw only what changed; the board (OSD fps) is the profiler.
- **Ports and tributes keep the original's LOOK, not its code**: design for KESTREL's units and
  show each gain as a HUD A/B (Matt, 2026-11-14).
- **Building**: one gate at a time under `flock prototypes/_gate_logs/build.lock` (`--fast` needs no
  lock); agents gate with `--only <tag>` and append to `prototypes/_gate_logs/merge_queue.txt`; the
  lead lands the queue in one batch (`tools/gate_batch.sh`); the pre-push hook is the gate; never
  `--no-verify`, never kill another session's build. A harness counts only if named in `build.sh`.
- **Sims**: two slots (`sim-a.lock` / `sim-b.lock`), <= 6 frames a profile.

## Roadmap

- **`docs/project/ROADMAP.md` is the source of truth for open work** (Matt, 2026-10-31); finished items move
  to `docs/project/ROADMAP_DONE.md` with their commit. Update it in the same commit as the work. The roadmap
  artifact is Matt's view, regenerated from the file.
- **Every unmerged branch has a row.** At the start of every lead session, and before any branch
  cleanup, run the forgotten-branch review (the command is at the top of ROADMAP.md).
- Put "update docs/project/ROADMAP.md" in every agent brief.
