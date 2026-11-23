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
| `.xm` | FastTracker 2, up to 12 channels, mixed in software onto the four Paula channels (two voices a channel up to 8 channels, three a channel for 9..12; `libs/zig/players/xm.zig`, see [XM](#xm-fasttracker-2) below) | no |
| `.raw` | 8-bit PCM at 12517 Hz | no |
| `.mp3` | streamed by the cart (`zg.mp3Ctl/Feed/Status`), see [MP3](#mp3-mpeg-1-mpeg-2-and-mpeg-25-layer-iii) | no |
| `.sap` | an Atari 8-bit tune's own 6502 code on the machine's POKEY (`libs/zig/players/sap_player.zig`): TYPE B and C, mono; D/S/R and STEREO are refused, with the reason on the console | yes: `tune` counts from 1, 0 = the file's DEFSONG |
| `.kt` | a klystrack song: klystron's cyd synth and music.c sequencer in integer Zig (`libs/zig/players/kt.zig`), bit-exact against upstream, its 16-bit stereo on the four Paula channels (see [KT](#kt-klystrack) below) | no: `tune` is the sequence row to start at (0 = the start) |
| `.sid` | a Commodore 64 **PSID** (HVSC): its 6502 code and the SID on cRSID (Hermit, `libs/c/crsid`), 22.05 kHz mono on the four Paula channels (see [SID](#sid-commodore-64) below). An RSID is refused: "RSID not supported" | yes: `tune` counts from 1, 0 = the file's default |
| `.vgm` `.vgz` | a Mega Drive / Genesis **VGM** (YM2612 + SN76489, the DAC, data blocks, DAC streams): our own MIT chips (`libs/c/vgm`), 26.6 kHz stereo on the four Paula channels (see [VGM](#vgm-mega-drive) below). A `.vgz` is inflated by the engine; a file over ~960 KB, or with neither chip, is refused | no: it plays from the top, looping where the file says |
| `.hip` | a Jochen Hippel **Amiga** module as UADE plays it: the module's own 68000 replay on the SNDH player's Musashi, poking an emulated Paula (`libs/zig/players/hip_player.zig`, `paula.zig`) on the four sample channels. A file that is not a `bra` jump table plus a `TFMX` song is refused | yes: `tune` counts from 1, 0 = the first song |

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

A tune that is not a file under `docs/music/` (one a program read off its own disk through the
drive, as a GEM program reads its data files) plays from the cart's memory instead:

```zig
const n = zg.disk.read(entry, buf);                         // the file, a block at a time
_ = zg.requestSongBytes(buf[0..n], .sndh, 0);               // or .sap / .xm / .hip / .kt / .sid / .vgm; copied this frame
zg.stopSong();                                              // stops it, as it stops a named one
```

It rides the effects queue (`libs/zig/sfx_queue.zig`, op 8): a `requestSong` made in the same
frame is applied first. SysInfo's SOUND page plays the SNDH, the SAP and the PCM on its disk
this way (`apps/zig/scenes/sysinfo/sound_play.zig`). On the board the sound CPU's bridge has no
op 8 yet: it is dropped there until it does.

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

Proofs: `apps/harness/sndh_call_check.mjs` (a call leaves the untouched channel, Timer
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
zg.requestSong("flight.mod");
_ = zg.requestModVolume(0.2);            // that song's own channels at 0.2 (-14 dB)
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
- **The music can be turned down under the effects**: `zg.requestModVolume(gain)`
  scales the song's own channels by `gain` (0..1), at once and from then on. The
  effect's borrowed channel is not scaled: it stays at `64/64 x 1/1.4`, the most
  the headroom allows, which is why the song comes down rather than the effect
  going up. A gain below 1 only lowers the worst case, so nothing clips that did
  not. Each MOD load starts at 1.0, so the call follows `zg.requestSong` in the
  same frame; it is queued with the effects, after that load. NaN or a gain
  outside 0..1 is refused and counted in `zg.sfxDropped()`, never clamped; with
  no MOD playing it is refused on the audio thread (`audioSfxRefused`).
  SKYSTRIKE's ZIG mode plays its flight music at 0.2: at 1.0 "The Hawk's Claw"
  with one channel lent is -19.8 dBFS RMS and its effects -27 to -29, 8 dB under
  it; at 0.2 the bed is -33.8 and every effect 4.6 to 7.0 dB over it
  (`apps/harness/skystrike_zig_mix.mjs` measures it on the audio modules).
  The YM has no such gain (it is the machine's): a game's PSG note is made
  quieter by sounding it on fewer of the YM's three voices (SKYSTRIKE's
  `psg_voices`: one voice is -9.5 dB).

The path: `libs/zig/sfx_queue.zig` (the cart's queue; each entry 16 bytes: op,
a, b, pad, ptr, len, rate), `pollSfx` / `sfxEntriesPtr` (`apps/zig/demo_main.zig`),
`postSfx` in `docs/sealed-loader.js`, the worklet's `sfxPlay` / `sfxStop` /
`sfxYm` / `modGain` messages, and `audioSfxPlay` / `audioSfxStop` / `audioSfxYm` /
`audioModGain` in demo-audio.wasm (`apps/zig/demo_audio_mod.zig`,
`libs/zig/players/sfx_voice.zig`, `ModPlayer.setGain`). A gain entry is op 4 with
the gain x 65536 in `len`.
The sealed machine-audio ABI is unchanged. The effect uses only
`machinePaulaTrigger` / `SetStep` / `SetVolume` and `machineYmWrite`.

**Only 4-channel ProTracker MODs load.** A `6CHN`, `8CHN` or `32CH` file has the
same header but more cells a row, so read as four channels it would play garbage
in time. The loader (`libs/zig/players/mod_format.zig`) refuses anything but
`M.K.`, `M!K!`, `4CHN` and `FLT4`, a file shorter than the 1084-byte header and a
song length of 0 or over 128. It counts each refusal (`audioModRejected`) with the
reason (`audioModError`: 1 short, 2 not 4-channel, 3 bad length), and the host
logs `MOD REJECTED` with the file's tag.

Proofs: `apps/harness/mod_sfx_check.mjs` (every rule above, on the real audio modules),
`libs/zig/players/mod_format_test.zig` and `libs/zig/sfx_queue_test.zig` (native),
and SKYSTRIKE's ZIG mode (`apps/harness/skystrike_zig_sound.mjs`: a game's own effects
and engine note over its flight MOD).

## XM (FastTracker 2)

`zg.requestSong("song.xm")` plays a FastTracker 2 module, in the browser and on
BARD. Its voices are mixed onto the four Paula channels, two a channel up to 8
channels and three a channel for 9 to 12, so a song of more than 12 channels is
**refused** (`audioXmError` 5), as are a version before 1.02 and a truncated file. The player follows FT2 for the envelope (sustain, loop,
fadeout), key-off (it cuts a note with no envelope), the instrument number's
volume reset, both frequency tables, and effects 0-6 9 A-F K E1 E2 E9-EE plus
the volume column's set and slides. It ignores tremolo, panning, global volume,
tremor, multi-retrigger, extra-fine slides, auto-vibrato and the panning
envelope (`xm.zig`'s header lists them all). There is no interpolation and no
volume ramping: the voices play through 8-bit buffers, like Paula.

A ScreamTracker 3 module becomes an XM with `tools/s3m2xm.py in.s3m out.xm`
(`--drop 6,7,8,9` removes tracks; by default all are kept). It prints what XM
cannot carry: channel panning, global volume and unmapped effects.

**Check a song against a reference player**, not by ear alone: ffmpeg's
libopenmpt renders a module (`ffmpeg -i song.xm -ar 44100 ref.wav`), and the
song rendered through `demo-audio.wasm` should match it second by second. A
real 1995 S3M, converted, matched at a spectral similarity of 0.995, in tune in
90 % of the windows. The player's own generated test song (`apps/harness/xm_song.mjs`,
`testSong(8)` and `testSong(12)`) is for the harnesses, built in memory: it is not
shipped as music.

**A tracker module needs a licence that allows bundling it.** The Mod Archive's
default "Mod Archive Distribution license" allows redistributing the original,
unmodified file only, not converting it or bundling it in a cart or a firmware
image. Pick a Public Domain or Creative Commons module, or the artist's
permission, and record the source URL, artist and licence in the scene's music
comment and here.

### Bundled modules

The XMs the carts ship (music debug key 5, XM TEST keys 1 and 2), each the
archive's file byte for byte (`apps/harness/xm_test_check.mjs` holds the md5s):

| File | Title, artist | Channels, size | Licence | Source | md5 |
|---|---|---|---|---|---|
| `keygen_9000.xm` | "Keygen 9000", Drozerix (chiptune) | 8, 55 KB | Public Domain | https://modarchive.org/module.php?173938 | `02b1f1dad70ea15a0b064c45468caa55` |
| `poppy_flower_girls.xm` | "Poppy Flower Girls", Drozerix (demo style); `drozerix_-_poppy_flower_girls.xm` on the archive | 12, 91 KB | Public Domain | https://modarchive.org/module.php?175325 | `251ef415c7e4a64b589f2fc3f86582df` |

What the player leaves out of them (`xm.zig`'s ignored list): the volume column's
vibrato in both, and in Poppy Flower Girls the 8xx panning, the Hxx global volume
slide and the volume column's panning slide.

The klystrack songs (`.kt`), upstream's example songs (kometbomb/klystrack, MIT, `apps/ports/klystrack/data/*.KT`
copied byte for byte with lower-case names). KT TEST (keys 1-4) plays them. `apps/harness/kt_test_check.mjs` holds the md5s:

| File | Size | md5 |
|---|---|---|
| `starport2.kt` | 1,822 B | `0246c50252e717ea7677fefb5c044ea4` |
| `castlevania.kt` | 2,793 B | `9657f6b0554d8df5548bb35c3f91cef5` |
| `oceanloader3.kt` | 8,144 B | `22139dc5dbaf6df1ec72b35b2db25775` |
| `dpintro.kt` | 9,725 B | `eaee7e7520571ce27a857b7edcd58e68` |

The Amiga modules (`.hip`), each modland's file byte for byte, renamed without spaces:

| File | Title, artist | Size | Source | md5 |
|---|---|---|---|---|
| `shaolin_title.hip` | "Chambers of Shaolin" title tune (Thalion, Amiga), Jochen Hippel: the Supplex FS2 screen's (CODEF 525) | 36,032 B | https://ftp.modland.com/pub/modules/Hippel/Jochen%20Hippel/shaolin%20title.hip | `48e2ebc6c7588bee78796281b677facc` |
| `rings_of_medusa.hip` | "Rings of Medusa" (Starbyte, Amiga), Jochen Hippel; 2 songs. Its replay waits on the beam (VHPOSR) | 69,540 B | https://ftp.modland.com/pub/modules/Hippel/Jochen%20Hippel/rings%20of%20medusa.hip | `024e14d61ff6c311a1d7df52a7d40700` |

The game's ST SNDH is a different arrangement (Matt listened), so the screen plays the
Amiga module, not the SNDH.

**A song you may only keep for yourself** goes in `docs/music/local.xm`, which
git ignores. The music debug screen plays it on key 6, XM TEST on key 3. In the browser it is fetched like any other song. On the
board, songs are linked into the firmware, so build `make board-fw CART=music`
with the file in place: `fpga/tools/song_pack.py` packs `local.xm` when it is
there and leaves it out, with a note, when it is not. That firmware then holds
the song: keep it off anything you publish.
SID TEST's keys 1-4 work the same way: four HVSC tunes (`cybernoid_ii.sid`,
`wizball.sid`, `commando.sid`, `club_style.sid`, the list in `song_pack.py`
`LOCAL_SONGS`), gitignored, copied from the SID study's set; without them the
screen says "NOT ON THIS MACHINE".

## KT (klystrack)

`zg.requestSong("song.kt")` plays a klystrack song, in the browser and on BARD. The player
(`libs/zig/players/kt*.zig`) is klystron's own engine ported line for line to integer Zig: the
sequencer (patterns, sequences, instrument programs, every command), the synth (pulse, saw,
triangle, noise and LFSR oscillators, the SID and YM envelopes, the ladder filter, ring
modulation, hard sync, FM, wavetables) and the FX buses (chorus, the 16-tap reverb, the bit
crusher). It runs at the klystrack cart's 22050 Hz with no oversampling, only the song's
channels, and skips the oscillator reads of a channel nobody hears.

**It is bit-exact against upstream.** `apps/ports/klystrack/kt_ref` builds upstream's cyd and
music.c untouched (from `apps/ports/fetch.sh`) and renders a song as the klystrack cart plays it;
`tools/kt_render.zig` renders the same song with the player; the four bundled songs are byte
identical for 300 s. The gate pins 45 s of each (`libs/zig/players/kt_core_test.zig`,
`apps/harness/kt_check.mjs`). What "upstream" means where it is not defined:

- the chorus delay curve is the klystrack cart's integer one (`kestrel_chorus.c`, within 1/256 of a
  sample of upstream's double `sin()`), computed when read rather than held as a 4 s table a bus;
- `get_freq` reads one entry past the frequency table for a note in the top semitone (95.01-95.99):
  the cart has 0 there, so 0 it is (kt_ref's `freqs.sed` makes upstream read the same);
- the random LFO shape's table is glibc's first 128 `rand()` (klystrack on Linux); the cart's
  wasi-libc gives another. No bundled song uses that shape;
- libm's constants (pan and reverb gains, the vibrato sine) are upstream's exact values,
  generated by `apps/ports/klystrack/kt_ref/kt_tables.c` into `kt_tables_gen.zig`.

**Output:** cyd's 16-bit stereo, each sample held for two 44.1 kHz frames, on the four Paula
channels as a high and a low byte a side (high byte at volume 511/256, low byte at 2/256, hard
left and right): `s = 256 h + l` plays as `(511 h + 2 l) / 65536`, the sample at full scale to
within 1/512 of gain and half a 16-bit step, from 8-bit channels and no machine change. The scope
view is the MOD's (mode 1): channels 0-1 show the wave, 2-3 its low bytes.

**Refused** (`audioKtError`): not a klystrack song (1), a version before 8 or after 27 (2), a
truncated file (3), more than 16 channels (4), tables over the song RAM (5), more than 8 FX buses
or a reverb tap above 0 dB (6), a bad wavetable (7), a pattern index or program out of range (8),
FX delay lines that do not fit the song RAM at start (9). Memory: the song's tables, 2 s of reverb
line a reverb bus (176 KB at 22050 Hz) and the chorus lines live in song RAM after the file.

**From memory:** `zg.requestSongBytes(bytes, .kt, row)` plays a .kt the cart holds (effects queue op
8, kind 5); the row to start at rides the entry's 32-bit last word, so a C cart can ask for a row past
255 (`apps/ports/klystrack/kestrel_bard.c` does: the klystrack tracker's Play hands its song over this
way, see its README).

**Cost on BARD** (16 KB D$ core, `make snd-bench`, Mc of a 60 Hz frame's 1.67): oceanloader3 0.44,
castlevania 0.48 (row 98), dpintro 1.28 (row 788: 1.17), starport2 1.03 (row 250) but 2.10 in its
intro (row 0: five FM-on-wavetable voices at once, 126 %). The synth runs a block at a time between
sequencer ticks (`kt_block.zig`), each channel on a copy of its state in a loop built for the
features it uses; ring modulation or hard sync in effect falls back to a sample at a time.
`apps/harness/kt_cost.mjs` ranks the player's code by function without a sim.

## SID (Commodore 64)

`zg.requestSong("tune.sid")` plays a C64 **PSID** (the HVSC format), in the browser and on BARD:
cRSID (Mihaly Horvath "Hermit", `libs/c/crsid/README.md`, credit him) runs the tune's 6502 code and
the SID in its light engine at 22.05 kHz mono, and `libs/zig/players/sid.zig` plays it on the four
Paula channels as MP3 does (a high and a low byte a side), upsampled to 44.1 kHz. BARD runs cRSID as
native C; the page runs the same C in machine-audio.wasm, and `apps/harness/sid_check.mjs` holds the two to
the same samples. `zg.requestSongBytes(bytes, .sid, subtune)` plays a .sid the cart holds (op 8,
kind 6): the path a C64 port takes for the tune on its own disk.

**RSID is refused** ("RSID not supported", status 2): an RSID is a real C64 program whose IRQs and
NMIs cRSID runs on every C64 cycle, ~2x BARD (docs/hardware/studies/SID_BARD_STUDY.md). Digi tunes are mostly RSID.
**Cost on BARD:** 48-60 % of a 60 Hz frame on PSID tunes (1x and 4x, 6581 and 8580, filtered), the
start ~0.5 Mc once. No Paula sound effect while a SID plays.

| File | What | md5 |
|---|---|---|
| `hermini.sid` | HerMiniSID by Hermit, cRSID's own test tune (379 B, 8580) | `537f693740ed05502fc23151381082d9` |

## VGM (Mega Drive)

`zg.requestSong("tune.vgm")` (or `.vgz`) plays a Mega Drive / Genesis VGM, in the browser and on BARD, on
our own YM2612 and SN76489 (`libs/c/ym2612`, `libs/c/sn76489`, `libs/c/vgm`: MIT, written from the
hardware documents; `libs/c/vgm/README.md` has the sources, the limits and the accuracy against the Gens
core). The chips render at the YM2612's clock / 288 (26,634 Hz NTSC) in stereo; `libs/zig/players/vgm.zig`
plays it on the four Paula channels as MP3 does, resampled to 44.1 kHz (that stage is C too, `zm_vgm_out.c`). BARD runs the C natively; the page
runs the same C in machine-audio.wasm, and `apps/harness/vgm_check.mjs` holds the two to the same samples.
`zg.requestSongBytes(bytes, .vgm, 0)` plays one the cart holds (op 8, kind 7), a `.vgz` included.

The file sits whole in song RAM: up to 983,040 bytes (a `.vgz` and what it inflates to likewise). Played:
the YM2612 (both ports, the DAC by 0x8n, 0xE0 and the 0x90-0x95 streams, type-0 data blocks), the SN76489
(Game Gear stereo too), the loop. Skipped: other chips, second chips, timers (no CSM).
**Cost on BARD:** ~58 % of a 60 Hz frame on Green Hill Zone's busy part, ~66 % with all six FM channels (peaks 65 % / 73 %), 26,634 Hz with the DAC and PSG (docs/hardware/studies/YM2612_BARD_STUDY.md section 6). No Paula sound effect while a VGM plays.

| File | What | md5 |
|---|---|---|
| `kestrel_fm.vgm` | KESTREL FM, VGM TEST's tune: written by `libs/c/vgm/make_tune.py` for this repo (MIT), six FM channels + DAC drums + PSG, 31 s loop | `0a722a24357c0c003ab6f3e90b814bc7` |
| `kestrel_fm.vgz` | the same, gzipped | `7c22417f14adc706a54e09d12b9d9789` |

## MP3 (MPEG-1, MPEG-2 and MPEG-2.5 Layer III)

`zg.mp3Ctl` / `mp3Feed` / `mp3Status` (the MP3 PLAYER cart, `C:\MUSIC`): a cart streams the
file's bytes in, pvmp3 (`libs/c/pvmp3`, integer) decodes them on the sound side and the 16-bit
PCM plays on the four Paula channels (`x >> 1`, 15 bits). Not a file kind the host fetches by
name: the cart owns the bytes. The status word's rate code (bits 4-7): 1 = 32 kHz, 2 = 44.1,
3 = 48, 4 = another, 5 = 22.05, 6 = 24, 7 = 16, 8 = 12, 9 = 11.025, 10 = 8 kHz.

| Stream | Samples a frame | To the chip's 44.1 kHz | Proof (`apps/harness/mp3_check.mjs`) |
|---|---|---|---|
| MPEG-1 44.1 kHz, stereo or mono | 1152 | sample for sample, **bit-exact** against a host decode | pinned hash of the reference >> 1 |
| MPEG-1 32 / 48 kHz | 1152 | linear, not bit-exact | output pinned |
| MPEG-2 22.05 / 24 / 16 kHz, MPEG-2.5 11.025 kHz, stereo or mono | **576** | 22.05 is an exact x2 and 11.025 an exact x4 (every 2nd / 4th output sample IS a decoded source sample, the ones between the linear midpoints); 24 and 16 kHz linear, the position counted in 1/44100ths so nothing drifts | the decimated output = the host decode >> 1 (pinned), midpoints within 1, length, rate code, a 1000 Hz tone read back by Goertzel, mono on both sides, output pinned |

A mono stream plays on both sides. The player's own decode never assumed 1152: it takes the
sample count from pvmp3 per frame; only the cart's clock did (it showed `--` and 00:00 for any
rate under 32 kHz, fixed with the rate codes above). The last source sample of a stream is not
played (the player ends as the converter asks for the one after it): at 22.05 kHz that is one
sample of 45 microseconds.

**For a long soundtrack, 22.05 kHz mono at 64 kbps** (MPEG-2): 8 KB of file a second (8 s fill
the 64 KiB input ring, half the 4 s of a 128 kbps stream), a decode of 576 samples of one
channel a frame, and under 11 kHz of audio bandwidth (the stream's Nyquist). Song RAM is the same for every format, 214 KB of the player's window: the
64 KiB input ring, 32 KiB feed staging, a 2 KiB frame, the PCM (4.75 KB, of which a 22.05 mono
frame uses 1.1 KB), the decoder state (about 28 KB of the 48 KB reserved), then the four Paula
rings. BARD cost (`make snd-bench SONG=<file> MUSIC=$PWD/../apps/zig/assets/mp3 SND_MP3=1 ZM_FRAMES=6`,
cycles a 1.67 Mc frame; measured 14 Nov 2026 on the `soc_hp_snd_dyn8sx` model, steady frames 2-5):

| Stream | average | peak (a frame that decodes) | frame without a decode |
|---|---|---|---|
| 44.1 kHz mono (MONO44) | 373k = 22 % | 601k = 36 % | 147k = 9 % |
| 22.05 kHz mono 64k (LSF22M) | 332k = 20 % | 452k = 27 % | 212k = 13 % |
| 44.1 kHz stereo 128k (TONES44, the earlier combo16 core) | 52.4 % | | |

Mono is the big saving. 22.05 kHz halves the decode (576 samples a frame: the peak drops from 36
to 27 %) and the file, but the general linear 22.05 -> 44.1 conversion adds ~65k cycles a frame
(~4 %); an exact x2 path (repeat and average) would recover most of it. (TONES44 no longer fits
the bench image's 2 MiB flash beside the players: 46 KB over.)

Test files: `apps/zig/assets/mp3/LSF*.MP3` (a 1000 Hz sine, self-generated, `make.sh` there).

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

- `node apps/harness/sndh_headless.mjs docs/music/<name>.sndh` runs an SNDH through the
  real audio modules and reports the subtunes, timers, YM registers and the
  output peak.
- `node apps/harness/c_music_check.mjs` boots the C and Rust carts, polls their request
  the way the loader does, and plays it: it must reach SNDH mode with a non-zero
  peak. It runs in `./build.sh`.
