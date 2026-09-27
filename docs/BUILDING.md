# Building and gating

`./build.sh` builds every wasm module, cart and disk, then runs the gate: RAM
windows, the ROM ABI, the native tests, every disk mounted, and the headless
harnesses that drive each screen end to end. Its failures are the silent kind (a
cart overrunning its window, a disk frozen against an old host), so nothing is
pushed without it. This page is how the gate stays fast without guaranteeing less.

## The commands

| command | what runs | typical time |
|---|---|---|
| `./build.sh` | **the full gate**: everything below, every harness | ~4-5 min |
| `./build.sh --changed [<rev>]` | full build, every cross-cutting check, only the harnesses the diff since `<rev>` can reach | ~1 min for one screen |
| `./build.sh --only <tags>` | as above, harnesses picked by tag substring | ~1 min |
| `./build.sh --fast` | wasm + disks + channels, **nothing checked** | seconds |
| `git push` | the pre-push hook: stamp, selective or full (below) | 0 s / ~1 min / ~5 min |

Every build and every gate runs under the one lock, because two concurrent gates
once OOM-killed a push on the 15 GB box:

    flock prototypes/_gate_logs/build.lock ./build.sh
    flock prototypes/_gate_logs/build.lock git push origin HEAD:main

The hook does not take the lock itself: the caller already holds it for the push,
and a second `flock` on the same file from inside would deadlock.

## What only ever gets narrowed

`--only` and `--changed` narrow the **per-screen harnesses** and nothing else.
Every cart and disk is still rebuilt, and every cross-cutting check still runs:
check_fits, zero_segments, ram_check, rom_abi_check, blitter_check, beam_check,
pack_stats, the native tests, mkdisks, channels, cache_bust, the doc generators'
checks and tests, disk_check, upload_check, tutorial_steps_check, verify and
tunein_check. A change that breaks any of those fails a narrowed gate exactly as
it fails the full one.

## The pre-push hook: three paths

1. **Green stamp.** A full `./build.sh` that starts and ends on a clean tree
   appends the tree's hash to `.git/zm-gate-green` (per clone, shared by its
   worktrees, never committed; `tools/gate_stamp.sh`). If the commit being pushed
   has a stamped tree, the hook says `gate already green for this tree` and runs
   nothing. This is not a bypass: a tree hash is the hash of exactly the bytes
   being pushed, so the gate has already given its answer for them. The stamp
   also records the toolchain (zig and node versions, and whether `prototypes/`
   exists, since some harnesses check more when it does); a different toolchain
   is a different key. "Clean" means no tracked change anywhere and no untracked
   file under the build's inputs (`apps libs rom machine tools docs .githooks
   build.zig build.sh`).
2. **Selective.** Otherwise the hook runs `build.sh --changed <remote sha>`: the
   diff between what the remote already has and what is pushed. It trusts that
   base, because the base passed this same hook when it was pushed. A new branch
   diffs from its merge-base with the remote's `main`; an unknown remote commit,
   or several refs with different bases, is the full gate.
3. **Full.** Anything `tools/gate_scope.py` cannot place, or untracked files under
   the inputs (they would be gated but not pushed).

After any gate the hook still refuses a push whose `docs/` differ from the rebuild.

## Which harnesses a diff reaches (`tools/gate_scope.py`)

The scope is computed **after** the build, from the diff plus the freshly rebuilt
`docs/`. That ordering is the core of the argument: every cart is rebuilt from
the pushed source, so a source change that altered cart Y's bytes (a scene file
shared with Y, say) shows up as a changed `docs/demo-Y.wasm` and pulls in Y's
harnesses, and a push whose committed `docs/` disagree with the rebuild is
refused anyway.

| changed path | harnesses |
|---|---|
| `apps/zig/scenes/<x>...`, `apps/zig/assets/screens/<x>/...` | every cart named `<x>`, `<x>_*`, or that `<x>` is `<cart>_*` of |
| `docs/demo-<cart>.wasm` / `.zmd` (a Zig cart) | that cart's |
| `apps/<file>` (a harness, a helper, a fixture) | the harnesses that run, import or read it |
| `tools/<cart>/...` | that cart's, and any harness naming `tools/<cart>/` |
| `*.md`, `docs/ports/...` | none (the doc checks are cross-cutting) |
| a NEW file in `docs/music/` | none |
| anything else | **full gate** |

"That cart's harnesses" means: every gate tag containing the cart's name (the
`--only` rule), every harness whose source or imports load `demo-<cart>.`
(`digital_solution` runs `demo-big_demo.wasm`, `union_tnt1` loads
`demo-union_multifake.wasm`), and every harness that builds a cart path at run
time (`union_demo`, `union_demo_doors` walk the hub's doors), which is therefore
in every narrowed set.

Always the full gate: `libs/`, `rom/`, `machine/`, `build.zig`, `build.sh`,
`.githooks/`, `tools/*` outside a cart's own dir, `apps/zig/cart.zig`,
`demo_main.zig`, `apps/c/`, `apps/rust/`, `docs/*.js|html|css|json`,
`docs/demo.wasm` (the menu), `docs/demo-audio.wasm`, a changed or deleted tune in
`docs/music/`, and the registration files `apps/zig/scenes/catalog.zig` and
`menu.zig`. So **adding a new cart is always a full gate**: it touches
`build.zig`, `cart.zig`, `catalog.zig` and `build.sh`, all shared, and a new
cart is exactly when the menu, the channel list and every disk change. Once
registered, later edits to that cart go selective.

The rules are unit-tested in `tools/tests/test_gate_scope.py`, which the gate
itself runs.

## Parallel harnesses (`tools/gate_lib.sh`)

`gate <tag> <cmd>` lines no longer run where they stand: they queue a job, and
`run_gates` at the end runs the queue `GATE_JOBS` at a time. Each job's output is
buffered and printed in queue order under its tag, one status line per job is
printed as it finishes, and every failure is re-printed at the end; the gate
fails if any job failed or never ran.

- `gate_timed <tag> <cmd>`: the harness asserts wall-clock time (ms a frame, a 60
  fps budget: `union_demo`, `polkadots`, `tsl_hybridglenz`, the Union screens'
  `perFrame` limits, `stream_pacing`, `c_music`'s timeout). These run **alone,
  after the pool**, so our own parallelism can never fail them. Their thresholds
  are unchanged. A new harness that measures time must use `gate_timed`.
- `always <tag> <cmd>`: queued whatever the selection (verify, tunein_check).
- `early <tag> <cmd>`: started in the background at once (rom_abi_check, ~40 s,
  overlaps the native tests and the disk repack).
- `GATE_JOBS`: default half the cores, at most 6 (4 here). `GATE_JOBS=1` is the
  old serial gate. `GATE_TEST_JOBS` (default 4) runs the native tests.
- `GATE_JOB_TIMEOUT` (default 1800 s) kills a wedged harness, which then fails
  the gate instead of stalling a push for ever.

Also: `tools/mkdisks.sh` caches each ZX0-packed cart under the hash of the cart
AND of the packer (`zig-out/zx0cache/`), so an unchanged cart is not repacked
(the disk is still rebuilt and compared byte for byte); and the tlb_spoon harness,
which ran twice (once outside any `gate` line), runs once.

## Measurements (2026-09-27, 8 cores, 15 GB, box otherwise quiet)

Full gate, warm caches, before and after:

| phase | before (serial) | after |
|---|---|---|
| zig build (after a rebase) | 28.5 s | same |
| C + Rust carts, window checks | 2.5 s | same |
| rom_abi_check | 38.1 s | in the background |
| native tests (41) | 27.7 s | ~23 s (4 at a time) |
| mkdisks | 39.6 s | ~4 s (pack cache) |
| docs / disks / upload / tutorial checks | ~9 s | same |
| harnesses that may run in parallel (97 jobs) | 260 s | 108-128 s |
| wall-clock harnesses, alone (35 jobs) | 96 s | 96 s |
| **total** | **503 s** | **276 s** (default `GATE_JOBS=4`), 242 s (6), 300 s (3) |

The longest single jobs set the floor of the pool: rom_abi_check 40 s,
union_intro_wab 33 s, each of gen4_3615's four lines ~25 s.

RAM: the heaviest harness peaks at 309 MB RSS (union_intro_wab), most under
160 MB. Four at a time is under 1.3 GB; the box's used memory stayed at the
level it had before the gate (5.1-5.2 GB, mostly other processes). The bound is
CPU, which the box shares with whatever else is running: a gate measured at
~8 min alone takes several times that next to other builds, which is where the
45-minute pushes came from, and why one gate at a time still holds.

Through the hook:

| push | time |
|---|---|
| one screen (vex.zig) | 55 s |
| a shared file (libs/) | 298 s (full) |
| a tree already gated | 0 s |
