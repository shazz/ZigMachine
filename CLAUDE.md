# ZigMachine — project rules for Claude sessions

## Music

- **The YM dump player (`libs/zig/players/ym_player.zig`, `.ym`/`.ymraw`) is DEPRECATED** (Matt, 2026-09-13). Every screen's music is an SNDH played by the 68000 SNDH player. Use a YM dump only as the last resort, when a real search of `prototypes/sndh_lf/` (via `tools/private_tools/sndh_index.py`) finds no SNDH of the tune, and record the best SNDH match score in the scene's music comment.

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
