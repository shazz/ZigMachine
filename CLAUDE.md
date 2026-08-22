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

✅ **Migrated from Zig 0.10 → 0.16 and building/running again.** The `dbug` scene renders
in the browser at ~60fps; channel-switching to the prebuilt scenes works.

⚠️ **Audio is stubbed to silence.** The old embedded-sample approach is gone (lost `.smp`);
`generateAudio()` now zero-fills the buffers. The whole audio pipeline is being **rethought** —
see `docs/REVIEW.md` § Audio.

⚠️ **Only the `dbug` dependency graph was verified to compile.** Scenes not reachable from the
current `floppy.zig` selection got the same mechanical migration but are **unverified**, and two
known 0.16 blockers remain in code they use — see "Remaining migration work" in `docs/REVIEW.md`.

## Notes for future edits

- This is now **Zig 0.16** source. Install used here: `~/.local/zig/0.16.0/zig`.
- The dense border-opening render loop lives in `bootloader.zig` (~150-400). Tread carefully.
- Two front-ends exist and drift apart: `docs/loader.js` (active, no audio) vs
  `docs/zigloader.js` (audio, unused). See REVIEW.md.
