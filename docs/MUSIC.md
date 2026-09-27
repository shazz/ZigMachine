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
| `.mod` | ProTracker 4-channel on the Paula channels: tags `M.K.`, `M!K!`, `4CHN`, `FLT4` only (a 6CHN / 8CHN file is **refused**, see below) | no |
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

## Sound effects: calling the running SNDH

A song request is a **load**: the host fetches the file, the player clears the
68000's RAM around the image, silences the YM, resets the MFP and runs INIT.
Right for a new tune; wrong for a game's sound effect, which would cut every
voice, envelope and digi still sounding, where the original lets them finish.

`zg.sndhCall(name, d0)` runs the **playing** image's INIT again, as a
subroutine with `d0`: no fetch, no reload, no chip or MFP reset. The replay
clock and every running timer keep their phase; afterwards the player re-reads
the MFP, so a timer INIT stopped stops and one it started is due a period from
then. The image decides what `d0` means. A driver that must not reinstall
itself takes a flag (Rick Dangerous's `sound.s`: bit 15 = resident); an INIT
that only points the replay at a new sequence (Joust's Dosound scripts, North
& South's `play_seq`) needs none.

```zig
zg.requestSongTune("rick_dangerous.sndh", sub);           // the first sound: a LOAD
_ = zg.sndhCall("rick_dangerous.sndh", 0x8000 | sub2);    // later ones: INIT on the running driver
```
```c
zm_sndh_call("joust_sfx.sndh", n + 1);            // C (returns 0 when refused)
```
```rust
zigmachine_music::sndh_call("joust_sfx.sndh", n + 1);   // Rust (false when refused)
```

The rules:

- **Every call of a frame gets through, in order** (up to 16 a frame; a refused
  call is counted: `zg.sndhCallsDropped()` / `zm_sndh_calls_dropped()`).
- **A song request or a stop made after calls discards them**: it reloads or
  stops the image they would run on. The host drains the calls after the
  frame's song request, so this keeps the two in the cart's order.
- **Calls land between two play ticks.** The worklet applies them between two
  render blocks (128 samples, 2.9 ms): every tick due before has run, the next
  comes on its old schedule. That is where a game's main loop calls its driver,
  between two VBL interrupts.
- **An image that is not the one playing is loaded first**, and the call's `d0`
  is its first INIT, unclamped (`audioSndhPlayRaw`). An image with a resident
  flag must handle that flag on a fresh load, so `sound.s` checks an
  `installed` byte before skipping the install.
- **An INIT that is called again must not allocate.** Only a load resets the
  68000 heap, so an INIT that asks GEMDOS `Malloc` for a buffer uses up more
  heap on every call. Allocate once, on the first INIT.
- **Calls made while sound is off are dropped, not kept.** A song request
  waits for the first gesture; a stale effect firing when sound comes on
  would be wrong.

Proofs: `apps/sndh_call_check.mjs` (a call leaves the untouched channel, Timer
A's phase and the position exactly as an untouched run's; a reload in its
place is caught) and the Rick Dangerous harness's resident check (the running
driver's RAM equals the cart's transcription, tick for tick, with later
requests, the paired shot and dynamite's double play among them).

## Sound effects over a MOD

A MOD has no code of its own to call, and it holds all four Paula channels. So a
cart playing a MOD hands the host its effects as **commands**, and the audio
thread plays them over the song (Zig only for now):

```zig
_ = zg.sfxPlay(gun_pcm, 12517, true);   // signed 8-bit PCM at 12517 Hz, looped
_ = zg.sfxStop(true);                    // stop it (true: only a looped effect)
_ = zg.ymWrite(8, 16);                   // a YM register (0-13), under the song
```

- **An effect borrows the song's quietest channel**: the one with the fewest
  notes over the song (each order entry counted as often as it plays). It plays
  there at full volume, which is `64/64 x 1/1.4`: still four channels at most,
  so the player's headroom stays exact. It uses that channel's own pan. The song
  goes on reading the channel row by row but writes nothing to it.
- **The channel goes back to the song** when a one-shot has played its last
  sample. A looped effect gives it back on `zg.sfxStop`, or after **4 s** with no
  stop, so a lost stop cannot keep it. After that, a looped sample the song holds
  there sounds again from its loop, and anything else waits for the channel's next
  note.
- **One effect at a time**: a new one cuts the last, as the ST's DMA chip did.
- **The YM is idle under a MOD**, so `zg.ymWrite` puts a PSG note under the song
  (an engine). The YM is mixed with the MOD from the first write. Writes are
  refused while an SNDH or a YM dump drives the chip.
- **The PCM is copied by the host at the end of the frame**, from the pointer the
  cart gave. It must stay where it is until then: an `@embedFile` does. It can be
  up to 64 KiB, at a rate of 1000-50066 Hz. The audio thread keeps it in the top
  64 KiB of song RAM, so a MOD larger than 960 KiB plays but refuses effects.
- **Commands are queued per frame, in order** (32 a frame). The host drains
  them after the frame's song request, and posts each one only once the load of
  a song requested before it has been posted. So an effect never lands on the
  song it was not meant for. A command refused by the queue is counted in
  `zg.sfxDropped()`. An effect with no MOD playing is refused and counted on the
  audio thread (`audioSfxRefused`), and the host logs a warning.
- **A new song takes back its channel**: a MOD request cuts the effect.

The path: `libs/zig/sfx_queue.zig` (the cart's queue; each entry 16 bytes: op,
a, b, pad, ptr, len, rate), `pollSfx` / `sfxEntriesPtr` (`apps/zig/demo_main.zig`),
`postSfx` in `docs/sealed-loader.js`, the worklet's `sfxPlay` / `sfxStop` /
`sfxYm` messages, and `audioSfxPlay` / `audioSfxStop` / `audioSfxYm` in
demo-audio.wasm (`apps/zig/demo_audio_mod.zig`, `libs/zig/players/sfx_voice.zig`).
The sealed machine-audio ABI is unchanged. The effect uses only
`machinePaulaTrigger` / `SetStep` / `SetVolume` and `machineYmWrite`.

**Only 4-channel ProTracker MODs load.** A `6CHN`, `8CHN` or `32CH` file has the
same header but more cells a row, so read as four channels it would play garbage
in time. The loader (`libs/zig/players/mod_format.zig`) refuses anything but
`M.K.`, `M!K!`, `4CHN` and `FLT4`, a file shorter than the 1084-byte header and a
song length of 0 or over 128. It counts each refusal (`audioModRejected`) with the
reason (`audioModError`: 1 short, 2 not 4-channel, 3 bad length), and the host
logs `MOD REJECTED` with the file's tag.

Proofs: `apps/mod_sfx_check.mjs` (every rule above, on the real audio modules),
`libs/zig/players/mod_format_test.zig` and `libs/zig/sfx_queue_test.zig` (native),
and SKYSTRIKE's ZIG mode (`apps/skystrike_zig_sound.mjs`: a game's own effects
and engine note over its flight MOD).

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
- **The MFP's interrupt controller is emulated** (`libs/zig/players/mfp.zig`).
  A timer calls its handler only while its IERA/IERB bit is set and its
  IMRA/IMRB bit is unmasked, as on the chip. Each tune starts with the MFP as
  TOS 1.04 leaves it: Timer C enabled, Timers A, B and D off. So an INIT enables
  its own timers, as it must on an ST (`Xbtimer` does it for you). Clearing a
  bit stops the handler but not the timer. That is how STOS's Maestro stops a
  digi, and how SID-voice tunes (Elite, Crystallized) silence a voice for a
  frame. The in-service registers are not modelled: a handler always runs to
  its `rte` before the next interrupt.
- **Ultrasonic tones are heard as their average.** A tone at period 0-5
  (25-125 kHz) is above the 44.1 kHz output's Nyquist frequency, so the sealed
  YM (`machine/audio/ym.zig`) gates it at 0.5, "open half the time". That is
  what the real chip's output and Hatari give. A point-sampled square would
  fold period 0 down to a 7300 Hz whistle. Digis (a volume per sample with the
  tone at period 0) and STOS's NOISE (mixer $C0) depend on it.

## Proving a tune plays (headless)

- `node apps/sndh_headless.mjs docs/music/<name>.sndh` runs an SNDH through the
  real audio modules and reports the subtunes, timers, YM registers and the
  output peak.
- `node apps/c_music_check.mjs` boots the C and Rust carts, polls their request
  the way the loader does, and plays it: it must reach SNDH mode with a non-zero
  peak. It runs in `./build.sh`.
