# Architecture Decision Records

Non-trivial technical choices and *why*, newest first. The rule of thumb: if a
future reader would ask "why did they do it this way?", it belongs here. Routine
choices that follow an established pattern do not.

Backfilled on 2026-09-12 for the ROM-chip work; entries before that date are
reconstructed from the commits that made them, so they are shorter.

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
