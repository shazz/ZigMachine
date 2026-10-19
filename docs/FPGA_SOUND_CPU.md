# The sound CPU

**Status (2026-10-10): built in simulation, not yet on the board.** Beat Dis plays natively at 43 % of a frame.

The sound CPU is a second VexRiscv. It runs the machine's players (`demo-audio.wasm` through wasm2c: the SNDH
player on Musashi, the MOD and YM players) next to the audio core, so the cart CPU keeps its whole frame. This page
replaces the survey in `FPGA_AUDIO_CPU.md`. The departures from that survey are in `decisions.md`
("2026-10-10 — The sound CPU").

## The block

`fpga/soc/zm_sound_cpu.py`, built with `hp_sim --sound-cpu` (`make soc-hp-snd`).

- **The core** is vexgen's `SndNd` netlist: RV32I + Zmmul with a 16 KiB 2-way I$ and a 4 KiB D$. Every module is
  prefixed `ZmSnd_` so it can sit next to the cart CPU's VexRiscv. It boots from `SOUND_BASE`, 14 MiB into the cart
  window.
- **It has no divider** (vexgen `nodiv`, 2026-10-15): -191 LUT, -106 FF in the board SoC. DIV/REM trap, so its
  firmware is built `-march=rv32i_zmmul` and divides in libgcc; `snd.elf` is refused if a DIV/REM gets in.
  `cycles/sound/zmmul.c` gives that libgcc a hardware `__mulsi3`/`__muldi3`. Cost in `make snd-bench`, Mc per
  frame: beat_dis 0.889 -> 1.015 (53 % -> 61 %, its player divides), wow_scroller 2.173 -> 2.161, Warhawk
  0.097 -> 0.113.
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
is the start BPM, 0 = the song's own tempo), the same way a `.mod` goes. The voices (up to twelve) are mixed in
software onto the Paula channels (`libs/zig/players/xm.zig`): two to a channel for up to 8 channels, three to a channel
for 9..12, so the sound CPU needs no more channels than a MOD. Its 32-bit mixer
keeps each position as a 32-bit frame index plus a 16-bit fraction, so a sample has no length cap beyond song RAM. The bench's test song is `testSong()` from
`apps/xm_song.mjs`, written outside `docs/music` (it is not shipped) and benched with `MUSIC=<that dir>
SONG=zm_test.xm`; the carts ship real modules (docs/MUSIC.md "Bundled modules"). Each block is mixed into the next span of a 16 KiB ring per Paula channel
(`xm_ring.zig`), never into one reused buffer: the audio core plays a stamped trigger up to the lead (four frames)
after BARD wrote it, and a single buffer had been overwritten by three or four later blocks by then. The board played
that as noise while the browser, whose chip reads the buffer at once, played the song (2026-10-17).

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
| `samplePlay` | `audioStreamStart(rate)`, then `host/audio_pcm.c` refills the stream ring from the cart's bytes before every render, 4 KiB ahead of the channel, looping or to its end (then `audioStreamStop`); the worklet's `refillSample` is the same |
| `sampleStop` | `audioStreamStop()`, if a sample plays |
| the stream imports | `zg.audioStreamStart` / `audioFeed` / `audioStreamStop` are env imports, not queue entries. `tools/host_gen.py` routes them through `host/hstream.h` to `host/audio_bridge.c`, which applies each at once (mid-frame, as the browser posts them) as an effect `0x81..0x83`. A feed's bytes are copied while BARD runs its command (ZIGGY waits for the ACK), since a cart may reuse its buffer within the frame |

  A refusal is logged with the count, as the browser's console does (`ZM FX ymWrite refused (n so far)`).
- **Across the mailbox (ZIGGY to BARD)**, `OP_EFFECTS` carries ARG entries of 4 words each from `C2S` word 8:
  `op | a << 8 | b << 16`, the PCM's DDR address, len, rate. That is 6 entries a command. A frame's queue
  (at most 32 entries) goes over in as many commands as it needs, in order.
- **The stream ring was silent on the board until 2026-10-17**: the three stream imports were `host_gen`'s no-op
  stubs, so ST Replay's F10 and `stream`'s music fed nothing. A `samplePlay` sample is read from the cart's
  memory in DDR for as long as it plays (BARD flushes its D-cache when the command arrives); the cart keeps it.
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

### Monty (Mad Max, Timer D digidrums)

TEX NEO SHOW plays Mad Max's "Auf Weidersehen Monty - digidrums" (1987, ripped by Mr Styckx, converted by
Grazey). Its driver starts MFP Timer D through XBIOS Xbtimer at 2457600 / 4 / 58 = **10,593 Hz from the
first frame**: about 176 interrupts per 60 Hz frame, drum or no drum. On Musashi that put BARD over its
budget, and the music played at about half speed on the board. Only this SNDH of the 5,897 in the
collection has the driver, so it is a native replay of its own (`libs/zig/players/digi_monty*.zig`), held to
Musashi like Beat Dis's.

**The rip** (offsets are the file's; the driver was assembled at $46A86 = file $40E, its song at
$60000 = $3A9E, its drums at $40500 = $F9E; `digi_monty_map.zig` names every state byte):

| Where | What |
|---|---|
| $86 INIT | first time only (word $AA): save 19 MFP bytes and 5 vectors at $1CA ($146), relocate ($1FC); then the driver's INIT $40E |
| $1FC | every long of the driver (word-stepped, to $F9E inclusive) in $46A86..$47616 moves; NOPs at driver +$500/$502/$572 (play's SR writes) and +$B48/$B4C (a `move.b #2,$484`); 20 drum pointers, 5 song pointers and every song long in $60000..$60D2A move |
| $40E | the drum's end pointer cleared, Xbtimer(D, /4, 58, $44C), the song's setup $EDA (the YM's 13 registers zeroed and written, four voices of $40 bytes at $70C) |
| $44C Timer D | if a drum plays (word $4D4 not $FFFF, pointer $448 not at end $444): one byte s onto volume C as `(s >> 1) + 8` (the samples are 4-bit); else it marks the drum idle. Software end of interrupt on ISRB |
| $320 PLAY | every SPEED frames each voice reads a row ($B82: notes, commands $80..$93 through the table at $984, $B8+ speed, $C0+ arpeggio, $D0+ envelope, $E0+ length); every frame each voice's period, vibrato, slide, envelope and mixer ($CE6), then registers 12 down to 0, register 10 left out once command $92 gives channel C to the drums |
| $9D4 (command $91 n) | drum n: start and end from the tables at $556 / $57E |
| $A4 EXIT | the MFP and vectors put back, two writes to the FDC's $FF8606 / $FF8604 |

The drums own channel C from frame ~2,305 (38.4 s); the song wraps at frame ~21,889 (6 min 5 s). Every row
of the song uses only commands the table covers.

**The proof:**
- `fpga/tests/test_sndh_monty.py`: the audio core's writes, a digest a frame, native = Musashi over
  23,000 frames (past the wrap, drums included), across a `sndhCall` and across mode switches 1/2 mid-drum.
  Mutant 3 (volume C written over the drums) must fail; one byte changed in the driver plays on Musashi; the
  board's queue stays under its depth at the general 4-frame lead.
- `apps/monty_native_check.mjs` (gate `tex_neoshow_music`, and its `--break`): in the browser's own modules,
  native = 68000 bit for bit over 50 s of samples, and 2-1-2-1-2 switching changes no sample. So the browser's
  output is unchanged.
- Mode 3 (PCM) has no Monty path: asked for it, the player answers 2.

The movem save of the drum trigger ($516) holds the 68000's d7, which only goes back into a register: the
native replay stores 0 above its low byte. Nothing reads it.

**Cost on BARD** (`make snd-bench SONG=auf_weidersehen_monty_digi.sndh`, soc_hp_snd, 8 frames from the start,
before the drums):

| Monty | Mc per 60 Hz frame | of 1.67 Mc |
|---|---|---|
| Musashi (before) | 3.35-3.86, about 3.61 | 216 % |
| **native** | **0.41-0.47, about 0.44** | **26 %** |

No resync and no full queue. On x86 (the oracle, 20,000 frames) it went from 362 to 141 µs per frame; the
host's software YM is most of what remains. Once the drums play, each interrupt does a few more bus accesses.
The sim cannot reach frame 2,305, so that case was not measured on BARD.

### Wow Scroller (MAN Cool, Timer A digi)

The Union Demo's TCB2 WOW!-SCROLLER plays `union/wow_scroller.sndh`: Timer A at 2457600 / 4 / 81 = 7,585 Hz,
about 126 interrupts per 60 Hz frame. The board measured it at 125 % of BARD (the OSD page). It is Beat Dis's
sibling, also converted by Grazey: one byte per interrupt through **the same volume table**, but indexed by the
raw byte (no `addi.b #$80`) and written with `movep.l` + `movep.w` (registers 8 and 9 through the PSG's
$8804/$8806 mirrors, then 10). Its 15 rows (start, length) at $B78 become a playlist at $AF8, which the 50 Hz
play moves along once the pointer is past the segment's end (the same overshoot as Beat Dis). Its init looks
up the `_MCH` cookie and picks the handler with `cmpa.w #3,a0`, which compares the word's **address**, so the
choice is always $202. `libs/zig/players/digi_wow.zig` is the native replay, Status 6.

Mode 3 now works for any byte-per-tick driver (`digi.Pcm`, `sndh_pcm.zig`). Wow's bytes are Beat Dis's
(unsigned, inverted), so the same `linear()` and the same 129/256 level apply. The TCB2 screen binds keys
1/2/3 to the modes, as BEAT DIS does. The default is 2, so the browser's output is unchanged.

**The proof:** `fpga/tests/test_sndh_wow.py`:
- native = Musashi over 4,500 frames (the playlist wraps at about 2,005), across a `sndhCall` and 1/2 switches;
- mode 3 differs only while it is on, follows the YM path, and the raw bytes do not;
- the queue holds;
- mutant 4 (Beat Dis's handler on Wow's bytes) fails.

`apps/wow_native_check.mjs` (gate `union_superscroller_music`, with `--break`) checks the browser's modules:
native = 68000 bit for bit over 40 s, and mode 3 correlates at 0.95 and hands back on the same sample.

**Cost on BARD** (`make snd-bench SONG=union/wow_scroller.sndh [SND_MODE=3]`, soc_hp_snd, 8 frames):

| Wow Scroller | Mc per 60 Hz frame | of 1.67 Mc |
|---|---|---|
| Musashi (before) | 2.65-2.69 | 160 % (the board's OSD showed 125 %) |
| **native, mode 2** | **0.48-0.49** | **29 %** |
| **native, mode 3** (PCM) | **0.24-0.25** | **15 %** |

No resync and no full queue in any of the three.

### Quartet (SingSong, Timer A, the state in registers)

The Dune Gen4 Demo's title and F3 play `dune_gen4_quartet.sndh`: Audio Visual Research's SingSong replay
(`prototypes/dune_gen4_re/quartet/`), four sample voices mixed by a Timer A interrupt at 2457600 / 4 / 38 =
**16,168 Hz**, about 270 a 60 Hz frame, with the sequencer on Timer C (PLAY, TC200). The survey put it at
11.8 k 68000 instructions and 273 Musashi calls a frame: **~374 % of BARD** (273 × 17.8 k + 11.8 k × 100
+ 0.2 M = 6.2 Mc), so the music played slow on the board.

Its handler is small, but its state is not in RAM: d0-d3 are the four voices' positions (offset word,
fraction word), a0-a3 their samples and a4 the PSG, left live in the registers between interrupts, and the
sequencer starts a note by writing d_i and a_i itself. `libs/zig/players/digi_quartet.zig` (status 9,
handler only, `digi_irq.zig`) therefore reads them from Musashi's register file at each interrupt and writes
back what the 68000 leaves (`Bus.getReg` / `setReg`, 10 reads and 6 writes), so a PLAY in between sees
exactly the 68000's registers. The Timer A vector is the SNDH glue's wrapper (it saves d0 to memory, since
the engine's PLAY arrives with d0 = 0); the driver follows its `ta_orig` to SingSong's handler at arming,
checks the handler and its wrap routine (relocated absolute addresses in the holes) and reads the table,
the four step longs, the four loop longs and the silence buffer off the instruction stream. A loop long with
a low word ($FFFFFFFF: no loop) sends a finished voice to 256 bytes of silence; a loop length is subtracted.

**The proof:** `fpga/tests/test_sndh_irq.py`: all four subtunes native = Musashi over 4,000 frames each,
across a `sndhCall` and 1/2 switches; mutant 7 (the sample index read unsigned) fails from frame 2;
and the survey must show Musashi called at most 4 times a frame (the PLAYs), because a handler refused
in RAM would pass the digest trivially. `apps/irq_native_check.mjs --song dune_gen4_quartet.sndh --status 9`
(gate `dune_gen4_music`, with `--break --mutant 7`): the browser's modules, 40 s bit for bit, modes
2-1-2-1-2 unbroken. Unit tests: `digi_quartet_test.zig`.

**Cost on BARD**: the survey estimated 1.0-1.1 Mc (60-66 %) with ~2.5 k cycles a native interrupt; snd-bench
(soc_hp_snd, 8 frames, subtune 1) measured **1.94-2.18 Mc, 117 %**, down from ~374 % but still over: a native
interrupt costs ~6.9 k on BARD, not 2.5 k (see "Every cart's music"), and Quartet takes 270 a frame.

## Every cart's music on BARD (2026-10-18)

`fpga/tools/bard_load_survey.py` runs every subtune of every SNDH a cart names (the song literals of
`docs/demo-*.wasm`, as `song_pack.py` finds them, plus the carts whose name is out of its reach) on Musashi in
the counting oracle (`make sndh-survey`: the calls into the tune and the 68000 instructions, per frame;
x86 time is no measure on this box, it moved 3x between two runs). It turns them into BARD Mc with a fit to
snd-bench: ~17.8 k cycles a call, ~100 an instruction, 0.2 Mc a frame for the rest. A digi tune is its
interrupts. Below, the worst half second of the worst subtune a cart can ask for; "board" is the OSD's
now/peak on 2026-10-18 (cart started, no input: union_textracker was the only overload it saw).

| Song (subtune) | Cart | Timer | Musashi est. | Board | Now |
|---|---|---|---|---|---|
| dune_gen4_quartet (1-4) | dune_gen4 | A 16,168 Hz + TC200 | 374 % | (by input) | handler native, status 9: **117 %** measured, still over |
| union/beat_dis | union_beatdis | A 15,753 Hz | 334 % | | native (status 1) |
| swedish_newyear_tcb_digi | swedish_newyear | A 15,753 Hz | 321 % | (by input) | handler native, status 10: 85 % measured |
| north_south_digi (effects) | north_south | A 5-17 kHz, bursts | 242 % for ~10 frames | | handler native, status 15 |
| union/thalion_forever | union_textracker | A 9,600 Hz | 225 % | **308/313 %** | handler native, status 8: **79 %** measured |
| auf_weidersehen_monty_digi | tex_neoshow | D 10,593 Hz | 220 % | 17/20 % | native (status 5) |
| digital/* (6 tunes), big/Labello | big_demo | A 9,600 Hz | 213 % | (by input) | handler native, status 7 |
| crystallized | dbug, music | B 15,360 Hz, drums | 198 % peak, 47 % mean | 22/34 % | handler native, status 14 |
| Swedish_New_Year_Demo_Sync | swedish_newyear | A 7,680 Hz | 181 % | (by input) | handler native, status 11 |
| snyd90_f6 | snyd_90 | C 7,402 Hz | 166 % | (by input) | handler native, status 12 |
| union/wow_scroller | union_superscroller | A 7,585 Hz | 160 % | 21/21 % | native (status 6) |
| tcb_spreadpoint | tcb_spreadpoint | A 7,680 Hz | 159 % | (by input) | handler native, status 13 |
| union/sharpness_buzztone | union_intro, union_main | A 6,826 Hz, drums | 91 % peak, 35 % mean | 11/17 % | Musashi |
| rick_dangerous (effects) | rick_dangerous | A 4,915 Hz | 109 % for 1.5 s | 10/17 % | handler native, status 15 |
| seven_gates_of_jambala (9) | replicants_emlyn | none in 9 | 15 % (subtune 2: 151 %, not asked for) | 14/25 % | Musashi |
| union/chambers_of_shaolin (7) | union_tnt3 | none in 7 | 15 % (subtune 4: 204 %, not asked for) | 18/23 % | Musashi |
| union/150_mph, alloy_run, elite_cfsr | | 2-3 kHz | 53-59 % | 30-41 % | Musashi |

Every other SNDH a cart asks for (about 90 files: the B.I.G. Demo's 45 C64 conversions, the tutorials'
default `sos.sndh`, every Union screen's) has no MFP timer and estimates 13-18 %; the board read them at
0-32 % now, 13-48 % peak (the peak includes the song's load). MODs are ~1 %, SAP 9-36 %, XM 25-47 %. The
measured points of the fit are under "Native players"; the model reads ~20 % high for Wow (160 % against the
board's 125 %) and ~30 % low for Thalion (225 % against 308 %), whose interrupt is longer.

### Handler-only drivers (`digi_irq.zig`)

A digi tune pays Musashi's call once per sample, but its sequencer once a frame. So a handler-only driver
replays only the timer interrupt in Zig and leaves INIT, PLAY and EXIT on Musashi; both keep the tune's state
in the same 68000 RAM (and registers: Quartet's d0-d3/a0-a3, SYNC's d7, the Timer C mixer's a6). The
handler is the converter's code, shared between his tunes, where a full replay needs each composer's
sequencer ripped. These tunes copy, relocate and patch their handlers, so each is found in the image by a
masked hash, checked again in RAM at its first interrupt after every INIT (its addresses read there), and its
self-modified operands are read from the code at every interrupt. maxYMiser and Rick Dangerous move their
routine, so those two match every address an interrupt arrives at, once per INIT. A handler that does not
match plays on Musashi.

| Status | Driver | Tunes |
|---|---|---|
| 7 | `digi_big.zig`, Mad Max's 3-voice mixer | the B.I.G. Demo's digital/ tunes, big/Labello |
| 8 | `digi_mix4.zig`, Hippel's 4-voice mixer | Thalion Forever |
| 9 | `digi_quartet.zig`, SingSong, state in registers | Dune Gen4's Quartet tunes |
| 10 | `digi_tcb.zig`, one byte a tick (Wow's, with a software end of interrupt) | Swedish New Year TCB #1 |
| 11 | `digi_sync4.zig`, a self-modifying 4-voice mixer | Swedish New Year SYNC |
| 12 | `digi_mix3.zig`, a 3-voice mixer on Timer C | snyd_90 part 6 |
| 13 | `digi_tcb3.zig`, three premixed volume streams | TCB's Spreadpoint |
| 14 | `digi_mym.zig`, maxYMiser's two digidrum routines | crystallized |
| 15 | `digi_sfx.zig`, two games' effect players | North & South, Rick Dangerous |

**The proof**, as for Beat Dis: `fpga/tests/test_sndh_irq.py` holds every tune to Musashi, frame digest for
frame digest (thousands of frames each, every subtune of the two games), across a `sndhCall` and 1/2 switches;
the survey must show at most 4 Musashi calls a frame (a handler refused in RAM would pass the digest
trivially); mutants 5-11 must fail. `apps/irq_native_check.mjs` does it in the browser's own modules, gated
per cart with its `--break`. Unit tests: `digi_*_test.zig`.

**Cost on BARD** (`make snd-bench`, soc_hp_snd, 8 frames):

| Tune | Musashi (est.) | Handler native (measured) |
|---|---|---|
| Thalion Forever | 225 % est., 308 % on the board | 1.31 Mc, **79 %** |
| the other handler-only tunes | 159-213 % | not measured (no sim run) |
| Quartet (1) | 374 % | 1.94-2.18 Mc, **117 %**: still over |
| Swedish New Year TCB #1 | 321 % | 1.35-1.53 Mc, **85 %**, but the write queue filled 196 times in 8 frames |

A native interrupt still costs ~6.9 k cycles on BARD (Thalion: 160 a frame), not the ~2 k the glue alone
would suggest: a third of the frame is bus waits, and forcing the 68000 accesses inline (+36 KB of code) made
it slower (1.34 Mc), so it is the I-cache. Reading RAM directly instead of a bus call per byte cut 7 %
(1.41 -> 1.31 Mc). The next lever is the player's per-interrupt path (`renderStereo`'s block, the MFP, the
queue push) kept small and hot, which helps every digi tune at once.

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
