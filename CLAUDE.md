# ZigMachine — project rules for Claude sessions

## Music

- **The YM dump player (`libs/zig/players/ym_player.zig`, `.ym`/`.ymraw`) is DEPRECATED** (Matt, 2026-09-13). Every screen's music is an SNDH played by the 68000 SNDH player. Use a YM dump only as the last resort, when a real search of `prototypes/sndh_lf/` (via `tools/private_tools/sndh_index.py`) finds no SNDH of the tune, and record the best SNDH match score in the scene's music comment.

## Rasters

- **A fake raster (colour bars drawn as PIXELS) must be converted to a REAL raster** (Matt, 2026-09-20).
  A raster bar on an ST is a colour register changed per scanline from an HBL handler — it is not a
  sprite, not a blitted strip, and not a per-row `@memset` into the framebuffer. Use `zg.copper`
  (up to 4 fixed entries a line), `zg.linepal` (up to 255 a line), or the plane's own
  `setFrameBufferHBLHandler`; `apps/zig/scenes/replicants_emlyn/rasters.zig` is the worked example.
  - **A real raster runs the full width of the raster, borders included**, because on an ST the border
    is painted from the same register. Bars that stop at the content edge are the giveaway — opening
    the sides costs `flickerBorder()` on *every* visible line (`openBorders(.all)`, not `.top_bottom`,
    which is MAXI).
  - **A CODEF remake is not evidence.** Remakes routinely fake the mechanism with a sprite. Check the
    bar art's palette: if it is ST-legal (every channel `nibble * 32`, i.e. a multiple of 32 in 0..224)
    the colours were ripped from the real screen's colour registers and only the *mechanism* was faked —
    keep the colours, rewrite the mechanism. Paint-program art is off that grid.
  - **Budget the writes per LINE, and budget CHANGES not entries** — a real raster coder never rewrites
    a register that already holds the right colour. One `move.w` to a colour register costs 12 cycles =
    12 low-res pixels; `movem.l` costs 8+8n, so 4.5 cycles = 4.5 pixels an entry. That is what sets how
    finely a non-horizontal raster can be quantised.

## Float math

- **No float in the per-frame path unless the original needed it** (Matt, 2026-10-11). On the FPGA
  console (KESTREL) the cart CPU (ZIGGY, rv32im at 100 MHz) has no FPU: every `f32`/`f64` operation is
  soft-float, and an `f64` divide costs hundreds of cycles. Float alone took polkadots to 2 fps on the
  board (28 after a fixed-point rewrite, same look), replicants_emlyn needed ~300 MHz, and skystrike
  runs 14 fps in-game where a STOS game ran on an 8 MHz 68000.
  - The ST original did its maths in integers: so does the port. Per-frame code (update, render,
    HBL handlers, anything per row, per pixel or per vertex) uses integers, fixed point (Q16.16,
    Q14), sine/cosine TABLES (`zg.fixtrig`, 1024 steps, u32 angles), and incremental steps.
  - A CODEF remake's JavaScript doubles are not the original's maths; convert them, don't copy them.
  - Float is fine at init (building a table once) and where a test pins a float reference;
    say why in a comment.
  - `libs/zig/effects/zig3d.zig` is f64: for per-frame 3D use a fixed-point projection
    (see `apps/zig/scenes/fuji_hobbytronic/fixed.zig`, `replicants_emlyn/fixed.zig`).
  - Exception: the intentional `_f32` twin carts (FPU test carts) keep float on purpose.


## Board speed (KESTREL)

- **Enabled planes, not stores, are what's slow on the board now** (refit to the posted-store board,
  2026-10-23, `fpga/review/reports/cost_model_recal_2026-10-23.md`). A store costs ~2.3 cycles, `@memset`
  ~2.3 a word, a palette write is ~free; every ENABLED plane costs ~0.59 Mc of compositing (+0.11 Mc a
  frame), so disabling or merging planes is the big lever. A CHISEL blit has ~800 cycles of fixed cost
  (for a scroll, a CPU word shift beats a blit shift); never CHISEL-copy within one plane. A misaligned
  access traps (~210 cycles); f32 add/mul is 9-10 cycles. The board drops below 60 fps between ~1.75 and
  2.1 Mc estimated (`apps/frame_cost.mjs`; inside that band the probe's `missed` column decides). Matt's
  rule still holds: "only modify what needs to be modified" (draw static things once, erase only what
  moved). `tools/perf_audit.sh <tag>` ranks the waste (no sim); `fpga/tools/board_fps.py` measures real
  fps on the board. Details in docs/PERF_AUDIT.md.

## Building

- **`./build.sh` is the full gate: about 4.5 min on a quiet box** (since 2026-09-27, docs/BUILDING.md).
  Harnesses run `GATE_JOBS` at a time (default 4); harnesses that measure wall-clock time are
  `gate_timed` and run alone after the pool. **A new harness that asserts ms/frame or a budget must use
  `gate_timed`, never plain `gate`.**
- **While iterating, gate only what changed** (Matt, 2026-09-19):
  - `./build.sh --only <screen>` — one screen, e.g. `./build.sh --only stniccc`
  - `./build.sh --changed [<rev>]` — builds everything and runs every cross-cutting check, but only the
    harnesses the diff can reach (`tools/gate_scope.py`); anything shared means the full gate
  - `./build.sh --fast` — wasm + `.zmd` disks only, then stops. NOTHING is checked (no
    RAM windows, no native tests, no harnesses) and the C/Rust carts are not rebuilt.
    For the edit-reload-look loop in the browser; never a substitute for a gate.
  The cross-cutting checks (`check_fits`, `ram_check`, `rom_abi_check`, `blitter_check`, `disk_check`,
  `upload_check`, `verify`, `tunein_check`, `zero_segments`) always run; only per-screen harnesses are
  skipped.
- **Land ready branches in batches: one gate for the whole queue** (Matt, 2026-11-13: "at each unlock,
  check for merge / install, if queue, do it before locking again"). Agents gate their own work with
  `--only <tag>` and, when green, append `<branch> <note>` to `prototypes/_gate_logs/merge_queue.txt`;
  they never run a full gate to land and never push. Each time the lock frees, the lead runs
  `tools/gate_batch.sh list`, then `merge <name>` (one integration branch from origin/main with every
  queued branch) and `gate <name>` (one full gate, then the push), clears the queue, and installs the
  board files ONCE (one system.rv32 for all ROM/BARD changes) before anyone takes the lock again.
- **The pre-push hook IS the gate — don't gate twice.** It skips a tree already stamped green
  (`.git/zm-gate-green`, written only by a full gate on a clean tree); otherwise it runs
  `--changed <remote sha>`, or the full gate for a shared change (`libs/`, `rom/`, `machine/`,
  `docs/*.js`, `build.zig`…) or a new cart (build.zig/cart.zig/catalog.zig). A one-cart push takes
  about a minute. So after a merge, just `flock prototypes/_gate_logs/build.lock git push`.
- **Only ONE gate at a time on this box.** Two concurrent `./build.sh` runs have OOM-killed a push (#75),
  and concurrent builds are what once made a push take 45 min. Take the lock for every build and push:
  `flock prototypes/_gate_logs/build.lock ./build.sh …`; sibling checkouts (`ZigMachine-*`) count.
  **Exception — `./build.sh --fast` takes NO lock** (Matt, 2026-10-19): it only builds wasm + disks
  (seconds), so use it freely to build and look at a change (browser, scene_hash, PNG frames) while
  another session holds the lock. Take the lock only for the real gate (`--only` / `--changed` / full)
  and for pushes.
- **Board-SoC sims are scarce: two slots, short runs** (Matt, 2026-10-17). Verilator sims (hp_sim,
  snd-bench) take `prototypes/_gate_logs/sim-a.lock` or `sim-b.lock`, and every agent shares those two.
  A sim costs minutes per frame plus the cart's boot (an emlyn run: 1 h 53 min for 9 frames). Hold ONE
  sim lock at a time; a profile needs <= 6 frames after boot (`--frames 6 --every 6`); never queue long
  runs (a 110-frame run plus one agent on both slots stalled seven agents for hours). Long pixel proofs
  come from the browser harnesses (`scene_hash.mjs`), not the sim. The lead sets a sim priority when
  agents queue.
  The board SoC sims at ~10 kHz: a heavy cart (~8 Mc/frame) takes ~1.5 h for 6 frames, so estimate the
  run time first, sim ONE cart per lock, and prefer the board itself as the profiler (OSD fps).
- A screen is only covered if its harness is **named in `build.sh`**. `apps/stniccc_headless.mjs` existed
  for weeks without being called there, so that screen had no end-to-end coverage at all. When adding a
  harness, add its `gate <tag> node apps/<name>.mjs` line in the same commit.

## Roadmap

- **`docs/ROADMAP.md` is the source of truth for open work** (Matt, 2026-10-31); finished items move to
  `docs/ROADMAP_DONE.md` with their commit. Update it in the same commit as the work (a row when work
  starts, the status as it moves). The roadmap artifact is Matt's view, regenerated from the file.
- **Every unmerged branch has a row.** At the start of every lead session, and before any branch cleanup,
  run the forgotten-branch review (the command is at the top of ROADMAP.md): `perf/chisel-queue-v2` sat
  8 days built and board-measured but unmerged, `perf/ziggy-read-bypass` 12 days built and never measured.
- Worktree agents don't see this file: put "update docs/ROADMAP.md" in their brief.
