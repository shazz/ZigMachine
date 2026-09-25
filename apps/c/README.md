# `apps/c/` — hello world in C

`hello.c` — an animated plasma proving the sealed ABI is language-agnostic. Same
`machine-video.wasm` as the Zig demo, driven from C: two imports
(`env.memory` + `hwVideoBase()`), a handful of exports, 8-bit palette indices
written straight into the shared video region.

## The contract this app implements
- **Imports** (`env`): `memory`, `hwVideoBase()`, `consoleLogJS(ptr,len)`.
- **Exports**: `boot()`, `frame(f32)`, `isPlaneEnabled(i)->bool` (required), plus
  no-op `hblDispatch/skipBoot/setShadeMode/pointer/input`.
- **Draw**: palette-index bytes at `hwVideoBase()+OFF_VRAM`; RGBA palette at
  `+OFF_PAL` (**alpha 255 = opaque**). Offsets mirror `machine/sdk/memmap.zig`.
- **Link layout** (must match `build.zig`'s demo module): `--import-memory`,
  `--initial-memory=--max-memory=5177344` (79 pages), `--global-base=0x100000`,
  `--no-entry`.

## Music: `zigmachine_music.h`
A C cart asks the host for a tune by name, the same song bridge a Zig scene
uses (`zg.requestSong` / `zg.requestSongTune`). The player is NOT linked into
the cart: SNDH runs on the emulated 68000 in `demo-audio.wasm` on the audio
thread, and the loader polls the cart once per frame for a request.

```c
#include "../zigmachine_music.h"   // from exactly ONE .c file per cart
void boot(void) {
    zm_request_song("sos.sndh");                      // a file under docs/music/
    // zm_request_song_tune("leavin_teramis.sndh", 9); // a subtune, counted from 1
}
```
- The header **defines** the four exports the host polls: `pollSongRequest`
  (1 = new request, cleared when read), `songNamePtr`, `songNameLen`, `songTune`.
  They carry `export_name`, so `build.sh` needs no change.
- The extension picks the player: `.sndh` / `.mod` / `.ymraw` / `.raw`. Tune `0` =
  the image's default; only an SNDH has subtunes.
- Both calls return 0 and queue nothing for a null, empty or >64-byte name or a
  tune above 255. Nothing plays until the user turns sound on; the request waits.
- `screen34.c` uses it. Proof: `node apps/c_music_check.mjs`.

## Channel change: `zigmachine_tvnoise.h`
On +/- the host calls `tuneIn(25)`; a Zig cart shows TV snow first, a cart
without `tuneIn` just cuts in. This header is that snow, byte for byte (same
PRNG, seed, ramp, band and plane setup as `apps/zig/demo_main.zig`). It defines
the `tuneIn` export and saves and restores what the snow overwrites, so the
cart starts exactly as after `skipBoot`. Three hooks:
```c
#include "../zigmachine_tvnoise.h"          // from exactly ONE .c file per cart
void frame(float dt)  { if (zm_tvnoise_frame()) return; ... }
void hblDispatch(...) { if (zm_tvnoise_hbl()) return; ... }
void skipBoot(void)   { zm_tvnoise_stop(); }
```
`screen34.c` (a channel) uses it; hello and tutorial are not channels and stay
minimal. Proof: `node apps/tunein_check.mjs`.

## `fujiboink.c`: a source port of an ST program
Xanth Park's FujiBoink! (START, Fall 1986), C to C from FUJIBOIN.C, with
FUJISTUF.S in `scenes/fujiboink/fujistuf.h`. What it shows a C cart can do:
- **ST bitplane semantics on a chunky plane**: each pixel holds the 4-bit value
  of the four ST planes, palette entries 0..15 are the colour registers.
- **Real rasters**: Timer B becomes the plane's HBL (`FB_HBL_ID`), which rewrites
  palette entries 4..7 per line.
- **Page flipping**: the second screen is plane 1's buffer, shown by writing
  `FB_BASE` at the VBL (Setscreen).
- **Blocking code**: the original waits for the VBL anywhere; here every waiting
  function is a protothread (`PT_YIELD` = `xbios(37)`).
- **Data by `#embed`**: `assets/screens/fujiboink/FUJIBOIN.D8A`, made by the
  original generators in Hatari. The thud is an SNDH (`thud.s`) requested per
  bounce, because a cart cannot write the YM directly.
Proof: `node apps/c_fujiboink_headless.mjs`, against Hatari captures.

## Build & run
```bash
bash apps/c/build.sh                          # -> docs/demo-c.wasm (uses `zig cc`)
node apps/verify.mjs docs/demo-c.wasm         # headless ABI check
cd docs && python3 -m http.server 3333
# open http://localhost:3333/sealed.html?demo=demo-c.wasm
```
No system `wasm-ld` needed — `zig cc` bundles lld.
