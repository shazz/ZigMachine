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
| `kestrel_ayumi.cpp` | built instead of upstream's `ayumi.cpp` (same API and chip model): the AY/YM stepped event to event in integers (tone edges, noise and envelope steps; what no channel hears advanced in bulk), each sample the exact average of its chip ticks (a box filter) instead of the cubic interpolator + FIR, a one-pole DC blocker. Any rate works; the cart runs 22.05 kHz (`kestrel_main.cpp`) |
| `patches/ayumi.h.sed` | `kestrel_ayumi.cpp`'s state at the end of `struct ayumi` |
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

## AY on BARD (design, 13 Nov; branch feat/chipnomad-bard)

Matt, 13 Nov: move the AY synthesis from ZIGGY to BARD, the way SID-WIZARD's SID went (`apps/ports/sidwizard/README.md`,
"The SID on BARD"). The goal behind it is reuse: a ChipNomad song should play in ANY demo, so the AY player is a
generic "AY chip on BARD" that any cart reaches through the BARD queue, and only the cart's playback code is
ChipNomad's. Status: design only. Nothing below is built yet (see the ROADMAP row).

### What exists (read for this note)

- The queue: `libs/zig/bard.zig` (Zig, the reference), `apps/ports/sidwizard/kestrel_sw_bard.c` (the C copy the
  cart uses), `fpga/cycles/bsound_bardq.c` (the cart side on ZIGGY's firmware), `fpga/cycles/sound/sbardq.c` (BARD),
  `fpga/host/bardq_pump.c` and `fpga/host/audio_bardq.c` (natively). A ring of 256 commands `{t, addr, value, seq}`,
  the cart writes the head, BARD takes what is due. The lead is 6144 output samples (~139 ms at 44.1 kHz). A full ring
  drops the write and counts it; BARD never waits.
- The player on BARD: `libs/zig/players/sid_live.zig` (cRSID's SID, mixed into CHORUS). It is the only player the queue
  feeds: the open command (`OP_BARD`) names no chip. The chip is chosen by the ADDRESS the cart writes: the queue's
  addresses are the C64's `$D400..$D418`, and `sid_live` takes them as SID registers.
- Timing: the stamps are output samples on the 44.1 kHz clock (`t = cycle x 32 / SampleClockRatio` in the SID cart).
  That is the queue's one time base.

### Message format (decision)

The ring entry does not change. An AY write is `{t, addr, value, seq}` with:

- `addr = 0xA000 | chip << 4 | reg`: `chip` 0..7 (one AY/YM per index; a project with three AYs uses 0..2), `reg`
  0..15 (the chip's registers, the 0x0D envelope shape included; a write to 0x0D always re-triggers the envelope, as on
  the chip). `0xA000..0xA07F` never collides with the SID's `0xD400..0xD418`. BARD dispatches on the address range: SID
  for `$D400`, AY for `$A000`, and a cart that wants both gets both.
- `t`: output samples at the queue's 44.1 kHz clock, the same as the SID's. Not AY clock ticks: one time base for every
  chip, and the ring's `t` already means that. Cost: a write lands up to half a sample (11 us) from its AY tick. The
  chip's tone counters are at the AY clock (the clock is the project's: 2 MHz on the ST; the ChipNomad default is not checked yet), so the error is
  below one tone step at the top octave; the comparison in step (d) measures it rather than assuming it.
- `value`: the register value as the cart's model takes it (the low 8 bits; the chip ignores the upper bits as it does).

### The chip model (one source)

`kestrel_ayumi.cpp` moves to `libs/c/ayumi/` (C, not C++: BARD runs C like cRSID, and the native host and the wasm cart
build the same file). Its API is upstream's `ayumi.h` (`ayumi_configure`, `ayumi_set_tone/noise/mixer/volume/envelope`,
`ayumi_set_pan`, `ayumi_process`, `ayumi_remove_dc`) with `float` where upstream has it. Floats on BARD are unverified: its
core is the sound CPU's (cost not measured), and the render is per output sample, so the "no float per frame" rule (CLAUDE.md) is a
ZIGGY rule; if a BARD float costs too much the measure in step (f) says so. The ChipNomad cart and the BARD player
call the same functions, so there is one model, not a fork.

### The BARD player (`ay_live`)

A Zig player beside `sid_live.zig`: takes the queue's commands with `addr` in the AY range, applies each at its sample
to the model (one `ayumi` per chip index), renders at 44.1 kHz, and mixes the stereo pair into CHORUS (ChipNomad's
per-channel pan stays: `ayumi_set_pan`). Check first: whether the SID's CHORUS output is stereo (`sid_live.zig`'s
output channels); if not, the pan is folded to mono and that is said in the report. Rate: 44.1 kHz on BARD (the
queue's rate, the SID's); the cart's 22.05 kHz path stays selectable for the comparison.

### The cart side

`apps/ports/chipnomad/kestrel_corelib.cpp` (the chip layer) posts each register write the tracker makes to the queue
instead of calling the model. Selection: at boot the cart asks the host for the queue (`hostBardAttach`, as the SID
cart does). Answer 0 (no queue: the native test host without BARD, an old board image) means the ZIGGY model runs, as
today. The default is BARD when the queue answers; a build flag `KESTREL_AY_ON_ZIGGY=1` forces the ZIGGY model for
measuring.

### What is NOT plain register writes (README lines 45-55)

Software-oscillator instruments (AY2 PWM, sync, samples, the timer callback `ayumi_set_timer_func`) step per chip tick
inside the model. Decision for v1: **they stay on the ZIGGY path, per chip** (a chip with such an instrument in use
renders on ZIGGY; the rest of the song's chips go to BARD). The reason is the ring's rate: BARD's ring takes 256 writes a
frame (~15,000 a second); a PWM at the AY clock needs one write per tick of its period, which is an order of magnitude
more than that. Finer-grained timed writes would not fit; running them on BARD would need the timer callback on BARD
(the player code moved, not the writes), which is a v2 question. One such instrument gets a test in step (b): the
per-chip fallback is checked to render the same as the all-ZIGGY build.

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

### Plan and proofs (steps b-h of the task)

- (b) `ay_live` + a native-host test (`fpga/host/audio_bardq.c` path, no board): random AY writes stamped at sample
  times, against the same model run directly; `--break` on a dropped write.
- (c) the cart posts (kestrel_corelib.cpp), ZIGGY fallback kept.
- (d) PCM comparison, `ports_headless.mjs chipnomad` (the AY Classic instrument) and `songs/MICROEGG.CNM`: exact if the
  sample rounding is zero, else RMS and spectral difference, with the reason.
- (e) build.sh gate lines for the new path, with a `--break`.
- (f) ZIGGY cycles before/after (`apps/frame_cost.mjs`, `tools/perf_audit.sh chipnomad`) and BARD load where measurable
  (`make snd-bench SND_BARDQ=1`, as SID's 58 %).
- (g) board staging: `prototypes/chipnomad_bard_card/` (MD5SUMS) per `.claude/skills/board-cart/SKILL.md`.
- (h) the ROADMAP row (added with this note).

### Open items, checked 13 Nov (second pass)

- **BARD stereo:** not settled. `libs/zig/players/sid_live.zig` and `fpga/host/audio_bardq.c` do not state a channel
  count, and docs/FPGA_AUDIO.md does not mention stereo. Needs the CHORUS mixer's port list.
- **ChipNomad's AY clock:** not settled. `ayumi_configure(clock_rate, sr)` is called from upstream's chip code with the
  project's clock; the cart's source does not pin a default. Needs upstream's `chip_ay` / project defaults.
- **Floats on BARD:** not free. `kestrel_ayumi.cpp` is float in `ayumi_configure` (ticks_q16 from `step`), `ayumi_set_pan`
  (sqrtf for the equal-power pan), the DAC table pointer, and the per-sample output scale (`* 1/32768`). The hot
  event-stepped loop is integer, but BARD needs an integer renderer (pan as a table, the DAC table as ints, output
  as ints), not the same file. So "one shared source" means a shared integer core with a float wrapper on the cart,
  which is a port with its own test, not a move.
- **Not built:** (b) to (h) need that integer core, the address dispatch in BARD's pump (fpga/host/bardq_pump.c and
  fpga/cycles/sound/sbardq.c), a BARD firmware rebuild, the cart posting and a comparison run. None is started.
