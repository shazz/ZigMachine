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

## Build & run
```bash
bash apps/c/build.sh                          # -> docs/demo-c.wasm (uses `zig cc`)
node apps/verify.mjs docs/demo-c.wasm         # headless ABI check
cd docs && python3 -m http.server 3333
# open http://localhost:3333/sealed.html?demo=demo-c.wasm
```
No system `wasm-ld` needed — `zig cc` bundles lld.
