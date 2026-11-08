# Architecture Decision Records

Non-trivial technical choices and *why*, newest first. The rule of thumb: if a
future reader would ask "why did they do it this way?", it belongs here. Routine
choices that follow an established pattern do not.

Backfilled on 2026-09-12 for the ROM-chip work; entries before that date are
reconstructed from the commits that made them, so they are shorter.

---

## 2026-10-04 — A primitive self-test bitstream, and an allowlist of silicon-proven modes in `make check`

**Status:** accepted; the board run is pending (`fpga/rtl/board/prim_test_top.v`, `fpga/tools/prim_allowlist.py`, `fpga/silicon_prims.json`)

**Context:** openXC7 wrote a wrong bitstream twice for a primitive mode that simulates right, gate
level included: the OSERDESE2 10:1 cascade, and the RAMB36E1 in 72-bit SDP mode (and the RAMB18 in
SDP x36 is now suspect). No simulation can catch that, and each one cost a night of board work.

**Decision:** One bitstream (`make prim-test`) holds a self-checking lane for every primitive and
mode the SoC netlist uses. Its memories, multipliers and adders are inferred, not instantiated, so
it tests what our Yosys flow produces (MUXF8, which ABC will not produce from a lone table, is the
one instantiated cell). `make check` lists the cells and modes in the board SoC's netlist and fails
on one marked bad, or never seen on silicon, in `silicon_prims.json`.

**Alternatives considered:** a Vivado cross-check (needs the vendor tool, finds a different
toolchain's behaviour, not ours); testing each mode only when it first appears (that is how both
bugs reached the board).

**Consequences:** a new Yosys mapping (a width, byte enables, a DSP register) breaks `make check`
until a prim-test lane covers it (`pending`, a warning) and the board has run it (`proven`). The
key is Yosys's choice, so a refactor that changes a memory's shape can fail the check with no
functional change. Re-run the bitstream on every openXC7 or prjxray-db update.

---

## 2026-10-04 — The blitter on the board SoC: HP2, registers tapped off the CPU's data bus, the start through an M-only window

**Status:** accepted, sim only (`fpga/soc/zm_blit_soc.py`, `zm_blit_hp.py`, `fpga/cycles/bblit.c`; z7 build `--blit`)

**Context:** `rtl/blitter/zm_blit` is proven equal to `machine/blitter.zig`
standalone (`docs/BLITTER_HW_SPEC.md` §10). On the board the cart's registers are
ordinary memory in DDR (the video region at `HW_VIDEO_BASE`), the cart CPU reaches
DDR through HP0 and the video DMA through HP1, and the machine's `hwBlit()` is a
wasm export the firmware calls synchronously.

**Decision:**
- *Memory: its own HP port, HP2*, behind a byte-port to 64-bit AXI3 bridge (reads
  64-bit, 1-beat, up to 4 in flight; writes WR32, 1-beat, up to 8 without their B).
  The bus address of linear 0 is `VBASE - HW_VIDEO_BASE` (the video's own CSR, no
  new one) and maps to DDR exactly as the CPU path does: the low 25 bits inside the
  32 MiB window at `DDR_BASE`, so nothing outside the cart's window is reachable.
  A read waits for every B and a write for every read's data, because AXI orders
  neither and zm_blit's contract is "a read after a write sees it".
- *Registers: tapped off the CPU's data bus*, the way the video snoop does (the
  D-cache is write-through, every store crosses it). The block stays memory, so the
  cart's loads read what the machine would. The tap drops the COMMAND byte of the
  region's stores: the machine runs an op when `hwBlit()` is called, not when
  COMMAND is stored (a cart may store it twice, or call hwBlit twice).
- *The start: the firmware's `hwBlit` stores the command byte to `BLIT_WINDOW`*
  (`0x9100_0000`, uncached, outside every seal window, so M-only). It goes through
  the SAME tap as the register stores, so it reaches zm_blit after all of them with
  no fence. The firmware then spins on STATUS.BUSY (which covers the tap, the op and
  every write's B), invalidates the D-cache and stores CYCLES and STATUS back where
  the machine leaves them. Before VBASE is set, and for a destination below
  `OFF_VRAM` (registers, palettes: the RTL's writes would pass behind both snoops),
  the machine's own code runs instead. The board link wraps the machine's export
  (`ld --wrap=w2c_machine_hwBlit`), so the native host and the wasm path are unchanged.
- *Opt-in on the z7 build (`--blit`)* while the gated-DMA timing work owns the
  bitstream; `soc/hp_sim.py` always has it. `ZM_BLIT=hw|sw` picks the firmware.

**Alternatives considered:** a start on the snooped COMMAND store (the RTL's own
rule) breaks the machine's call semantics; a Wishbone slave for the registers
(stores routed away from DDR) would make loads of the block read the RTL, not
memory, and change what the cart sees; a CSR for the start would reach zm_blit by
another path than the register stores and need a drain fence; sharing HP0 with the
CPU would make the blitter's traffic and the CPU's refills wait on each other in
one bridge; sharing HP1 with the video DMA would put a bulk master in front of the
only real-time one. The DDR controller arbitrates HP0-HP3 already.

**Consequences:** +2,646 LUT, +1,578 FF, +8 DSP48, 0 BRAM on the board SoC (Yosys,
6,919 -> 9,565 LUT). U-Boot must set HP2's AFI widths like HP0/HP1's
(`mw.l 0xf800a000 0; mw.l 0xf800a014 0xf01`), and only on a `--blit` bitstream
(the AFI hangs without the port's clock). No QoS is set: the video DMA may need
priority over HP2 if a heavy blit makes the scanout underrun on the board. v1 is a
pixel at a time and a read costs the full HP latency; pipelined reads and row
bursts are §10.5's next step.

---

## 2026-10-03 — The YM DAC curve and envelope hold, fixed from the hardware comparison

**Status:** accepted (`machine/audio/ym.zig`; tests `ym_env_test.zig`, `ym_dac_test.zig`)

**Context:** Putting jotego's jt49 on the FPGA and comparing it with `ym.zig`
(`docs/FPGA_AUDIO.md` §3) showed two machine bugs. Envelope shapes 11 and 15
(CONT ALT HOLD) held at the end of the ramp; the datasheet, Hatari's `YmEnvDef`
and jt49 hold at the *alternated* level (11 `\---` high, 15 `/___` low). And the
DAC table (an AY-style curve) was up to 7.8 dB too quiet at low volumes against
Paulo Simoes's measurement of a real ST, so Drooling played 1.8 dB quieter than
on jt49.

**Decision:** the hold flips the level when ALT is set. The DAC is the
datasheet's log curve with an offset, `amp(L) = (10^(1.6025 (L-31)/20) - 0.0018)
/ 0.9982` for L >= 2 (0 below), fitted to the measurement: every fixed volume is
within 1.03 dB of it (jt49 is within 1.6 dB). Hatari's measured table is GPL, so
only the two fitted constants and, in the test, 14 rounded dB figures derived
from the measurement are in the tree. The 3 channels stay a linear sum: against
the measured 16x16x16 table, median error 0.95 dB, 90th percentile 1.74 dB,
worst 4.0 dB (all three at 15, where a real ST compresses to +5.5 dB over one
channel). Drooling vs jt49 after the fix: level +0.51 dB median (was +1.81),
spectra 0.990 (0.988), strongest partial in the same bin 100 % (98.3 %),
loudness envelopes correlate 1.000 (0.995).

**Alternatives considered:** jt49's own table (GPL-3, and 1.6 dB off the
measurement, where the fit is 1.03); a pure 3 dB/step log curve (7 dB off at
volume 1); a non-linear 3-channel mix (a load-resistor model, `G / (G + 1)`,
cuts the worst case to 2.0 dB but costs a divide a sample and would make the
machine disagree with the FPGA's linear mixer, so it waits for both to move).

**Consequences:** every tune's quiet passages and envelope tails get louder
(up to 7.5 dB at volumes 2..4); volume 15 is unchanged (0.33 of full scale, the
RTL mix's contract). The render loop is the same code, so the cost is the same.

---


## 2026-10-03 — Warm reset keeps the cart's memory through a firmware hook; cart text lives in a side file

**Status:** accepted
**Context:** Matt's must-haves for the glass menu: a cold and a warm reset, a
persisted master volume, and carts described by more than their file name.
**Decision:**
- *Warm reset* is `CTRL.WARM` (bit 3) read once by the cart CPU's firmware at
  boot. The firmware keeps the machine's memory arena only if a cold boot
  marked it (`glass/firmware/glass_boot.c`); otherwise it reports
  `TRAP_WARM_LOST` and runs nothing. It never falls back to a cold boot on its
  own: the user asked to keep that memory.
- *Volume* is a register (`AUDIO_VOL`, 0x3C) the mixer multiplies in, so the
  ARM is still never on the audio path.
- *Settings* go to `glass.cfg` on the SD card, which stays mounted read-only;
  a save remounts it read-write for the write and the rename only.
- *Cart descriptions* are `shelf.txt` beside the disks, generated by
  `fpga/tools/shelf_meta.py` from the catalog, the cart matrix's comments and
  the scene headers.
**Alternatives considered:** warm reset as "run the image in DDR again" (crt0
and the heap would zero the cart's memory anyway, so it would be a slow cold
reset); a metadata block inside the `.zmd` (the format has no free room, and the
browser loader parses those headers); a hand-written metadata list (a second
list drifts from the catalog); settings in a separate writable partition (a
repartition for two values).
**Consequences:** the board firmware must place the arena at a fixed address
(not a heap `calloc`). Carts whose source records no group or year show none,
and `shelf_meta.py --check` lists them. A power cut during a settings save can
leave `glass.cfg.new` beside the old file, which is ignored.

## 2026-10-02 — The seal's mechanism: U-mode plus fixed windows in VexRiscv's translation slot

**Status:** accepted for review (`fpga/rtl/seal/README.md`; it refines the ADR below, which names no mechanism)

**Context:** The cart, the ROM and the firmware share one VexRiscv, and the board
build has no wasm bounds checks. The previous ADR says "a hardware bus window",
but there is only one bus master, and the window has to know who is running.

**Decision:**
- The firmware runs in M and the cart and ROM run in U.
- `ZmSealPlugin` replaces VexRiscv's static translator. It asks
  `rtl/seal/zm_seal.v` whether an address may be read, written or executed,
  using the core's own privilege, against windows fixed at elaboration
  (`zm_seal_map.vh`).
- A "no" is a precise trap and the access never reaches the bus. A data denial
  is reported as a page fault (13/15), because VexRiscv's DataCache ignores
  non-paging permissions on uncached accesses.
- The cart calls firmware imports through an instruction-fetch fault at a
  registered entry point, so cart code is unchanged.

**Alternatives considered:**
- A privilege CSR outside the core: stores still in flight at the switch get
  judged wrong (`sw; ecall`).
- VexRiscv PMP: programmable regions the seal does not need, and by reading,
  the same uncached-path gap.
- A Wishbone decoder after the core: no privilege, and a store's `err` is not
  seen.
- Bounds checks: −36 % of the cart's cycles.

**Consequences:**
- About +13 to +84 LUT and +39 FF (Yosys).
- No per-access cycles and no fmax loss (81 vs 79 MHz under openXC7).
- About 46 to 51 cycles per gate.
- The firmware must link into the windows and must validate any address it
  touches for the cart (misaligned emulation, `hwBlit`).

---

## 2026-10-02 — FPGA video composites into a DDR framebuffer; the seal is a hardware bus window

**Status:** accepted (Matt, after the Fable review, `fpga/REVIEW_FABLE.md` findings 1–2)

**Context:** The board plan raced the beam: the compositor drew line by line
while the cart's `frame()` ran concurrently, and HBL handlers fired as CPU
interrupts. The machine's contract is a strict order every frame, `hwClear`
(global HBLs) → `frame()` → each plane with its HBL handlers. Carts draw in
place, so racing the beam tears them, breaks the palette writes, and voids
scene_hash as the oracle for the board. Separately, the cart, ROM and firmware
share one VexRiscv address space, and the recommended build drops wasm2c's
bounds checks, so nothing seals the cart.

**Decision:**
- **Composite each frame into a DDR framebuffer** in exactly the machine's
  order and at compositor speed. A sequencer runs clear, then `frame()`, then
  the planes, and HBL handlers are called from it, not taken as interrupts.
  Scanout reads the previous, completed frame. The cost is one frame of
  latency and about 80 MB/s of DDR.
- **The seal is a hardware bus window.** The cart CPU's master is masked to its
  own windows. Any other address raises a bus-error trap, and the
  sequencer/`mem_base`/firmware state is not addressable by the cart.

**Alternatives considered:**
- Keep beam racing with shadow palettes: authentic timing, but no oracle and
  torn carts.
- Decide after bring-up.
- For the seal: PMP + U-mode (needs PMP in the core plus trap plumbing), or
  keeping the bounds checks (~36 % cycles).

**Consequences:**
- No per-line deadline. Two of the machine's line-major corner cases
  (badflicker, equinox) disappear.
- The board frame is hashable against the wasm machine.
- HBL interrupt cost is gone.
- The line-racing scanout and the compositor's live register reads get
  reworked around a sequencer.
- DDR bandwidth for the framebuffer joins the CPU's HP traffic.

---

## 2026-10-02 — The console's ARM runs Linux and one Zig program over `/dev/mem`

**Status:** accepted · design in `docs/FPGA_GLASS.md`, code in `fpga/glass/`

**Context:** On the Z7-Lite the ARM does I/O only, MiSTer-style. It reads the
`.zmd` shelf off the SD card, loads a cart into the cart CPU's DDR, resets it,
passes it a USB keyboard and joypad, and drives an OSD menu. Something has to
run on the ARM for that.

**Decision:** **Linux, built by Buildroot, running one static Zig program
(`glass`).** `glass` reaches the PL's register block (M_AXI_GP0) and the cart
window (the top 32 MiB of DDR, reserved `no-map`) through `/dev/mem` with
`O_SYNC`. Until our Buildroot image exists, zeST's own kernel and rootfs are
the stopgap ("plan B" in `boot.cmd`), booted with `mem=480M` so Linux keeps off
the cart window. zeST's `BOOT.BIN` (FSBL + U-Boot) brings the PS up in both
plans.

**Alternatives considered:**
- **Bare metal** (Xilinx standalone or our own): it boots fastest and has no OS
  to maintain. But the PS's USB controller would need a host stack, HID parsing
  and hotplug, plus a FAT driver, all written and debugged against hardware.
  That is weeks of work before a key press reaches a cart.
- **U-Boot alone** (scripts, `usbkbd`, `fatload`, `fpga load`): it can load and
  start a cart, but it stops being resident once it hands over. Its keyboard
  support is polled and crude, and it has no way to keep an OSD menu and input
  forwarding running alongside a cart.
- **PetaLinux:** it needs Vivado and the vendor's BSP flow, the very things
  this project avoids (the open toolchain, ADR 2026-10-01). Buildroot builds a
  mainline kernel with a ten-line config fragment.
- **A kernel driver or UIO** instead of `/dev/mem`: a driver is cleaner, but it
  is one more thing to build against each kernel, and plan B's kernel is not
  ours. The register block is 64 KiB and the console is a single-user
  appliance, so root and `/dev/mem` cost nothing real.
- **C instead of Zig** for the program: Zig cross-compiles to
  `arm-linux-musleabihf` with no sysroot, makes a static binary that runs on
  either kernel, and imports `libs/zig/depackers/zx0.zig`. The board then
  unpacks a cart with the same code as `rom.wasm`'s `romDepack`. The one piece
  that must run on the cart CPU (`glass_input.c`) is C, as its firmware is.

**Consequences:**
- USB HID, hotplug, evdev and FAT come for free, and zeST already proves the
  kernel side on this exact board.
- Boot takes seconds, not milliseconds.
- The SD card is mounted read-only, so a power cut cannot corrupt it.
- The cart window must be kept from Linux, by a device-tree `reserved-memory`
  node (plan A) or `mem=` (plan B).
- `glass` is tested on the desktop against a simulated register block, so
  everything except the `/dev/mem` mapping and evdev is proven before the board
  arrives.

---

## 2026-10-01 — The FPGA machine runs RISC-V carts translated from wasm (`fpga/`)

**Status:** accepted · design in `docs/ZIGMACHINE_IN_FPGA.md`, tree in `fpga/`

**Context:** The target is a MicroPhase Z7 (XC7Z010, 17,600 LUTs), with the ARM
doing I/O only and the console in fabric. The CPU that runs carts had to be
either a wasm softcore or a conventional ISA.

**Decision:**
- **A RISC-V core (VexRiscv) runs the carts.** wasm stays the cart format and is
  translated before it reaches the board (wasm2c, then clang/zig for
  `rv32imf`).
- **The seal is enforced by the AXI interconnect** (the cart master sees only its
  windows), not by wasm.
- **`fpga/` is a self-contained tree**: its own uv env, Makefile and tests,
  outside `./build.sh`. Reused cores are pinned shallow submodules.
- **The memory map is exported from `machine/sdk/memmap.zig` by reflection**,
  never retyped.

**Alternatives considered:**
- **A wasm softcore.** None exists to reuse, and wasm is designed to be
  compiled. It would need `i64`/`f32`/`f64` in hardware, and on a 7010 it would
  not fit beside the machine.
- **A real 68000 running the carts.** Zig and Rust have no m68k target. The
  68000 is kept only as the optional SNDH coprocessor.
- **Typing the memory map into Verilog.** Two copies drift.
- **Vendoring the cores.** That copies GPL sources into the tree, so
  submodules were used instead.

**Consequences:**
- Proven before any hardware: all 90 carts translate and compile for
  `rv32imf`, and VexRiscv `standard` measures 2,019 LUTs and `jt49` 286.
- The FPU (`f32`, 3–5K LUTs) decides whether the 7010 is enough.
- A bitstream containing `jt49`/`fx68k` is a GPL combined work. That must be
  settled before one is distributed.

---

## 2026-09-27 — The sealed YM gates a tone above Nyquist at its average (0.5)

**Status:** accepted

**Context:** Matt heard SKYSTRIKE's engine and gun sound higher in the port than
on Hatari, and a high-pitched sound in Sky_Strike.sndh tune 3 that the original
does not have. The game's YM registers and the Timer A rate were identical to
Hatari's (engine th=5: R6 $1A, R11/12 $003D, R13 $0A, mixer $C0; gun: TACR 1,
TADR $6E = 5585 Hz), and so were the envelope fundamental (64 Hz) and the noise
spectrum's null (clock/(16*26) = 4807 Hz). The difference was a narrow line at
7300 Hz carrying most of the port's energy (the gun's 7-8 kHz band at -2.5 dB,
Hatari's at -22.4 dB). `Ym2149.render` point-sampled each tone's square at
44.1 kHz. Both effects leave tone period 0 enabled (STOS NOISE writes mixer $C0
and periods 0; Maestro's digi writes a volume per sample over mixer $F8), and
period 0 is a 125 kHz square: sampled, it folds to |125000 - 3 * 44100| =
7300 Hz. Tune 3 sets channel A to period 0 at volume 14-15 for 5 VBLs at a time.

**Decision:** a tone whose step per output sample exceeds 0.5 (above Nyquist:
periods 0-5 at 44.1 kHz) gates the channel at 0.5 instead of 1 or 0
(`Ym2149.toneGate`). The real chip's output, low-passed, and Hatari's 250 kHz
model, filtered down, both give that average: the square is open half the time.
Tones at or below Nyquist are the same float as before (`VOL * 1.0`), so no
other sound changes. It covers every path, since the SNDH player, the YM dump
player, the MOD's direct `zg.ymWrite` effects and the free-standing effect voice
all render through `Ym2149.render`. Tested in `machine/audio/ym_test.zig`.

**Alternatives considered:** band-limiting every tone (a box filter over the
sample interval, or rendering at 250 kHz and decimating, as Hatari does). It is
more accurate for the harmonics of audible squares too, but it changes every
tune on the shelf and costs far more per sample. The aliasing of an audible
square's harmonics is a much smaller effect than a whole fundamental folded
into the audible band. Hatari's output low-pass (the port is still 3-7 dB
hotter above 10 kHz) was left alone: it is a separate question.

**Consequences:** Across all 389 subtunes on the shelf (docs/music, big/,
digital/, union/; 120 s each), 363 render byte-identical. 26 change, and each
has an audible tone at period 5 or below (no other tune changed):
auf_weidersehen_monty_digi #1, bangkok_knights #1, count_zero_2 #1, dugger #3
and #4, joust_sfx #8 and #17, leatherneck #1, pro_bmx_simulator_a #1, skystrike
#1 and #3, sos #1, sowatt_an_bass #1, stniccc_2000 #1, big/Battle_Of_Britain #1,
big/Chimera #1, big/Gerry_The_Germ #5, big/Monty_On_The_Run #1,
big/Sam_Fox_Strip_Poker #5 and #6, big/Sanxion_Loader #1, big/Sanxion_Title #1,
big/Thrust #1, union/chambers_of_shaolin #6, union/mega_apocalypse #1 and
union/thundercats #1. The rms moves by 1% or less, except for the Monty digi
tune (3819 channel-VBLs at period 0, rms 0.1745 -> 0.1640, -6%): a digi played
over a period-0 tone is now heard at the average level, as on an ST, without
the whistle on top. SKYSTRIKE after the change: the engine's bands from 0 to
8 kHz are within about 1 dB of Hatari's at th=5 and th=9, the gun's likewise,
and the engine's rms is 3225 against Hatari's 3367 (4741 before).

---

## 2026-09-27 — The SNDH player's MFP honours IER/IMR (enable, mask, pending)

**Status:** accepted · code in `libs/zig/players/mfp.zig`, guide in `docs/MUSIC.md`

**Context:** The player ran any MFP timer whose control register was set, and
ignored IERA/IERB and IMRA/IMRB. STOS's Maestro stops a digi by clearing Timer
A's IERA/IMRA bits, so Skystrike's SAMSTOP left the digi playing
(`docs/ports/SKYSTRIKE.md` §9). Its `sound.s` works around this by also
clearing TACR.

**Decision:** Model the MC68901's interrupt controller for the four timers. A
timeout sets a channel's pending bit only if the channel is enabled. Clearing
an IER bit also drops its pending bit. A pending channel interrupts only when
unmasked, and it waits while masked. IPR and ISR are clear-only from software.
The counters run regardless. The reset state is what TOS 1.04 leaves, read off
Hatari after boot: IERA = IMRA = $1E, IERB = IMRB = $64 (Timer C on; A, B and D
off). Xbtimer enables and unmasks its timer, as TOS's does. In-service is not
modelled: a handler is called synchronously and runs to its RTE, so nothing can
nest for ISR to block. VR stays $40 (auto-EOI) instead of TOS's $48 for the
same reason.

**Alternatives considered:** Leave the chip alone and let each port stop its
timer (Skystrike's workaround). But the tune's code is the source of truth, and
every such port would rediscover the bug. Modelling ISR blocking too: it only
matters for nesting, which the synchronous player never does, and it risks
silencing a handler that skips its end-of-interrupt.

**Consequences:** Across all 389 subtunes on the shelf (120 s each), 386 render
byte-identical. Three change, each because the tune masks a timer with IMR and
the old player ignored the mask: Crystallized's Timer B SID voice, Elite's
Timers A and D, and VEX's Timers A and D (Elite and VEX use the same SID
player). Each masks a voice for whole frames at a time, and the handler used
to run on. The output peaks are unchanged, and there are 0.3-3.5% fewer YM
register changes. A tune that starts a timer without
enabling its interrupt now goes silent, as it would on an ST. None on the shelf
does; the sndh_call check's hand-made tune did, and now enables Timer A.

---

## 2026-09-26 — zg.sndhCall: INIT on the running SNDH, a cart-export queue (no HW bump)

**Status:** accepted · guide in `docs/MUSIC.md` ("Sound effects")

**Context:** Every song request reloads the SNDH: the host refetches it, the
player zeroes the 68000's RAM around the image, silences the YM, resets the
MFP and runs INIT. Rick Dangerous plays its effects as subtunes of one driver
image, so each effect cut every voice and digi still sounding, and the cart's
one-request-per-frame bridge dropped the game's paired plays (the shot's
`play(8,1); play(8,0)`, dynamite's two `$0A`).

**Decision:** `zg.sndhCall(name, d0)` queues INIT(d0) on the RUNNING image, up
to 16 per frame, in order. It rides the song bridge's shape, not a machine
register: the cart exports `pollSndhCalls` / `sndhCallD0(i)` /
`sndhCallNamePtr/Len` (Zig `demo_main.zig`, C `zigmachine_music.h`, Rust
`zigmachine_music.rs`), the loader drains them after the frame's song request
and posts `{type:"sndhCall", d0}`; the open `demo-audio.wasm` runs
`SndhPlayer.callInit` (no load, no silence, no MFP reset, clock and timer
phases kept, then `rearm()`). A song request or stop made after queued calls
discards them (ZigOS/C/Rust), which is what keeps the two channels in the
cart's order. A call on an image that is not playing loads it with the call's
d0 as its first INIT (`audioSndhPlayRaw`), so a stale host never plays a
default subtune in its place.

**Why no HW 1.8.0:** the brief proposed a register and a `hwVersion` bump.
Neither sealed binary changes: the song bridge is a contract between cart
exports and the loader, and the player is the OPEN `demo-audio.wasm`. Bumping
`hwVersion` would rebuild `machine-video.wasm` only to change a number that no
longer describes it, and a register would split the one music bridge into two
mechanisms. The loader feature-detects `demo.pollSndhCalls`, as it already
does `songTune`.

**Alternatives considered:** the worklet decides "already loaded" (it has no
file to load when it is not); calls as subtune requests with a "resident" bit
in `songTune` (still one request a frame, still a fetch); a register queue in
the video machine (sealed code, and the audio thread cannot read it).

**Consequences:** The drop rule inside a driver (Rick's play_sound) now decides
on the AUDIO clock, while the cart's transcription decides on the cart clock;
the two agree when their tick counts do (the harness proves it in lockstep),
and a request the cart passes may still be dropped by a driver whose tune
ends a tick later. Calls made while sound is off are dropped.

## 2026-09-26 — The machine hands out RAM: a bump arena (HW 1.7.0)

**Status:** accepted · guide in `docs/MEMORY.md`

**Context:** A cart imports its memory, so the linker cannot assume it is zero and
writes every zero byte of a module-scope buffer into the data segment.
`demo-swedish_newyear.wasm` spent 1866 KB of its 2 MiB window on ~600 KB of real
content, and 16 modules on main carried zero runs of 64 KB+. The ABI could only *measure* the
window (`hwRamFree`), and every scene that wanted scratch space hand-rolled
`hwRamBase() + hwRamUsed()` with no reservation and no failure count.

**Decision:** Sealed instructions `hwRamAlloc(bytes, alignment)`, `hwRamMark`,
`hwRamRelease(mark)`, `hwRamAllocFailures`, backed by two registers
(`REG_RAM_ARENA_TOP` 0x6C, `REG_RAM_ALLOC_FAILS` 0x70). A **bump arena** from the
declared high-water up: memory is zeroed (what a static promised), a refusal
returns 0 and is counted, release is to a mark. The per-cart reset rides on
`hwSetCartHigh`, which the host already calls at every boot, chainload and swap,
so no new host hook was needed; `hwInit` preserves the arena like `CART_HIGH`.
`hwRamUsed/Free` include the arena. ZigOS wraps it as `zg.mem` (an
`std.mem.Allocator` plus typed `alloc(T, n)`); C and Rust get small wrappers. A
gate (`apps/zero_segments.mjs`) fails any new zero run of 64 KB+.

**Alternatives considered:** a general malloc/free heap in the machine (free
lists, fragmentation, a lot of sealed code for demo carts that allocate once at
boot); letting the linker zero `.bss` itself with bulk-memory passive segments
(`zig cc` does this for C, but it is toolchain-specific and gives no failure
count or per-part reuse); a ZigOS-only allocator over `hwRamBase + hwRamUsed`
(not language-agnostic, and the machine could not reset it per cart).

**Consequences:** Nothing is freed singly: a multi-part cart marks and releases.
`hwRamBase() + hwRamUsed()` stays the first unowned byte, so the existing
depack-to-free-RAM scenes are unchanged, but their scratch is still unreserved:
an allocation made after it reuses those bytes. Arena use is invisible to
`check_fits`, like ZX0 depack targets. Rust carts now link `--no-stack-first`:
rustc's stack-first default put the stack below `0x100000` (machine RAM) and left
`.bss` out of the data segments, so the measured high-water missed the cart's
zeroed statics and the arena handed them out.

---

## 2026-09-19 — Overscan + hardware scroll needed no machine change

**Status:** accepted

**Context:** The AUTOMATION 442 port (CODEF screen 420) wants a tiled background
that pans across the *whole* 400×280 overscan window with zero per-pixel work per
frame. The two capabilities existed separately — `FB_MODE = 2` (SCROLL) pans a
bigger-than-screen buffer, `FB_MODE = 4` (OVERSCAN) draws the border bands — and
the obvious move was a fifth render mode combining them.

**Decision:** No new mode, and no change to `machine/video.zig`.
`renderPlaneOverscan()` already reads its buffer as `lfb(fb_id)` (i.e. through
`FB_BASE`, the pan point) with `fbStride(fb_id)` as the row pitch, so an OVERSCAN
plane bound to a larger buffer with `FB_STRIDE = buf_w` pans correctly the moment
`setScroll()` rewrites `FB_BASE`. The only thing missing was an SDK entry point:
`LogicalFB.setOverscanScrollPlane(buf_w, buf_h)` in `libs/zig/zigos.zig`, which is
`setOverscanBuffer()` with `setScrollPlane()`'s allocation and stride.

**Alternatives considered:** a `FB_MODE = 5` "overscan scroll" render path (more
machine surface, an ABI-visible constant, and a duplicate of a loop that already
did the right thing); or painting the pan per frame into a 400×280 overscan buffer
(112k pixel writes per frame — exactly the cost the hardware scroll exists to avoid).

**Consequences:** No register layout changed, so no ABI rebuild. The one asymmetry
is that `renderPlaneOverscan()` does not re-read `HSCROLL` per scanline, so this
mode has coarse scroll only — a scene wanting per-line distortion still needs
`FB_MODE = 2` and closed borders. Documented in `docs/HW_API.md` §3.

---

## 2026-09-12 — The ROM's ABI names a PLANE, not a pointer

**Status:** accepted

**Context:** The machine/rom split claims a ROM is "just a module linked against
the HW ABI, so any language can call it". The first flat ABI (`guiOpen(os_ptr,
fb_ptr, w, h)`) passed only `u32`s and therefore *looked* language-agnostic. It
was not: those numbers are the addresses of the caller's `ZigOS` and `LogicalFB`,
so their meaning is "you must be a Zig program that links ZigOS". A C app has
neither — it writes palette indices straight into the video region. Nothing caught
this because nothing had ever written the caller.

**Decision:** Entry points a non-Zig app needs take a **plane number**.
`guiOpenPlane(plane, w, h)` and `romInstallPalettePlane(plane)` let the ROM read
that plane's framebuffer base and stride out of the sealed video registers itself,
and lend its own `ZigOS` for text (`ZigOS.initTextOnly()` binds the fonts and
touches no hardware). `guiOpen` stays for Zig callers.

**Alternatives considered:** Exporting ZigOS's layout so C could build the structs
— couples every app to an internal layout. Having the app pass a raw framebuffer
address — plausible, but `FB_BASE` is moved by ZigOS's VRAM allocator, so the
register is the only correct source and the ROM can read it without being told.

**Consequences:** The polyglot claim is now testable and tested
(`apps/verify.mjs` reads the framebuffer back and requires GEM's own output).
`romInstallPalettePlane` is not a convenience: GEM draws in palette *indices*, so
a caller with its own palette gets correct pixels in the wrong colours — a plasma
rainbow renders a GEM panel solid red. An ABI can be technically satisfied and
practically useless.

---

## 2026-09-12 — The machine reclaims a program's resources; the host does not remember them

**Status:** accepted

**Context:** Launching became a host-side cart swap, so a program is torn down and
replaced. Twice this produced the same silent failure: the outgoing program cannot
release what it holds, because by the time anything notices, it is gone. ROM
handles stayed marked used until the tables filled and every call became a no-op
(an app that draws perfectly whose dialogs never appear). Music kept playing over
the next screen.

**Decision:** Reclamation is the machine's job, invoked on every cart
instantiation: `romReset()` for the ROM's handle tables, `machineAudioReset()` (via
the cart-level `audioReset()`) for the sound chip. Neither names a player or a
handle kind.

**Alternatives considered:** The host remembering which player/handles were live
and sending matching stops — that design is what produced the bug, and it needs a
new case for every new resource type. (It had already failed once: `audioSndhStop`
was exported but had no message case in the worklet, so it was unreachable.)

**Consequences:** A new player type or handle kind is covered without touching the
host. Both are guarded by tests that fail when the reset is stubbed out.

---

## 2026-09-12 — GEM is its own wasm module, in its own RAM window

**Status:** accepted · plan in `docs/PHASE2_ROM_CHIP.md`

**Context:** GEM was a Zig module every cart linked statically, so the toolkit
existed once per cart and `gem_desktop.zig` embedded the app it launched — every
app GEM could start was inside GEM's binary.

**Decision:** `rom.wasm`, linked against `machine/sdk/` like a cart, with its own
2 MiB window at `[0x500000, 0x700000)` **above** the video region. The host
instantiates machine → rom → cart. Apps import the named module `rom_sdk` (a
header of `extern` declarations) and never `rom`.

**Alternatives considered:** Carving the ROM window out of the cart's 2 MiB —
defeats the purpose, since the point is that an app's RAM stays the app's.

**Consequences:** `SHARED_PAGES` 79 → 112, which is a **breaking change for every
cart ever packed** (a cart declares the imported memory's max and refuses a larger
one). That is why `tools/mkdisks.sh` had to exist first. The `Rect`/`BLACK`/`WHITE`
constants are now *defined* in the header rather than re-exported from
`rom/gem/gui/types.zig` — a header that imported the toolkit would drag it back
into every app — so those two definitions must be kept in step by hand.

**Note on the original motivation, which was wrong:** this was planned to reclaim
RAM. `gem.Desktop` is 2332 bytes. What actually capped ST Replay's sample buffer
was a duplicated data segment (see below). The real value delivered is the
polyglot ABI and that the desktop no longer contains its apps.

---

## 2026-09-12 — The machine answers "how much RAM is left?" (HW 1.2.0)

**Status:** accepted

**Context:** A cart's window is shared by its statics, its stack, and everything
it links. Running past the top does **not** trap — it writes into the video region
and the machine dies later, somewhere unrelated. Buffer sizes were guesses.

**Decision:** Sealed instructions `hwRamBase/Top/Size/Used/Free`, backed by
`REG_CART_HIGH`. The machine cannot know a cart's high-water (the linker bakes it
in), so the **host** measures it from the wasm and declares it via
`hwSetCartHigh` — which keeps the instruction language-agnostic. `hwRamFree()`
reports 0 when undeclared, deliberately indistinguishable from "full": an unknown
window must read as *take nothing*.

**Consequences:** One measurement routine (`docs/wasm_hiwater.js`) is shared by
the loader and the checkers, so the hardware and the tools agree to the byte. Each
module is measured against **its own** map — the audio thread's window is half the
size at the same address, and measuring it against the video map would let a cart
grow a megabyte into song RAM unnoticed.

---

## 2026-09-12 — Each screen defines how to leave; the host does not bind keys

**Status:** accepted

**Context:** The loader interpreted Escape globally (skip boot, then back to the
menu) and returned before `demo.key()` ever saw it, so no screen could bind it —
ST Replay's "Esc = stop" rebooted the machine instead. Space/Enter, WASD and 1-7
had the same shape, and in an application W both wiped and moved a selection.

**Decision:** The host forwards keys and the machine decides. `demo_main.zig`
routes Escape: the boot ROM skips while it is up, a cart that handles keys owns
it, a plain scene cart falls back to the menu. A cart may declare `ownsKeyboard`
to stop the host interpreting the rest.

**Consequences:** Carts that declare nothing keep the old behaviour, so no packed
disk changed.

---

## 2026-09-12 — `.zmd` disks are built by a recipe, and verified offline

**Status:** accepted

**Context:** The disks were build output nobody could rebuild. They drifted a week
behind the wasm and froze an import list the host no longer had, so every disk
failed to instantiate — recoverable only by reading the images back.

**Decision:** `tools/mkdisks.sh` repacks them from the built carts, deriving the
list from `docs/demo-*.wasm` and repacking only what is stale.
`apps/disk_check.mjs` mounts every image and **instantiates** its cart against the
host's real `env`. Both run from `build.sh`.

**Consequences:** A host ABI change is caught offline in one command instead of as
a black screen. The env object is an ABI: a retired import becomes a documented
no-op stub, never a deletion.

---

## 2026-09-06 — Four ownership areas (`machine`/`rom`/`libs`/`apps`)

**Status:** accepted · see `docs/HARDWARE_SPEC.md` §12 and each area's README

**Decision:** Split the tree by who owns the code, with cross-area imports going
through **named modules** (`@import("zigos")`, `@import("rom")`,
`@import("hardware")`) rather than relative paths.

**Consequences:** Named modules are path-independent, which is why the reorg
barely touched imports. A file may belong to only one module, so a module that
needs another area's code must import it by name — this is what forced `rom_sdk`
to reach GEM through `@import("rom")` rather than `../gem/`.

---

## 2026-08-22 — Seal the hardware behind a memory-mapped ABI

**Status:** accepted · design in `docs/HARDWARE_SPEC.md`

**Decision:** The machine is sealed wasm modules that coders receive as binaries
plus header files (`machine/sdk/`); everything crosses through a fixed memory map
and a small set of entry points. "You get the memory map, not the schematics."

**Consequences:** The constraint *is* the console — and because the seal is a wasm
ABI rather than a Zig API, apps in any language sit on it.

## 2026-10-09 — Vivado for board bitstreams; openXC7 kept as the open flow

**Status:** accepted
**Context:** The first cart on the Z7-Lite showed a broken picture for several days. A primitive self-test bitstream (`make prim-test`) showed that openXC7/prjxray produces wrong silicon for RAMB36 SDP x72, RAMB36 TDP x9 (parity bit) and SRL16E/SRLC32E, although all of them simulate correctly. The OSERDESE2 cascade had already failed earlier. Working around each one (sliced RAMs, `-nosrl`, register slices on the untimed PS7 pins) removed most of the corruption, but a shear remained. The same RTL built with Vivado ML Standard 2026.1 gave a clean picture once our own scanout phase bug (zm_video_scanfetch) was fixed. openXC7 also needed 19+ min per SoC build and sometimes stalled or failed to place; Vivado takes ~3 min.
**Decision:** Board bitstreams are built with Vivado (`--toolchain vivado`, `tools/vivado_bit.sh` for small tops). openXC7 stays in the tree as the open-source flow. It runs under the silicon allowlist (`fpga/silicon_prims.json`), with `-nosrl`, and `make prim-test` re-runs after any toolchain update.
**Alternatives considered:**
- openXC7 only, avoiding every bad primitive: an unbounded hunt, and slow builds.
- A compositor-only test design: it would have run through the same broken toolchain.
**Consequences:**
- A closed, free-as-in-beer toolchain becomes a build dependency for the board: a licence file node-locked to the machine, ~80 GB, and ncurses5 shims.
- The free licence has no ILA, so signals are observed through glass registers.
- The RTL must stay portable to both tools; Vivado rejects two constructs Yosys accepts.

## 2026-10-09 — SNDH in software on the cart CPU; the audio core behind a stamped write queue

**Status:** accepted
**Context:** The board SoC had pictures but no sound. The audio core (`fpga/rtl/audio/`: jt49 + the four Paula channels, PCM sample-exact to the Zig machine) and HDMI audio (`fpga/rtl/hdmi/`) were proven on the board on their own (`make ym-test`). The machine's music is mostly SNDH: the tune's own 68000 code on Musashi (`libs/zig/players/sndh_player.zig`, in `demo-audio.wasm`). The plan had an audio CPU for it. The 7010 is at ~49 % LUTs with the audio core in, and a second CPU plus its memory path is a large step.
**Decision:** For now the players (MOD, YM dump, SNDH = Musashi) run in software on the cart CPU: `demo-audio.wasm` through wasm2c, in its own 3 MiB memory in DDR, driven by the firmware (`fpga/cycles/baudio.c`) after each cart frame. Their chip calls (`machine*` imports) become the core's register writes, each STAMPED with the sample it lands before in the machine's stream (`fpga/host/audio_imports.c`). The firmware renders ahead of the sound (67 ms) and pushes the writes into a 2,048-entry queue (`rtl/audio/zm_audio_sched.v`) that applies each at its sample, between two mixes. The core's register window (`AUDIO_WINDOW`, 0x9200_0000) is outside every seal window: only the firmware reaches it. PCM bytes are read from the players' memory in DDR on HP3, one 8-byte read per byte. HDMI with audio (`rtl/video/zm_hdmi_out.v`) replaces DVI.
**Alternatives considered:**
- An audio CPU now (the plan): the right end state, but a second core, its RAM and its own bus on a nearly full 7010, before the music is even heard.
- Writes applied when the CPU makes them (no stamps): the YM would hear the frame's writes in one burst at frame time, so a 50 Hz tune jitters and a digidrum (a write every timer tick, 7-16 kHz) collapses.
- The PCM in BRAM: the song RAM is 1 MiB; the 7010 has 240 KB of BRAM.
**Consequences:**
- The music costs cart-CPU cycles every frame (`docs/FPGA_AUDIO.md` "6. In the SoC", 1.67 Mcycles a frame at 100 MHz): a 50 Hz SNDH ~0.28 Mc (17 %), a MOD 8 kc, but a digidrum SNDH 2.95 Mc (7.6 kHz timer) to 7.95 Mc (15.7 kHz): those do not fit, which is what the audio CPU is for.
- The stamps make the sound independent of the CPU's timing: the sim proves the core applies the machine's writes at the machine's samples.
- A PCM sample the players rewrite less than the lead (67 ms) before it is played would be read new (the STE DMA double buffer case): not met by any cart measured; an audio CPU running in step with the core removes it.
- The players run with the cart's translation (no bounds checks, M mode, as the whole board firmware today): the seal does not yet separate them.
- An audio CPU later drives the same queue; a second sound chip gets its own register range behind it.

## 2026-10-10 — The cart's DDR window follows the glass's LOAD_BASE

**Status:** accepted
**Context:** The HP bridges hard-coded the cart window at DDR `0x0400_0000`, where U-Boot leaves room for `loadx`. Under Linux that address is the initramfs (`boot.cmd` loads it at `0x4000000`), and the dts reserves `0x1E00_0000` for the cart. The glass already had a `LOAD_BASE` register that `glass` wrote, but the PL left its output unconnected.
**Decision:** The window comes from `LOAD_BASE[31:25]`, applied once, in the register slice at the PS7 (`hp_slice`), so the four masters keep addressing `DDR_BASE` and the simulation's DDR model is unchanged. Its reset value is `0x0400_0000`, so the U-Boot flow (`board_run.py`) needs no extra write; `glass` writes `0x1E00_0000`, and checks for PL `VERSION` >= 1.3.0 first.
**Alternatives considered:** Reset to `0x1E00_0000` as the spec said. U-Boot relocates itself into the top of DDR, so a forgotten write would let the cart overwrite U-Boot. Threading a base signal through each bridge means four edits instead of one, and the sim model would have to follow.
**Consequences:** The base must be 32 MiB-aligned (the low bits are ignored). Change it only while `CTRL.RUN` is 0. `board_shot.py`'s mailbox `ddr_base` is the firmware's constant `0x0400_0000`, so it is right under U-Boot only.

## 2026-10-10 — `hostMicros`: a host clock import, for benchmarks only

**Status:** accepted
**Context:** The raytrace carts are the FPGA CPU benchmark, so they have to report a measured rate (pixels per second) on both the browser and the board. No cart could read a clock: the machine ABI has the frame counter (`REG_FRAME`, one per host call) and `BLIT_CYCLES`. `dt` is wall time in the browser, but every FPGA host passes a constant 16.6. The board firmware does time `cart.frame()` with the SoC cycle counter, but the cart cannot see that number.
**Decision:** Carts can import `env.hostMicros() u32`, a free-running microsecond counter that wraps about every 71 minutes. Like `diskReadBlock` or `hostAudioFeed`, the host provides it to the cart directly; it is not a machine register.
- The browser (`docs/sealed-loader.js`) derives it from `performance.now()`. The board defines `HOST_MICROS()` from the cycle counter, and `fpga/tools/host_gen.py` calls that hook.
- A host that does not provide it answers **0**: the harness and `host_gen` no-op stub does, and so does `disk_check`'s env. A cart must treat 0 as "no clock" and fall back to a fixed amount of work per frame. That fallback keeps gate frame counts and fingerprints deterministic.
- **It is a benchmark aid only.** No screen may use it for choreography, pacing or animation. Carts stay frame-locked: the machine runs at a fixed 60 Hz and a screen counts frames.

**Alternatives considered:**
- A machine timer register (an MFP-like counter in the register block): this bumps the ABI version. The machine module would also have to import a host clock, so all 84 places that instantiate it would need the new import.
- Bounding work from `dt`: in the browser `dt` is quantised to 60 Hz ticks and says nothing about headroom, and on the board it is a constant.
- Reading the board's cycle counter from outside the cart (`ZM AF`): this gives no number in the browser and none on screen.

**Consequences:**
- Only carts that import it are affected, and an older disk has no such import.
- The browser's `performance.now()` is coarsened to about 0.1 ms without cross-origin isolation. That is fine for an 8 ms budget, but not for timing a single pixel.

## 2026-10-10 — One local change to the vendored Musashi: no per-instruction register save

**Status:** accepted
**Context:** On the FPGA, an emulated 68000 instruction cost the cart CPU about 1,160 cycles. A digidrum SNDH (beat_dis.sndh) ran about 6,840 of them a frame, 8.0 Mcycles against a 1.67 Mcycle budget. A profile of the native player showed Musashi's `m68k_execute` copying D0-A7 into `REG_DA_SAVE` before **every** instruction: 16 loads and 16 stores, so a bus error can restore them. Only `m68k_pulse_bus_error` reads them back, and the SNDH player never calls it.
**Decision:** `libs/c/musashi/upstream/m68kcpu.c` keeps the loop inside `#ifndef ZM_NO_DA_SAVE`, and `config/zm_musashi.h` defines it. This is the one local change to the vendored code; `libs/c/musashi/README.md` records it and the way to re-apply it after an update.
**Alternatives considered:**
- Leave upstream byte-for-byte: the cost stays.
- Patch a copy at build time (a sed step in build.zig): the change is just as real but harder to see.
- Change the player instead: it cannot reach the loop.

**Consequences:**
- beat_dis.sndh costs 6.5 Mcycles a frame on the cart CPU instead of 8.0 (-18 %); x86 native -38 %.
- The player's stamped chip writes are byte-identical with and without the loop: sos, wow_scroller and beat_dis, 10 s each, native.
- The SNDH gates pass (`./build.sh --only sndh sndh_call sndh_relocate union_beatdis union_superscroller union_demo_music union_intro_music c_music`). union_superscroller's 4 ms wall-clock budget failed once under a load of 15 on 8 cores; run alone it passes, at 3.43 ms median.
- A future screen that needs bus-error emulation must `#undef ZM_NO_DA_SAVE`.

## 2026-10-10 — The sound CPU, and native replays for recognised SNDH drivers

**Status:** accepted
**Context:** On the cart CPU the players cost a 50 Hz SNDH ~17 % of the frame and a digi SNDH 3-5× the frame (the 2026-10-09 ADR). `FPGA_AUDIO_CPU.md` recommended a small VexRiscv with a small cache, from DDR. Measured on the hp_sim:
- Musashi's stores and its code size dominate. A small I$ is 2-3× slower than 16 KiB.
- A write-through D$ with blocking stores waits on every AXI B response.
- beat_dis interrupts 263 times a frame at ~14.6 k cycles each, so even at the routed ~149 MHz it would cost 154 % of a frame.
**Decision:**
- **The sound CPU** (`docs/FPGA_SOUND_CPU.md`): a second VexRiscv (`Snd`: 16 KiB 2-way I$, 4 KiB D$), running the same `demo-audio.wasm` through wasm2c.
  - It runs from DDR on **HP3, shared with the audio core's PCM reads through an arbiter**; no new HP port.
  - Its stores are posted: a `WishboneHP` option, default off elsewhere. Every "acked means in DDR" consumer (the video snoop, the blitter start, read-after-write) waits for `idle`.
  - It talks to the cart CPU through a two-bank mailbox at `SOUND_WINDOW`.
  - It stays at the sys clock: no CDC island.
- **Native replays** (`libs/zig/players/digi.zig`): for a recognised driver (handler + sequencer signatures, tables in range), the SNDH player's 68000 calls run as Zig on the same bus. Everything else is unchanged.
  - A near miss plays on Musashi and is logged.
  - The oracle (`fpga/tests/test_sndh_native.py`) holds the native writes to Musashi's over the whole tune.
  - Beat Dis is the first driver.
- **The board's queue** drops volume writes that repeat the last queued value. A native digi runs a 3-frame lead (`host/audio_queue.h`).
**Alternatives considered:**
- The survey's small core (I4D4, 1841 LUT): beat_dis 10.8 Mc, wow_scroller over budget.
- A 32 KiB I$ / 16 KiB D$: wow_scroller 73 % instead of ~100 %, for 15 BRAM tiles instead of 8.5. Kept for later.
- A 150 MHz sound island: ~149 MHz routed out of context, still 154 % for beat_dis, plus a CDC at three interfaces.
- fx68k: GPL-3, 3.4K LUTs, and it would not fix the per-interrupt cost of a digi tune.
- A standalone native player outside the SNDH player: two clocks and two MFPs to keep equal, by hand.
**Consequences:**
- The cart CPU's frame no longer pays for the music.
- 50 Hz tunes and Beat Dis fit. The other digi SNDHs (including the 10 sharing Beat Dis's handler) still overrun on the sound CPU and resync, which `ZM AUD resyncs` counts, until each gets a sequencer or Musashi's interrupt entry gets cheaper (the next lever, `docs/FPGA_SOUND_CPU.md`).
- The native code also runs in the browser (in `demo-audio.wasm`, +2.8 KB). Its output there is the oracle-checked stream, unchanged.
- New exports: `audioSndhNative`, `audioSndhNativeEnable`, and `audioSndhNativeMutant` (test only).

## 2026-10-10 — POKEY written from scratch, audio only, against a Zig model

**Status:** accepted
**Context:** Phase B of the sound-CPU plan puts an Atari POKEY (C012294) beside the YM, driven later by a 6502 SAP player. The available HDL cores (MiSTer Atari800 and others) and the reference emulators (MAME `pokey.cpp`, ASAP) are GPL. The project's own code is MIT, so it cannot absorb them. jt49 is the one GPL core already in a bitstream, and it is kept as a separate module (`fpga/third_party/README.md`).
**Decision:** A POKEY written from public hardware documentation only: the Altirra Hardware Reference Manual's POKEY chapter, Atari's C012294 data sheet, and De Re Atari ch. 7. No GPL source was read. It is audio only: four channels, AUDF/AUDC, every AUDCTL bit, STIMER, and SKCTL init mode. There are no IRQs, serial port, keyboard, pots, RANDOM or two-tone mode.
- `libs/zig/players/pokey.zig` (moved to `machine/audio/pokey.zig` on feat/sap: it is the sealed machine's chip) is the reference model, cycle by cycle. `pokey_test.zig` checks the documented formulas: (N+1)×28 and (N+1)×114 cycles on the bases, N+4 at 1.79 MHz, N16+7 for a joined pair, and poly periods of 15, 31, 511 and 131071.
- `fpga/rtl/audio/zm_pokey.v` (plus `_pair` and `_poly`) runs on a 315/176 MHz enable from 100 MHz (63/3520, `zm_audio_frac`). `tests/test_rtl_pokey.py` requires its four channel levels to match the model bit for bit after every machine cycle. The scripts cover all 256 AUDCTL values and all 8 distortions on every channel, with and without volume-only: 1.24 M cycles on a fast enable and 60 k on the real one. 16 break tests (`ZM_RTL_BREAK=1`) each break one rule and require a failure.
- Points the documents leave open were decided as follows. Each is one place in the model and the RTL, so it can be corrected from a recording of a real chip:
  - The polys are XNOR Fibonacci LFSRs. Init mode clears them to 0, and a poly's output is bit 0. The trinomials (x^4+x+1, x^5+x^2+1, x^9+x^4+1, x^17+x^5+1) were chosen for their periods; the real chip's taps and phase may differ. An XNOR sequence has 15 ones in 31, so 5-bit gating passes 15 borrows of 31.
  - The 9-bit poly is the 17-bit register with its feedback entering at bit 8 (and 16).
  - The N+4 and N+7 periods come from a 3-cycle (single) or 6-cycle (joined) reload delay after a borrow, with the counter frozen during it.
  - A joined low channel rolls over to 0xFF and still clocks its own output flip-flop.
  - STIMER reloads all four counters and clears the four output flip-flops and both high-pass latches.
  - A disabled high-pass latch is held at 0, so it passes the signal through. An enabled one latches the filtered channel's output from before the cycle, on the filter channel's borrow (ch3's low-byte borrow when 3+4 are joined).
  - Init mode holds the polys and the 64/15 kHz dividers at 0. Channels on 1.79 MHz keep counting.
  - The mix is the plain sum of the four levels (0..60), not the chip's non-linear analog sum.

**Alternatives considered:**
- A GPL core (MiSTer Atari800) as a separate module, like jt49: quicker, but a second GPL block in the bitstream, and there is no model of our own to test it against.
- Porting an emulator's C (MAME, ASAP): GPL, and ruled out by the licence.
- A behavioural model only, no RTL: the FPGA needs the chip, and the sound CPU will drive it directly.

**Consequences:**
- The cost is small: 207 LUTs, 206 FFs, no BRAM or DSP. With the PAL enable added on feat/sap (a `pal` input, 100 MHz × 901/50805 = 1773447.495 Hz; the model's `Clock` is the same two ratios), it is 241 LUTs, 231 FFs, WNS +4.17 ns. Vivado out of context at 100 MHz on the xc7z010-1 gives WNS +4.68 ns (`PERIOD=10 IMPL=1 CLOCK=clk fpga/tools/vivado_ooc.sh zm_pokey ...`). The critical path is the shared `zm_audio_frac` accumulator, not POKEY.
- It is not in the SoC yet. The audio core gives it a register range and adds `mix` to the YM's box filter (the `cen` output marks the machine cycles), on the sound-CPU branch.
- Accuracy against the real chip is unproven where the documents leave a choice open (listed above). The cycle model is one file, so a correction is a model change plus the matching RTL line, and the bit-exact testbench catches any drift between them.
- Register writes coinciding with `cen` land after that machine cycle. The testbench does not exercise that case.

## 2026-10-10 — SAP: a 6502 of our own, the POKEY in the machine, sample-exact in the core

**Status:** accepted
**Context:** Phase B of the sound CPU: Atari 8-bit music (SAP files) next to the ST's. Every existing 6502 or SAP player we could use is GPL: ASAP, the MAME/Atari800 cores, MiSTer's. The POKEY was already written from scratch on feat/pokey, with a model and bit-exact RTL.
**Decision:**
- **The 6502** (`libs/zig/players/cpu6502*.zig`): written from public documentation, instruction-stepped with exact cycle counts, and held to 14,160 SingleStepTests vectors (MIT). Those check registers, RAM, cycles and every bus write, in order.
  - Read-modify-write instructions write the old value first.
  - The stable unintended opcodes run. The unstable ones and the JAMs stop the tune with the reason; no answer is guessed.
- **The SAP player** (`sap.zig`, `sap_bus.zig`, `sap_player.zig`): types B and C. D/S/R and STEREO are refused with a reason.
  - The Atari around the 6502 is the minimum players touch: POKEY, WSYNC, VCOUNT, RANDOM, GTIA's PAL.
  - Every other hardware write is counted and surfaced, never dropped silently.
  - Each POKEY write is stamped with the CPU cycle it was made at, so it is heard inside the frame, at its sample.
  - It runs in `demo-audio.wasm`: the browser, the native host, and the sound CPU through wasm2c.
- **The POKEY joins the sealed machine** (`machine/audio/pokey.zig` in machine-audio.wasm). Audio ABI 1.2.0: `machinePokeyWrite`, `machinePokeyClock`, `machineRenderPokey`. The chip runs PAL or NTSC, and its clocks are exactly the RTL's ratios.
- **In the FPGA's audio core** (`zm_audio_pokey.v`) the POKEY does not run free. At each sample strobe it runs exactly the machine cycles the model runs for that sample:
  - 40 or 41, from the model's own fraction of the clock over 44.1 kHz, restarted by the clock write in both;
  - as a burst, with the mix waiting for it, and writes held during it.
  - So the core equals the machine sample for sample (`pokey_exact`), as the Paula channels do.
**Alternatives considered:**
- ASAP or a GPL 6502: ruled out by the licence (the code is MIT).
- Klaus Dormann's functional test as the 6502 oracle: GPL-3.
- A free-running POKEY enable in the core (the first cut): the cycles fall into the sample windows differently from the model. It agrees to within a few machine cycles a sample, never exactly, and every mismatch would need a judgment call.
- Stamping a frame's writes at its start: simpler, but a player spreads AUDF/AUDC over its run (the synthetic test's AUDF3 lands 100 lines after AUDF1).
**Consequences:**
- The SAP stack is ours end to end and testable at each layer: the 6502 against SingleStepTests, the RTL against the model every machine cycle, the core against the machine every sample. ASAP stays outside the repo as an optional black-box check: envelope correlation 0.86-0.94 on five ASMA tunes.
- The POKEY costs 339 LUT, 298 FF and 1 DSP in the audio core. The burst holds the mix about 45 clocks of the 2,267 a sample has.
- Not modelled: ANTIC's DMA cycle-stealing (stamps are early by its share), IRQ-driven players (TYPE D), the second POKEY (STEREO).
- demo-audio.wasm's zero data grows 44 B; the Atari's 64 KiB and the write queue live in song RAM.

## 2026-10-11 — The blitter's pixel unit is pipelined; reads pass writes only where they cannot alias

**Status:** accepted
**Context:** On the board the blitter cart ran GLENZ at 40 fps, RUBBER 17, TILES 9, DELAY 27. The hp sim showed why: one pixel in flight, every access a single-beat AXI transaction, and the HP2 bridge holding every read until every write had its B. Any op that reads memory paid a whole HP read (~22 clocks) per pixel: 24-36 clocks a pixel for keyed BLITs and triangles.
**Decision:**
- `zm_blit_px` issues a pixel's reads and moves on; up to 32 pixels wait in `zm_blit_pxq` and are combined and written in order, through a one-word buffer (consecutive bytes = one strobed write).
- A read may run ahead of an earlier pixel's write only where it provably cannot alias it: C always (an op writes each byte once), A/B when `zm_blit_chk` proves the source spans disjoint from the destination span from the registers; otherwise (`ordered`) the v1 order.
- A channel whose byte is in the word it fetched last reuses that word (same proof), so a row costs W/4 reads per channel; nothing is reused across ops.
- The HP2 bridge holds a read only behind a write in flight covering its byte; writes go back to back.
- The sim DDR model takes `reads=8` outstanding read bursts per port in the hp sim (the AFI's acceptance).
**Alternatives considered:**
- A per-pixel CAM of in-flight destinations (exact for every BLIT, scrolls included): 2 x 34 x 23-bit compares on the read path, at 100 MHz with the SoC already tight; the register-level span test costs two adders and four compares, and only an op over its own destination falls back.
- AXI row bursts with a prefetch buffer: fewer transactions still, but with word reuse the pixel unit's one pixel a clock is already the limit for all but the 3-channel cookie-cut.
**Consequences:**
- hp sim, blitter cart: GLENZ 39 -> 60+ fps, RUBBER 18 -> 31 (now the cart's own CPU work), TILES 9.6 -> 53, DELAY 25 -> 59; tsl_hybridglenz 12.9 -> 19.4 fps (the rest is its CPU). Every hash unchanged.
- An `ordered` BLIT (a smear or scroll over its own destination) stays at the v1 rate.
- About +700 LUT and +500 FF for the blitter (Vivado OOC), no BRAM.

## 2026-10-11 — The blitter's addresses follow the sequencer's y; no multiplier on the pixel path

**Status:** accepted
**Context:** With the f32 FPU cart core the full SoC (87.5 % LUT) missed 100 MHz by 0.45 ns on 29 endpoints, all the same family: a register -> `y - y0` -> DSP (`* stride`) -> `+ base` -> `+ x` into the pixel unit's first register (`zm_blit_px` `p_a`/`p_b`; `p_dst` the same minus the subtract). Without the FPU it met by 0.02 ns.
**Decision:** `zm_blit_row` holds, per channel (A, B in the BLIT sequencer; D in the core for all four ops), the address of the row the sequencer is on and of the next one in the op's direction (`dn`: BLIT DESC, a LINE drawn upwards); every sequencer moves y by at most one row a clock and one way per op, so the pixel address is a compare, a 2:1 mux and `+ x`. The first row's product comes from a free-running 3-clock setup pipeline fed by the check's box, which is final three clocks before `go` reaches the sequencers: no clock added to any op.
**Alternatives considered:**
- A register stage between the sequencers and the pixel unit (a skid slice with valid/ready): one clock of latency per op and still a DSP + two adders in one clock, only moved.
- Pure incremental counters in each sequencer (+1 per pixel, +stride per row): exact for BLIT/FILL, but TRIANGLE starts each span at an arbitrary x and LINE moves both ways; the row walk covers all four with one module.
- Starting the walk after `go` (multiply after the start): +3 clocks on every op.
**Consequences:**
- Results and clocks per op unchanged (`blitter_tb` traces, cycles column included, identical in fast/random/deep); hp sim blitter cart equal to `scene_hash.mjs` and native.
- Vivado OOC P&R at 10 ns: WNS +0.108 -> +0.188 ns, the address family out of the worst paths (the worst is now the check's `bx1`); synthesis estimate +0.412 -> +0.736. About +490 LUT / +435 FF.
- A hidden contract: the box must be final three clocks before `go` (zm_blit_chk's header says so; a break test computes the first row a clock early and is caught).

## 2026-10-11 — Mode 3 plays a converted copy of the digi samples, above the image in 68000 RAM

**Status:** accepted
**Context:** Beat Dis in mode 3 (the samples on a PCM channel) was "inaudible: noisy plus weird loops" on the board. The board was not at fault: the board SoC sim's PCM output equals the native host's sample for sample, and the browser plays the same noise. The tune's bytes are unsigned and inverted (its volume table sums loudest at byte 0, silent at 255), and a Paula channel plays signed bytes, so every sample folded at its midpoint (correlation with the YM rendering 0.44). The 2026-10-10 tests checked that mode 3 played and handed back, not what it sounded like.
**Decision:** At load, a recognised digi driver's samples (from the sample data to the image's end plus the handler's 320-byte overshoot) are written converted (`127 - byte`, `digi_handler.zig linear`) into a shadow just above the image, reserved from the 68000's bump heap (`sndh_native.recognise` returns where the heap may start). Mode 3 triggers the channel in the shadow. No room below the heap's limit: mode 3 is not offered (asking answers 2).
**Alternatives considered:**
- Converting the tune's bytes in place on entering mode 3 and back on leaving: no extra RAM, but ~420 KB rewritten at every key press (a resync on BARD), and the 68000's data changed under Musashi's feet.
- A buffer in demo-audio's own memory: about 280 KB is free there; a whole Beat Dis is 421 KB, and per-segment copies (up to 124 KB) would have to be timed against the board's 3-frame lead.
- An unsigned/inverted sample format in the PCM channel (engine.zig and zm_audio_pcm.v): a new ABI field and a new bitstream for one tune's encoding.
**Consequences:**
- Firmware only: BARD's play image (demo-audio.wasm) changes; no bitstream.
- The load does ~421 KB more byte work, inside the load the stamp already re-anchors after (`audio_song_loaded`).
- Mode 3 follows the YM rendering (correlation 0.87-0.89, level matched by AC RMS: 129/256); `test_sndh_native.py` holds it and its mutant 2 (the raw bytes) fails; `bard_fx_run.py` holds the board sim's mode-3 samples to the machine's exactly across two segment changes.

## 2026-10-15 — The board's system image and lean cart images, bound by a versioned table

**Status:** accepted
**Context:** Every board `.zmd` carries one statically linked rv32 image (`fw.bin`, `cycles/board.mk`): ZIGGY's firmware, the wasm2c'd machine and ROM, BARD's play image (1.45 MB of it) and the cart. That is ~1.65 MB raw, ~255 KB packed per cart, ~6.4 MB of shelf for 15 carts, and a ROM or firmware fix means re-shipping every cart. The browser already keeps `machine.wasm` / `rom.wasm` apart from the cart and binds them at instantiation.
**Decision:** The board image is split in two, linked separately. glass writes both into the cart window on every load.
- **The system image** (`sys.bin`, one per variant: sim/board × audio × blit × FPU): the firmware (`bmain.c` and the rest of `fw.a`), machine, ROM, the wasm2c runtime, picolibc, and the BARD image blob. It is linked at the window's start exactly like today's `fw.bin`, so the reset vector, `.data`/`.bss`/heap/stack at 16 MiB and the BARD copy to `SND_BASE` do not move. The SD card carries it once, as `zigmachine/system.rv32`: a 16-byte header (`SYS_MAGIC` "ZMSY", the table version, the image length, a check word) before the image, ZX0-packed. glass reads and depacks it once at start-up.
- **The cart image** (`cart.bin`, per cart): the wasm2c'd cart, its env forwarders, its song files (`song_pack.py`) and libgcc, linked by `cycles/cart.ld` at the fixed `CART_IMG_AT` = window offset `0x0030_0000` (CPU `0x4030_0000`). It starts with its header (`CART_HDR_MAGIC` "ZMCA"). It has no `.data`, no TLS and no libc (`-nostdlib`, link-time asserts): every stateful service comes from the system, so there is one heap, one trap context and one `errno`. Its `.bss` follows the image and is zeroed by the system at every boot, cold or warm, as crt0 zeroes the system's.
- **Memory map** (window offsets): system at `0` (at most `CART_IMG_AT`, checked at link); cart at `0x0030_0000`; the shelf disk on the first 4 KiB boundary after the cart's `.bss` end, ending by `DISK_END` (12 MiB) as before; the rest is unchanged.
- **The table, cart → system** (`zm_sys_table`, in the system's rodata, handed to the cart's `bind()`): a magic, the version, a count, then function pointers in the order of `fpga/cycles/sys_abi.txt`. First the runtime (`env.memory`, `wasm_rt_trap`, funcref tables, `__assert_func`, `memcpy` & co, the libm calls wasm2c emits, `hostMicros`, the drive's `diskReadBlock`), then every `env.*` the browser binds a cart to: each `rom.wasm` export and the `MACHINE_ENV` list, as `ret f(struct w2c_env*, args)`. `tools/host_gen.py --split` writes the cart's forwarders (one indirect call each; `scene_hash.mjs`'s no-op stubs stay inline) and, once, the system's wrappers.
- **The header, system → cart** (fixed offset 0 of the cart image): the version the cart needs, its `.bss` range, `SHARED_PAGES`, its RAM high-water, `sizeof(w2c_cart)` (the system callocs the instance), then the entry points (`instantiate`, `boot`, `skipBoot`, `frame`, `isPlaneEnabled`, `hblDispatch`) and the song, input and disk-app bridges, the `--call` table and the song files: everything `env.c` gave the firmware by name.
- **Versioning:** `major.minor` in `sys_abi.txt`. A cart needs `major` equal and `minor` at most the system's. Adding a ROM export appends entries (minor + 1); removing, retyping or reordering anything, or changing the header, the bridges, the runtime list or `CART_IMG_AT`, is a major bump. Two refusals, both loud: glass compares the cart's header with `system.rv32`'s before touching DDR (`CartAbi` on the OSD, with both versions); the firmware compares again before binding (`ZM CARTABI need a.b have c.d` on the console, `CART_TRAPPED` with `TRAP_CART_ABI`, which glass names). No magic at `CART_IMG_AT` is `TRAP_NO_CART`.
- **The gate:** `fpga/tools/sys_abi.py --check` (in `build.sh`, stdlib Python, no fpga toolchain) recomputes the layout from `docs/rom.wasm`, `docs/machine-video.wasm` and the fixed lists, and fails when it differs from `sys_abi.txt`, or when the file's body does not hash to the hash recorded for its version; `--update` rewrites it with the right bump; `--break` proves a changed layout is caught.
- **BARD:** its image stays a blob inside the system (`snd_img.o`), copied to `SND_BASE` at boot as today. It is system code: one copy on the card. The songs it plays are cart data: the cart's header points at them, and `bsound.c` reads them through it.
- **The browser and the native host:** untouched. `host_gen.py` without `--split` writes the same `env.c` byte for byte; `scene_hash.mjs` and `build/host/<cart>/host` are the references the split images are held to.
- **The monolithic image stays** (`board-fw`, `hp-sim`, `board_run.py`'s U-Boot flow) as the oracle the split is compared against; glass loads either (a lean cart is recognised by its magic).

**Alternatives considered:**
- Linking each cart against the system's symbols (`--just-symbols`): no table, no call overhead, but every system rebuild silently invalidates every cart.
- Real dynamic linking (ELF relocations resolved by glass or the firmware): general, but a loader in two places for a fixed, small interface.
- Sharing `wasm_rt_call_stack_depth` with the system: it is a TLS variable, so the cart would have to hard-code an offset into picolibc's TLS block. The cart keeps its own counter instead (`-D_Thread_local=`): the 10,000-frame limit counts cart frames only, not the machine's few frames under them. A trap ends the run either way.
- Leaving the cart's libm/`memcpy` in the cart (no indirect call): picolibc's libm writes `errno` through `tp`, which points into the system's TLS block.
- Glass leaving the system resident and writing only the cart: faster swaps, but a cold load is a power cycle; the whole window is rewritten and read back as before.

**Consequences:**
- The shelf carries one system image plus lean carts; the per-cart numbers are in the PR. A ROM/firmware/BARD fix is one file on the card, for every cart of the same major.
- Each machine/ROM call and each libm/`memcpy` call costs one more indirect call on ZIGGY. Frames are byte-identical; cycles move by that.
- `build.sh` fails a ROM export change until `sys_abi.py --update` bumps the version, and a major bump means rebuilding every cart.
- `board_run.py` (U-Boot `loadx`) still loads monolithic images only.

## 2026-10-17 — `hostMicros` may pace a cart's audio feed (amends 2026-10-10)

**Status:** accepted by Matt 2026-10-17 (amends "`hostMicros`: a host clock import, for benchmarks only"); alternatives to revisit are on the roadmap
**Context:** ST Replay's INTERNAL output feeds the stream ring from the cart every frame (`apps/zig/scenes/st_replay_play.zig`). The speaker plays in real time, so the feed must follow real time. In the browser `dt` is real; on the board every host passes a constant 16.6 ms, and ST Replay runs ~15 fps there (hp_sim: 6.74 Mcycles a frame at 100 MHz). Paced by `dt`, the cart hands over a quarter of what the ring plays and the replay is mostly stale bytes. The 2026-10-10 entry forbids `hostMicros` for pacing.
**Decision:** A cart may pace an AUDIO feed (bytes handed to the speaker, and a playhead that follows them) by `hostMicros` when it answers non-zero, and falls back to `dt` when it answers 0. Animation and choreography stay frame-locked, as before.
**Alternatives considered:**
- Pass the board's real frame time as `dt`: every cart that animates by `dt` changes speed on the board, and hp_sim stops matching scene_hash.
- A ring-level register the cart polls (a DAC FIFO's half-full flag): the honest hardware model, but a new import, a worklet-to-page position report, and a BARD mailbox word. Worth it if a second cart needs it.
- Make ST Replay reach 60 fps on the board (its panel is redrawn every frame): still fragile, any slow frame starves the ring.
**Consequences:**
- The 0 fallback keeps scene_hash, the native host and every harness deterministic: they never see the clock.
- The EXTERNAL output (zg.samplePlay) needs no clock to sound right (BARD paces itself); it uses the same clock only for its playhead.

## 2026-10-17 — Native KESTREL carts use the wasm2c carts' calling convention, unchanged

**Status:** accepted
**Context:** Matt wants to see the bare machine: a "hello world" cart written for ZIGGY directly, once in C and once by hand in RV32 assembly, not compiled from wasm. The 2026-10-15 split already gives the board a lean cart image the system calls through a header (`zm_cart_hdr`) and that calls the machine and the ROM through a versioned table (`zm_sys_table`). Every lean cart so far is wasm2c output, so the header's entry points take wasm2c's arguments: the cart's instance (`struct w2c_cart*`, `inst_bytes` of it calloc'd by the system) and, at `instantiate`, the system's `struct w2c_env*`, which every table call into the machine or the ROM takes first.
**Decision:** A native cart mimics that convention exactly; the system image, `sys_abi.txt` and glass do not change (the board's `system.rv32` stays byte-identical).
- The cart defines its own `struct w2c_cart` (any layout: it is opaque to the system, which only allocates `inst_bytes` and passes the pointer back) and keeps the `env` pointer it is given at `instantiate`.
- The shared memory (registers, palettes, planes, the cart window) is reached exactly as a wasm cart reaches it: the table's runtime entry `w2c_env_memory(env)->data` is byte 0, `hwVideoBase()` is the video registers' offset. The ROM reads text and buffers from that memory, so the cart copies its string into its own corner of the cart window (`CART_RAM_BASE`) and declares `cart_high` past it, as a wasm cart's statics do.
- Bridges the cart does not use (songs, input, disk app, `--call` exports, song files) all point at one zeroed block: the system tests every bridge field for NULL and every list ends at a NULL name.
- Build: `cycles/native/native.mk` (`make native-cart NAME=hello|hello_asm`), linked by the same `cycles/cart.ld` as the wasm2c carts. `tools/native_cart.py check` holds the image to glass's and `bsys.c`'s rules; `native_check.c` holds the assembly's plain numbers (table indices, header offsets) to the generated header, so a table change fails the build.
- The disk: a native cart has no `docs/demo-<tag>.zmd`, so `native_cart.py disk` writes a v1 disk next to the image whose wasm boot cart only says "this disk runs on KESTREL only", and `glass_shelf.py` takes `<fw-dir>/<tag>/disk.zmd` before the docs shelf disk. `glass_sd.py --fw-dir build/hcycles/split/native_fpu` then stages it like any lean cart.

**Alternatives considered:**
- A "native" header flag or version and a simpler call path in `bsys.c` (no env, no instance): a few instructions fewer per call, but a new system image for every board, a second path to keep correct in `bsys.c`, glass and the tools, and a table bump; the wasm2c convention costs a native cart one saved pointer.
- A wasm-free disk with no boot cart: the disk format and `zmdisk.js` want one, and a browser that mounted the disk would fail with a parse error instead of saying why.

**Consequences:**
- Native carts are board only: the browser shows the stub's message, `scene_hash.mjs` has nothing to compare, and there is no pixel reference beyond the board itself.
- The assembly cart hard-codes table indices; `native_check.c` makes a table change a build failure, not a wrong call. A major table bump means rebuilding these carts like every other.
- A native cart is free to ignore wasm's sandbox (it can poke any address); the system does not protect itself from one any more than from a wasm2c cart.

## 2026-10-18 — The ZIGGY bench: a native cart that measures the board, its results read from DDR

**Status:** accepted (perf/ziggy-bench)
**Context:** The board's cost model (every store a blocking ~27-cycle DDR write, `@memset` ~60 cycles a word, CHISEL ~1.85 cycles a byte, ~1.09 Mc an enabled plane) was fitted to 92 carts' frame rates, not measured. The posted-write buffer (`soc/zm_hp_posted.py`) is about to be A/B-tested and needs a measurement that runs unchanged on both bitstreams. ZIGGY has no console on the board (`cycles/bboard.c` prints nothing: the JTAG UART has no reader).
**Decision:** A native cart (`fpga/cycles/native/bench/`, the 2026-10-17 convention) times each test with ZMCycles read directly: the firmware runs carts in M-mode, so the CSR is reachable (rdcycle is not: the core's `mcycle` is not readable). Its results go into a text log that is the first object of the cart's `.bss` (`log.c` is linked first), whose address the cart header already carries (`bss_start`); `fpga/tools/bench_collect.py` reads it with busybox `devmem` over the serial shell. No system, ABI, glass or RTL change.
**Alternatives considered:**
- A `glass ctl` command that dumps cart memory, or a cart→glass text channel (a table entry): faster to read and reusable, but a glass rebuild or an ABI 1.2 entry (`sys_abi.txt` is append-only) for one tool. Worth it if a second cart wants to report text.
- `dd`/`hexdump` of `/dev/mem`: `read()` on a no-map reserved region is not reliable on ARM; `devmem` maps it as glass does.
- `env.hostMicros` as the clock: 1 µs (100 cycles) resolution and a 64-bit divide per call.
**Consequences:**
- The bench relies on M-mode carts; if the firmware ever enters carts in U (the seal), the counter loads trap and the bench must time through a table entry instead.
- The log costs ~2-5 s of `devmem` calls to read; the cart and the reader agree on its layout by hand (`log.c` / `bench_collect.py`), held by `test_bench_collect.py` and the placement test.

## 2026-10-18 — BARD's audio state reaches the cart through its S2C register bank (sys table 1.2)

**Status:** accepted
**Context:** In the browser the loader writes the worklet's `audioState` into the running cart (`ym_regs`, `audio_mode`, `song_ms`, `scopes`, through the cart's `get*Pointer` exports). The board never did: D-BUG's scroller and logo are clocked by `song_ms` and sat in their intro, music_debug's oscillograph saw mode 0 and drew nothing, and the YM VU meters (gen4_3615, swedish_newyear, union_deltaforce) stayed flat. With the music on BARD only the sound CPU knows the state; the system image also had no way to learn where a lean cart keeps those fields, since the cart header is fixed at 1.x.
**Decision:**
- BARD publishes mode, SNDH position and the 16 YM registers in S2C words 12..18 (`fpga/cycles/aud_state.h`) after each render, storing a word only when it changed. ZIGGY reads them after the cart's frame and `cycles/bmirror.c` writes into the cart only the bytes that differ.
- The cart's field offsets go to the system once, right after instantiation: a lean cart calls a new host entry, `hostAudioMirror`, appended to the table (1.1 -> 1.2, a minor bump: every 1.1 index stands, a 1.1 cart runs unmirrored). The monolithic image calls the same hook from `host/boot.c`.
- On the board only (`ZM_BOARD`; `ZM_AUDIO_MIRROR=1` for a sim), because sims are hashed against `scene_hash.mjs`, which has no audio.

**Alternatives considered:**
- A versioned block in DDR that BARD writes and ZIGGY reads after a D-cache range invalidate: every BARD write is a blocking DDR store (~27 cycles), and the reader must invalidate. The S2C bank is LUTRAM already shared by both CPUs, uncached on both sides, with 20 free words: the same versioned block, no DDR traffic, no invalidate, no RTL change.
- A pointer bridge in the cart header: a header layout change, so a major bump and every cart rebuilt.
- A new cart import (`zg.audioState()`), polled by ZigOS each frame: every cart's wasm and the browser loader change, and so does every harness's import list.
- Mirroring `scopes`: no CPU has the mixed Paula samples on the board (Paula is RTL), so there is nothing to mirror.

**Consequences:**
- A cart that reads the state now looks on the board as in the browser with sound on. Its frames therefore differ from a no-audio reference once music plays, which is why the sim keeps the mirror off.
- The cost is a few stores a frame on each CPU while a tune plays: the position word every frame, plus the YM registers that changed (`tests/test_audio_mirror.py` pins "unchanged costs nothing").
- MOD and sample scopes stay flat on the board.

## 2026-10-18 — ZIGGY's stores are posted on the board, with a fence before every IO store

**Status:** accepted (pending the board measurement)
**Context:** The bench cart measured every ZIGGY store at 18 cycles on the board: one HP0 write, waited for to its B response, whatever the width or stride; memset is 18 cycles a word. BARD already posts its stores through `soc/zm_hp_posted.py`, which keeps up to 8 writes in flight and never waits for a B response before issuing the next.
**Decision:**
- HP0 is built with `posted=8` (`soc/zm_board_mem.py POSTED`, `--posted N` on the z7 build and hp_sim, 0 = blocking). A model port with an 18-cycle B response takes a store stream at 3 cycles a store with 7 writes in flight, against 23 blocking (`tests/test_hp_posted_rate.py`).
- Every consumer of "an acknowledged store is in DDR" was checked:
  - The bridge's own reads, the video's `drained` and the CHISEL start already waited for `idle`.
  - A master that reads DDR when the cart rings an IO register did not: BARD's mailbox (song and PCM bytes over HP3), CHORUS's PCM without BARD, and any CSR doorbell.
  - `soc/zm_io_fence.py` now holds every ZIGGY store to the IO space (byte bit 31) until `idle`. That is release ordering for device writes; loads are not held.
- DDR-only protocols (the debug mailbox, the cart request block: data first, magic last) keep their order: one AXI ID, AWCACHE 0000, the buffer drains in program order.
**Alternatives considered:**
- Write-combining consecutive stores into bursts: deferred until the board shows how close posting alone comes to CHISEL's ~4 cycles a word.
- Fencing IO loads too: no consumer needs it, and every poll loop would pay for the drain.
**Consequences:**
- Same CSR map: the firmware and every cart image are unchanged.
- ZIGGY's I- and D-bus share the one HP0 bridge, so every read (a D$ or I$ miss, an uncached load) still waits for the buffer to drain. Only store runs between misses go faster. (Since 2026-10-19 a refill only waits for stores to its own line: the read-bypass ADR below.)
- Vivado: 15,045 LUT (+157), sys WNS +0.011 ns at 100 MHz.
- An IO store after a burst of DDR stores waits for them to drain: at most 8 writes, which overlap, so about one write response plus the issue slots (tens of cycles).
- `ZMCycles.dbus_wait` now counts that wait.

## 2026-10-18 — FRESCO composites runs of handler-free planes line-major; W64 is one ARM-side switch

**Status:** accepted (perf/fresco-linemajor; the board's numbers pending)
**Context:** The board's FRESCO probe (`fps_20261018-222023`) shows the 30 fps carts are compositor-bound: a row read costs ~400 sys cycles and a row write ~1,040 (32-bit write beats), and a plane pass loads the PFB row and the picture row and stores both back, so a line composited by N planes moves its rows N times (`fpga/PLANES_PLAN.md` §1, rank 1 W64 and rank 2 line-major). The plan's rule groups the planes *below the first plane with an HBL handler*; on the carts it was meant for (automation442, supplex_fs2, union_main: every overscan plane has its flicker handler; replicants, stcs, ancool: a raster handler on plane 0) that group is empty.
**Decision:**
- **RTL** (`rtl/video/zm_video_pass.v`): three command bits. `hold`: no row LOAD, the line buffer and the accumulator go on from the line's pass before; `keep`: no STORE, READY follows MIX; `nopfb`: the STORE writes the picture row only. `dirty` and a new `filled` are sticky across held passes (cleared only on a take without `hold`), so a group's last pass stores the PFB row when any of its passes painted or filled it. `fill` and `first` mean what they say on any pass: the firmware sends them on a group's lowest pass only. The cmd CSR grows by 3 fields at its top, its address does not move: an old firmware writes 0 (plane-major), and a new firmware on an old bitstream is still exact (the bits are ignored, so each pass reloads and restores the rows the pass before stored).
- **The rule** (`cycles/bplanes.c`): every maximal run of consecutive enabled planes with no HBL handler is a group, wherever it sits; handler planes stay plane-major. In plane-major no cart code runs between the passes of such a run either, so every pass reads the same state and each LATCH takes the same registers in both orders; a plane enabled or not is asked where `video.zig` asks, before any pass of the run, which no code separates from its turn. A handler plane is never in a group: its handler may write RESOLUTION, RES_FLICKER, a palette or the LFB that another plane reads at line y (`tools/video_order_group.py`: interleaving s:medium's or s:overscan's handler planes changes the frame).
- **No PFB row store** (plan option 3) when a group is the frame's top layer: nothing loads that row again this frame and the next frame's clear rewrites it. Not on a handler plane on top: its handler could enable a plane above it, which would load the row.
- **Where:** on the board by default; a sim only with `ZM_LINEMAJOR=1` (its run-to-run timings stay comparable); a hashed frame is always plane-major (its PFB is hashed after each plane, as scene_hash does).
- **W64 and the A/B switches:** one ARM-side switch, `glass run --fw-opt=N` (`fpga/glass/src/afi.zig`). With bit 1 (W64) glass holds the cart CPU, pauses 1 s for HP1 to drain, sets HP1's WRCHAN_CTRL 0xf00 and reads it back; every load then writes `0xc0f0_00NN` to the word bdiag's `hp_cfg` tag already lived in (window end − 0x1F8), which the firmware applies at boot. A run without bit 1 (or without `--fw-opt`) puts the channel back to 0xf01. Bits 4 (plane-major) and 5 (keep the PFB store) switch line-major off for an A/B with one `system.rv32`. W64 stays off by default until the board proves it (hp-test on HP1, bdiag mode 3 with `board_run.py --w64`, then vcal's W).
**Alternatives considered:**
- The plan's rule as written: exact, but no gain on the carts that need it.
- Grouping handler planes whose handlers only flicker the border: union_main's frame does not change when its three flicker handlers interleave, but nothing at run time can tell such a handler from one that writes what another plane reads.
- The W64 knob as a glass register the firmware reads (two independent switches the lead could set apart) or as a second `system.rv32` (no A/B with one image).
- A runtime detector of handler side effects: LFB stores are not snooped, and a frame found wrong cannot be redone.
**Consequences:**
- Pixels: unchanged (`tests/test_rtl_linemajor.py`: line-major replays of the whole corpus, every multi-plane frame grouped whole, PFB and picture exact; `tests/test_video_order_group.py`: the rule never changes a frame's consumed state; ZM_LM_CHECK in the board-SoC sim).
- On the board the PFB in DDR is stale after a frame whose top layer is a group: `board_shot.py --what pfb` needs `--fw-opt=0x20`.
- The carts with a handler on every plane gain only from W64 (and nothing from the group rule); leonard-like carts (handler-free planes) lose a row load and a row store per extra plane and line.
- vstat's `painted` share no longer counts a group's passes (they are not waited on one by one).
- Vivado (board recipe, posted 8, FPU core): 15,035 LUT (85.4 %, -10 against posted alone), sys WNS +0.043 ns; the CSR map is unchanged.

## 2026-10-19 — W64 needs HP1's write channel 64-bit from boot; glass refuses a run-time 32 -> 64 switch

**Status:** accepted (perf/fresco-linemajor; supersedes the "glass sets 0xF00 at run start" half of the 2026-10-18 ADR)
**Context:** `glass run --fw-opt=2` showed every other picture column missing (Matt, 19 Oct). The RTL was right: the lm8 netlist drives SAXIHP1WDATA[63:0] = the whole beat, WSTRB 0xFF, AWSIZE 3, AWLEN n-1 when `hp_cfg` bit 1 is set, and the bench's W beats halved (fr.dirty.p1 545 -> 422 Kc). A marker fill of both pictures (`prototypes/w64_re/fbpeek.c`, 0xDEADBEEF, then 300 ms of compositing) showed which words are written: words 0 and 3 of every 16 bytes, words 1 and 2 never, with the right data in the written ones (beat 0's low lane, beat 1's high lane). That is not "the upper lane dropped". On the same bitstream and firmware:
- HP1 set 0xF00 by U-Boot right after `fpga loadb`, before any HP1 traffic (`prototypes/w64_re/boot_w64.py`): W64 writes every word on 11 carts (marker left 0 / 0 / 0 / 0), and GEM's picture is identical to the W32 one (224,000 of 224,000 pixels, same hash).
- the same boot, then a run-time 64 -> 32 switch (glass `--fw-opt=0`): WR32 correct.
- then a run-time 32 -> 64 switch (`--fw-opt=2`): words 0 and 3 only again. WRCHAN_CTRL reads back 0xF00 every time.
So a channel that has carried 32-bit writes and is then set 64-bit keeps a 32-bit lane walk (0xF01 then 0xF00 with no traffic between is untested, so every path now sets the final width once); the 10-03 "odd columns black" and the 10-19 "odd columns missing" are this, not the openXC7 BRAM and not the RTL. Whether an AFI reset (SLCR FPGA_AXDS) would clear it is unverified.
**Decision:**
- W64 is a boot-time choice: HP1 WRCHAN_CTRL 0xF00 from the first write. `uboot_serial.set_afi(hp1_w64=True)` writes 0xF00 in place of 0xF01 (never 0xF01 then 0xF00).
- glass (`afi.zig` `want`): `--fw-opt` with W64 on a channel that is not 0xF00 is `error.W64NeedsBoot` (glass exits with a message: reboot with boot.cmd's 0xF00); without W64, a 64-bit channel still goes to 0xF01 at run time (proven correct).
- boot.cmd keeps 0xF01 for now (superseded the same night by the next ADR: W64 is the default): the rootfs's own glass predates `afi.zig` and would run the menu's WR32 beats on a 64-bit channel. Making W64 the default needs boot.cmd HP1 0xF00 and a rootfs glass that sets 0xF01 for a non-W64 run, together.
**Alternatives considered:** an RTL change (nothing in the PL is wrong); switching at run time through an AFI reset pulse (unverified, and a wedged AFI needs the RST KEY); keeping the run-time switch with a warning (it silently halves the picture).
**Consequences:** W64's numbers from 10-19 hold (the broken run already sent 8-byte beats): fr.dirty.p4 1.133 -> 0.995 Mc, fr.dirty.p2 0.727 -> 0.611. Board fps, same bitstream (lm8 6261127d) and boot, fw-opt 0 -> 2: automation442 30.1 -> 60.2, deltaforce 40.3 -> 60.2, stcs 31.3 -> 48.2, union_l16 30.3 -> 41.1, ancool 30.1 -> 40.0, fallen_angels 40.3 -> 51.6, union_main 22.1 -> 26.2, dbug 25.4 -> 28.2, leonard 59.4 -> 59.4 (`prototypes/w64_re/fps_*`). A board rebooted the usual way (boot.scr 0xF01) cannot run W64 until the next boot.

## 2026-10-19 — W64 is the board default: boot.cmd HP1 0xF00, glass W64 on a 0xF00 channel, the rootfs carries that glass

**Status:** accepted (Matt approved W64 as the default; perf/fresco-linemajor; supersedes "boot.cmd keeps 0xF01 for now" above)
**Context:** W64 (the video DMA's 8-byte row writes on HP1) is pixel-exact when HP1's write channel is 64-bit from boot, and worth fr.dirty.p4 1.133 -> 0.995 Mc and up to 2x fps (automation442 30 -> 60). It needed three things to agree, or a plain reboot would run 4-byte beats on a 64-bit channel (half the words lost): the U-Boot script, the glass's default, and the glass S99glass starts, which is the initramfs's /usr/bin/glass (it predated afi.zig and was replaced by hand with `cp /mnt/sd/glass` after every reboot).
**Decision:**
- boot.cmd: HP1 WRCHAN_CTRL 0xf00, once, right after `fpga loadb` (never 0xf01 first); HP0/HP2/HP3 stay 0xf01.
- glass (`afi.zig` `resolve`): with no `--fw-opt`, the channel decides: 0xF00 means W64, and every load writes the FW_OPT word `c0f00002` (the firmware reads an untagged word as all off, so W64 needs the word, not just the width); 0xF01 means what it meant before (no word, width left). `--fw-opt` still overrides for A/B: W64 on 0xF01 is `W64NeedsBoot`; an option set without W64 on 0xF00 (`0`, `0x30`) sets 0xF01 at run time (64 -> 32 is correct) with a warning, and stays W32 for every later run of that boot, since 32 -> 64 is never done at run time.
- The rootfs: `fpga/tools/rootfs_glass.py` swaps the one `usr/bin/glass` entry of Buildroot's newc `images/rootfs.cpio` (stripped with Buildroot's strip, as post-build.sh does) and re-wraps it as `mkimage -T ramdisk` does; every other entry keeps its bytes (the round trip on the card's rootfs is byte-identical). `glass_sd.py --buildroot` stages the rootfs that way, and marks a plain copy of Buildroot's own rootfs STALE.
- `uboot_serial.set_afi` / `board_run.py --w64` keep W32 as their default: that is the bare-metal bdiag path, where the firmware is given `hp_cfg` directly and no glass runs.
**Alternatives considered:** re-running Buildroot (its post-build.sh takes the glass from the main checkout's zig-out, a tree other sessions build in; and it would rebuild an image to change one file); a glass that switches HP1 to 0xF00 at run time (that is the bug); keeping 0xF01 and booting W64 by hand (`boot_w64.py`) for every measurement.
**Consequences:** proof on the board after a plain reboot (`prototypes/w64_re/proof_default.txt`, `default_boot_console.txt`): WRCHAN_CTRL 0xF00, `glass run /mnt/sd/zigmachine` with no flag logs `HP1 write channel 0xF00, fw-opt 0x2`, the FW_OPT word reads `c0f00002` after each load, fbpeek's marker fill leaves 0/0/0/0 on gem, leonard, automation442, medium_overscan, st_replay, deltaforce and union_main, and GEM's picture hash is ca88023d, the same as W32's. Bench fr.dirty.p4 0.996 Mc (p1 0.423, p2 0.612); fps automation442 60.2, deltaforce 60.2, stcs 48.2, leonard 59.4. The W32 arm (`--fw-opt=0`) on the same boot: 0xF01, word `c0f00000`, GEM hash ca88023d. Risks: a disk whose firmware predates the FW_OPT word would send 4-byte beats into the 64-bit channel (the seven carts marker-checked run the card's system.rv32 6ada2908, which reads it; the other shelf disks were not marker-checked one by one); a future SD staging without `--buildroot` copies no rootfs. Rollback: on the card, `boot.scr.bb67385d` -> boot.scr (HP1 0xf01) and `rootfs.cpio.uboot.31eeb461` -> rootfs.cpio.uboot, reboot (the old card glass is `glass.a896da36`). Restore both or neither: the old rootfs under the new boot.scr is the forbidden pair (a glass without afi.zig on a 0xF00 channel). If Linux does not come up at all, recover from U-Boot over serial with `prototypes/w64_re/trial_boot.py rootfs.cpio.uboot.31eeb461 0xf01` (boot.cmd replayed by hand with the old rootfs), then rename on the card; the new glass is still correct on 0xF01. Seen on the way: on a W32 run, GEM's static picture keeps fbpeek's marker in all four words alike (rows the firmware does not recompose while nothing changes) while W64 rewrites them; uniform across lanes, so not a lane loss, and GEM's unmarked hash is identical.

## 2026-10-24 — Pure HBL handlers join line-major groups (HW 1.8.0); a copper list in both machines (HW 1.9.0)

**Status:** accepted (Matt delegated to the lead; Fable reviewed fpga/review/FRESCO_OPTIONS.md: stay frame-serial)
**Context:** a frame on the board is the cart plus FRESCO's line passes, ~60 % of a later layer's pass is row I/O, and a plane with an HBL handler was always plane-major (its rows moved once per plane). The slowest multi-plane carts have a handler on every plane, mostly flicker and own-palette writes; and per-line palette stores cost the CPU ~28 sys each (tcb_colorshock 0.86 Mc a frame).
**Decision:**
- 1.8.0 `REG_FB_HBL_PURE` (u8 x4 at 0x74): the cart says a plane's handler is pure (own palette and/or flickerBorder only). The board then runs it right before its own pass inside a line-major group, storing RES_FLICKER as that plane's own handler left it (cycles/vseq_group.c); the browser ignores the flag. ZigOS sets it in openBorders, copper, linepal and setFrameBufferHBLHandlerPure. Gate: `pure_hbl` (fpga/tools/video_order_pure.py).
- 1.9.0 `REG_FB_COPPER` (u16 x4 at 0x78): a per-plane list of line records (PAL, PALREF, REG HSCROLL, FLICK; reserved opcodes stop a list) that the machine applies after the plane's handler and before the line: machine/copper.zig in the browser, rtl/video/zm_video_copper.v on the board, WRITEBACK (cmd op 6) putting the palettes back in the region at frame end. zg.copper builds its lists at frame end and installs no handler; a raw list API for carts (tcb_colorshock's per-row palette through PALREF tables in VRAM).
- HBL handlers stay for racing the beam (Matt, 2026-10-23); idea 1 (composite at scanout) is not opened (94 % LUT, sys WNS +0.04 ns, a slow line becomes garbage, it loses the scene_hash oracle).
**Alternatives considered:** a palette-only copper (does not move flicker planes); trusting every handler (wrong for carts whose handlers talk: bladerunners, vex); a hardware copper only (3a gets the grouping with no RTL); RES_FLICKER bumped by FLICK (needs a copy-back after every pass: FLICK is a per-line flag instead).
**Consequences:** 3a on the board: replicants 30 -> 60 fps, supplex_fs2 30 -> 60, tcb_colorshock 30 -> 50, union_main 29 -> 40 (pictures equal the browser's on 28 frames, tools/board_pic.py). 1.9.0 costs zm_video_comp +576 LUT / +348 FF (Vivado OOC synth, 1,775 -> 2,351), WNS unchanged; a 1.9.0 cart needs a 1.9.0 machine (hosts hand carts no hwVersion), so the board's system.rv32 and the carts go on the card together.

## 2026-10-24 — The board runs a disk's wasm boot sector through a small interpreter in the system image

**Status:** accepted (roadmap item from Matt; board check pending)
**Context:** a ZigCart v2 disk's first 1 KB is an executable wasm module (`$1234`) that the browser runs before the disk's cart (sysinfo's "No virus", replicants_emlyn's crew note). The board ran only native carts (wasm2c + rv32), so neither screen showed there.
**Decision:** the firmware interprets the disk's OWN sector bytes: `fpga/host/wint*.c` (integer MVP, f32/f64 bit moves, sign extension, memory.fill/copy, multi-value blocks; float arithmetic, call_indirect and tables refused at load) and `fpga/host/bootsec.c` (the browser's sector loop: hwInit, boot(), per frame hwClear/frame/pollCartRequest/planes). `cycles/bbootsec.c` runs that phase in `bmain.c` between `host_boot_machine` and `host_boot_cart` (the sector's data segments land in the cart's RAM window, so it must run before the cart is instantiated, as in the browser). Board images only (`ZM_BOOTSEC`); not for a program GEM launched off the disk (req 3), nor when the glass brings GEM back over it (req 4: `BOOTSEC_SKIP` word, map_cart.zig).
**Alternatives considered:** wasm2c each disk's sector into a native blob on the fat disk (a third image kind on the card, a placement and an ABI in the glass, and native code off the card cannot be time-limited); a per-disk lean cart linking GEM + the sector (one GEM build per data disk). The interpreter needs no build step, works for any v2 disk, and is a sandbox: every opcode and immediate checked at load, every access bounds-checked, a fuel budget per call (16 M instructions for boot(), 1 M a frame), a 30 s frame cap, an HBL handler or a trap ends the phase and the cart boots anyway.
**Consequences:** novirus' boot() is ~1.0 M interpreted instructions (its 64000-byte clear is a byte loop), replicants' 166 K (memory.fill); a frame is a few. The board shows the sector for its 120 / 240 frames before GEM / the screen. The sector's `beep` is silent on the board (the sound CPU starts with the cart). The system image grows 23 KB of code (linked after fw.a); .data/.bss do not move; code after bmain.o/bsys.o moves 152 B. Proof without the board: the interpreter equals node's WebAssembly on both sectors (whole memory, every frame) and on 24,844 opcode calls; the native host's `--bootsec` picture equals `scene_hash.mjs X.zmd` (`fpga/tests/test_board_bootsec.py`, 7 break mutants under ZM_RTL_BREAK=1).

## 2026-10-19 — CHISEL's lazy wait: hwBlit may return before the op ends, when the cart opts in

**Status:** accepted (pending the board measurement)
**Context:** The ZIGGY bench shows CHISEL runs on its own (still busy after the CPU's loop in 28 of 28 contention runs), yet every hwBlit on the board spins until BUSY falls. An 8x8 fill costs ~910 cycles through hwBlit: ~450-500 of fixed latency in the spin (GO to BUSY low, `ch.raw.fill8.x64` = 544 with the cart's own stores) and ~370 of wrapper (the table call, VBASE, the D$ line range, CYCLES/STATUS). A big fill adds ~1 cycle a byte of spin. The CPU could do other work meanwhile, but the firmware cannot see the cart's CPU pixel accesses (plain wasm2c loads and stores), and zm_blit drops register stores while BUSY (`zm_blit_regs.v`), so returning early by default would corrupt both the next op's registers and any CPU drawing that follows a clear.
**Decision:**
- Opt-in, per cart: `BLIT_ASYNC` (region 0xE4, u8, outside the tap's 24 words and every snoop window; the machine never reads it). With it set, `fpga/cycles/bchisel.c` returns once CHISEL has started (one uncached load after GO, so the tap starts the op before any later store reaches it).
- The wait moves to: the next hwBlit (after its own D$ plan is worked out), a NOP hwBlit (ZigOS `chisel_async.sync`), every machine/ROM env entry and the drive (`HOST_CHISEL_SYNC`, generated by `tools/host_gen.py`), the end of each HBL handler and of `frame()` (`bmain.c`).
- The lazy op's D$ lines are planned at GO (`bdinval.h bdi_plan_op`) and dropped at the sync; after it every word of the block is stored back through the tap, so registers the cart wrote while CHISEL ran (dropped by the engine) are what the next op reads.
- Adopted where every pixel between kick and sync is CHISEL's: fuji_hobbytronic (the clear overlaps the logo's maths), tsl_hybridglenz (stage and glenz), stniccc (each span's fill overlaps the next span's edge walk; the keyframe copies sync first).
**Alternatives considered:**
- Lazy by default: incorrect, for the two reasons above, in 90+ carts that clear then draw with the CPU.
- A new cart import (`hwBlitAsync`/`hwBlitSync`): a sys-table bump, every loader and harness import list, for what a byte and a NOP already say.
- A CHISEL command queue (descriptor list, ~100-200 LUT): amortises the per-op latency for many-small-op carts, which this cannot; deferred until the board numbers of `as.*` say how much of the ~910 is left.
**Consequences:**
- No RTL change, no sys-table bump, browser and scene_hash unchanged (the machine is synchronous).
- A lazy op costs ~80-100 cycles more CPU (the replay); it pays when the CPU has more than that to do before the next sync.
- A cart that touches a lazy op's pixels before syncing draws wrong on the board only: the contract is the cart's, and only carts whose code was read for it opt in.


## 2026-10-23 — The lazy CHISEL wait: only entries that can touch memory wait; getters do not

**Status:** accepted (perf/chisel-queue-v2; supersedes "every machine/ROM env entry" in the 2026-10-19 lazy-wait ADR)
**Context:** 7740706e put `HOST_CHISEL_SYNC` in front of every machine and ROM env entry. On the board that turned each wrapper from a two-instruction tail jump into a framed function, and its flag shared a D$ line with statics written all the time; with the 72 bytes of new statics moving the shared memory's place in ZIGGY's 4 KiB direct-mapped D$, rno_natrium fell 60 -> 54 fps and union_l16 36 -> 31 (firmware bisect, prototypes/chisel_queue_re/bisect).
**Decision:**
- An entry waits for a lazy op when it can touch memory a lazy op reads or writes: every ROM entry (it draws and reads with the CPU), the drive, the RAM arena's alloc/mark/release (alloc zeroes memory), the end of each HBL handler and of `frame()`. The getters (`tools/host_gen.py` `GETTERS`: `hwVideoBase`, the `hwRam*`/`hwRomRam*` sizes, `romScratchLen/Ptr`, `deskDir*`) return a value, touch nothing, and do not wait. hwBlit waits inside, as before.
- The wait's rare path is a `jal t0` into `bchisel_sync_saved`, which saves the caller-saved integer registers itself, so a waiting entry keeps its tail jump and gets no frame; `bchisel_pending` has its own 32-byte line.
- The shared memory sits at a measured offset in a 4 KiB page (`host/mem_place.h`, fix/bard-local-base), so the next static added to the firmware does not move it.
**Alternatives considered:** keep the wait everywhere and only make it frameless (union_l16 came back, rno_natrium did not); drop the per-entry wait altogether (a ROM call over a lazy op's pixels would read stale ones).
**Consequences:** board (card bitstream, firmware only): rno_natrium 60.2, union_l16 38.5, polkadots 54.9 (main 60.3 / 38.5 / 52.5); gen4_3615, fuji_hobbytronic, tsl_hybridglenz, union_tnt1 unchanged at 60. A new machine or ROM entry waits unless it is added to `GETTERS`, which the tests hold to value-returning entries. stniccc's queue was not re-measured with this firmware (its bitstream must be JTAG-loaded).

## 2026-11-01 — CHISEL v2: span-list AFFINE, a 2-D MAP, the small-ops bundle, the QUEUE landed (HW 1.11.0)

**Status:** accepted (Matt approved CHISEL v2; bitstream and board A/B pending, the lead's)
**Context:** The blitter was ~20 % of the die and the brief asked for a LUT cut before new ops. Fable's ISA
study (fpga/review/KESTREL_NEXT_ISA.md §2) showed texture classes are D$-miss bound on ZIGGY, so CHISEL
should own the texel reads; the retro survey asked for mirror, collision and the Amiga area fill; the
QUEUE (board-measured, never merged) had to land first.
**Decision:**
- The fold first (checks serialised, FILL on the BLIT walker, halftone in LUTRAM: -329 LUT) with the
  in-plane overlap fix (the box's own span; a walk that never reads behind itself runs unordered).
- AFFINE takes a **span list** (x0, x1, y, u0, v0, du, dv), not a fixed-width row table: Mode 7 rows are
  full-width spans and the same op rasterises textured polygons the CPU scan-converts. MAP is 2-D
  ((u8, v8) + U_OFF/V_OFF) rather than 1-D offsets: a tunnel is one map and a moving offset.
- Lists and maps must sit in cart RAM / the ROM window (never written by CHISEL), so their reads,
  streamed through an aux side of the read port (zm_blit_rdmux, zm_blit_tfetch), never order.
- Every new register lives in the block's words 0..23 (C_BASE/C_STRIDE, the strides' high halves,
  X1/Y1), so a QUEUE descriptor reaches it; BLIT_COLL (a status) sits at 0xE6.
- COLL is per kick in CHISEL and ORed into memory by the firmware: a stored flag could not stay sticky.
**Alternatives considered:** a per-row parameter table (only floors); a textured TRIANGLE in RTL (more
LUTs; the CPU does per-row setup cheaply); dependent map reads through the pixel unit (it has no
dependent-read path); 1.10.0 (taken by LBASE).
**Consequences:** +952 LUT net over main (4,276 in all, 23 DSP, 1 RAMB18), both clocks close out of
context; over the "LUT-neutral" wish, cuts ranked in docs/ROADMAP.md's CHISEL v2 row and BLITTER_HW_SPEC
10.4. stniccc queues every fill (painter's order) against its CPU path: the board decides. 88 mutants,
cart 112 and its harness prove the ops.
## 2026-10-19 — ZIGGY's cache-line refills overtake posted stores to other lines

**Status:** accepted (pending the board measurement)
**Context:** With `posted=8` a store costs 2.25 cycles on the board, but every read still waited for `idle`: the buffer empty and every write answered. memcpy went only from 6.1 to 2.73 c/B: per 32-byte line ~48 cycles of refill, ~18 of stores, ~20 waiting for the previous line's stores (`fpga/BENCH_REPORTS.md`, 2026-10-18 late).
**Decision:**
- `WishboneHP(read_bypass=True)` (`fpga/soc/zm_hp_bypass.py`): a burst read (a D$ or I$ refill) is sent unless a store to the same 32-byte line is still unanswered; then it waits as before.
- A store is in DDR only at its B response (AWCACHE 0000, one ID, in order). The ring forgets an address when it is issued, so the tags live from push to B: 16 slots (8 buffered, 8 in flight), each with a 20-bit line tag compared to the read's line.
- A single (classic) read keeps the full drain. IO loads never reach this bridge, and the IO-store fence (`idle`) is unchanged.
- The compare is registered, off the AR path: with stores pending a refill starts one cycle after its request. This relies on the master holding the request until its ack and pushing no store meanwhile.
- On for the board and its sim (`zm_board_mem.READ_BYPASS`). `--no-read-bypass` on the z7 build and on hp_sim turns it off. BARD keeps the drain.
- AXI ordering: AR and AW/W are separate channels with no order between them. HP0 has one read outstanding on ID 0 and writes in order on ID 0. Only a read and a write to different lines ever overlap, which AXI allows and no load can observe. `hp_slice` registers each channel on its own, so it cannot reorder within one. A refill of code the CPU has just stored (the loader, then `fence.i`) goes through the same compare, because the I-bus shares the bridge.
**Alternatives considered:**
- Comparing only the 8 buffered entries: wrong. An issued store is still not in DDR until its B (break test `retire_on_issue`).
- Letting single reads bypass too: nothing gains (the D$ and I$ only refill main RAM), and an uncached poll would lose its order (break test `classic_too`).
- Narrower or hashed tags (12 bits: about -110 LUT in yosys): a false match only drains, so it stays correct. Not done until the LUT budget needs it.
- One tag per run of same-line stores, so memcpy's 8 stores use one slot: fewer comparators, but more logic and more mutants. Deferred.
**Consequences:**
- Yosys `synth_xilinx` on the bridge alone (`prototypes/read_bypass_re/lut_estimate.py`): +294 LUT and +346 FF at 20-bit tags. The board was at 15,045 LUT (85.5 %) with sys WNS +0.011 ns. Vivado's number comes from the lead's bitstream.
- Model memcpy (`tests/test_hp_bypass_rate.py`, calibrated to the board's 2.73 c/B with the drain): 2.78 to 2.25 c/B.
- A load can now reach DDR before an earlier store to another address. That breaks only a Dekker-style protocol (store A, load B, with another master doing the reverse) over DDR. A grep of `fpga/cycles` finds no poll loop on DDR: every poll is on an IO register. Every cross-master handoff uses an IO doorbell (fenced) or data-then-flag stores (store order is unchanged).


## 2026-11-01 — The cart RAM window grows to 4 MiB; video and the ROM window move up 2 MiB (HW 1.12.0)

**Status:** superseded by "2026-11-02 — Cart window 3 MiB, HW 1.13.0" (accepted by Matt, 1 Nov 2026; branch `feat/cart-window-4mb`; never ran on the board).

**Context:** the C port of pt2-clone (a ProTracker clone) cannot load a module in the 2 MiB cart window
`[0x100000, 0x300000)`: code statics, the tracker's buffers and a 1-2 MB module do not fit. The window
was last raised in v1.1 (1 → 2 MiB), and the ROM got its own window above the video region in 1.3.0.

**Decision:** cart `[0x100000, 0x500000)` (4 MiB), video region at `HW_VIDEO_BASE = 0x500000`
(ends ~0x6DC000), ROM RAM `[0x700000, 0x900000)`, `SHARED_PAGES` 112 → 144 (9 MiB). Every number is
in `machine/sdk/memmap.zig`; `build.zig` now imports it (`SHARED_PAGES`, `CART_RAM_BASE`,
`ROM_RAM_BASE`) instead of repeating literals, and memmap gains comptime checks that the cart window
stops at the video base, the video region clears the ROM window, and `SHARED_PAGES` ends exactly at
`ROM_RAM_TOP`. Carts that ask `hwVideoBase()` / `hwRamTop()` need no source change; every cart must be
rebuilt (the imported memory's declared max), as at 1.3.0.

**Alternatives considered:** carve the ROM window or VRAM smaller to stay at 7 MiB (the ROM's 2 MiB is
GEM's, VRAM is already the plane pool); stream the module from disk (a tracker edits the module in
RAM); a growable memory (the board places the memory once, at a fixed offset: it must never move).

**Consequences:** a breaking ABI change: all wasm carts, the C and Rust carts and the disks are rebuilt
on the branch. Board images are NOT (only `tutorial`, as a link proof): `bsys.c` refuses a cart whose
header `pages` is not the system's (TRAP_CART_ABI), so a new `system.rv32` refuses every image on the SD
card until `make board-shelf` and the `progs/<disk>/*.zmd` are redone. On the board the wasm memory (calloc'd from ZIGGY's data region) grows 7 → 9 MiB.
**CHISEL's RTL carries 23-bit linear addresses** (`zm_blit_core/px/pxq/row.v`, `zm_blit_chk.v`'s
`s_small`): the old map ended at 0x700000 < 2^23, the new ROM window ends at 0x900000, so on the board
a CHISEL op with an absolute source in the ROM window's top 1 MiB (0x800000+) is refused or wraps,
while the browser's machine does it. The bitstream must also be re-synthesised for the new
`ZM_HW_VIDEO_BASE` anyway (memmap.vh). The seal's `linear` window (`rtl/seal/zm_seal_map.vh`, 8 MiB)
is also smaller than the new memory; the board firmware runs the cart in M today, so it is not
enforced, but the seal plan must widen it to 16 MiB. Both are roadmap rows.
The board firmware still links (`make board-fw CART=tutorial`, both `ZM_AUDIO=1` and `snd`): the heap
the memories are calloc'd from is 14.0 MiB (needs 9 + 3 MiB for the players' memory) and 10.05 MiB
with `snd` (needs 9 MiB): about 1 MiB to spare in the sound-CPU layout, so the next growth needs that
link (board.mk `HRV_LDFLAGS_snd`, 12 MiB) widened first.

## 2026-11-02 — Cart window 3 MiB, HW 1.13.0

**Status:** accepted (Matt, 2 Nov 2026); branch `feat/cart-window-3mb`. Supersedes the 2026-11-01 4 MiB ADR.

**Context:** HW 1.12.0's 4 MiB cart window made the shared memory 9 MiB and put the ROM window at
`[0x700000, 0x900000)`. The board cannot reach the top of it: CHISEL carries 23-bit linear addresses
(`zm_blit_core/px/pxq/row.v`, `zm_blit_chk.v`'s `s_small`), and the seal's `linear` window
(`rtl/seal/zm_seal_map.vh`) is 8 MiB. 1.12.0 never ran on a board.

**Decision:** cart `[0x100000, 0x400000)` (3 MiB), video region at `HW_VIDEO_BASE = 0x400000` (ends
0x5DBFE0), ROM RAM `[0x600000, 0x800000)`, `SHARED_PAGES` 144 → 128: the memory ends at exactly
8 MiB = 2^23, so every address an op may touch fits CHISEL's 23 bits and the seal's window again. The
board needs a re-synthesis for the new video base (memmap.vh), no RTL change. `ZM_HW_VERSION` 1.13.0.
pt2-clone, the reason for 1.12.0, still loads modules: its sample slots are capped at 13312 bytes
(two 33-slot pools live during a load, `apps/ports/pt2/patches/pt2_config.c.sed`).

**Alternatives considered:** keep 4 MiB and widen CHISEL to 24 bits (every address path in
zm_blit_core/px/pxq/row/tfetch and the chk's `s_small`, plus the seal window to 16 MiB): rejected as
RTL and timing risk on a design at 89 % LUT with sys at +0.049 ns; accept that a blit sourcing ROM RAM
above 8 MiB is refused on the board (browser and board would differ silently); shrink the ROM window
instead (it is GEM's 2 MiB).

**Consequences:** another breaking ABI change: every wasm cart, the C and Rust carts, the four C-port
carts and the disks are rebuilt; a 1.13 `system.rv32` refuses 112- and 144-page board images
(TRAP_CART_ABI) until `make board-shelf` and `progs/<disk>/*.zmd` are redone. The board firmware's heap
margin grows by 1 MiB against the 1.12.0 figures. A cart has 1 MiB less than at 1.12.0 (still 1 MiB
more than before it). The next HW minor is 1.14.

## 2026-11-02 — C program ports live in apps/ports; upstream fetched at pinned SHAs; carts committed prebuilt

**Status:** accepted
**Context:** pt2-clone, GrafX2, klystrack and ChipNomad were ported as carts in the gitignored
`prototypes/` (each upstream cloned beside its port, the shared SDL2 layer in `prototypes/kestrel_sdl2`).
Shipping them on GitHub Pages needs their source in the repo, and GrafX2 is GPLv2: its cart must come
with its corresponding source. Vendoring the four upstreams would add tens of thousands of files of
other people's code, under three licences, to a repo that changes them never (every change is a
`patches/*.sed` applied to a mirror at build time).
**Decision:** `apps/ports/<port>/` holds only what is ours: the `kestrel_*` glue, the patches, the
Makefile, the run rig, each port's disk data, and the upstream licence text; `apps/ports/kestrel_sdl2`
is the shared layer. `apps/ports/fetch.sh` clones each upstream at its pinned SHA (klystrack and its
klystron submodule as a pair) and binaryen 132 (npm, sha256-checked) into `apps/ports/upstream/`
(gitignored), and refuses a checkout at another commit. The carts `docs/demo-<tag>.wasm` are committed
prebuilt, like the `c-*`/`rust-*` carts; `./build.sh` never needs the upstreams. A rebuild at the pins is
byte-identical (`__DATE__` in ChipNomad is pinned to its upstream commit's date for that).
`tools/mkdisks.sh` stays the one recipe for their disks (the ports' Makefiles lost their `disk`
targets), with every file named in order, as a glob's order follows the locale.
`apps/ports_headless.mjs` gates each cart (boot, a UI pin, one real interaction, a `--break`).
**Alternatives considered:** vendor the upstreams (or git submodules: the repo has none outside
`fpga/third_party`, and a submodule still needs a fetch); rebuild the carts in `./build.sh` (the gate
would need four upstream checkouts, binaryen and minutes of C++ on every run, for carts that change
only when someone works on a port).
**Consequences:** the pre-push "docs/ matches source" check cannot see a stale port cart (it cannot for
C/Rust carts either): change a port, run `make -C apps/ports/<port> install` and commit the cart. A new
upstream version is a new pin in `fetch.sh` plus patches that still apply (each must change its file or
the build stops). GrafX2's cart is GPLv2 (`apps/ports/grafx2/README.md` names its corresponding source);
the rest of the repo keeps its licence. Ripped test pictures (`prototypes/grafx2/port/testpics*`) stay
local. `docs/demo-<tag>.wasm` changes to `docs/` for these tags are "shared or unknown" to
`tools/gate_scope.py`, so they take the full gate, as the C carts do.

## 2026-11-02 — The C ports pace their audio by `hostMicros`; pt2's Paula in integers; the board pointer over the borders

**Status:** accepted (fix/pt2-board; extends 2026-10-17 "`hostMicros` may pace a cart's audio feed")
**Context:** On the board pt2-clone ran 28 fps idle and 10-13 playing, its song at half tempo and its ring
replaying stale bytes: each frame fed rate/60 samples, and the board passes dt = 16.6 ms whatever the frame
took. Its Paula mixed in double with BLEP, RC filters, 2x oversampling and dither: ~5,500 cycles a 48 kHz
sample on ZIGGY (no f64). The mouse stopped at the visible window (glass clamped to 640x200) while pt2's screen
and the browser's pointer reach the borders. Right Alt (pt2: play song) shared Alt's code.
**Decision:**
- `apps/ports/kestrel_sdl2/include/kestrel_audio.h`: each frame a port takes `kestrel_frame_us()` (hostMicros
  when the host has a clock, else dt; harnesses answer 0) and runs its SDL audio callback for that time
  (`kestrel_audio_pump`, a fractional sample carried, a silent lead fed first). The port's SDL clock advances by
  the same time, so pt2's pattern cursor and scopes stay with the sound. Each port caps a frame's time:
  pt2 67 ms (a stall), klystrack and ChipNomad 33 ms, because their synths cost more than real time on the
  board (cyd ~13,000, ayumi ~4,600 cycles a sample): uncapped they would slow the UI to 1-3 fps.
- pt2: `kestrel_paula.c` replaces `pt2_paula.c` (same API): integer, point-sampled, mono, 24 kHz, the A500
  low-pass and LED filter in fixed point, no BLEP or high-pass (~150 cycles a sample).
- REG_POINTER carries the whole raster (800x280, borders included); the cart CPU's firmware subtracts
  PTR_BORDER_X/Y, so `pointer()` gets the browser's coordinates (negative over the border). Glass 0.4.0 and
  the system image must land on the card together.
- Right Alt is 0xE018 (sealed-loader.js MOD_CODES.AltRight by evt.code, glass KEY_RIGHTALT); ST Replay takes it
  as Alt.
**Alternatives considered:** pass the board's real frame time as dt (every animating cart changes speed on the
board, hp_sim stops matching scene_hash: the reason of 2026-10-17); keep pt2's mixer and lower the rate (still
soft-float per voice per sample: ~25 % of the CPU at 32 kHz plus the I$ misses of its code); f32 BLEP (an FPU
op is ~10 cycles, the BLEP's 16-tap convolution per edge would still cost more than the whole integer mix).
**Consequences:** pt2's sound loses BLEP's alias suppression and the 5 Hz DC filter (inaudible through the 8-bit
mono stream). klystrack and ChipNomad keep their UI rate on the board but play slow until their synths fit
(ROADMAP). A glass without the system image (or the reverse) is off by 80/40 pixels.

## 2026-11-02 — Paula channels for carts: Amiga registers, chip RAM uploads, timed writes (HW 1.14.0)

**Status:** accepted (feat/cart-paula, step 1 of the ROADMAP row "Paula channels for carts")
**Context:** Matt, 2 Nov: "using them like Paula channels is the minimum". Only the players (BARD on the board,
the worklet in the browser) could drive the four Paula channels, so pt2-clone re-mixed Paula in software on
ZIGGY into an 8-bit mono 24 kHz stream. The questions: what a cart calls, where its samples live, when a write
takes effect, who owns the channels.
**Decision:**
1. *The API* is four `env` imports, the host's own like `hostAudioFeed`: `hostPaulaClaim(lead) -> u32`,
   `hostPaulaUpload(src, off, len)`, `hostPaulaWrite(entries, n)`, `hostPaulaRelease()`. The writes are Amiga
   Paula's registers ($DFF096 DMACON, $DFF0A0+16x LCH/LCL/LEN/PER/VOL) plus a KESTREL AUDxPAN at +$C, applied
   by `libs/zig/players/paula.zig`, the model the Hippel player's 68000 already drives: LC/LEN latched at the
   DMA start and at the wrap, so attack-then-loop, sample swaps and 9xx offsets are the hardware's, and an
   Amiga replay ports by forwarding its register writes (pt2 does, verbatim). Not a register page: the cart's
   memory is not the audio side's in either host, and a batch import is one call a frame on the board's ABI.
   Served by `docs/sealed-loader.js` + the worklet, and by `host/hstream.h` hooks where the players run in C
   (native host, BARD, ZIGGY without BARD): system table 1.6 (four host entries appended, carts for 1.5 run).
   HW 1.14.0, the version reserved for this and the coming true-colour plane (it joins the same number).
2. *Samples* live in chip RAM = song RAM (1 MiB), uploaded by the cart, as an Amiga program copies samples to
   chip RAM. Zero-copy is not possible in the browser (the worklet is another thread with its own memory). On
   the board it would be: PCM_BASE is any bus address and `AudioHP` adds the DATA offset masked to 4 MiB, so
   PCM_BASE = the cart's memory makes the 3 MiB cart window reachable without an RTL change; left for later
   (it would bypass the players' module, which is where the latch model and the timing live today, and only
   the board would have it). pt2 uploads what a voice is about to play at its DMA start and when a playing
   voice gets an LC/LEN outside it (~13 KB a note at most: cheap in the browser, a BARD memcpy on the board).
3. *Timing*: every write carries the cart's sample clock (44.1 kHz) and is played at that sample by
   `cart_paula_queue.zig` in demo-audio.wasm (so the browser, the native host and BARD run the same code). One
   offset ties the clocks, the first batch a `lead` ahead (the claim's argument: the cart's longest frame;
   pt2 125 ms, its stream's lead before); a late batch or a jumping clock re-anchors (counted). The Amiga's
   one-shot is the sample then its 2-byte loop (paula.zig), not the machine engine's "stop at the end".
4. *Ownership*: the claim stops every player, stream and sample and zeroes chip RAM; while a cart holds the
   channels the worklet and `host/audio.c` refuse every song, `sndhCall`, effect and stream; the machine's
   reset on the next cart (`audioReset`) releases them. A song request is refused, not queued.
5. *pt2*: `kestrel_paula_hw.c` forwards `paulaWriteWord/Ptr` (LC as an offset in `song->sampleData`, the null
   sample to chip RAM's zeroed top 128 KB), pans LRRL from `config.stereoSeparation` on the machine's pan law,
   and stamps each write with its own output clock (the replayer ticks inside the audio callback, so a tick's
   writes carry the tick's sample). When the claim answers 0 (a host without the channels, a pool over 896 KB)
   the integer software mixer plays as before; it also stays for PAT2SMP / MOD2WAV (never forwarded). The
   A500 / LED filters are dropped on the hardware path. Scopes and VU need no read-back (pt2's are its
   replayer's).
**Alternatives considered:** a PCM-level API (trigger(ptr, len, loop) + step/volume/pan, the machine's
`machinePaula*`): every Amiga replay would re-implement the AUDxLC/LEN latch, which is what makes it sound
right (paula.zig's header); per-call imports per register (a mailbox round trip each on the board); applying
writes at the frame edge (a 50 Hz replay on a 20-60 fps cart jitters by a frame); copying samples at every
trigger into per-channel slots (the trigger lands up to a lead after the copy: a re-triggered voice would be
overwritten while it still plays).
**Consequences:** pt2's sound is 44.1 kHz, 16-bit, stereo on the hardware channels, and ZIGGY no longer mixes
(its audio cost is the replayer). An edit to a sample a voice is looping is heard at its next trigger. A cart
holding the channels has no SNDH/MOD music or effects. The board needs the system image (table 1.6, the
Paula hooks), BARD's image and the rebuilt pt2 cart; no bitstream change. No POS read-back yet.

## 2026-11-02 — ChipNomad's AY resampled by a box filter; pt2 presents only the rectangles it drew

**Status:** accepted (perf/ports-synth; follows "The C ports pace their audio by `hostMicros`")
**Context:** On the board ChipNomad ran 11 fps and its song slow: ayumi cost ~4,900 cycles a 44.1 kHz sample
(8 substeps, a cubic interpolator and a 19-tap FIR in float a sample) and needs rate >= clock / 64. pt2 idled
at 28 fps: its present read the whole 320x255 ARGB frame buffer every frame (~1.7 Mc, a D$ miss every 8 pixels)
although idle pt2 redraws only its scopes, VU meters and pointer. klystrack's cyd cost ~15,000 cycles a sample.
**Decision:**
- `apps/ports/chipnomad/kestrel_ayumi.cpp` replaces upstream's `ayumi.cpp` (same API, struct and chip model:
  counters, LFSR, envelope shapes, DAC tables, pans, the soft-oscillator timer once a tick). The chip is stepped
  event to event in integers; a sample is the exact mean of its ticks (a box filter); DC removal is a one-pole
  high-pass. ChipNomad runs 22.05 kHz: ~1,000 cycles a sample with its mixer (~22 % of ZIGGY for real time).
- pt2: every `video.frameBuffer` write site calls `kestrel_fb_dirty(x, y, w, h)` (sed patches); `present()`
  converts only the marked rows and columns. `-DKESTREL_PRESENT_CHECK` builds compare with a full conversion.
- klystrack keeps cyd, made cheaper only where the stream stays byte-identical (32-bit wavetable accumulators
  via klystron's own `LOWRESWAVETABLE`, reverb taps by delay, idle FX buses and unheard channels skipped), and
  the shared software renderer gets an indexed fast path. cyd still costs ~12,500 cycles a sample: the feed
  stays capped at 33 ms.
**Alternatives considered:** keep ayumi with a shorter FIR (still 8 float substeps a sample and the rate floor);
an integer port of ayumi's interpolator + FIR (several times the box filter's work, for alias suppression the
8-bit mono stream does not keep); pt2's present comparing with the previous frame, or checksumming rows (both
still read every pixel); klystrack at 11 kHz (halves cyd, dulls every song).
**Consequences:** ChipNomad's high tones alias more than with the FIR and its top octave is a little softer (rms
-9 % on the gate's note); pitch and chip behaviour are upstream's tick for tick. A new pt2 write site that does
not mark its rectangle leaves stale pixels: the check build finds it. klystrack plays slow on the board until cyd
is cut further (fewer channels or taps, a lower rate) or moves to BARD (ROADMAP).

## 2026-11-02 — klystrack repaints only while something moves; cyd sleeps when silent; the chorus LUT in integers

**Status:** accepted (perf/klystrack-board; follows "ChipNomad's AY resampled by a box filter; pt2 presents only the rectangles it drew")
**Context:** On the board klystrack ran 5-6 fps doing nothing (OSD cart_c 19.9 Mc) and took ~11 s to show its UI.
`apps/frame_cost.mjs` (a names build: `make -C apps/ports/klystrack names`) showed the idle frames alternating 46.7 /
3.2 Mc est: upstream repaints the whole UI 30 times a second whatever happens (`gfx_domain_is_next_frame` in the main
loop and in each dialog's loop), and cyd mixes every channel every sample with nothing playing. boot() was 1002 Mc,
630 of them a double `sin()` for each of the chorus LUT's 88,200 entries (`cydchr_set`, at every load of a song with
a chorus). pt2's way (each draw site marks its rectangle) does not apply: klystrack repaints everything each time.
**Decision:**
- The 30 Hz repaint (main loop, msgbox, help, hub dialog) runs only while something moves: a song plays, one of the
  last 15 repaints changed the picture (the presenter hashes each picture), an SDL timer fired (the info line clears
  itself), or a key/click/drag was queued (it may open a dialog that paints on the tick). Events and song-position
  changes repaint at once, as upstream. A frame with no present moves the SDL cursor over the last picture
  (`kestrel_plane_cursor`): upstream never repaints for a plain pointer move.
- cyd's callback is skipped (zeros fed) when no song is set, every channel's gate is off and envelope 0, and the
  output has been exactly 0 for 2.2 s, longer than the reverb's 2 s delay line (no feedback) and the 50 ms chorus.
- The chorus LUT comes from a generated Q30 sine table, linearly interpolated, phase stepped exactly: within +-1/256
  sample of upstream (7 of 151,404 stream bytes differ by 1 LSB over a 7 s play).
- `kestrel_heap.c` gets an opt-in first-fit rover (`-DKESTREL_HEAP_ROVER`, klystrack only): same blocks chosen; the
  other three ports compile to the same object without it.
**Alternatives considered:** a dirty-rectangle present (the union is the whole screen on every repaint); repaint at a
lower fixed rate (still ~15 Mc a repaint on the board, every frame once a frame takes over 33 ms); a shadow copy of
the last picture to compare (300 KB the heap does not spare; the hash is folded into the conversion the present
already does); `CYD_PAUSED` when stopped (klystrack plays note previews and keyjazz through the same engine).
**Consequences:** frame_cost idle 24.9 -> 0.72 Mc (cart 6.7 -> 0.02), boot() 1002 -> 204 Mc; playing unchanged
(34.2: one repaint + cyd at 2.7x real time; next an 8-bit renderer target and cyd on BARD). Something that changes
the picture with no event, timer or song after 15 identical repaints would not be drawn until the next event; none
is known in klystrack. `apps/ports_headless.mjs klystrack` moves the pointer over the idle UI (`--break pointer`) and
presses F5 only after cyd has gone quiet, so both new paths are gated.
## 2026-11-02 — True-colour plane: RGB565 through FRESCO's painter (HW 1.15.0)

**Status:** accepted (feat/truecolor-plane; the study and Matt's decisions of 1 Nov in
`fpga/review/TRUECOLOR_PLANE.md`)
**Context:** Matt, 31 Oct / 1 Nov: one plane in true colour, the Falcon's 16-bit 565 first, for the port of
"Are You Sitting Comfortably?" (feedback blur, additive light, 565 pictures) and for pictures that band at 256
colours. The study costed four designs; Matt chose A0 with payer 1, no colour key, bit 0 ignored, 8888 later,
scanout from the cart's buffer (option B) and CHISEL 16-bit lanes declined, mpp_truecolor's 4-plane mode first.
The study said HW 1.12.0 and then 1.14.0 ("joins the Paula version"); main had taken 1.12.0, 1.13.0 (cart window)
and 1.14.0 (cart Paula) by the time it was built, so it is **1.15.0** (`ZM_HW_VERSION 0x0001_0F00`).
**Decision:**
1. *The ABI*: `FB_MODE_TRUECOLOR` (5, 320x200 in the window, logical HBL lines) and `FB_MODE_TRUECOLOR_FULL`
   (6, 400x280 over the whole raster from (0, 0), borders open, physical lines). A pixel is a little-endian u16
   R5 G6 B5, expanded by bit replication (`machine/video_tc.zig expand`, Hatari's Videl formula) with alpha 255.
   `FB_STRIDE`, `HSCROLL` (re-read per line, as SCROLL mode) and LBASE are bytes; **bit 0 of a line's address is
   ignored** on both machines. No new register; mode values above 6 keep the stride-400 back-compat rule.
2. *A compositor citizen*: the browser renders it in the same line loop as every mode (`renderPlaneTruecolor`:
   handler, copper record, LBASE, HSCROLL), and FRESCO paints it through the painter: the byte index doubles,
   the half-word at `align + 2c` is registered beside the palette read and expanded (wiring) in place of the
   palette's answer (`zm_video_paint.v`); `zm_video_plane.v` gives the two modes their geometry and fetch (640 /
   800 bytes) and HSCROLL; `zm_video_copper.v` covers mode 6's border lines. The half-word select ignores bit 0
   by construction, so the study's AND on the address was not needed. Fetch, mixer, row I/O, pass, dirty lines,
   the PFB oracle and the browser's canvases are untouched.
3. *Payer 1* (the read-back mux cut to the 6 words the firmware reads, -138 LUT) was already on main (77fad6fd,
   board_combo8). So this branch's bill is the mode alone: **OOC synth of `zm_video_comp` at 8 ns (Vivado
   2026.1, maxThreads 2): 2,422 -> 2,450 LUT (+28), 1,944 -> 1,961 FF (+17), 15 BRAM tiles, 13 DSP, WNS +1.029 ->
   +0.932 ns** (u_paint 87 -> 97, u_plane 237 -> 248, u_cop 636 -> 637). The study measured +28 / +17 on its
   older base: the same.
4. *The firmware* (`cycles/vseq.c`, `vdrow.h`, `host/vdirty_copper.h`) gives mode 6 physical lines and mode 5
   the window; the dirty-line planner compares 640 / 800-byte lines at `(base + row * stride + HSCROLL) & ~1`.
   No CSR, no read-back, no system-table change: the glass reads nothing new.
5. *ZigOS*: `fb.setTruecolorPlane(.window | .full)` returns a `zg.tc.Fb` (`row`, `put`, `put2` two pixels a
   32-bit store, `fill`, `copyRect`), `zg.tc.rgb565`, `zg.truecolorBuffer` and `fb.showTruecolor` to
   double-buffer. Nothing more until a cart asks.
6. *mpp_truecolor*: mode 3 becomes one RGB565 plane (plane 1, its own two buffers) in place of four planes of
   255 per-line colours. The converter writes the nearest 565 word under the machine's expansion (every pixel
   within 4 of the source per channel); the caption is printed into the 8-bit spare and widened to white words.
   It is no longer lossless (5,390 colours on the spheres where 4 planes showed all 39,015), and the look is the
   same at a glance. frame_cost: mode 3 **2.49 -> 0.70 Mc/frame** (FRESCO 4 passes -> 1); modes 1 / 2 0.81 / 0.97
   -> 0.81 / 0.70 (the next switch is built with a row copy, no per-pixel plane split).
**Alternatives considered:** option B, the board scanning the cart's buffer out (saves ~0.46 Mc for a whole-screen
565 plane, but the picture is no longer the PFB, tears unless the cart flips at VBL, and reverses the 2026-10-24
frame-serial decision); 8888 (twice the bandwidth, a 9-bit painter index; later, when a cart asks); a colour key
(+6-10 LUT, loses one 565 value; the Falcon parts put the 8-bit plane over the 565 one); CHISEL 16-bit lanes
(150-250 LUT in a block already over its target).
**Consequences:** +28 LUT in the comp domain, which board_combo9 closed by +0.105 ns: the lead's next bitstream
is the real timing check (OOC slack has not predicted the placed design's before). The worst OOC path moved to
`u_plane`'s mode decode -> the address stage (mode_i -> addr_q, still +0.93 ns). A true-colour plane cannot
show holes: sprites and text over it come from an 8-bit plane. mpp_truecolor needs a 1.15.0 machine and board.
Tests: `machine/video_tc_test.zig` (all 65,536 values), `apps/truecolor_check.mjs` (+ `--break`, 6 model
mutants), synthetic `truecolor` in `fpga/tests/test_rtl_video.py` with 8 RTL break tests (`tc_*`),
`test_vdirty.py::test_a_truecolor_plane_skips_only_unchanged_lines`, and mpp_truecolor's harness (one
`FB_MODE_TRUECOLOR` plane showing the converter's 565 picture).

## 2026-11-02 — The C ports are GEM programs on data disks; quitting is request 4 from the shared SDL2 layer

**Status:** accepted
**Context:** Matt (2 Nov): "pt2 clone, grafx2, klystrack, chipnomad, can you make them like ST replay as
FAT files?" The four ports booted as bootable disks: no desktop, no way to see or leave the disk, and on the
board no OS to return to (SysInfo's reason for becoming a data disk). Each program already read its files off
the mounted floppy (`kestrel_wasi.c`), and a program GEM launches keeps the same disk mounted.
**Decision:** each port's disk is a DATA disk (`tools/mkdisks.sh` `portdisk`: `--no-boot`, plus the shared
"SDL" boot sector `docs/boot-sdl.wasm`, as SysInfo's "No virus": the sector runs, then GEM boots over it, its FLOPPY window lists
`BOOT.WSM` and the program's files (8.3 names; GEM's 12-file cap), a double-click runs it. Quitting lives in the
shared layer, `apps/ports/kestrel_sdl2/src/kestrel_quit.c`: `kestrel_quit()` makes the cart's `pollCartRequest`
export answer 4 (SysInfo's and ST Replay's protocol); `SDL_Quit()` and `exit()` call it, and each port calls
it where its main loop ends (pt2: `editor.programRunning`, emitted by `split_main.py`; GrafX2 and klystrack:
their main returning; ChipNomad: `mainLoopTriggerQuit`). pt2's "REALLY QUIT ?" (`askBox`, a modal loop that
cannot return on a cart without Asyncify) becomes a two-press confirm on the status line.
`apps/ports_headless.mjs` launches every port from GEM (`apps/ports_gem.mjs`, as `sealed-loader.js`), checks
the program GEM runs is the committed cart, and quits it back to the desktop (`--break quit`).
**Alternatives considered:** a per-port quit (four copies of the same request, and SDL_Quit/exit left
dead); pt2 under Asyncify so `askBox` works (it would cover every pt2 dialog, but costs every input path
pt2's frame reaches on the board: a separate decision); readable program names (`PT2.WSM`): `disk_check.mjs`,
the glass and its tests look for `BOOT.WSM` on a v2 data disk, so the ports follow ST Replay and SysInfo.
**Consequences:** on the board the four programs are staged under `progs/demo-<tag>/BOOT.WSM.zmd`
(`fpga/tools/glass_shelf.py`), and a board firmware built before `pollCartRequest` existed in these carts
quits nothing: rebuild the four board firmwares with the carts. pt2's other `askBox` dialogs (CLEAR, the
sampler's) still hang the cart, as before. The ports harness now also depends on GEM (`docs/demo-gem.wasm`,
`docs/rom.wasm`).

## 2026-11-03 — True-colour fade: brightness and colour offset in FRESCO's 565 expansion (HW 1.16.0)

**Status:** accepted (feat/tc-fade; Matt, 3 Nov: "I like the hw fade... go for it if it fits!")
**Context:** On the Falcon a true-colour fade rewrote every pixel, so demos kept to bitplanes. The 1.15.0
true-colour plane expands each 565 pixel to 888 in FRESCO's painter: that is the place to fade it.
**Decision:**
1. *Registers*, the register block's only free bytes: `TC_FADE` u8 x4 at 0x0C (bits 0..4 coefficient, bit 5
   toward white, 6..7 ignored) and `TC_OFS_R/G/B` i8 x4 at 0x14 / 0x18 / 0x1C, channel-major so each is one
   aligned u32 word (four planes' bytes) and the RTL stores four words. Reset 0 = the 1.15.0 picture.
   `ZM_HW_VERSION 0x0001_1000`; no system-table change (no import or export: carts store to registers).
2. *The rule* (docs/HW_API.md "True-colour fade"), per expanded channel x: `w = c + (c >> 4)` (31 is weight
   32, full), `y = (x * (32 - w) + 16) >> 5` toward black, the same on the complement toward white
   (`255 - (((255 - x) * m + 16) >> 5)`: ~x on 8 bits in RTL), then `clamp(y + ofs, 0, 255)`. GBA BLDY's
   17 levels were the alternative; 32 steps keep a slow fade smooth and cost the same multiplier.
3. *Per line*: read after the line's handler and copper record (the HSCROLL rule); a copper `REG` may name
   this plane's four bytes (the value's low byte); another plane's stops the list. The register keeps the
   value, so the board's firmware copies the four words back with HSCROLL (`vseq_copper_end`).
4. *RTL*: `zm_video_tcfade.v` (three 8x6 multiplies in DSP48 + the clamp) as a fourth painter stage for every
   mode; the plane's bytes latched at the paint's start. The register block gets ONE write port for the
   copper and the snoop (the palette's precedent: the drain rule keeps CPU stores out of a pass): two ports
   on six words cost +160 LUT.
5. *The planner* (`cycles/vdrow.h`) carries a true-colour plane's fade in its geometry: a fade moves every
   pixel and no fetched byte.
6. *ZigOS*: `fb.setTruecolorFade(coef, .black | .white)`, `fb.setTruecolorOffset(r, g, b)`,
   `zg.tc.fadeCtl`, `zg.tc.copperReg`. TC TEST key 8 is the example.
**Bill (OOC synth of `zm_video_comp`, 8 ns, Vivado 2026.1, maxThreads 2):** 2,450 -> **2,589 LUT (+139)**,
1,961 -> 2,160 FF (+199), 13 -> **16 DSP (+3)**, 15 BRAM, WNS +0.932 -> **+0.908 ns** (the worst path is still
u_plane's mode -> address, not the fade). Where: u_fade 67 LUT / 3 DSP, the latch and stage +0, u_regs
386 -> 361 (four more words, one write port), u_cop 637 -> 722 (the REG decode, lanes). Variants measured:
two write ports 2,776; without the read-back of the four words 2,736; registers only (no copper REG)
2,575. Board estimate: 15,754 + 139 = 15,893 / 17,600 LUT (90.3 %), DSP 73 / 80.
**Alternatives considered:** u16 registers per plane (no 16 free contiguous bytes); the fade in the TC
plane's unused palette entry (free storage and per-line copper PAL already, but palettes left over from
8-bit modes would fade existing carts); a global fade (copper writes would cross planes, which line-major
groups on the board order differently from the browser); registers only, no copper REG (measured
2,575 with the two-port register block; not re-measured with one port).
**Consequences:** every painter pass is one clock longer (~0.1 % of a line). The board's combo build is
the real timing check. Tests: `machine/video_tc_fade_test.zig` (every channel x coefficient x direction,
offsets, the copper REG), `apps/tc_test_check.mjs` key 8 (+3 mutants), vsynth `truecolor` with copper and
handler fades (coverage `tc_fade`, `tc_fade_per_line`), 11 `tcf_*` RTL mutants, `test_vdirty.py`
FADE view + `VD_BREAK=FADE`.

## 2026-11-04 — The KESTREL SDK: an outside cart depends on the repo as a Zig package

**Status:** accepted
**Context:** Matt (31 Oct): a friend with a Z7-Lite wants to write demos without the SoC, Verilator or
Vivado. A cart is registered in three places today (cart.zig's index, build.zig's cart matrix, catalog.zig),
all inside the repo, and the board pipeline (`fpga/` split-cart) reads `docs/demo-<tag>.wasm`.
**Decision:** a cart outside the repo has its own `build.zig` + `build.zig.zon` with a PATH dependency on the
repo, and calls `@import("kestrel").addCart(b, dep, .{ .name, .root_source_file })` (`sdk/build_cart.zig`,
re-exported by `build.zig`). addCart builds that one cart from `apps/zig/demo_main.zig` with the matrix's
modules and memory layout; it does not rebuild machine-video.wasm or rom.wasm (the card's system.rv32 was
built from the shipped bytes). The template's Makefile copies the cart into the SDK's `docs/` (marked in
`docs/.sdk/`, refusing a repo cart's name) for the browser and for `make -C fpga split-cart`, which takes
the SDK's toolchain through command-line variables (RV_CC, RV_ARCH, WABT, `CART_RTLIB`, CARTS_DIR) and
`UV_NO_PROJECT=1` (the split-cart scripts are stdlib-only: no LiteX venv). A riscv gcc without an
rv32imf/ilp32f multilib (Arch, xPack) links Zig's compiler_rt, trimmed to libgcc's helpers
(`sdk/zrt_cart.sh`), in place of libgcc; the cart links no libc in any case.
**Alternatives considered:** a "user cart" slot in build.zig fed by `-Dcart=<path>` (one file touched, but
the coder's directory has no build.zig, so ZLS cannot resolve `@import("zigos")`, and builds run inside the
SDK tree); vendoring a prebuilt picolibc + libgcc for rv32imf (a binary blob per release, GPL runtime
exception notices, and still a second gcc's objects); requiring Ubuntu's toolchain (excludes Arch and macOS).
**Consequences:** sdk/build_cart.zig repeats the handful of module definitions a cart needs; if build.zig
gives demo_main another import, `gate sdk` (apps/sdk_check.mjs, the template built from a temp dir outside
the repo) fails until build_cart.zig follows. A compiler_rt-linked cart has not run on the board yet: its
soft-double helpers are IEEE like libgcc's, and wasm2c range-checks every float-to-int conversion before
the helper, but one board run should confirm it.

## 2026-11-06 — The SD card's layout: boot files at the root, KESTREL/, CARTS/, HD/ (C: is /HD)

**Status:** accepted (Matt, 6 Nov 2026)
**Context:** everything glass reads lived in `/mnt/sd/zigmachine/` (system.rv32, kos/, progs/, glass.cfg, shelf.txt, the category folders), and the card's root had gathered ~25 `rollback_*` folders and loose files beside the boot files. KOS's C: (docs/KOS_FAT.md F5) showed the WHOLE partition in GEM: the boot files, the system, every rollback copy; `progs/by-hash` alone could fill the desktop's 32-file limit.
**Decision:** four places. `/` holds the boot files only (the BootROM and U-Boot need them there; their `.prev` / `.<hash>` copies stay beside them for recovery from U-Boot). `/KESTREL/` holds the system (system.rv32, kos/desktop.rv32, glass.cfg, progs/, an optional `glass` override, `rollback/`). `/CARTS/` is the OSD's shelf. `/HD/` is C: (the future GEMDOS hard disk). The names are defined once a side (`fpga/glass/src/layout.zig`, `fpga/tools/sd_layout.py`), held equal by `fpga/tests/test_sd_layout.py`. glass detects the layout from the directory it is given (`KESTREL/` there, else `zigmachine/`, else the directory itself), so an old card and the card's rollback keep working with the new glass, and the old rootfs keeps working on a card migrated back. C: is rooted in the desktop shell (`gem_fat.zig` walks from `/HD`'s cluster); glass still serves raw sectors of the whole partition, so no host changed. No `/HD`: no C: icon (as a host with no C:), rather than an empty drive. S99glass runs `KESTREL/glass` instead of the rootfs's when the two differ and the SD one runs (the "a newer SD copy overrides for development" rule), and says so on the console. An old card moves with `fpga/tools/sd_migrate_layout.sh` on the board: mkdir and mv only, idempotent, `--back` to undo; a loose root `glass` goes to `rollback/`, never to `KESTREL/glass`, so a stale hand-copied binary cannot become the override.
**Alternatives considered:** glass filtering C:'s sectors to `/HD` (glass would need to parse FAT and remap clusters: a second FAT implementation for nothing, the shell already runs KOS's reader); a second FAT partition for HD (repartitioning every card, and Linux mounts only p1); keeping `zigmachine/` and only adding `HD/` (the root stays cluttered, and the system and the shelf stay mixed, which "the OS in the boot image" wants apart).
**Consequences:** every staging path moved (`KESTREL/...`, `CARTS/...`: MANIFEST rows, `sdk/release.sh`'s card check, `board_carts.sh`'s md5 list), and anything outside the repo that names `zigmachine/...` on the card is stale (the board-cart skill, prototypes' install scripts, card_full_re/planA/RECOVERY.md's plan-B line). The old rootfs on a migrated card runs glass on an empty shelf: restore both or neither (the old rootfs + `--back`). `docs/kos-c.img` is card-shaped, so the page's C:\ lists `HD/`'s four entries. An override glass older than this layout reads `/mnt/sd` as a flat shelf: S99glass checks that it runs, not what it knows.

## 2026-11-06 — KOS GEMDOS runs in the cart, over the sector imports; writes will go through glass at the file level

**Status:** accepted (phase 1, read-only, built on `feat/gemdos`; phase 2, writes, built on `feat/gemdos-write`, docs/KOS_GEMDOS_WRITES.md)
**Context:** Matt, 6 Nov: "start the gemdos like FS to support HD so for example grafx2 can read files from HD/ substructure". Carts could read their own `.zmd` (flat: `zg.disk`, the C ports' WASI layer at `/`) and the desktop shell walked C: once into GEM's model, but no program could open a file in a folder of C: (the SD card's `/HD`, KOS_FAT §4c). The C ports reach files through wasi-libc (fopen, opendir, stat, chdir), which the shared SDL2 layer answered over the floppy only.
**Decision:** a GEMDOS library (`rom/kos/gemdos*.zig`: Fopen / Fread / Fseek / Fclose, Fsfirst / Fsnext / Fsetdta, Dgetdrv / Dsetdrv / Dgetpath / Dsetpath, Fattrib; TOS's names, handles, DTA and error codes) runs IN THE CART over KOS's FAT reader and the two sector imports every host already serves: `diskReadBlock` (A:, a FAT image) and `kosDriveRead` (C:, unit 2, a system-table entry since 1.8). C:\ is rooted at `/HD` as the desktop shell roots it. No host code and no system table change: the same Zig answers on the page, the native host and the board, and a cart using it needs table >= 1.8 (combo16 is 1.9). For the C ports the library is one wasm object (`gemdos_c.zig`, C linkage) under an opt-in WASI layer (`-DKESTREL_CDRIVE`, `kestrel_sdl2/src/opt/kestrel_wasi_c*.c`) that adds C: as wasi-libc's second preopen, `/C`: `fopen("/C/PICTURES/X.PI1")` is `Fopen("C:\PICTURES\X.PI1", 0)` with no change to a port's sources, and the other ports' carts stay byte-identical. Requests are what cost on the board (~0.5 ms a round trip: glass's 2 kHz poll), so the library caches 4 KB runs and reads 4 KB or more straight into the caller's buffer, contiguous clusters merged into requests of up to 32 KB. Writes (phase 2) will never be sectors from a cart: glass owns them at the file level (a second request block, paths under `/HD`, a C: generation word that drops the carts' caches).
**Alternatives considered:** GEMDOS in glass at the file level for reads too (a round trip on every call, Fsnext included, and a file API written three times: the firmware's, the native host's, the page's); in rom.wasm behind new ROM exports (every host and ~100 harnesses instantiate rom.wasm with a fixed env: why KOS_FAT F2 kept the reader in the shell cart); `zg.gemdos` in `libs/zig` (the layering is machine < libs < ROM < apps and the reader is KOS's, so the module `kos_gemdos` sits beside `kos_fat`; moving fat.zig into libs is a separate refactor if wanted); a C reimplementation for the C ports (two FAT readers to keep equal).
**Consequences:** a cart using GEMDOS carries ~10 KB of code and 16 KB of cache a drive; long file names show as their 8.3 aliases (name files on `/HD` in 8.3); A: does not mount over a `.zmd` (those keep their own reader). wasi-libc never folds `..` in its working folder, so the C layer offers `kestrel_getcwd` (a port maps `getcwd` to it) to fold it. Phase 2 bumps the system table (new imports) and needs glass to remount the card read-write for each write, with the desktop and every cart dropping their sector caches when glass bumps C:'s generation.
**Phase 2 (6 Nov, built as designed, with these choices):** one import, `env.kosFileOp(req)` (table 1.10, appended: 1.9 carts still run), a 12-word request in the cart's memory (rom/kos/kfs_abi.zig). Where C: is an image (the page, the native host) the host half is KFS, a FAT12/16/32 writer in Zig (rom/kos/kfs*.zig) shipped as `docs/kos-cfs.wasm` and wasm2c'd into the native host, so the image writer exists once; on the board glass uses Linux's own vfat, remounted read-write per request, and never writes sectors itself (the kernel caches the FAT it mounted). The path gate (rom/kos/kfs_path.zig: plain 8.3 names under C:\, nothing else) is shared by both and runs on the host's own copy of the request. A save is written to `~KOS<slot>.TMP` and renamed at the last write; Fwrite buffers 32 KB so a picture is one request. The generation reaches the cart in each write's answer (wasm cannot read a window word), and the library drops its caches after each of its own requests instead of asking the generation on every call (a round trip each); the desktop re-reads C: at every start. Alternatives: glass writing raw sectors with KFS under the read-only mount (one writer for all hosts, but the kernel's cached FAT goes stale and any later rw mount would clobber it); a FAT writer in JS and in C (three writers); no temp name (a crash mid-save loses the old file).

## 2026-11-06 — MP3: pvmp3 in demo-audio, a fed byte stream, and a 15-bit output on the Paula channels

**Status:** accepted
**Context:** Matt wants a jukebox for MP3 files on C:. BARD (rv32 Zmmul, no divider, no FPU) has to decode
them (fpga/review/MP3_BARD_STUDY.md: Helix and pvmp3 both ~35 % of BARD at 44.1 kHz stereo). Two files on the
SD card hold minutes of music, far past song RAM, and CHORUS's PCM channels are 8-bit.
**Decision:** pvmp3 (Apache-2.0, libs/c/pvmp3, vendored unmodified at an AOSP commit) is compiled INTO
demo-audio.wasm like Musashi, so the page's AudioWorklet, the native host and BARD (wasm2c) run the same integer
code and agree bit for bit. The cart streams: system table 1.11 appends `hostMp3Ctl` / `hostMp3Feed` /
`hostMp3Status`; the cart reads the file (KOS GEMDOS) and feeds bytes into the player's 64 KiB ring, keeping
fed - used under it; the status (state, rate, errors, underruns, bytes used, frames, BARD's load) comes back
through the worklet's audioState on the page and BARD's S2C bank on the board. The output is two Paula channels
a side, a high byte at VOL 256 and a low byte at VOL 2, which carries exactly `x >> 1` (15 bits, -6 dB):
fpga/tests/hilo_probe.py proved 6000/6000 samples on the RTL and the engine, and 0/6000 for a full `x`. Matt:
"go with b, will be good enough, keep c in the roadmap". 32 and 48 kHz files are converted on BARD (linear,
exact rate, not bit-exact).
**Alternatives considered:** Helix (RPSL: source-publication terms for a downloadable image); pvmp3 native on
BARD with a separate wasm for the page (two builds to keep equal); the whole file in song RAM (1 MiB: a few
minutes at most); a 16-bit CHORUS PCM mode (option c: RTL, a HW bump; a ROADMAP row for the next bitstream);
kt.zig's 511/256 high-byte volume (louder, but not exact).
**Consequences:** no Paula sound effect while an MP3 plays; the output is 6 dB under full scale; the cart owns the
flow control and must trust the status only a few frames after a start. Carts now import one KOS module
(`kos_gemdos`, whose `.fat` is the FAT reader): a cart that had both failed to compile.

## 2026-11-07 — SID: cRSID native on BARD, the same C in machine-audio.wasm, PSID only

**Status:** accepted
**Context:** Matt: "can we build a soft version of the SID chip on BARD?". fpga/review/SID_BARD_STUDY.md measured
cRSID 1.58 (Hermit, "do what you want, mention me"): its default engine is ~2x BARD; the light engine at 22.05 kHz,
with three bit-exact divide/state patches and its filter table regenerated, is 48-60 % on PSID tunes built natively
with `-march=rv32im -mno-div`. Through wasm2c (the MP3 player's path) it would cost ~1.3x that. RSID tunes (real C64
programs) are ~2x BARD in every configuration. cRSID's state (a C64: 276 KB) does not fit demo-audio's 1 MiB.
**Decision:** the lead chose: cRSID vendored unmodified (libs/c/crsid/upstream), patched at build time by
`patch.sh` (sed patches + the regenerated table, beside it). The players call it through two `machine*` imports
(`machineSidLoad`, `machineSidRender`): on the page machine-audio.wasm answers with the C compiled to wasm; on BARD,
ZIGGY and the native host `fpga/host/audio_sid.c` answers with the same C built natively (`host/crsid.c`, the only
object BARD builds with `-mno-div`). `apps/sid_check.mjs` holds the two to the same samples. The player
(libs/zig/players/sid.zig) puts the 22.05 kHz mono on Paula as MP3 does (hi/lo bytes, x >> 1) after a linear 2x
upsample. RSID is refused with a status ("RSID not supported"). A load is a fresh C64 (cRSID's globals cleared, its
dither LFSR reset), so a tune's samples never depend on what played before. Glass names it PLAYER_SID (11).
**Alternatives considered:** cRSID in demo-audio.wasm (no room; and wasm2c on BARD, 62-78 %); the HQ engine (~2x
BARD); reSID/reSIDfp (GPL, far heavier); unpatched cRSID at 22.05 kHz (55-82 %: over the bar on a filtered 1x tune).
**Consequences:** machine-audio.wasm grows by ~400 KB (cRSID's zero-filled C64 is a data segment: the memory is
imported); snd.bin is 1.99 MB of its 2 MiB limit; the SID mutes Paula sound effects as MP3 does; RSID digi tunes do
not play.

## 2026-11-07 — The BARD queue: a ring in the cart's memory, the Paula queue's timing, SID live first

**Status:** accepted
**Context:** ROADMAP (Matt, 31 Oct, "could be funny"; 7 Nov, "run it now"): commands ZIGGY → BARD and events back
with neither CPU waiting on the mailbox. Every cart → sound path so far is a per-frame call the board forwards as a
mailbox command, and anything with bytes (a Paula write batch, a feed) makes ZIGGY wait for BARD's ACK. The first
user is a GoatTracker 2 port whose replay writes SID registers each tick: BARD's cRSID must play those writes live.
**Decision:**
- **The ring is in the cart's own memory** (`libs/zig/bard.zig`, `zg.bard`): a 64-byte header, 256 commands and 16
  events of 16 bytes. Each header word has one writer (cart or host); single producer, single consumer. A command
  is the Paula queue's entry `{t, addr, value, seq}`; `seq` = its ring index, written last (and every slot's
  seq set to ~0 at the open, so a zeroed slot 0 never passes for command 0), so a reader takes an
  entry only once it is whole. A full ring refuses the command (counted in the header); the cart never blocks.
- **One system-table entry** (1.12, appended): `hostBardAttach(block, lead) u32` hands the ring over once (0:
  no queue here). After that there is no call: the host takes the commands after each cart frame and writes back
  what it took, the sound side's position and the events.
- **Time is the Paula queue's** (HW_API 5): `t` on the cart's 44.1 kHz clock; the first batch anchors a `lead`
  ahead, a late or runaway batch re-anchors (an event says so). `cart_paula_queue.zig` became `QueueOf(cap,
  stage)`, and SID live (`libs/zig/players/sid_live.zig`) is a second instance, so both devices share one
  mechanism. `zg.bard.due(t)` paces a replay on the sound side's clock, whatever the cart's frame rate.
- **SID live = file mode with no file**: `zm_sid_raw(model)` loads a static 2-byte PSID (init = play = RTS, PAL,
  the model in its flags) through the same `zm_sid_load`, so every field a tune's load sets is set the same way;
  a write is the 6502's store into cRSID's `IObankWR[$D400 + reg]`. Upstream stays unmodified. The .sid player
  renders up to the next due write (at most 128 engine samples ahead), and a write lands at the first 22.05 kHz
  engine sample at or after its stamp.
- **Three hosts, one semantics**: the page (`sealed-loader.js` bardDrain / bardPublish, the worklet's bardQueue /
  bardState), the native host and ZIGGY with the players (`host/audio_bardq.c` + `host/bardq_pump.c`) and the
  board, where **BARD reads the ring in DDR itself** (`cycles/sound/sbardq.c`): ZIGGY writes the head in C2S word
  5 after the frame, BARD drops its D-cache and takes the whole entries when the head moved; its answer is S2C
  words 23-31 (commands taken, position, event count, three event slots), copied into the cart's block by ZIGGY
  (`cycles/bardq_s2c.h`). The open is one mailbox command (ACK once); nothing else waits.
- **Events back**: a mark when the sound side reaches a stamp the cart asked for (a beat, a row), each reset, each
  re-anchor and each drop, with the stamp. Arguments are 24 bits on every host (the board packs kind and arg in a
  word). More than three events in one ZIGGY frame on the board, or a full cart event ring, are counted lost.
**Alternatives considered:** the effects queue / a `hostPaulaWrite`-style batch per frame (ZIGGY waits for the
ACK of a batch with bytes on the board; the ACK is microseconds, but it is a wait, and a per-frame call); a
separate DDR ring that ZIGGY copies into (a copy for nothing: the cart's memory is already DDR); BARD writing the
answer into the cart's memory (ZIGGY's D-cache would hold stale lines); events in DDR (ZIGGY would drop its whole
D-cache each frame); a sed patch into cRSID's memory writes to log a real tune's writes (upstream untouched
instead; the test tune is a Zig tracker).
**Consequences:** a cart that opens the queue owns the SID player (any song request ends it, the machine's reset
too). The board's event bandwidth is three a ZIGGY frame. BARD drops its 4 KiB D-cache whenever the cart's head
moved (once a frame for a playing tune). Paula writes could move onto the same ring later (the entry format is
the same; `addr` routes), and GoatTracker 2 is the next row.

## 2026-11-07 — SID-Wizard: the PC version's design (its C64 program on its own libcRSID), vendored; owner-only key codes

**Status:** accepted
**Context:** Matt asked for SID-Wizard 1.97 (Hermit's C64 tracker) as a cart: its UI is the C64's 40x25 text
screen. Its PC version runs the native 6502 program on SID-Wizard's own libcRSID (a C64 with CIAs, VIC raster
IRQs, a keyboard matrix and KERNAL disk traps), behind an SDL 1.2 host. The machine's key ABI had no Tab, Home,
End, PageUp or PageDown, and SID-Wizard needs Tab (C64 CONTROL: track stepping, the file dialog's fields).
**Decision:** (1) the same design: the native program on SID-Wizard's libcRSID (not libs/c/crsid's 1.58, which is a
PSID player without that C64), upstream's keyboard/mouse/disk code unchanged over a tiny SDL 1.2 key-state header,
and a small host of ours for the picture (the C64-UI mode at zoom 1 as palette indices into the 400x280 plane),
the sound (kestrel_audio_pump at 22.05 kHz, each sample one cRSID_generateSample(): the C64 is clocked by the
audio, as upstream) and the files (floppy + C:). (2) Upstream is vendored in apps/ports/sidwizard/upstream,
unmodified (no repository to pin; WTF licence), patched at build time by sed patches like the other ports.
(3) Tab, Home, End, PageUp, PageDown are new key codes 0xE019..0xE01D, **owner-only**: the browser sends them
only to a cart that owns the keyboard (so Tab still moves the page's focus for a scene), the board glass's
firmware the same; on the board Page Up/Down page the OSD while it is open and reach the cart as 0xE01C/0xE01D
when it is closed. F11/F12 are not added (the board's OSD hotkeys). (4) The 1 MHz parts are clocked less often
with upstream's results (CIAs + VIC at their next event or an I/O access, the envelopes once a sample in exact
steps, the key matrix on a $DC01 read) and forced inlining is off: 11.6 -> 5.9 Mc/frame playing.
**Alternatives considered:** an SDL 1.2-on-SDL2 shim (the PC display code at 32 bits, zoomed, then converted every
frame: dearer than drawing the C64 screen as indices); GoatTracker (a PC UI, not the C64's); libs/c/crsid for the
C64 (no CIA/VIC/keyboard); a cart-side remap of an existing key for CONTROL (no spare key on a PC keyboard that the
browser forwards); forwarding the new codes to every cart (steals Tab from the page for scenes that ignore it).
**Consequences:** the C64 costs ~3.5x real time on ZIGGY: the cart runs at ~16-19 fps on the board but the C64
inside at ~30 % speed (songs play slow) until the SID moves to BARD (`kestrel_sw_sid.h`, one switch, after
feat/bard-queue) and/or a smaller 6502 core (ROADMAP). Every cart that owns the keyboard may now receive
0xE019..0xE01D: the ports and GEM ignore them (ports_headless presses them before each port's pin; gem_headless
"owner-keys-ignored").

## 2026-11-08 — SID-Wizard's SID on BARD: stamped writes on the BARD queue, the C64 clocked by the frame's time

**Status:** accepted
**Context:** On the board SID-Wizard ran at ~20 fps with the SID (cRSID's light engine) on ZIGGY, where the audio
clocked the C64: ZIGGY could emulate only ~30 % of real time, so songs played slow and broken. The BARD queue
(decisions.md 2026-11-07) is on main: a cart can write SID registers stamped on its 44.1 kHz clock and SID live
plays them on BARD. Matt: "start the move to BARD using the queue".
**Decision:**
- **Every SID write goes on the queue** (`apps/ports/sidwizard/kestrel_sw_bard.c`, a C copy of `libs/zig/bard.zig`'s
  ring): captured in libcRSID's I/O write path, handed over after the instruction that made it, stamped
  `t = C64 cycle x 32 / SampleClockRatio` (2 output samples a 22.05 kHz "C64 sample": exactly the cart's clock;
  985248 cycles a second would drift 0.1 % against it). A reset and the 25 registers as the C64 has them open the
  queue, at t 0. The cart renders no SID (`SW_SID_ON_BARD`, default 1; 0 keeps the old way to measure against).
- **The C64 is clocked by the frame's real time** (`kestrel_frame_us`, capped at 100 ms), no longer by the audio.
  Its CIAs, raster lines and so the IRQs that run the player follow the clock; the stamps follow the C64. So the
  song's tempo is the C64's, whatever ZIGGY's frame rate (a 60 ms frame makes the same writes with the same stamps
  as three 20 ms ones: `apps/sidwizard_bard_check.mjs` tempo).
- **When ZIGGY cannot run all of that 6502** (the editor's main loop never idles; the C64 costs ~3.9 Mc a 60th
  estimated, ~2.3x real time), the main program yields (`kestrel_sw_pace.c`): each frame the emulation may take
  85 % of the real time it covers (hostMicros); past that, except in the frame's first tenth, the 6502 runs only
  inside IRQ handlers (I flag set) and the main program waits in libcRSID's idle state until the next frame. The
  IRQs (player, raster splits; ~40 % of the C64's time) come on time and run whole: the song keeps its tempo, the
  editor answers slower. With no host clock (every harness) nothing waits, so page and native host stay equal.
**Alternatives considered:** keep the audio as the clock and render on BARD (the C64 would still run at ZIGGY's
speed: wrong tempo); clock the C64 by frame time and let it fall behind (the cap, then slow music again); skip
whole frames of C64 time (IRQs lost: the player skips ticks); detect the editor's idle loops (it has none: no PC
takes more than 3 % of the time); a faster 6502 core (the right long-term lever, ROADMAP).
**Consequences:** the main program's speed on the board depends on how much the IRQs leave (estimate ~10-60 % of
a C64's), so key handling and redraws lag there; the music does not. The cart's oscilloscope and main-volume keys
no longer act on the sound (the samples are BARD's). A write is heard a lead (6,144 samples, ~139 ms) after the C64
made it, as BARD SID's.
