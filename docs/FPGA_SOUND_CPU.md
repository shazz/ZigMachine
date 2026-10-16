# The sound CPU

**Status (2026-10-10): built in simulation, not yet on the board.** Beat Dis plays natively at 43 % of a frame.

The sound CPU is a second VexRiscv. It runs the machine's players (`demo-audio.wasm` through wasm2c: the SNDH
player on Musashi, the MOD and YM players) next to the audio core, so the cart CPU keeps its whole frame. This page
replaces the survey in `FPGA_AUDIO_CPU.md`. The departures from that survey are in `decisions.md`
("2026-10-10 — The sound CPU").

## The block

`fpga/soc/zm_sound_cpu.py`, built with `hp_sim --sound-cpu` (`make soc-hp-snd`).

- **The core** is vexgen's `Snd` netlist: RV32IM with a 16 KiB 2-way I$ and a 4 KiB D$. Every module is prefixed
  `ZmSnd_` so it can sit next to the cart CPU's VexRiscv. It boots from `SOUND_BASE`, 14 MiB into the cart window.
- **Its memory is DDR on HP3.** It shares the port with the audio core's PCM reads through one Wishbone arbiter
  (I-bus, D-bus, the core's PCM port) in front of one `WishboneHP`, so no new HP port is used. Stores are
  **posted** (8 entries, `soc/zm_hp_posted.py`); see "Where the cycles go".
- **Its D-bus also reaches** `AUDIO_WINDOW`, the audio core's stamped write queue. Only the players push writes,
  so the queue moved off the cart CPU's bus.
- **The cart CPU sees `SOUND_WINDOW` only.** It copies the sound image to `SOUND_BASE`, sets RUN and forwards the
  cart's song requests (`fpga/cycles/bsound.c`).

## On the board

`soc.zigmachine_soc --target z7 --sound-cpu` (with the glass) builds the board SoC with the sound
CPU: `add_audio(sound=True)`, the same block as the sim's `hp_sim --sound-cpu`, with HP3 shared between
the sound CPU and the core's PCM reads through the arbiter. The CSR map is the same as without it:
the sound CPU's registers are a Wishbone window (`SOUND_WINDOW`), and the audio core's window moves
behind it. Its cart images are `ZM_AUDIO=snd` (`make board-fw ZM_AUDIO=snd CART=<cart>`, into
`build/hcycles/board_snd/`). They load the sound image, start it and forward the cart's song
requests through the mailbox, so the cart CPU spends almost nothing on the music.

Proved in sim (`hp_sim --sound-cpu`, `tools/audio_sim_run.py tutorial --model build/soc_hp_snd --audio snd
--frames 60`): the 523 song writes land at the machine's samples, same values, same order, and the core's
107,047 samples are bit for bit those of the core fed the machine's writes on the same timeline
(`tools/audio_core_replay.py build/hcycles/audio/tutorial_snd`). The `ym` sound comparison fails the same
way it does with the music on the cart CPU (jt49's envelope phase, [FPGA_AUDIO.md](FPGA_AUDIO.md)).

## Registers

`SOUND_WINDOW` = 0x93000000 (uncached), `soc/zm_sound_regs.py`:

| Word | Name | Cart CPU | Sound CPU | What |
|---|---|---|---|---|
| 0-31 | C2S | RW | R | commands, cart to sound |
| 32-63 | S2C | R | RW | answers and counters, sound to cart |
| 64 | CTRL | RW | R | bit 0 RUN: the sound CPU leaves reset |
| 65-67 | CYCLES, IBUS_WAIT, DBUS_WAIT | R | R | sys clocks: since reset, and spent waiting on each bus |
| 68 | PUTC | - | W | a character to the sim's console |
| 69 | ID | R | R | 0x5A4D5343 'ZMSC' |

Each bank has one writer, so no word ever has two masters.

## Mailbox

`fpga/cycles/snd_mailbox.h`.

- **Boot.** The cart writes a nonce to `C_SEQ`, then sets RUN. The sound CPU instantiates the players, echoes the
  nonce in `S_ACK` and sets `S_READY`. A nonce is used because S2C is the sound CPU's alone, and a previous run
  may have left `READY` set.
- **A command.** The cart waits for the previous ACK, then writes OP (PLAY or SNDH_CALL), ARG, the song's pointer
  and length in its own image, and the name. Then it bumps `C_SEQ`. The sound CPU acts on it, then echoes the SEQ.
  EFFECTS is the third op: see "Effects".
- **Between commands** the sound CPU renders whenever a frame (735 samples) is due. Its stdout goes to a 64 KiB
  ring at 0x41FEF000, which the cart prints between frames.

### Which songs a cart image holds

KESTREL has no file system for the players. Every song ZIGGY can ask BARD for is linked into the cart's own image
(`build/hcycles/songs/<cart>.c`, `fpga/tools/song_pack.py`), and the PLAY command points BARD at those bytes. The
table takes two sources. One is the songs the native host started in its first 600 frames with no input. The other is
every string literal in the cart that ends in a player's extension (`SONG_EXTS`, held to `host/audio.c`'s
`audio_play` by a test). A song a cart only reaches through input, like the jukebox's rows, gets in by the second
source alone.

**FastTracker 2 (`.xm`).** `host/audio.c` stages an `.xm` and calls `audioLoadXm` then `audioXmPlay` (its tune field
is the start BPM, 0 = the song's own tempo), the same way a `.mod` goes. The eight voices are mixed in software two
to a Paula channel (`libs/zig/players/xm.zig`), so the sound CPU needs no more channels than a MOD. Its 32-bit mixer
takes samples up to 32000 frames; a longer one is refused (`SampleTooLong`). The test song is `docs/music/zm_test.xm`
(`apps/xm_song.mjs` writes it).

**The bug this closed (2026-10-10).** `sap_test` (cart 86) played Warhawk on the board, but Enter did nothing. The
packer's extension list had no `.sap`, so the table held only Warhawk, the one song the 600 input-free frames
started. Every other request reached BARD with no bytes. BARD printed `ZM SONG MISSING` and Warhawk played on. Now:

- the packer takes `.sap`, so `sap_test`'s table holds all five files. BMX Simulator's three songs are tune numbers
  of one file, passed in `C_ARG`;
- a song-named literal that is no file under `docs/music/` fails the build (`song_pack: ... no such song`). It is
  no longer skipped;
- on BARD, a request with no bytes still prints `ZM SONG MISSING <name>`.

**Proof without a board.** `ZM_SIM_KEYS=F:event,...` (sim images only, `cycles/binput.c`) feeds the glass's key FIFO
from the same script as the native host's `ZM_GLASS_KEYS`. With `--keys`, `tools/audio_sim_run.py` presses the same
keys on both sides, and `tools/audio_sim_compare.py --songs` checks every song from its own start. The two sides
start a song at different samples: in the sim, `sap_test`'s frame takes about 2.05 Mcycles (20.5 ms at 100 MHz), so
the cart runs at 30 fps there. The sound is compared for the first song only, because a later song starts on chip
state (tone phases, polynomial counters) that the earlier song left after playing a different length of time on each
side.

    tools/audio_sim_run.py sap_test --model build/soc_hp_snd --audio snd --frames 16 --mode exact \
        --keys 3:100e020,4:e020,6:100000d,7:d,9:100e023,10:e023     # Up (to BMX), Enter, Right (song 2)

| Song | Samples | Writes | Differences |
|---|---|---|---|
| Warhawk.sap (at start) | 3,675 | 45 | 0, and the sound: 0 of 3,675 samples |
| BMX_Simulator.sap song 1 (Enter) | 2,205 | 24 | 0 |
| BMX_Simulator.sap song 2 (Right) | 11,760 | 123 | 0 |

`sap_test`'s image, all five tunes included: 1,719,888 bytes for ZM_AUDIO=snd and 1,694,304 for ZM_AUDIO=1, against
the 12 MiB cap in `board.mk`. The five files are 12,555 bytes.

## Effects

The cart's effects queue (`libs/zig/sfx_queue.zig`: `zg.sfxPlay`, `sfxStop`, `ymWrite`, `requestModVolume`,
`requestSndhMode`) reaches the players on the board as it does in the browser. Before this, the board's song
bridge carried only songs and `sndhCall`s, so on KESTREL with BARD, Beat Dis's keys 2 and 3 did nothing.

- **ZIGGY drains the queue.** `host/audio_bridge.c` reads `pollSfx` / `sfxEntriesPtr` after the frame's song
  request and `sndhCall`s, the order of `docs/sealed-loader.js` `postSfx`. A play whose bytes are not in the
  cart's memory is dropped and logged (`ZM FX sfxPlay out of the cart's memory`). The cart exports join the
  song bridge table (`tools/host_gen.py`).
- **The players apply each entry** (`host/audio.c` `audio_effects`) as `docs/audio-worklet-sealed.js` does:

| Entry | Applied on BARD (and on the native host, and on ZIGGY without BARD) |
|---|---|
| `requestSndhMode(m)` | `audioSndhMode(m)`, logged as `ZM SNDH mode asked m got g at <sample>` |
| `sfxPlay` | the PCM is copied into `audioSfxBufPtr` (none while no MOD plays), then `audioSfxPlay(len, rate, loop)` |
| `sfxStop` | `audioSfxStop(loop only)` |
| `ymWrite` | `audioSfxYm(reg, val)` |
| `requestModVolume` | `audioModGain(q16)` |

  A refusal is logged with the count, as the browser's console does (`ZM FX ymWrite refused (n so far)`).
- **Across the mailbox (ZIGGY to BARD)**, `OP_EFFECTS` carries ARG entries of 4 words each from `C2S` word 8:
  `op | a << 8 | b << 16`, the PCM's DDR address, len, rate. That is 6 entries a command. A frame's queue
  (at most 32 entries) goes over in as many commands as it needs, in order.
- **A play's PCM stays in the cart's memory.** BARD reads it while it runs the command, after it invalidates its
  D-cache. The browser copies the bytes as it drains the queue. So ZIGGY waits for the ACK of any command that
  holds a play, and the cart may then reuse its buffer the next frame.
- **Timing.** An effect takes hold at BARD's write stamp when BARD reads the command. That is up to the lead
  (3-4 frames) ahead of what is heard, the same latency as a song request. The browser applies it at the
  worklet's next block.

**The proof.**

- **Natively** (`tests/test_bard_effects.py`): union_beatdis's own key 3, sent through the glass's router
  (`ZM_GLASS_KEYS`), goes through the cart's queue and the bridge to the players. The result equals
  `sndh_oracle` switching to mode 3 at the same sample (`ZM_SNDH_MODE_AT`). Over 190 frames, that is
  78,808 writes, against 149,674 without the switch. Key 2 (the default mode) changes no write.
- **On BARD** (`tools/bard_fx_run.py`, `make snd-fx`): ZIGGY runs a scripted cart (`cycles/sound/sfx_cart.c`)
  over the real bridge and mailbox. It starts Beat Dis at frame 1, waits out the load (about 0.6 s on BARD), and asks for mode 3 five frames
  later. BARD runs
  the play image every cart uses. CHORUS's writes, from the audio tap, are compared with the oracle's at the
  sample where BARD applied the switch.
  BARD applied the switch 3,675 samples into the song. Over the 7,466 samples the tap holds, the core
  applied 2,667 writes, and they equal the oracle's with the switch: 0 differences. Without the switch,
  the oracle makes 5,112 writes over the same span (the YM volumes the PCM channel replaces).
- **The mutant** (`FX_DROP=1`) drops the request in `bsound.c`. Nothing reaches BARD, and the check fails.
  Its core writes equal the oracle's without the switch: 0 differences. Against the oracle with the switch,
  they part at the switch's sample (+3,675): the oracle zeroes the YM volumes and starts the PCM channel, and
  the core plays on.

The sim takes about 40 minutes (`ZM_BARD_SIM=1` runs it from the test; otherwise the test checks the last
run again). The scripted cart waits out the song's load before it counts frames. Without that wait, the
frames lost to the load were caught up at once, and the sim ended before the song was heard.

## Size

`fpga/tools/sound_ooc.py`: Vivado out of context on the xc7z010-1, the whole block (core, decoder, arbiter, posted
bridge, registers).

| Core | LUT | FF | BRAM tiles | DSP | Routed at 150 MHz |
|---|---|---|---|---|---|
| **I16w2D4 (the one built)** | 2353 | 1879 | 8.5 | 4 | WNS -0.049 ns: ~149 MHz |
| I32w2D16w2 | 2387 | 1887 | 15 | 4 | WNS -0.253 ns: ~145 MHz |

The core alone is about 1840 LUT; the glue is about 500. Inside the SoC both will close lower than out of context.
There is no clock-domain crossing: HP3's ACLK is the sys clock. A faster island would need one at the mailbox,
`AUDIO_WINDOW` and the PCM port, and was not built (see "beat_dis").

## Where the cycles go

The budget is 1.67 Mc per 60 Hz frame at 100 MHz. These figures are from the hp_sim, in Mc per frame:

| Tune | Cart core, original player | + Musashi patch + ReleaseFast | + posted stores | Sound core I32w2D16w2 |
|---|---|---|---|---|
| sos.sndh (50 Hz) | — | 0.21 | 0.19 | 0.19-0.29 (sound core I16w2D4) |
| wow_scroller | — | 2.12 | 1.87 | **1.22 (73 %)** |
| beat_dis (digi) | 8.0 | 5.87 | 5.19 | 3.85 (231 %) |

- **Stores dominated.** The D-cache is write-through, and a blocking store waits for its AXI B response.
  Musashi stores about 20 times per 68000 instruction. Posting 8 stores cut wow_scroller's D-bus wait by 85 %.
- **The Musashi patch** removes a per-instruction copy of the 16 registers that only bus-error handling reads
  (`libs/c/musashi/README.md`), -18 %.
- **ReleaseFast** for the board's players is another -10 %. It isn't used yet, because the browser's wasm would grow.

## Native players

**A digi tune is mostly per-interrupt overhead on Musashi, not emulation.** beat_dis interrupts 263 times per 60 Hz
frame. Each interrupt runs about 26 68000 instructions but costs about 14.6 k sound-CPU cycles. Overclocking can't
close that: the routed fmax is ~149 MHz, which still leaves 154 %. So a recognised driver gets **native
routines** instead (`libs/zig/players/digi.zig`):

- **Only the 68000 calls are replaced:** a driver's init / play / exit and its timer handler, written in Zig on the
  same bus functions Musashi uses. The SNDH player's clock, MFP, PSG and render loop are unchanged around them.
  The YM writes and their stamps therefore match by construction, and the tune's state stays in 68000 RAM. Either
  path can take over from the other at any point.
- **A driver is a handler and a sequencer.**
  - `digi_handler.zig` is the 3-voice volume-table byte replay, found in 11 SNDHs.
  - `digi_beatdis.zig` is Beat Dis's sequencer.
  - The rip is in `prototypes/beatdis_re/README.md`.
- **Recognition is all or nothing.** Both signatures must match (masked FNV hashes) and the tables must be in range.
  A handler with an unknown sequencer, or tables out of range, is a **near miss**: it plays on Musashi, and the
  console says so (`ZM SNDH near miss: ...`). No path is ever guessed.
- **The oracle** is `fpga/tests/test_sndh_native.py`. It compares the audio core's writes, digested per frame
  (`host/sndh_oracle.c`), between native and Musashi:
  - over the whole tune, past the loop's wrap (12,100 frames);
  - across a mid-tune `sndhCall`;
  - plus a mutant (no VBL overshoot) that must fail.
- **The write queue** (`host/audio_queue.h`): a digi tune writes 788 YM registers per frame.
  - The board drops volume writes that repeat the value last queued (47 % of beat_dis's).
  - It runs a 3-frame lead for a native digi.
  - The test models the queue over the whole tune: at most 1,738 writes in flight, against a depth of 2,048.

| beat_dis | x86 host | sound CPU |
|---|---|---|
| Musashi | 274 µs/frame | 3.85 Mc, 231 % (I32w2D16w2; more on I16w2D4) |
| **native** | 80 µs/frame (the host's software YM is most of it) | **0.71-0.73 Mc, 43 %** (I16w2D4): `make snd-bench SONG=union/beat_dis.sndh` |

On the sound CPU, native beat_dis showed no resync and no full queue over 8 frames, with status 0. Stalls are a
small share: the D-bus waited 136 k of the 715 k cycles. The rest is the SNDH player's glue per interrupt (the render block, the
MFP, the bus decode), about 2.2 k cycles each, against 14.6 k on Musashi.

### The modes (zg.requestSndhMode)

A screen picks how the SNDH playing is played (`libs/zig/players/sndh_native.zig`). Beat Dis's screen binds them
to 1, 2 and 3.

| Mode | What | Checked by |
|---|---|---|
| 1 | the tune's 68000 code on Musashi | the reference |
| 2 (default) | the native replay: the same writes | `test_sndh_native.py`, and switching 1/2 mid-tune changes no sample (`union_beatdis_headless.mjs` 3b) |
| 3 | native, the samples on a PCM channel at the timer's rate (8-bit, full rate, level matched by AC RMS: 129/256), from a converted copy | `test_sndh_native.py`: it follows the YM path (correlation 0.87), the raw bytes (mutant 2) do not; the YM path resumes on the same sample after |

- In mode 3 the timer still runs and moves the sample pointer; only its YM writes are left out.
  That is why a switch either way carries on from the same sample.
- **The bytes are not signed PCM.** Beat Dis's are unsigned and inverted: its volume table sums loudest
  at byte 0 and silent at 255. A PCM channel plays signed bytes, so until 2026-10-11 mode 3 folded every
  sample at its midpoint: "noisy plus weird loops" on the board, and the same noise in the browser,
  which no test listened to. The load now writes the samples converted (`127 - byte`) into a shadow above
  the image, reserved from the 68000's heap, and the channel plays that (ADR 2026-10-11).
- A mode that doesn't exist is refused (the answer is 0) and logged.
- A tune with no native driver answers 1 to modes 2 and 3, and the console says so.
- **On the board too** (since 2026-10-10): the song bridge carries the effects queue, so keys 1-3 switch the
  mode there as in the browser. See "Effects".

## The gap, and the next lever

The other 10 tunes with the same handler (Robocop, Sidewinder, Joe Blade 2, Dominator, Laser Dance, Tonic Tile,
Dark Sat, Guardians, Mach 3) still play on Musashi until each gets its own sequencer module. So does every other
digi SNDH. **On the sound CPU those cost 2-3× a frame, so they fall behind: the board's audio resyncs and drops
frames.** This is a known gap, not a silent degradation: `ZM AUD ... resyncs` counts it.

**The next lever is a cheaper Musashi interrupt entry.** The 14.6 k cycles per interrupt are mostly the glue around
26 instructions: `m68k_execute`'s entry and exit, the instruction hook, and the render block and MFP
bookkeeping per interrupt. Cutting that helps every digi SNDH at once, with no per-tune work.

## Phase B: Atari SAP tunes on the POKEY

The sound CPU also plays Atari 8-bit music: a `.sap` file's own 6502 code (`libs/zig/players/cpu6502*.zig`,
`sap_player.zig`) driving the machine's POKEY. Like everything here, it is part of `demo-audio.wasm`. The POKEY is a
chip of the sealed machine (`machine/audio/pokey.zig`) and of the audio core (`rtl/audio/zm_audio_pokey.v`,
`docs/FPGA_AUDIO.md`). The design decisions are in `decisions.md` ("SAP: a 6502 of our own").

| What | How it is held |
|---|---|
| the 6502 | 14,160 SingleStepTests vectors (MIT): registers, RAM, cycles, every bus write (`cpu6502_test.zig`) |
| the POKEY RTL | the model, every machine cycle, both clocks, 16 break tests (`test_rtl_pokey.py`) |
| the POKEY in the core | the machine, every sample (`pokey_exact` in `test_rtl_audio.py`, 7 break tests) |
| the SAP player | a synthetic TYPE B player assembled in the test, plus five ASMA tunes (`test_sap.py`) |
| the browser path | `apps/sap_check.mjs`: a PAL tone at its pitch to 0.2 %, unknown writes counted, STEREO refused; `--break ntsc` |
| the whole chain | Warhawk on the sound CPU (soc_hp_snd) into the audio tap equals the native host: 60 writes, 3,015 samples, 0 differences |
| against ASAP | optional, black box (asapconv, outside the repo): envelope correlation 0.86-0.94 on five tunes |

**Cost on the sound CPU** (I16w2D4, `make snd-bench MUSIC=<dir> SONG=Warhawk.sap`):
- **about 125-131 k cycles** a 60 Hz frame with a PLAYER call, **7.7 % of the frame**;
- about 3.5 k for a frame without one: PLAYER runs at 50 Hz, so one 60 Hz frame in six has no call;
- the load takes 0.5 M cycles. No resync and no full queue.

**Not played, and said so on the console:** TYPE D/S/R (IRQ-driven and the others), STEREO (a second POKEY).
ANTIC's DMA cycle-stealing is not modelled: the stamps are early by its share. The tunes are in
`prototypes/sap_asma/` (SOURCES.txt), not on the site: publishing them is Matt's call.
