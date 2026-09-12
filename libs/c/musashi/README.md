# Musashi — the 68000 the SNDH player runs on

An SNDH file is not a register dump, it is a **program**: 68000 code that pokes
`$FFFF8800/02` a few hundred times a second. To play one, the machine has to run
that code. This is the CPU it runs on.

The chip stays ours: `libs/zig/players/sndh_player.zig` traps the emulated PSG
writes and forwards them to the **sealed** YM2149 in `machine-audio.wasm`. So the
division of labour matches the real hardware — CPU emulated here, sound made by
the machine — and none of it happens in the page.

## Provenance

| | |
|---|---|
| Upstream | <https://github.com/kstenerud/Musashi> (`master`, v4.60) |
| Fetched | 2026-09-12 |
| Licence | MIT — see `upstream/readme.txt` |
| Local changes to `upstream/` | **none.** It is a byte-for-byte copy |

`upstream/` holds only what a 68000 build needs: `m68k.h`, `m68kconf.h`,
`m68kcpu.[ch]`, `m68kfpu.c`, `m68kmmu.h`, `m68k_in.c`, `m68kmake.c`, `softfloat/`
and `readme.txt`. The disassembler and the example host are not vendored.

To update: drop a new upstream tree into `upstream/`, rebuild, run
`node apps/sndh_headless.mjs`.

## How it is built (`addMusashi` in `build.zig`)

- **`m68kops.c` is generated, not committed.** Musashi's 1967 opcode handlers come
  out of `m68kmake`, so the build compiles that tool for the HOST, runs it, and
  feeds the result to the wasm compile. 800 KB of generated C stays out of the repo.
- **`config/zm_musashi.h`** is force-included (`-include`) ahead of every Musashi
  source. It has to work that way: `m68kcpu.h` says `#include "m68kconf.h"`, and a
  quoted include resolves next to the *including file* before it ever consults
  `-I`, so a shadowing `m68kconf.h` elsewhere is silently ignored no matter how
  early its directory appears — a dead config that still compiles. Every upstream
  option is wrapped in `#ifndef`, though, so defining them first wins and the
  vendored tree stays pristine. Pass the path **absolutely**: a relative
  `-include` lands in the dependency list as something Zig's cache cannot resolve
  and every C step fails with `CacheCheckFailed`.
- **`freestanding/`** supplies the handful of libc headers `wasm32-freestanding`
  does not have, plus `stubs.c` for the symbols that survive to link time. All of
  them belong to code a 68000 cannot reach (68881 FPU, 68030/040 MMU), so they
  trap rather than pretend — the exception being `setjmp`, which
  `m68k_execute()` genuinely calls to arm a bus-error trap and which therefore
  returns 0 for "no jump".

## What it costs

`demo-audio.wasm` goes from ~40 KB to ~1.05 MB. That is the opcode table, and the
68000-only settings in `zm_musashi.h` already fold away the 010/020/030/040 paths.
If it ever needs to shrink, the FPU and softfloat are the next things to go — they
exist only because `m68kcpu.c` includes them unconditionally.
