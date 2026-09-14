# Music — the SNDH player, from Zig, C and Rust

ZigMachine plays real Atari ST music. An **SNDH** file carries the tune's own
68000 replay routine; the machine runs that code on an emulated 68000 (Musashi)
driving the sealed YM2149, exactly as the ST did. Nothing is pre-rendered, and
an SNDH is a few KB where a register dump is hundreds.

**A cart never links the player.** It asks the host for a tune *by name*, and
the host plays it on the audio thread. That is why the same four exports work
from any language.

```
cart (Zig / C / Rust)           host (docs/sealed-loader.js)          audio thread
requestSong("sos.sndh") ──►  polls pollSongRequest() every frame ──► demo-audio.wasm:
                             reads songNamePtr/Len + songTune         68000 runs the SNDH
                             fetches docs/music/<name>                 ─► sealed YM2149
```

## Formats

The file extension picks the player. Files live under `docs/music/`.

| Extension | Player | Subtunes |
|---|---|---|
| `.sndh` | the tune's own 68000 code on the sealed YM (preferred) | yes: `tune` counts from 1, 0 = the file's default |
| `.ymraw` | YM5!/YM6! register dump (**deprecated**, last resort only) | no |
| `.mod` | ProTracker 4-channel on the Paula channels | no |
| `.raw` | 8-bit PCM at 12517 Hz | no |

**The YM dump player is deprecated: use SNDH.** A dump records the chip only
once per frame, so SID voices, digidrums and samples played through the YM
volume DAC come out wrong (the Union Demo menu's dump turned its SID intro into
bleeps; the menu now plays the real `union/alloy_run.sndh`). A screen plays a `.ymraw` only as the last resort, when a real search
finds no SNDH of the same tune, and its music comment gives the best SNDH score. Prove a match by running both and comparing YM registers 0-5 and
8-10 frame by frame; a real match is ~100% (screen 34's
`SoWattTcbSprites.ym` == `sos.sndh`, 100% over 400 frames).

## Zig

```zig
const zg = @import("zigos");

zg.requestSong("rings_of_medusa.sndh");          // the file's default tune
zg.requestSongTune("leavin_teramis.sndh", 9);    // subtune 9 (counts from 1)
```

`apps/zig/demo_main.zig` already exports the four functions the host polls.
Request once, in `init()`: each request replaces the tune playing.

## C

```c
#include "../zigmachine_music.h"   // from exactly ONE .c file per cart: it DEFINES the exports

void boot(void) {
    zm_request_song("sos.sndh");                       // default tune
    // zm_request_song_tune("leavin_teramis.sndh", 9);  // subtune 9
}
```

`apps/c/zigmachine_music.h` defines `pollSongRequest`, `songNamePtr`,
`songNameLen` and `songTune` with `export_name`, so `apps/c/build.sh` needs no
change. Build with `bash apps/c/build.sh`. Example: `apps/c/scenes/screen34.c`.

## Rust

```rust
mod zigmachine_music;                                    // once per cart: defines the exports

zigmachine_music::request_song("sos.sndh");
zigmachine_music::request_song_tune("custodian.sndh", 1);
```

`apps/rust/zigmachine_music.rs` is the Rust twin of the C header. Build with
`bash apps/rust/build.sh`. Example: `apps/rust/scenes/v8_populous.rs`, which
plays David Whittaker's Custodian (`custodian.sndh`, subtune 1).

## Stopping the music

`"none"` is a reserved song name: requesting it stops whatever is playing (the
host resets the audio players, as it does when a program ends). No file under
`docs/music/` may be called `none`. A stop also cancels a song still being
fetched, so a slow earlier request can never start after it.

```zig
zg.stopSong();          // Zig
```
```c
zm_stop_song();         // C
```
```rust
zigmachine_music::stop_song();   // Rust
```

## Rules and limits

- **Names** are paths under `docs/music/`, at most 64 bytes, no `..` and no
  leading `/`. C and Rust calls return 0 / `false` and queue nothing for an empty
  or over-long name or a tune above 255 (Zig truncates a long name instead).
- **Sound starts only after a user gesture** (a click or key), as browsers require.
  A request made earlier waits and plays at the first gesture.
- **The machine reclaims the sound chip** when a program ends: leaving a screen
  silences its tune.
- **STE-DMA SNDHs** (`FLAG ~a`) may need the STE DMA sound chip, which this
  machine does not have. Listen before shipping one: some still drive the YM
  audibly (Sharpness Buzztone), others play silence.
- **Digidrum SNDHs** that start their drums through XBIOS `Xbtimer` are
  supported; a drum can begin late in the tune (Monty: 38.4 s).

## Proving a tune plays (headless)

- `node apps/sndh_headless.mjs docs/music/<name>.sndh` runs an SNDH through the
  real audio modules and reports the subtunes, timers, YM registers and the
  output peak.
- `node apps/c_music_check.mjs` boots the C and Rust carts, polls their request
  the way the loader does, and plays it: it must reach SNDH mode with a non-zero
  peak. It runs in `./build.sh`.
