# `apps/rust/` — hello world in Rust

`hello.rs` — the same plasma as `apps/c/`, in `no_std` Rust, proving a Rust cart
drives the sealed `machine-video.wasm` (8-bit palette indices into the shared
video region) AND calls the Zig ROM chip: `rom.wasm` draws a GEM panel over the
plasma, which `apps/verify.mjs` reads back.

## The contract this app implements
- **Imports** (`#[link(wasm_import_module = "env")]`): `memory`, `hwVideoBase()`,
  `consoleLogJS`, and from the ROM (`rom/sdk/rom.zig`): `guiOpenPlane`,
  `romInstallPalettePlane`, `guiRect`, `guiFrame`, `guiText`.
- **Exports** (`#[no_mangle] pub extern "C"`): `boot`, `frame(f32)`,
  `isPlaneEnabled(i)->i32` (required), plus no-op
  `hblDispatch/skipBoot/setShadeMode/pointer/input`.
- **Draw**: palette-index bytes at `hwVideoBase()+OFF_VRAM`; RGBA palette at
  `+OFF_PAL` (**alpha 255 = opaque**). Offsets mirror `machine/sdk/memmap.zig`.
- **Link layout** (must match `build.zig`'s demo module): `--import-memory`,
  `--initial-memory=--max-memory=7340032` (112 pages), `--global-base=0x100000`,
  `--no-entry`.

## Music: `zigmachine_music.rs`
The Rust twin of `apps/c/zigmachine_music.h`: ask the host for a tune by name,
the same song bridge a Zig scene uses. The SNDH player is not linked into the
cart. It runs in `demo-audio.wasm` on the audio thread, and the loader polls
the cart once per frame.

```rust
mod zigmachine_music;                                   // once per cart: defines the exports
zigmachine_music::request_song("sos.sndh");             // a file under docs/music/
zigmachine_music::request_song_tune("leavin_teramis.sndh", 9); // subtune, from 1
```
- Declaring the module exports `pollSongRequest` (1 = new request, cleared when
  read), `songNamePtr`, `songNameLen`, `songTune`. `build.sh` needs no change.
- Tune `0` = the image's default. Both calls return `false` and queue nothing for
  an empty or >64-byte name or a tune above 255.
- `hello.rs` declares the module but requests nothing; `apps/c_music_check.mjs`
  checks that it exports the bridge and stays silent.

## Channel change: `zigmachine_tvnoise.rs`
The Rust twin of `apps/c/zigmachine_tvnoise.h`: the TV snow a Zig cart shows on
+/- (`tuneIn(25)`), byte for byte, then the cart starts exactly as after
`skipBoot`. Declaring the module defines `tuneIn`; `build.sh` exports it with
`--export-if-defined`, so carts without it still link.
```rust
mod zigmachine_tvnoise;
// frame():       if zigmachine_tvnoise::step() { return; }
// hblDispatch(): if zigmachine_tvnoise::hbl() { return; }
// skipBoot():    zigmachine_tvnoise::stop();
```
`v8_populous` (a channel) uses it; hello and tutorial are not channels and stay
minimal. Proof: `node apps/tunein_check.mjs`.

## Scenes: `scenes/<name>.rs`
One cart per screen, like `apps/c/scenes/`: `scenes/<name>.rs` is the crate root
(its submodules in `scenes/<name>/`, pulled in with `#[path]`), its generated data
in `assets/screens/<name>/` (`include_bytes!`), built to `docs/demo-rust-<name>.wasm`.
`build.sh` builds hello plus every scene, or just the ones named.

- **`v8_populous`**: CODEF screen 490, THE FABULOUS V8's Populous crack intro.
  The flash, the tiled background with the giant V8 fading in and out, the logo
  waving line by line, the ras-filled wave scroller and Totorman's bouncing member
  list. Requests David Whittaker's "Custodian" (`custodian.sndh`, subtune 1)
  through `zigmachine_music.rs`; `apps/c_music_check.mjs` proves it plays. On the
  menu as V8 POPULOUS (RUST), or `?demo=demo-rust-v8_populous.wasm`.

## Prerequisite
```bash
rustup target add wasm32-unknown-unknown
```

## Build & run
```bash
bash apps/rust/build.sh                        # -> docs/demo-rust.wasm (bundled rust-lld)
node apps/verify.mjs docs/demo-rust.wasm       # headless ABI check
cd docs && python3 -m http.server 3333
# open http://localhost:3333/sealed.html?demo=demo-rust.wasm
```
No system `wasm-ld` needed — rustc bundles `rust-lld`.
