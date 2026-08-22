# ZigMachine

A fantasy console written in **Zig**, compiled to `wasm32-freestanding-musl`, rendered to
`<canvas>` in the browser. Ports of oldskool Atari/Amiga cracktro effects run as "channels".

## Quick Reference

- **Stack:** **Zig 0.16.0** → WebAssembly + hand-written JS/HTML front-end (no bundler) + Python asset tools
- **Build:** `zig build -Drelease=true -Dwasm` (outputs `docs/bootloader.wasm`)
- **Run:** `cd docs && python3 -m http.server 3333` → `/` or `/debug.html`
- **Pick a scene:** compile-time, edit `src/floppy.zig` (currently `dbug`)
- **Orientation / where I stopped / open questions:** see **`docs/REVIEW.md`** ← read this first

## Status (2026-08-22)

✅ **Sealed hardware — VIDEO layer implemented & proven in-browser.** The machine
is now two builds: sealed `machine-video.wasm` + open `demo.wasm` share ONE
`WebAssembly.Memory` via a memory-mapped ABI (`src/sdk/`). `music_debug` runs
**unchanged** at ~60fps against the sealed machine — open `docs/sealed.html`
(`zig build -Dwasm` → `machine-video.wasm`, `demo.wasm`, `audio.wasm`). Audio
module split + §11 repo reorg are the next steps. See `docs/HARDWARE_SPEC.md §12`.

✅ **Migrated from Zig 0.10 → 0.16 and building/running again.** The `dbug` scene renders
in the browser at ~60fps; channel-switching to the prebuilt scenes works.

⚠️ **Audio is stubbed to silence.** The old embedded-sample approach is gone (lost `.smp`);
`generateAudio()` now zero-fills the buffers. The whole audio pipeline is being **rethought** —
see `docs/REVIEW.md` § Audio.

✅ **All demo channels migrated & rebuilt.** Every scene wired as a channel compiles on 0.16;
all 16 `docs/wasm/*.wasm` were rebuilt from fresh source (`the_union` has no source scene, kept
as-is). Four non-channel scenes are still broken — `demo`, `demo_test`, `bladerunners_fullscreen`
(scratch/experimental, stale API — real rework), `tex` (missing asset). See `docs/REVIEW.md`.

## Notes for future edits

- This is now **Zig 0.16** source. Install used here: `~/.local/zig/0.16.0/zig`.
- The dense border-opening render loop lives in `bootloader.zig` (~150-400). Tread carefully.
- Two front-ends exist and drift apart: `docs/loader.js` (active, no audio) vs
  `docs/zigloader.js` (audio, unused). See REVIEW.md.
