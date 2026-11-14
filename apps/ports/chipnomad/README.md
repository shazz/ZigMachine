# ChipNomad on the ZigMachine / KESTREL

[ChipNomad](https://github.com/Megus/chipnomad-tracker) (Megus, MIT) is an LSDJ-style tracker for the AY-3-8910 /
YM2149, in C++17. Its text screen is drawn in the Atari ST's 8x8 system font in 8x10 cells: 40x20 cells =
exactly a 320x200 plane. The cart is `docs/demo-chipnomad.wasm`, the program `BOOT.WSM` on the GEM data disk
`docs/demo-chipnomad.zmd`, with three of upstream's example projects (`songs/`: `MICROEGG.CNM`, `MICROPIZ.CNM`,
`WB7.CNM`, from `tracker/packaging/common/projects`, MIT as the tracker) for the PROJECT screen's Load. GEM boots
over the disk, a double-click on `BOOT.WSM` runs ChipNomad (it starts on an empty project); SETTINGS (SELECT +
Down from the song screen), "Quit ChipNomad", A goes back to the desktop (`../README.md`).

## Licence

`LICENSE` is upstream's (MIT, ChipNomad). The cart is built from upstream commit
`e4b10d550fa19e3a00c95689450f0a3f542d5589` (10 Oct 2026), which `../fetch.sh` clones untouched. Ours (MIT, as
the repo): every `kestrel_*` file, `patches/*.sed`, `Makefile`, `run.mjs`.

## Build

    apps/ports/fetch.sh
    make -C apps/ports/chipnomad link         # build/demo-chipnomad.wasm (byte-identical to docs/ at the pin)
    make -C apps/ports/chipnomad install      # copy it to docs/, repack docs/demo-chipnomad.zmd (tools/mkdisks.sh)
    node apps/ports_headless.mjs chipnomad    # the gate's check: boot, UI pin, X puts a chain in the song

Upstream's `version.cpp` shows `__DATE__`; the Makefile pins it to the upstream commit's date so a rebuild
is reproducible.

## Layout

| file | what |
|---|---|
| `kestrel_main.cpp` | the cart's exports: upstream's `main()` up to its main loop runs in `boot()` (after the C++ static constructors, `__wasm_call_ctors`: a cart has no `_start`), one pass of the loop per `frame(dt)` |
| `kestrel_corelib.cpp` | ChipNomad's platform layer (corelib) for the machine: colours get palette indices on first use and are drawn straight into VRAM, the frame's real time of audio to the machine's stream (`kestrel_audio.h`), files over the floppy |
| `kestrel_font8x10.cpp` | the ST 8x8 font in 8x10 cells |
| `patches/corelib_font.cpp.sed` | that font as the only resolution |
| `patches/project_io.cpp.sed` | no C++ exceptions on the cart: a throw logs its message and stops the cart |
| `kestrel_ayumi.cpp` | built instead of upstream's `ayumi.cpp`: upstream's API (float clock and pans) over the integer AY core every renderer shares, `libs/c/ayumi` (the chip stepped event to event, a sample the exact average of its ticks, a one-pole DC blocker; README there). Any rate works; the cart runs 22.05 kHz (`kestrel_main.cpp`) |
| `patches/ayumi.h.sed` | the core's state (`struct zm_ay`) at the end of `struct ayumi` |
| `kestrel_chip.cpp`, `patches/chipnomad_lib.cpp.sed` | the AY on BARD: ChipNomad's chip factory makes upstream's SoundChipAY with its writes also posted on the BARD queue ("AY on BARD") |
| `kestrel_bard.cpp` | the BARD queue's ring, the cart side (the C copy of `libs/zig/bard.zig`) |
| `tools/bard_compare.mjs` | BARD against ZIGGY on a song (`KESTREL_AUTOPLAY` builds) or the gate's script; `--dump` the commands for `snd-bench` |
| `patches/ayumi_filters.cpp.sed` | the FIR's double constants made float (the filters still link: `chip_ay.cpp` names them for its quality setting, which no longer changes anything) |
| `run.mjs` | headless runner for experiments |

Keys are ChipNomad's desktop mapping (A = X, B = Z, START = Space, SELECT = Left Shift, arrows).

## Status (2 Nov 2026)

- A fresh project's instruments are type None (silent): a note plays once its instrument has a type (on the
  instrument screen, A held + Right: AY Classic). The gate does exactly that (`ports_headless.mjs chipnomad`).
- KESTREL board (2 Nov, before perf/ports-synth): 11 fps, the song slow: upstream's ayumi cost ~4,900 cycles
  a 44.1 kHz sample (8 substeps, cubic interpolation and a FIR in float a sample) and needed rate >= clock / 64.
  perf/ports-synth: `kestrel_ayumi.cpp` at 22.05 kHz, ~1,000 cycles a sample including ChipNomad's mixer
  (frame_cost: cart 3.65 -> 0.46 Mc a frame playing, est 4.45 -> 1.18 Mc with FRESCO), ~22 % of ZIGGY for
  real time; the feed cap is back to 67 ms (a stall). Same pitch (zero crossings identical to upstream's
  stream), level within 10 % (rms 19.2 vs 21.0: the box filter keeps less of the top octave than the FIR).
  The chip state matches upstream's tick-by-tick model exactly (a 3,000-case native test of random register
  writes against upstream's update_mixer, during development). Software-oscillator instruments (AY2 PWM,
  sync, samples, ChipNomad's timer callback) still step tick by tick, as upstream: they cost more.
- Runs; read-only floppy (projects cannot be saved). A malformed project file stops the cart instead of
  showing an error (no exceptions).

## AY on BARD (13 Nov; branch feat/chipnomad-bard)

Matt, 13 Nov: move the AY synthesis from ZIGGY to BARD, the way SID-WIZARD's SID went (`apps/ports/sidwizard/README.md`,
"The SID on BARD"). The goal behind it is reuse: a ChipNomad song should play in ANY demo, so the AY player is a
generic "AY chip on BARD" that any cart reaches through the BARD queue, and only the cart's playback code is
ChipNomad's. **Built**: the sections below are the design as built; "Results" has the numbers (decisions.md
2026-11-13).

### The queue and the message format

The BARD queue (`libs/zig/bard.zig`; this cart's C copy `kestrel_bard.cpp`): a ring of 256 commands `{t, addr, value,
seq}` in the cart's memory, the lead 6144 output samples (~139 ms); a full ring drops the write and counts it, nobody
waits. `t` is an output sample on the queue's 44.1 kHz clock. Its devices are picked by address
(`libs/c/ayumi/zm_ay_bank.h`):

- `0xA000 + chip x 16 + reg`, `chip` 0..7: `reg` 0..13 the chip's registers (13 re-triggers the envelope), 14
  configure (bits 0-23 the clock in Hz, bit 24 YM; a fresh chip; under 8 Hz the chip off), 15 the pans of A, B, C
  (`k / 200` a byte each, bit 24 equal-power); `0xA080 + chip` its Q15 gain. A chip plays from its configure.
- One device an open: the first SID reset or AY configure picks it, the other's commands are refused (counted).

### The model, the device and the cart

- **One model**: `libs/c/ayumi` (C, integers only: BARD has no FPU and no divider). This cart calls it through
  `kestrel_ayumi.cpp` (upstream's float API), BARD natively (`fpga/host/audio_ay.c`), the page in
  `machine-audio.wasm` (`machine/audio/ay.zig`): `machineAyReset / Write / Render`.
- **The device** (`libs/zig/players/ay_live.zig`, in demo-audio.wasm): the due writes applied, then the chips rendered
  up to the next, at 44.1 kHz, so a write lands on its output sample; stereo on the four Paula channels.
- **The cart** (`kestrel_chip.cpp`): ChipNomad's chip factory (patched) makes upstream's SoundChipAY with three
  overrides. `setRegister` also posts, stamped with the audio callback's position x 2 (the cart runs 22.05 kHz: the
  tracker's ticks fall where they did on ZIGGY); `render` posts the project's clock, type, pans and `0.6 x mixVolume`
  when they change and renders nothing; a configure re-posts only the registers the tracker wrote (a fresh chip is the
  cart's own model, whose mixer and noise period are not the register view's 0x3F and 0). The queue is asked for during
  the first 60 frames, the stream quiet meanwhile; no answer (an old board image, a harness host) renders on ZIGGY as
  before, and so does a build with `KESTREL_AY_ON_ZIGGY=1` (`make EXTRA=-DKESTREL_AY_ON_ZIGGY=1`).
- **Software oscillators** (AY2 PWM, sync, samples, the timer callback `ayumi_set_timer_func`) step per chip tick
  inside the model: no register stream to post. The first one sends the **whole cart** back to ZIGGY (the queue closed,
  the stream started) until its chips are made again (a project load): the stream and the queue's player share the
  Paula channels and song RAM, so one chip on each cannot play. Running them on BARD needs the playback code there (v2,
  with the .cnm player).

### The .cnm player (later, not in this task)

Matt's goal: a demo cart plays a ChipNomad song with one call, as screens do with `zg.requestSong("x.sndh")`
(`libs/zig/players/players.zig` dispatches a format to its player). The boundary, kept clean now so the later work is a
move, not a rewrite:

1. **Playback core** (cart side, to come): the tracker's sequencer and project reader, without the UI. It turns a
   project into timed `(chip, reg, value, tick)` events at the tracker's tick rate. It must not know about the chip.
2. **Chip writes**: the event sink. Two sinks: the BARD queue (this design, any cart), and the ZIGGY ayumi (the tracker
   and the no-queue fallback). The `addr` encoding above is the only contract between them.
3. **BARD** (`ay_live`): renders the queue's writes. It knows nothing about songs.

A demo would then call `zg.requestCnm("x.cnm")` and get the core's events through sink 1. Upstream's tracker reads the
project through its own file classes and the UI through corelib; the core needs those reads cut from the screen code.
That cut is the work; the boundary above says where it goes.

### Proofs (build.sh)

- `bard_ay`: `libs/c/ayumi/check/check.sh` (the core = the old cart model, `--break`); `apps/ay_live_check.mjs` (wasm
  engine = native C; the queue player = the engine a lead late `>> 1`, stereo; refusals; `--break drop | late`).
- `ports_chipnomad`: `apps/chipnomad_bard_check.mjs` (the gate's C-4 on BARD: page = native host_audio both sides,
  nothing refused / dropped / re-anchored, no stream; `--break stamp | reg`); `ports_headless.mjs chipnomad` is the
  fallback (its host answers no queue).

### Results (13 Nov)

- **Stereo: yes.** CHORUS's mixer (`fpga/rtl/audio/zm_audio_mix.v`) sums the Paula channels with their pans into
  `pcm_l` / `pcm_r`, which go out as `smp_l` / `smp_r` (`zm_hdmi_out.v`); the YM and POKEY add to both sides. The AY
  device puts its stereo on the four Paula channels as the MP3 player does (a high and a low byte a side, `x >> 1`),
  so ChipNomad's ABC / ACB / BAC pans are kept. (The ZIGGY path folds to mono: the stream is 8-bit mono.)
- **The integer core** (`libs/c/ayumi`): every sample the same as this cart's ayumi before the move, 3,000 random
  chips and 9.84 M samples at 22050 and 44100 Hz (`libs/c/ayumi/check/check.sh`). The float set-up it replaced: the
  pans are a 201-entry table equal to `sqrtf` for every pan ChipNomad makes; the tick rate `clock x 8192 / rate` equals
  the float step's for every ChipNomad clock preset at 22050 / 44100 / 48000 Hz (1.5-3.7 % of arbitrary clocks drift
  1/65536 tick a sample). The rebuilt cart's stream was byte-identical to the old cart's.
- **ChipNomad's default AY clock: 1,773,400 Hz** (`tracker/src/project_utils.cpp:13`, the ZX Spectrum 128's; the
  presets are 0.75, 1, 1.75, 1.7734 and 2 MHz). It is per project: MICROEGG.CNM 1773400, MICROPIZ and WB7 1750000; the
  cart posts it with each chip's configure.
- **BARD vs ZIGGY** (`tools/bard_compare.mjs`, BARD folded to the stream's 8-bit mono 22.05 kHz): MICROEGG.CNM, 20 s:
  correlation 1.0000, 98.2 % of the samples equal, difference rms 0.14 LSB, rms ratio 1.001, zero crossings 25,832 vs
  25,818. The gate's C-4 (AY Classic), 6 s: 0.9997, 96.4 %, 0.60 LSB, the crossings equal. Not bit-exact by
  construction (two output formats, the 0.6 gain in Q15 against float).
- **ZIGGY** (`apps/frame_cost.mjs --bard`, MICROEGG playing, frames 121-180): 1.38 Mc a frame (p95 1.8, max 2.44; cart
  0.55) on ZIGGY -> 0.86 Mc (p95 0.91, max 0.92; cart 0.15) with the AY on BARD. FRESCO's 0.7 is most of what is left.
- **BARD**: BARD_LOAD_PLACEHOLDER
- **Not done**: the software oscillators stay on ZIGGY, whole cart (`kestrel_chip.cpp`: the stream and the queue's
  player share the Paula channels, so one chip cannot play on each); a sample preview (`previewSource`) is not heard
  while the AY is on BARD; a clock or chip type change restarts the chip's counters on BARD; one device an open (SID or
  AY, not both). BARD's F11 says "SID" while the queue plays the AY (one player id for the queue).
- **Risks on the board**: a host that never answers the queue (a ZM_AUDIO=1 image) keeps the stream quiet for the
  first 60 frames (~5 s at ChipNomad's board rate; it boots into an empty project, so nothing is lost). The stamps run
  on real time capped at 67 ms a frame (`kestrel_frame_us`): below ~15 fps a frame loses time and the next batch
  re-anchors the queue (`.resync`), heard as a stutter where the stream used to slow down; the harnesses run on dt.
