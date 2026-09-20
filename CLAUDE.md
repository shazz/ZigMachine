# ZigMachine — project rules for Claude sessions

## Music

- **The YM dump player (`libs/zig/players/ym_player.zig`, `.ym`/`.ymraw`) is DEPRECATED** (Matt, 2026-09-13). Every screen's music is an SNDH played by the 68000 SNDH player. Use a YM dump only as the last resort, when a real search of `prototypes/sndh_lf/` (via `tools/private_tools/sndh_index.py`) finds no SNDH of the tune, and record the best SNDH match score in the scene's music comment.

## Building

- **While iterating, gate only what changed** (Matt, 2026-09-19) — a bare `./build.sh` runs ~50 headless
  harnesses and takes far too long for a one-line edit:
  - `./build.sh --only <screen>` — one screen, e.g. `./build.sh --only stniccc`
  - `./build.sh --changed` — derives the screen set from the working tree
  The cross-cutting checks (`check_fits`, `ram_check`, `rom_abi_check`, `blitter_check`, `disk_check`,
  `upload_check`, `verify`, `tunein_check`) always run; only per-screen harnesses are skipped.
- **Run the bare `./build.sh` before pushing or merging.** `--changed` already falls back to the full
  gate when the diff touches anything outside `apps/zig/scenes/` or `apps/zig/assets/screens/`, because
  a change under `libs/`, `rom/`, `machine/`, `docs/*.js` or `build.zig` can break a screen whose own
  files never changed — the silent, cross-cutting failure the gate exists to catch.
- **Only ONE gate at a time on this box.** Two concurrent `./build.sh` runs have OOM-killed a push (#75).
  Check with `pgrep -f build.sh` first; sibling checkouts (`ZigMachine-*`) count.
- A screen is only covered if its harness is **named in `build.sh`**. `apps/stniccc_headless.mjs` existed
  for weeks without being called there, so that screen had no end-to-end coverage at all. When adding a
  harness, add its `gate <tag> node apps/<name>.mjs` line in the same commit.

## What a git worktree does NOT have

`.claude/`, `TODOS.md` and `tools/private_tools/` are gitignored and untracked, so a
`git worktree` (or a fresh clone) contains none of them. This file used to be untracked
too, which meant **an agent working in a worktree saw no project rules at all** — it
would happily ship a `.ym` dump and be correct by its own lights. That is why it is
tracked now.

The rest stays local-only by design, so if you are in a worktree:

- **`tools/private_tools/`** lives in the MAIN checkout only. Run those tools from there
  with an absolute path: `python3 /path/to/main/tools/private_tools/sndh_index.py <query>`,
  likewise `fetch_codef.py` (the CODEF fetcher — NOT `tools/fetch_codef.py`, which is a
  stale path some docs still use) and the per-screen `*_assets.py` converters.
- **`prototypes/`** (the SNDH archive, the CODEF mirror) is gitignored too — same rule,
  read it from the main checkout.
- If you are briefing an agent that will work in a worktree, **put the rules it needs in
  the brief**. It cannot read what is not there.
