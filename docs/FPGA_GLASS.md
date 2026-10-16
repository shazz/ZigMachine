# The glass: the FPGA console's front panel

*Design and state of the ARM side of [`ZIGMACHINE_IN_FPGA.md`](ZIGMACHINE_IN_FPGA.md),
first written 2026-10-02. The code is in `fpga/glass/` (the ARM program),
`fpga/rtl/glass/` (the PL block) and `fpga/glass/boot/` (U-Boot, Linux).*

On a MiSTer, Main_MiSTer on the ARM reads the SD card and the USB devices, and
an OSD drawn by the FPGA framework lets you pick a core and a file. The
ZigMachine console works the same way. The ARM lists the `.zmd` shelf on the SD
card, loads a cart into the cart CPU's DDR, resets it and passes it the keyboard,
the mouse and the joypad. It does all of that while the console runs in the PL. The ARM never
runs a cart and is never on the video or audio path. The design is MiSTer's;
none of MiSTer's code (GPL) or zeST's code (GPL-3) is used.

```
  SD card ─┐                        PS (dual Cortex-A9, Linux)         PL (XC7Z010)
  USB HID ─┤   glass run  ──/dev/mem──► M_AXI_GP0 ──► zm_glass_regs ──► cart CPU reset
           │       │                                  │   key FIFO, JOY, POINTER ──► CSRs ──► cart CPU firmware
           │       │                                  └── OSD text ──► zm_glass_osd ─┐
           │       └──/dev/mem──► DDR 0x1E000000 ◄── HP port ◄── cart CPU          │
           │                                                                          ▼
           │                       compositor ─► mixer ─► scanout ─────────────► OSD ─► DVI ─► HDMI
```

## Status

| Piece | State | Evidence |
|---|---|---|
| Register map, one source (`glass/src/map.zig` → `gen/glass_map.{vh,py}`) | **done** | `make memmap` |
| `zm_glass_regs` (AXI3 slave, key FIFO, pointer, cart reset, reports, `AUDIO_VOL`, `CTRL.WARM`, `OSD_POS`) | **done**, 269 LUT, 433 FF (Yosys, 2026-10-10) | CXXRTL testbench; 24/24 break tests caught |
| `zm_glass_osd` (32×16 text, ST system font, 2×; movable, transparent spaces) | **done**, 91 LUT, 154 FF, 2 BRAM (Yosys); Vivado P&R 71 LUT, WNS +19.1 ns at 40 MHz | 8 whole 800×600 frames checked pixel by pixel; 13/13 break tests caught |
| In the z7 SoC (PS7 GP0, OSD hook, CPU reset) | elaborates and synthesises; **does not route yet** | whole SoC 4,424 LUT (25.1 %), +355 for the glass. openXC7 packs and places the PS7, but routing diverges (below) |
| ARM program `glass` (loader, menu pages, keymap, mouse, pad, evdev, `/dev/mem`) | **done**, host-tested | 62 Zig tests, 43 break tests caught; static `arm-linux-musleabihf` binary 3.7 MB |
| Console page: cold and warm reset, volume and mute, `glass.cfg` | **done**, host-tested | below, "Cold and warm reset", "Volume", "Settings" |
| Debug page (versions, live stats, board) | **done**, host-tested | below, "The debug page" |
| Cart descriptions (`shelf.txt`, `tools/shelf_meta.py`) | **done** | 73 catalog carts described, 55 with a field nobody wrote down (`--check` lists them) |
| Warm-boot hook in the cart CPU's firmware (`glass/firmware/glass_boot.c`) | **stub**, tested | 13 checks, 4 break tests caught; not linked into a firmware yet |
| Remote shell over Ethernet (DHCP, dropbear, avahi) | **Linux side written**; the PL's EMIO wiring is not | below, "Remote shell" |
| Load path, end to end | **done** | the 9 board images `fpga/cycles` links land byte for byte in the fake DDR |
| Disk streaming: ZWINDOW places the shelf disk in DDR, ZIGGY serves `diskReadBlock` from it | **done in the sim** (2026-10-11): no RTL change, no new CSR | every `docs/` shelf disk comes back byte for byte from its fat disk; the drive answers as the browser's own function on every case (`tests/test_board_disk.py`); stniccc streams SCENE1.BIN in the board SoC sim with the browser's hashes (below, "The disk in DDR") |
| GEM over a data disk: the firmware tells GEM the disk is in and hands it the FAT listing, from the disk in DDR | **done in the sim** (2026-10-11): no RTL change, no new CSR, no descriptor flag | the listing is the browser's byte for byte (`tests/test_board_gemdisk.py`); GEM opens ST Replay's floppy in the board SoC sim with the browser's hashes (below, "GEM over a data disk") |
| Programs off a data disk: ZIGGY asks (request block + `CART_STATE`), ZWINDOW loads the program's prebuilt image over the same disk, and GEM again on request 4 | **built, host-tested** (2026-10-11): no RTL change, no new CSR | firmware block = glass's reader; the glass's swap in its zig tests; the request in the board SoC sim (below, "Programs off a data disk"); the swap itself needs the board |
| Cart-side input routing (`glass/firmware/glass_input.c`) | **done, linked into every board firmware** (2026-10-10): once a frame, before `cart.frame()`, `cycles/binput.c` drains the key FIFO (32 a frame at most), then the joypad and the mouse, through `host/input_bridge.c` into the cart's exports (`host_input`, generated per cart by `tools/host_gen.py`: NULL where a cart has no such export) | 19 key cases + 7 pointer polls against `sealed-loader.js`'s rules; 3 break tests caught. `tests/test_board_input.py`: the native host plays a key-FIFO script (`ZM_GLASS_KEYS`) through the same router, and SPACE on union_beatdis gives the browser's own `key(32)` hashes, a mutant router is caught |
| SD card staging (`tools/glass_sd.py`), U-Boot script, DTS, Buildroot tree | **written** | `boot.scr` is byte-identical to `mkimage`'s; the DTS compiles against a stub dtsi |
| Anything on the board | **waiting for the board** | below, "What needs the board" |

## Features at a glance

Every glass feature, built or planned. Where: **core** = in the PL, **ARM** =
the `glass` program or Linux, **both** = a PL register (or the cart CPU's
firmware) plus ARM code. FPGA cost is what the feature adds to the PL. Figures
without `~` are measured (Yosys `synth_xilinx`, `tools/util.py`); figures with
`~` are **estimates**, not measurements. "—" = ARM only, no PL cost.

| Name | Description | Where | Status | Complexity | FPGA cost (LUT / BRAM / DSP) |
|---|---|---|---|---|---|
| OSD | 32×16 text over the picture, F12 | core | built, host-tested; on the board via the OSD test bitstream | S | 91 / 2 / 0 (with the overlay's position and transparency) |
| Frame-rate overlay | `FPS 38.2` in the corner, F11, the picture still visible | both | built, host-tested; not yet on the board | S | in the OSD's 91 (+46 LUT over the fixed OSD); `OSD_POS` in the register block's 269 |
| Register block (GP0) | the ARM's view of the console | core | built, host-tested | M | 269 / 0 / 0 (433 FF, 6 LUTRAM) |
| Cart shelf + load | list the `.zmd` disks, place a cart in DDR, boot it | ARM | built, host-tested | M | — |
| Disk drive | the cart reads its own disk block by block (`diskReadBlock`), as in the browser | both | built, sim-tested; not yet on the board | S | — (a descriptor in DDR, no register) |
| Cold reset | reload from SD, clear the cart's memory, boot: a power cycle | ARM | **must-have**, built, host-tested | S | — |
| Warm reset | restart the cart CPU over its memory: the ST's reset button | both | **must-have**, built, host-tested; firmware hook stubbed | M | 1 FF (`CTRL.WARM`, in the 245) |
| Volume / mute | master volume 0..255 + mute, persisted | both | **must-have**: register, menu and the multiply built (`soc/zm_audio_vol.py`, between the audio core and HDMI, 2026-10-10); not yet heard on the board | S | register in the 245; multiply ~1 DSP48 + ~20 LUT |
| Debug page | versions, live stats, board info | ARM | **must-have**, built, host-tested | S | — |
| Cart descriptions | title, group, year, machine, one line, from `shelf.txt` | ARM + tool | **must-have**, built | S | — |
| Settings persistence | `glass.cfg` on the SD card (volume, mute, the F11 overlay) | ARM | **must-have**, built, host-tested | S | — |
| USB keyboard | evdev → neutral key events → the cart's exports | both | built, host-tested | M | key FIFO, in the 245 |
| USB mouse | evdev → `POINTER`, clicks latched | both | built, host-tested | M | `zm_glass_ptr`, in the 245 |
| USB joystick | evdev → `JOY` → `input()`; the OSD works with it | both | **must-have**, built, host-tested; board checklist below | S | `JOY`, in the 245 |
| Remote shell over Ethernet | ssh over the RJ45: DHCP, dropbear, `zigmachine.local` | ARM (+ PL wiring) | **near-term**: Linux config done, PL EMIO wiring to do | M | ~10 LUT + 1 IOBUF (MDIO); the MII is wires |
| Cart upload over the network | `scp` a `.zmd` into the shelf; glass rescans | ARM | **near-term**, nearly free once the shell runs | S | — |
| Hard-drive emulation | a block device for carts, backed by an image on the SD | ARM (+ firmware) | future | M | — |
| CRT screen effects (SC1425-like) | scanlines, mask, bloom, curvature on the scanout | core | future | L | ~1,500–3,000 / ~2–4 / ~4–8 |
| Adebug-like debugger | halt, step, breakpoints, registers, memory, disassembly | both | future | XL | ~300–600 (VexRiscv debug plugin + a GP0 port) |
| USB floppy | `.st`/`.msa`/`.zmd` from a USB floppy drive | ARM | future | M | — |
| Console network (bridged) | carts see a network device, the ARM bridges it | both | future | XL | ~300–600 / ~1–2 / 0 (a packet FIFO) |
| Scanlines / scaling / 50-60 Hz / border | display options | core | future | M | ~200–800 / 0–2 / 0–2 |
| Key and pad remap | which key or button is which | ARM | future | S | — |
| Favourites / recent / folders | shelf organisation | ARM | future | S | — |
| Screenshot to SD | the ARM reads the physical framebuffer from DDR | ARM | future | S | — |
| Save states | freeze the cart's memory and the machine's state | both | future | L | ~0 (the ARM copies DDR while the CPU is held) |
| Settings beyond volume | everything else in `glass.cfg` | ARM | future | S | — |

## The ARM software stack (ADR 2026-10-02)

**Linux, built by Buildroot, running one static Zig program, `glass`, that
reaches the PL and the cart's DDR through `/dev/mem`.** The full argument is in
`decisions.md`. In short:

- USB HID, hotplug and FAT come for free with Linux. Bare metal would mean
  writing a USB host stack.
- zeST runs Linux on this exact board, so its kernel already has `/dev/mem`, evdev
  and HID. That gives a stopgap (plan B) before our own Buildroot image exists.
- Zig cross-compiles to `arm-linux-musleabihf` with no sysroot, and the program
  reuses `libs/zig/depackers/zx0.zig`. The board unpacks a cart with the same
  code as `rom.wasm`'s `romDepack`.

## The PS↔PL interface

The register block sits on **M_AXI_GP0 at `0x43C0_0000`**, in a 64 KiB window.
Every access is an aligned 32-bit word. The block is clocked from the SoC's sys
clock (the PL drives `MAXIGP0ACLK`), so it lives in one clock domain.

| Offset | Register | | What it does |
|---|---|---|---|
| `0x00` | `ID` | ro | `0x5A4D474C` "ZMGL". The ARM drives nothing until it reads this. |
| `0x04` | `VERSION` | ro | 1.4.0 (1.1 added `POINTER`; 1.2 `AUDIO_VOL` and `CTRL.WARM`; 1.3 `LOAD_BASE` moves the HP window; 1.4 `OSD_POS` and `CTRL.OSD_STATS`) |
| `0x08` | `CTRL` | rw | bit 0 `RUN`: 0 holds the cart CPU in reset, and 0 is the reset value. bit 1 `OSD`: show the overlay. bit 2 `KEY_FLUSH`: a strobe that empties the FIFO and clears the overflow flag. bit 3 `WARM`: the next boot keeps the cart's memory (below, "Cold and warm reset"); the firmware reads it at boot through the `glass_boot_warm` CSR. bit 4 `OSD_STATS` (1.4): a text cell holding a plain space (no inverse) is transparent, so only the text covers the picture (below, "The frame-rate overlay"). |
| `0x0C` | `STATUS` | ro | bit 0 `RUNNING`, bit 1 `KEY_FULL`, bit 2 `KEY_OVERFLOW` (sticky) |
| `0x10` | `CART_STATE` | ro | Written by the cart CPU's firmware: 0 reset, 1 booting, 2 running, 3 trapped. Bits 31:8: the trap code when trapped (`TRAP_WARM_LOST` = `0xFFFF01` for a warm boot with no memory to keep), the firmware's version (major.minor.patch, 8 bits each) when booting or running. Cleared while the CPU is held. |
| `0x14` | `CART_BEAT` | ro | The firmware's frame count: the ARM's watchdog |
| `0x18` | `LOAD_BASE` | rw | The DDR address of the cart CPU's RAM: bits 31..25 replace the top of every HP0-HP3 address at the PS7 (`soc/zm_board_mem.py` `hp_slice`), so it must be 32 MiB-aligned. Reset value `0x0400_0000`, U-Boot's window (U-Boot relocates itself over `0x1E00_0000`); `glass` writes `0x1E00_0000` before `CTRL.RUN` and refuses a PL older than 1.3.0, which ignores it. Write it only while `RUN` is 0: every HP master is idle then. |
| `0x1C` | `LOAD_SIZE` | rw | The bytes of image the ARM placed there |
| `0x20` | `KEY_PUSH` | wo | One key event into the 16-entry FIFO. A push into a full FIFO is dropped and sets `KEY_OVERFLOW`. |
| `0x24` | `KEY_LEVEL` | ro | Events waiting |
| `0x28` | `JOY` | rw | Held directions and fire (`JOY_*`) |
| `0x2C`, `0x30` | `OSD_FG`, `OSD_BG` | rw | Ink and paper, `0x00RRGGBB` |
| `0x34` | `SCRATCH` | rw | For bring-up: proves the bus before anything else |
| `0x38` | `POINTER` | rw | The mouse: x (bits 9:0), y (19:10), buttons (23:20). Reads back the cart's view, with SEQ in 31:24. Below, "The mouse". |
| `0x3C` | `AUDIO_VOL` | rw | The master volume: bits 7:0 the level (255 = unity), bit 8 `MUTE`. Reset value `0x0FF`: unity, not muted. An output port to the audio mixer. Below, "Volume". |
| `0x40` | `OSD_POS` | rw | (1.4) The OSD window's top-left on the 800×600 output: x in bits 10:0, y in 25:16. Reset value `0x00AC_0090`, (144, 172): centred, as before 1.4. A window partly past the right or bottom edge is clipped; one wholly past it is not drawn. |
| `0x1000`… | OSD text | wo | 512 words, row-major: `{inverse, glyph}` |

**The AXI slave** takes single beats only, which is what an uncached 32-bit
store or load from the ARM produces. AW and W may come in either order. IDs are
echoed and RLAST is always set. Every response is OKAY: an unmapped address
reads 0, and a write to it is ignored. A stray access can therefore never fault
the menu. The ID check is what detects a missing or wrong bitstream.

**There are no keyboard registers in the machine.** `machine/sdk/memmap.zig`
has none. A cart takes input through its exports (`input`, `inputRelease`,
`key`, `keyUp`, `setShadeMode`), and which export a key goes to depends on
`ownsKeyboard()`, which only the cart can answer. So the ARM sends **neutral key
events**, and the cart CPU's firmware applies the browser's rules
(`fpga/glass/firmware/glass_input.c`, a copy of `docs/sealed-loader.js`'s
keydown and keyup logic):

```
bits 20:0  the code demo.key() gets: the character of a printable key, or the
           browser's private-use code (F1..F10 0xE001.., Esc 0xE012, the
           modifiers 0xE014..0xE017); the arrows, which the browser sends only
           to input(), get 0xE020..0xE023
bit 24     down (clear = released)
bit 25     auto-repeat
```

On the cart CPU's side the block is five CSRs: `glass_key_data`,
`glass_key_valid`, `glass_key_pop` (write to pop), `glass_joy` and
`glass_pointer`, plus `glass_boot_warm` (`CTRL.WARM`). There are three more
that the firmware writes: `glass_pointer_ack`, `glass_cart_state` and
`glass_cart_beat`.

### The mouse (`POINTER`, `zm_glass_ptr.v`, `glass/src/mouse.zig`)

The browser (`docs/sealed-loader.js`, "Pointer input") calls
`demo.pointer(x, y, buttons)` on every `mousemove`, on `mousedown` and on
`mouseup`. Its rules, which the board keeps:

- **Coordinates** are the machine's physical-visible area, 0..639 by 0..199
  (`hwPhysWidth − 2·hwBorderX` by `hwPhysHeight − 2·hwBorderY`). A low-res cart
  halves x itself (`gem_desktop.zig`); `union_textracker.zig` clamps.
- **Buttons:** any mouse button is bit 0. A double-click is a one-off pulse of
  bit 1, sent after the second release's state and before the release itself
  (`gem_desktop.zig` opens the item under the pointer on it). There is no wheel.
- **A click shorter than a frame is still seen:** the browser defers the release
  by one animation frame.

**Why a register and not FIFO events.** The pointer is a *state*: only the
newest position matters, and the browser sends one per move. Mouse motion in
the 16-entry key FIFO would arrive at up to 1 kHz, crowd the keys out and set
`KEY_OVERFLOW`, and a firmware draining it once a frame would make one cart call
per stale position. A register holds the newest state and costs the firmware one
CSR read a frame. What a plain register would lose is the click shorter than a
poll, so the PL keeps it:

- The ARM writes x, y and the buttons held. Each write adds one to an 8-bit
  `SEQ`, and every button pressed since the firmware's last ack stays set in
  the word the cart reads (held | latched).
- The firmware reads `glass_pointer` once a frame. When `SEQ` differs from the
  one it last delivered, it calls `pointer()` and writes that `SEQ` to
  `glass_pointer_ack`.
- An ack whose `SEQ` is stale (the ARM wrote since) is ignored, so a press can
  never be acked before the cart has seen it. An ack that drops a latched button
  the ARM no longer holds adds one to `SEQ`, so the release is delivered on the
  next poll. This is the browser's one-frame deferred release.

**On the ARM** (`mouse.zig`): `REL_X`/`REL_Y` are summed, scaled by
`--mouse-scale=PCT` (100 = one pixel a count, kept to 1/256 pixel), into an
absolute position clamped to 640×200, which starts in the middle. y moves at
half rate, because a ZigMachine row is twice as tall as a column is wide. The
position is written once per `SYN_REPORT`, so x and y move together, and a
sub-pixel nudge writes nothing. Linux has no double-click, so `glass` times it:
a second press within 400 ms of the first, from the events' own timestamps.
`REL_WHEEL` is dropped, as the browser has no wheel.

**Routing is per event, not per device** (`main.zig`): `EV_REL` and
`BTN_LEFT..BTN_TASK` go to the mouse, `EV_ABS` and the other buttons from 0x100
up to the pad, and the rest to the keymap. A wireless combo receiver that puts
a keyboard and a mouse on one node therefore works, as does a mouse on its own
node.

**The firmware** (`glass_input.c`, `glass_pointer()`) skips the call for a cart
without a `pointer` export, but still acks. The cart CPU's `SEQ` memory starts
at 0, the PL's reset value, so a mouse nobody has touched calls nothing.

**Without a mouse** (`host/input_bridge.c` `input_pointer_script()`): a script
`F:word,...` plays what the ARM would write to `REG_POINTER` before frame F
(`word` in hex: `x | y<<10 | buttons<<20`), each write adding one to `SEQ` as the
PL does, into the same `glass_pointer()` poll. The native host reads it from
`ZM_GLASS_POINTER` and a sim image from `ZM_SIM_POINTER` (`cycles/board.mk`), the
mouse twins of `ZM_GLASS_KEYS` / `ZM_SIM_KEYS`. The PL's button latch is not
modelled (a script holds a press for a frame; the latch has its own RTL tests).
`tests/test_board_pointer.py` drives the GEM desktop with it: a click on the
FLOPPY DISK icon and the double-click pulse give the hashes of the browser's own
`pointer()` calls, a malformed script is refused, and two mutant routers (the
call dropped, x and y swapped) are caught. In the board-SoC sim (2026-10-11), a
GEM image built with `ZM_SIM_POINTER=2:7828,3:107828,4:7828,5:207828,6:7828` (move
to the floppy, click, double-click) gave, for frames 2/4/6, `71dbd6ea…`,
`51dfe723…` (icon selected), `22934ae1…` (`Drive A: is empty`), total
`b84fbef4…`: the native host's `ZM_GLASS_POINTER` run and `scene_hash.mjs` with
the same `--call F:pointer:40,30,b`, byte for byte.

### The joypad (`JOY`, `glass/src/pad.zig`)

`pad.zig` folds a pad's events into the held `JOY_*` bits, which the firmware
turns into `input()`/`inputRelease()` edges (`glass_joy()`):

- an analog stick counts as pushed past a third of its declared range from the
  centre, using the range it reports (`EVIOCGABS`);
- a hat d-pad counts on any step;
- a d-pad reported as buttons uses `BTN_DPAD_*`;
- fire is `BTN_TRIGGER` (a joystick), `BTN_SOUTH` or `BTN_EAST`.

A DualShock or DualSense adds a touchpad node and a motion-sensor node, which
report `ABS_X`/`ABS_Y` too. `evdev.zig` reads each node's `INPUT_PROP_*` bits and
ignores the axes of a touchpad, touchscreen or accelerometer. The kernel
(`boot/buildroot/linux.fragment`) has `xpad` (Xbox and XInput pads, and most
8BitDo pads in X mode), `hid-sony`, `hid-playstation`, `hid-nintendo` and
`hid-microsoft`, plus the LED class they depend on. Anything else is
`hid-generic`.
`cpu_run` drives VexRiscv's reset directly.

**USB joystick support is a must-have** (Matt, 2026-10-03), and it is built:
`pad.zig` → `JOY` → `glass_joy()` in the firmware, the drivers above, and the
OSD driven by the d-pad (Left/Right too) and fire. The debug page shows the
evdev name of the last pad that sent an event, so a pad that is plugged in but
dead is told apart from one Linux never bound.

**On-board checklist, once Linux runs.** Plug each pad in next to the keyboard
and the mouse (through the hub on the one USB host port). For each: the four
directions and fire reach the cart (a screen that reads the joystick, e.g.
the Union demo's doors), the OSD moves and loads with it, and the debug page's
`pad` row names it.

| Pad | Driver expected | Notes |
|---|---|---|
| A generic USB joystick | `hid-generic` | sticks are `ABS_X/Y`, fire `BTN_TRIGGER` |
| An Xbox-style pad (360 / One / XInput) | `xpad` | d-pad as hat or buttons, fire = A |
| DualShock 4 / DualSense | `hid-playstation` (DS4 may bind `hid-sony`) | its touchpad and motion nodes must not move the stick (`evdev.zig`) |
| Switch Pro | `hid-nintendo` | needs kernel ≥ 5.16 |
| 8BitDo (X mode, then D mode) | `xpad`, then `hid-generic` | try both modes |
| Atari-style stick via USB adapter (2600-daptor, Retro-Bit) | `hid-generic` | a digital stick reports a hat or ±full-range axes; one fire button |

## The DDR layout (512 MiB, one MT41J256M16)

| PS physical | Size | Who | What |
|---|---|---|---|
| `0x0000_0000` | 480 MiB | Linux | The kernel, the rootfs in RAM, and `glass` |
| `0x1E00_0000` | 32 MiB | **the cart CPU** | Its whole RAM, seen at `0x4000_0000` (LiteX `main_ram`). Reserved with `no-map` (`zigmachine-z7lite.dts`); plan B uses `mem=480M`. |

Inside the cart window, the layout is the one `fpga/cycles` links
(`cycles.mk`, `board.mk`, `sound.mk`), plus what ZWINDOW places for the drive.
Offsets are from the window's start; the cart CPU (ZIGGY) sees offset 0 at
`0x4000_0000`, the PS at `0x1E00_0000`.

| Offset | CPU address | Size | What | Written by |
|---|---|---|---|---|
| `0x0000_0000` | `0x4000_0000` | the image, < 12 MiB | `fw.bin`: code, constants, `.data`'s load copy (ends at `__data_source_end`). Split: the **system image** `sys.bin`, < 3 MiB | ZWINDOW (load) |
| `0x0030_0000` | `0x4030_0000` | split only | the **lean cart image** `cart.bin`, its header first; its `.bss` follows (`CART_IMG_AT`, "System image and lean carts") | ZWINDOW (load) |
| image end (split: the cart's `.bss` end), rounded up to 4 KiB | | the disk, up to `0x00C0_0000` | **the shelf disk** (`DISK_*`, below "The disk in DDR") | ZWINDOW (load) |
| `0x00C0_0000` | `0x40C0_0000` | 1 MiB + 1 MiB | the two pictures (`cycles/bmailbox.h`) | ZIGGY |
| `0x00E0_0000` | `0x40E0_0000` | 2 MiB | the sound CPU's image (`ZM_AUDIO=snd` only) | in `fw.bin`'s link |
| `0x0100_0000` | `0x4100_0000` | 16 MiB (12 with `snd`) | `.data`, `.bss`, the machine's 7 MiB arena, the heap, a 1 MiB stack | ZIGGY |
| `0x01C0_0000` | `0x41C0_0000` | to `0x01FE_F000` | the sound CPU's RAM (`snd` only) | BARD |
| `0x01FE_F000` | `0x41FE_F000` | 64 KiB | the sound CPU's console ring (`snd` only) | BARD |
| `0x01FF_FC00` | `0x41FF_FC00` | 16 B | **the disk descriptor** (`DISK_DESC_*`) | ZWINDOW (load) |
| `0x01FF_FD00` | `0x41FF_FD00` | 64 B | **the cart-swap request block** (`CART_REQ_*`, "Programs off a data disk") | ZIGGY |
| `0x01FF_FE00` | `0x41FF_FE00` | 12 B | the write-path diagnostic's control (`cycles/bdiag.h`) | the ARM, on request |
| `0x01FF_FF00` | `0x41FF_FF00` | 256 B | the debug mailbox (`cycles/bmailbox.h`) | ZIGGY |

The machine's 7 MiB shared memory (cart window, VRAM, PFB, ROM window) is
`calloc`'d from that heap by the firmware, as on the native host. A load writes
the image, the disk and its descriptor, and zeroes everything else. A warm reset
touches nothing.

The **OSD buffer is not in DDR.** It is 2 KB of text RAM, plus the 2 KB font,
in BRAM inside `zm_glass_osd`, as MiSTer's OSD is. That costs no DDR bandwidth
and no scanout arbitration, and the overlay keeps working when the cart CPU or
DDR is wedged, which is exactly when the menu is needed.

During boot, U-Boot uses `0x0100_0000` (the bitstream), `0x01F0_0000` (the DTB),
`0x0200_0000` (the zImage) and `0x0400_0000` (the initramfs). All of them are
below the cart window.

## Boot flow

1. **Power-on.** The BootROM reads `BOOT.BIN` from the SD card (with the boot
   jumper set to SD). That file is zeST's for now: its FSBL brings up DDR3, the
   clocks and MIO, which is the `ps7_init` nobody publishes for the 7010, and it
   starts U-Boot. zeST's PS7 configuration already enables GP0 and HP0.
2. **U-Boot** runs distro boot and finds `boot.scr` (`fpga/glass/boot/boot.cmd`):
   - `fpga loadb` with `zigmachine.bit`, which replaces whatever `BOOT.BIN` left
     in the PL;
   - **Plan A:** `bootz` with our zImage, `zigmachine.dtb` and
     `rootfs.cpio.uboot` (Buildroot, `fpga/glass/boot/buildroot`);
   - **Plan B** (the stopgap): zeST's `uImage` and `rootfs.ub`, with its device
     tree where `BOOT.BIN` leaves it (`0x800000`), plus `mem=480M` and
     `init=/bin/sh`.
3. **Linux.** In plan A, `S99glass` mounts the SD card's FAT partition
   read-only on `/mnt/sd` and keeps `glass run /mnt/sd/zigmachine` running,
   restarting it if it dies. In plan B, you type that at the shell, from
   `/mnt/glass`.
4. **`glass`** maps GP0 and the cart window, checks `ID`, sets the OSD colours,
   scans the shelf and shows the menu over a cart CPU still held in reset.

## The OSD

- **Window:** 32 × 16 characters of the machine's own 8×8 system font
  (`machine/assets/fonts/system_font_atari_1bit.raw`), drawn 2×. That is 512 ×
  256 pixels at (144, 172), centred on the 800 × 600 output (`OSD_POS`'s reset
  value; the frame-rate overlay moves it).
- **Where it sits:** on the pixel stream between `zm_video_scan` and
  `zm_dvi_out`. It is the last layer, after the mixer, so it never changes a pixel
  the scene-hash oracle checks. The hook is one marked block in
  `soc/zm_video_pipe.py`, and `rtl/video/` is untouched.
- **Timing:** three pixel-clock stages (text RAM, font ROM, pixel), with the
  syncs delayed to match. Its position comes from the stream itself (DE and
  VSYNC), so it needs nothing from `zm_vtiming`.
- **F12** opens and closes it, as on MiSTer, and F12 never reaches a cart.
  - While it is open the cart gets **no input**. Every key the cart saw go down
    is released first, as are the joypad bits and the mouse buttons, so nothing
    stays held behind the menu. The pointer stays where it was, and motion over
    the menu is dropped.
  - **Esc** closes the menu over a running cart (there is nothing to close it
    over before the first load).
- **F11** toggles the frame-rate overlay while the menu is closed (below). Like
  F12 it never reaches a cart; with the menu open it does nothing.

### The frame-rate overlay (F11, `app_stats.zig`)

`FPS 38.2` in the top-left corner over a running cart, without hiding the
picture. It is the same OSD, put in another mode rather than a second block:

- `glass` writes `OSD_POS` = (16, 16), sets `CTRL.OSD | CTRL.OSD_STATS`, and
  writes row 0 only; every other cell is a plain space, which `OSD_STATS` makes
  transparent. The text keeps its paper (`OSD_BG`), so it stays legible over any
  picture.
- The number is `stats.zig`'s: `CART_BEAT` frames over a one-second window of the
  ARM's clock, `--.-` until a whole window has been seen (after a load, a reset).
  `glass` redraws it on every tick (ten a second); only changed cells cross the
  bus, so that is one write burst a second.
- **Opening the menu** (F12, or a trapped cart) puts the window back centred and
  opaque; **closing it** brings the overlay back if it was on.
- The toggle is saved in `glass.cfg` (`fps=1`), so it survives a restart.
- **A PL older than 1.4.0** has neither the bit nor `OSD_POS`. F11 then does
  nothing (it would show an opaque blank window mid-screen) and the setting is
  kept for a newer bitstream. It is never a reason to refuse the PL.
- In the PL it costs the two position subtractions (from constants to
  registers), the space compare and the synchronisers: the OSD went from 45 to
  91 LUT and 154 FF (Yosys). Vivado out of context, placed and routed at the
  40 MHz pixel clock: 71 LUT, 159 FF, 1 BRAM tile, WNS +19.1 ns (the worst path
  is font ROM → pixel mux, 3 logic levels).
- **The menu** has three pages (`menu.zig`, one file a page). Row 15 is always
  the status line: the page's hint, `loading…`, or the last error. A joypad
  works everywhere: the d-pad is the arrows and fire is Enter; Back is an item,
  as a pad has no Esc. `glass sim-menu DIR [shelf|console|debug]` prints any
  page on a desktop (the drawings below are its output; `*` marks the cart in
  the window, and the cursor's row is inverse on the screen).

### The shelf page (`page_shelf.zig`)

```
 ZIGMACHINE  SHELF     2/5   >      title bar (inverse), cursor/count, > = console
 TEX B.I.G. DEMO                    rows 1..9: the carts by title
*OXYGENE STNICCC 2000               (cursor row inverse, * = loaded)
 TLB TWIDDLE DEMO
 tutorial                           a disk shelf.txt does not list: its own title
 VEX 2025 GTA VI



--------------------------------
Oxygene 2000            atari st    group, year, machine
Oxygene / STNICCC 2000, the         the one-line description,
polygon flight (scene1.bin          word-wrapped over 3 rows,
stream)                             '~' if it does not fit
ENTER load  > console  F12 close    status
```

↑/↓ move, Enter or Space loads, → opens the console page, Esc closes the OSD
over a running cart, and R and W are the cold and warm reset. A title longer
than its 31 columns is cut with `~` in the list and **scrolls** (a marquee,
holding at each end) while it is the selected one. A disk that `shelf.txt` does
not list shows `no shelf.txt entry` and its file name in the details.

### The console page (`page_console.zig`)

```
 ZIGMACHINE  CONSOLE       < Esc
                                
 Cold reset                         cursor row inverse
 Warm reset
 Volume  ################ 100%      ←/→ change it, 16 steps
 Mute    off                        Enter or ←/→ toggle
 Debug...
 Back

--------------------------------
Reload the cart from the SD         what the selected item does
card, clear all its memory and
boot it: a power cycle. (R on
the shelf)
ENTER do  <> change  Esc back
```

A volume or mute change reaches `AUDIO_VOL` at once and is saved to `glass.cfg`
when you leave the page (Esc, Back, or closing the OSD), so holding ← does not
write the card sixteen times.

### The debug page (`page_debug.zig`)

Read-only, redrawn twice a second while it is open (`App.tick`). Any key that
means "back" returns to the console page.

```
 ZIGMACHINE  DEBUG     live  Esc
glass 0.2.0 db551a22                the ARM program: version + git hash (build.zig)
PL    ZMGL 1.2.0                    ID + VERSION from the registers
fw    0.1.0                         the cart CPU firmware (CART_STATE 31:8)
cart  RUNNING  beat 41226           CART_STATE, CART_BEAT = frames run
fps   50.0     trap -               measured from the beat over 1 s; last trap code
loads 3  last 412 ms                loads since start, the last one's time
up    1:02:03                       the glass program's uptime
ddr   1E000000+32M img 412K         the cart window, LOAD_SIZE
cpu   46.8 C                        Zynq die temperature (XADC, iio)
mem   390/480 MB free               /proc/meminfo
pad   Xbox Wireless Controller      the last pad heard from (evdev name)
input 3 evdev nodes                 devices open
                                
                                
read-only, live      Esc back
```

The temperature comes from the kernel's `xilinx-xadc` iio device
(`in_temp0_raw + offset`, times `scale`); without it the row says `n/a (no
XADC)`, as does `mem` without `/proc`. `fw` shows `-` while no cart runs.

## Cart load sequence (`fpga/glass/src/loader.zig`)

1. Read `ID`. If it is wrong, stop with `NoGlass`.
2. Parse the `.zmd` (v1 or v2), and find the FAT file of type 3 (`CART.RV32`):
   `NoBoardImage`.
3. Depack it with the machine's ZX0 depacker (an unpacked image is taken as it
   is), and check the result fits the window: `BadImage`, `TooBig`. Rebuild the
   shelf disk from the fat disk and check it fits between the image and the
   pictures: `BadFat`, `DiskTooBig` (`loader.plan`, below "The disk in DDR").
   **Steps 1 to 3 touch neither DDR nor the CPU**, so a bad disk leaves the
   running cart running.
4. Clear `RUN`, and check that `STATUS.RUNNING` dropped: `WontStop`.
5. Write the image, the shelf disk and its descriptor into the window one word
   at a time, zero the rest, then read the whole window back: `DdrMismatch`. The
   mapping is uncached, so nothing is left in a cache when the CPU starts.
6. Write `LOAD_BASE` and `LOAD_SIZE`, and strobe `KEY_FLUSH`, so no keys typed
   for the menu reach the new cart.
7. Set `RUN`. Poll `CART_STATE` until it reads `RUNNING`: `CartTrapped` with the
   code, or `CartSilent` after 2 s. Either way the CPU goes back into reset.
8. Close the OSD. From then on `glass` polls `CART_STATE` about ten times a
   second. A trap holds the CPU and reopens the menu with the trap code.

## Cold and warm reset

Two menu items (and R and W on the shelf page), with exactly these effects:

| | Cold reset (R) | Warm reset (W) |
|---|---|---|
| What it is | a power cycle of the console | the ST's reset button |
| The image on the SD card | re-read and depacked | not read |
| The cart window in DDR | rewritten: the image, the shelf disk and its descriptor, zeros everywhere else (`.data`, `.bss`, heap, stack and the machine's 7 MiB memory all cleared), read back | **untouched** |
| The cart CPU | held, then booted with `CTRL.WARM` clear | held, then booted with `CTRL.WARM` set |
| The firmware's own C statics | crt0: `.data` copied, `.bss` zeroed | the same (crt0 always runs) |
| The machine's memory arena (wasm linear memory) | zeroed, data segments applied, marked | **kept**: no zeroing, no data segments |
| The cart | `init` runs over fresh memory | `init` runs again over its old memory |
| The key FIFO | flushed | flushed |
| Keys, joypad bits, mouse buttons held | released when the OSD opened | released when the OSD opened |
| `POINTER` SEQ, `AUDIO_VOL`, the OSD | kept | kept |
| `CART_STATE`, `CART_BEAT` | cleared while held | cleared while held |
| Load count (debug page) | +1 | unchanged |

**The warm-boot hook** (`glass/firmware/glass_boot.{h,c}`, a stub: no board
firmware links it yet). At boot the firmware reads `glass_boot_warm` and asks
`glass_boot_kind()`:

- **COLD**: lay the machine's arena out at a FIXED address past `.bss` (not a
  heap `calloc`, so a later warm boot can find it), zero it, apply the wasm
  modules' data segments, then `glass_boot_mark()` the two words below it
  (magic `ZMME` and a check tied to the arena's size), and call the cart's
  `init`.
- **WARM**: the mark is there, so keep the arena as it is; the modules' globals
  (the stack pointer among them) start afresh, and the cart's `init` runs over
  its old memory.
- **WARM_LOST**: `WARM` was set but the mark is missing (a cold load zeroed the
  window, or the last cold boot never got as far as marking). Nothing runs; the
  firmware reports `CART_TRAPPED` with `TRAP_WARM_LOST`. The ARM holds the CPU
  and says `warm reset: memory lost, use R`. It never quietly cold-boots: the
  user asked to keep that memory.

`glass_boot_plan()` turns the kind into the steps (zero the arena, apply data
segments, call init, the first `CART_STATE` word), which is what the board
firmware's `main()` will follow. The firmware reports its version in
`CART_STATE` bits 31:8 while booting and running (`GLASS_FW_VERSION`, 0.1.0).

**On the ARM** (`loader.warm`): check `ID`, hold the CPU (`WontStop` if it does
not stop), write `CTRL` = `WARM | KEY_FLUSH` then `WARM | RUN`, wait for
`RUNNING` as a load does, and clear `WARM` once the cart is up, so that any later
boot is cold unless asked. `hold()` always drops `WARM`.

**A failed load and the window.** A disk refused before the CPU is stopped
(unreadable, not a disk, no board image, bad ZX0, too big) leaves the old cart
running and in the window, so R and W still reset it. Once the window has been
written (`DdrMismatch`, `CartTrapped`, `CartSilent`), it holds the new disk: R
reloads that disk, and W reports `memory lost`.

## Volume (`AUDIO_VOL`)

`AUDIO_VOL` is an output port of `zm_glass_regs` (`audio_vol[8:0]` = `{mute,
volume}`, sys clock), exported by `soc/zm_glass.py` as `glass.audio_vol`. The
audio mixer (`fpga/rtl/audio/`, built separately) must apply it **in the mix,
after the voices are summed and before the HDMI sample FIFO**:

```
gain = mute ? 0 : vol + vol[7]          // 0..256: 255 is exactly unity
out  = (mixed_sample * gain) >>> 8      // signed, one DSP48 per channel or one shared
```

It is a slow, quasi-static control: synchronise it into the audio clock with
two flops per bit; a change that lands mid-sample gives one sample at a mixed
gain, which is inaudible. The reset value (`AUDIO_VOL_RESET` = 255, not muted)
plays at unity, so a bitstream with no glass program running is never silent.
`glass` writes it at start from `glass.cfg`, and on every change in the console
page.

## Settings (`glass.cfg`)

`<SHELF_DIR>/glass.cfg` (`/mnt/sd/zigmachine/glass.cfg`), `config.zig`:

```
# glass.cfg: the console's settings, written by glass (docs/FPGA_GLASS.md)
volume=200
mute=0
fps=0
```

`fps=1`: the F11 frame-rate overlay is on. F11 saves it at once.

- **Missing** means "never saved": the defaults (255, not muted), and nothing
  is reported, as nothing is wrong.
- **A line that does not parse** (`volume=300`, `mute=yes`, an unknown key) is
  reported on the status line (`glass.cfg: bad line N`) and in the log; its key
  keeps its default, and every good line still applies.
- **Saving.** The SD card stays mounted read-only (a power cut cannot hurt it).
  A save remounts it read-write (`mount(MS_REMOUNT)`), writes `glass.cfg.new`,
  renames it over `glass.cfg`, and remounts read-only. A cut mid-write leaves the
  old file (vfat renames one directory entry). If the card will not go
  read-write, the status says `not saved: card read-only` and the change stays
  pending for the next save; the volume already applies.

## Cart descriptions (`shelf.txt`)

The shelf shows each cart's catalog title, and the selected one's group, year,
machine and a one-line description. They come from `<SHELF_DIR>/shelf.txt`, one
line a disk, tab-separated:

```
FILE              TITLE                 GROUP    YEAR  TYPE      DESCRIPTION
demo-stniccc.zmd  OXYGENE STNICCC 2000  Oxygene  2000  atari st  Oxygene / STNICCC 2000, the polygon flight ...
```

**Why a side file, not a block in the `.zmd`.** The disk format has no free
room for it without a format change, and the browser loader parses those
headers. A side file needs neither, and a fix to a description needs no disk
repacked.

**Where the text comes from** (`fpga/tools/shelf_meta.py`; nothing is typed a
second time):

- TITLE and TYPE: `apps/zig/scenes/catalog.zig`, through `tools/channels.py`'s
  parser (its 22-character cap and machine types);
- DESCRIPTION: the cart matrix's comment in `build.zig` (`"demo-stniccc", // 38 —
  Oxygene / STNICCC 2000, ...`), else `cart.zig`'s comment on the import, else
  the first sentence of the scene's header comment;
- GROUP: the capitalised name before the first ` / ` of that description;
- YEAR: the first year (1985..2029) in the description or the header;
- except `OVERRIDES` in `shelf_meta.py`, the one place a field is typed: where the
  catalog's title is the browser menu's verb rather than the cart's name (GEM:
  `EXIT TO GEM` becomes `GEM DESKTOP`, Digital Research, 1985, TOS 1.00's
  desktop), or the source names no group (`st_replay`: `Microdeal`, from its
  description). An empty override field keeps what the repo says, and
  `tests/test_shelf_titles.py` holds each override to a catalog cart and the
  OSD's 22-character, upper-case, ASCII title.

Text is folded to ASCII (the OSD draws the ST's 8-bit font). A field nobody
wrote down stays empty: `shelf_meta.py --check` lists those carts (55 of 73
today, mostly a missing year), and the fix is a better comment at the source,
not a second list. `tools/glass_sd.py` writes `shelf.txt` next to the fat disks
it stages. A missing `shelf.txt` is not an error: the menu shows each disk's own
title and says `no shelf.txt: titles only`. A line with fewer than two fields is
counted and reported (`shelf.txt: N bad lines`).

## The fat disk

A board needs the cart translated to rv32, linked with the machine and the ROM.
That is what `fpga/cycles` builds (`fw.bin`, 0.2 to 0.6 MB). `tools/zmd_fat.py`
appends it, ZX0-packed, to a shelf disk as one more FAT file. Everything else in
the disk keeps its bytes: the wasm cart, its files and the title. A v1 boot
sector's checksum is re-tuned to the sum it had, so a bootable disk stays
bootable and a data disk stays a data disk. The packed images are 60 to 360 KB.

`tools/mkdisks.sh` does not write these disks yet. The board images need the
fpga toolchain, which `./build.sh` does not run, so `tools/glass_sd.py` makes
the fat shelf for the SD card. A FAT entry of type 3 is invisible to the
browser.

**Which carts.** `tools/glass_sd.py` `SHELF` lists the carts the card carries, and
`make -C fpga board-shelf` builds a board firmware for each (`ZM_AUDIO=snd` for
the sound-CPU images). A listed cart with no firmware is staged as `MISSING` in
`MANIFEST.txt` rather than silently left off; a firmware in `--fw-dir` that is not
listed is still staged (a cart being tried out).

**GEM on the shelf** (`demo-gem.zmd`, the cart `apps/zig/scenes/gem_desktop.zig`
over the ROM's desktop). Its board images are 1.66 MB (`board/gem/fw.bin`) and
1.68 MB (`board_snd/gem/fw.bin`); its fat disk is 247 KB. It boots in the board-SoC
sim (`tools/hp_sim_run.py gem --frames 6 --every 2`: `ok`, no underrun, hashes
= `scene_hash.mjs` = the native host). Mouse and keyboard come
through the glass like any cart's (it owns the keyboard, so every key goes to
`key()`). What it does not get on the board yet:

- **Its own disk is not a data disk.** `demo-gem.zmd` is bootable, so the browser
  boots it with `diskApp` false and GEM's FLOPPY DISK says `Drive A: is empty`; the
  board does the same. GEM gets a disk to open from a DATA disk on the shelf
  (`st_replay`), below, "GEM over a data disk".
- **Program launch** is ZWINDOW's (below, "Programs off a data disk").
- **The OSD title** is `GEM DESKTOP` (Digital Research, 1985), not the catalog's
  `EXIT TO GEM`, which is the browser menu's verb for it; `st_replay` keeps its
  catalog title, `ST REPLAY`, with the group `Microdeal` (`shelf_meta.py`
  `OVERRIDES`, below, "Cart descriptions").

## System image and lean carts

decisions.md 2026-10-15. A monolithic board image repeats ~1.65 MB of firmware, machine,
ROM and BARD image in every fat disk. The split puts them in one **system image**, on the
card once as `zigmachine/system.rv32`, and leaves each fat disk a **lean cart image**: the
wasm2c'd cart, its env forwarders and its songs (`make -C fpga board-split ZM_AUDIO=snd`,
then `tools/glass_sd.py --system build/hcycles/split/board_snd/sys.bin --fw-dir
build/hcycles/split/carts`). Measured on the 15-cart shelf: 7.66 MB → 3.92 MB; a cart's
packed board image ~270 KB → 11 to 112 KB (skystrike 396 KB and Beat Dis 250 KB are their
songs); `system.rv32` is 257 KB.

- **The table.** The cart calls the machine, the ROM, the wasm2c runtime and libc/libm
  through `zm_sys_table`, which the system hands to the cart's `bind()`; the system calls
  the cart through the header at the start of its image (`zm_cart_hdr`: entry points,
  bridges, `.bss` range, sizes). `fpga/cycles/sys_abi.txt` is the layout and its version
  (`major.minor`); `tools/sys_abi.py --check` in `build.sh` fails a layout that changed
  without a bump (`--update` bumps: minor for an appended ROM export, major otherwise).
- **Versions.** A cart runs on a system of the same major and at least its minor. glass
  checks when it loads the disk (`system.zig`), before DDR or the CPU are touched; the
  firmware checks again (`cycles/bsys.c`) and reports `TRAP_CART_ABI`.
- **Loading.** glass reads `system.rv32` once at start-up. A fat disk whose board image
  starts with `CART_HDR_MAGIC` is a lean cart: the system goes at offset 0, the cart at
  `CART_IMG_AT`, the shelf disk after the cart's `.bss`. A monolithic image loads as before,
  so both kinds of disk can share a card.
- **The firmware.** `bsys_link()` finds the cart, checks its version, zeroes its `.bss`
  (cold or warm) and binds it before `bdisk_boot` and `host_boot`. The cart has no `.data`,
  TLS or libc (`cycles/cart.ld` refuses them); its wasm call-depth counter is its own.
- **The sim.** `tools/hp_sim_split.py <carts>` runs the pair in the board SoC sim with the
  sound CPU, against the references the monolithic image is held to; `--abi-skew` builds
  carts claiming another version and expects the refusal.

## The disk in DDR

A cart that streams from its disk (stniccc's SCENE1.BIN, the stream cart, any
`zg.disk` user) calls `env.diskReadBlock(block, dst)`. In the browser that is
`docs/sealed-loader.js`'s drive over the mounted `.zmd`. On the board ZWINDOW
already holds the disk when it loads the cart, so it leaves a copy in the cart
window, and ZIGGY's firmware serves the call from it. No register is involved
and nothing changes in the PL.

**What ZWINDOW places** (`loader.plan`, `zmd.Disk.shelfDisk`). The disk the
browser mounts, which is not the fat disk. `shelfDisk` undoes
`tools/zmd_fat.py` byte for byte: it cuts the board image off the end, zeroes
its FAT entry, puts the file count back, and for a v1 disk restores the
total-blocks field and the checksum word. A fat disk whose board image is not
the last file, ending the disk, is refused (`BadFat`). The rebuilt disk goes on
the first 4 KiB boundary after the image (`DISK_ALIGN`) and must end by the
pictures at offset 12 MiB (`DISK_END`), or the load stops with `DiskTooBig`
before the CPU is touched. With today's images (1.7 to 2.4 MB) that leaves
about 9.5 MiB for a disk; the largest shelf disk is 1.1 MiB.

**The descriptor** (`map.zig`, four little-endian words at window offset
`DDR_CART_BYTES - DISK_DESC_FROM_TOP` = `0x01FF_FC00`, CPU `0x41FF_FC00`, in the
top 4 KiB that the link keeps free):

| Word | Value |
|---|---|
| 0 | `DISK_MAGIC` = `0x4B44_4D5A` ("ZMDK") |
| 1 | the disk's window offset (not a CPU address: ZWINDOW never sees `CART_CPU_BASE`) |
| 2 | the disk's bytes |
| 3 | `~(magic ^ offset ^ bytes)` |

**What ZIGGY does** (`cycles/bdisk.c`). It reads the descriptor at boot, cold or
warm, before `host_boot` runs the cart's init, because init may already read
the disk (stniccc's does). It accepts the descriptor only if the magic and the
check hold, the disk starts at or after its own image's end
(`__data_source_end`), and it ends by `DISK_END`. Anything else, including
U-Boot's `loadx` flow and a glass older than this, means no disk, and
`diskReadBlock` answers 0, as `scene_hash.mjs`'s stub does. ZIGGY never writes
the disk or the descriptor, and ZWINDOW wrote both before the CPU left reset,
so the D-cache never holds a stale line of them.

**The drive's answers** (`fpga/host/disk.h`, the same code in the native host
and the firmware). It does exactly what the browser's function does:

| Call | Answer |
|---|---|
| no disk | 0; nothing is written, and `dst` is never looked at |
| block `b` | `buf.subarray(b*512, b*512+512)` copied to `dst`, returns its length: 512, or less for a partial last block |
| past the end | 0, `dst` never looked at |
| `b` ≥ `0x8000_0000` | past the end like any other: 0, `dst` never looked at. The block is unsigned (`block >>> 0` in the browser, which once read it as a negative i32 and counted it from the end). |
| `dst` + n past the 7 MiB memory, or `dst` ≥ `0x8000_0000` | the browser throws a `RangeError` out of the cart. Here it is a wasm trap (`WASM_RT_TRAP_OOB`), which the firmware reports as `CART_TRAPPED` |

The call is synchronous in both: the bytes are in memory when it returns. One
block is one `memcpy` from DDR to DDR through the D-cache. stniccc reads 128
blocks for each 64 KB part of its stream.

**The board SoC sim** loads the same picture. `tools/ddr_init.py` writes the DDR
image with the shelf disk and the descriptor where ZWINDOW puts them, and
`tools/hp_sim_run.py` compares the result with `scene_hash.mjs --disk` and
`host --disk`.

## GEM over a data disk

A disk whose boot sector does not sum to `$1234` (`docs/zmdisk.js`: a *data*
disk; today only `demo-st_replay.zmd`, with `BOOT.WSM` and `SAMPLE.RAW`) is not a
cart. The browser boots GEM for it, and after every `demo.frame()` it
(`docs/sealed-loader.js`):

1. polls `pollCartRequest()` (a double-clicked program is request 3, below,
   "Programs off a data disk");
2. calls `insertDisk(1)`, so FLOPPY DISK opens the disk instead of the empty
   drive's alert;
3. once `isBooted()`, writes the disk's FAT listing into `diskDirPtr()` (records
   of `rom.deskDirEntryBytes()` bytes, at most `rom.deskDirMaxFiles()`: a 16-byte
   name, the type at +16, the size u32 LE at +17, a v2 disk's date u32 LE at +21)
   and calls `setDiskFileCount(n)`, once.

**On the shelf** (`tools/glass_shelf.py`). `st_replay` is in `SHELF`. A data
disk's fat disk carries GEM's board image (`board/gem/fw.bin`), not its own, and
nothing else marks it: ZWINDOW places the disk in DDR exactly as for any cart
("The disk in DDR"), and the firmware decides from the disk's boot sector, as
the browser does. No descriptor flag, no register. `make board-shelf` also
builds `board/st_replay/fw.bin`: the program GEM launches (next section).

**In the firmware** (`cycles/bdiskapp.c`, `host/disk_app.h`, `host/zmd_dir.h`).
At boot, after the drive found its disk, `bdiskapp_boot` parses it (`ZM GEMDISK
data n`). A bootable disk, a disk that does not parse, or none: nothing happens
(`ZM GEMDISK off rc`), as the browser with `diskApp` false. Each frame, after
`cart.frame()` and before the song bridge, `disk_app_frame` does the three steps
above through the cart's exports (`host_dapp`, generated per cart by
`tools/host_gen.py`; a cart without one gets no call). A request is reported
once, `ZM CARTREQ f req name found`. The listing is the browser's byte for byte,
including what a JS object does to it: a repeated name keeps its first place and
the last entry's values; array-index names (`"0"`, `"17"`) come first in numeric
order; `__proto__` is never listed; a name is UTF-8-decoded with U+FFFD for bad
bytes and a leading BOM dropped, then cut at the first NUL that no line break
follows (`cstr`'s `/\0.*$/`). The one limit beyond the browser's: at most 256
FAT entries (the format holds 24). Where the browser throws (a short disk, no
magic, a corrupt v1 checksum, a FAT past the end, records past the memory's
end), the firmware traps the same way the cart would.

**Proof.** `tests/test_board_gemdisk.py` runs the browser's own `parseDisk` and
listing block in node against `zmd_dir.h` on ST Replay's disk and 11 built ones
(v1, v2 with a date, repeated and array-index names, bad UTF-8, a BOM, NUL cuts,
`__proto__`, more files than the ROM's cap, no files, a type byte past the end,
and every error), at three record layouts. `scene_hash.mjs --data-disk` runs the
loader's step text for text (`apps/scene_hash_disk.mjs`), and the native host's
`--data-disk` equals it: GEM, the mouse onto FLOPPY DISK (40,30), a click, the
double-click pulse, then a double-click on `BOOT.WSM` (75,65) in the window,
40 frames every 5: `IDENTICAL` (`54bb583d…`), the window showing `782756 bytes
used in 2 items` with both icons (without the disk the same clicks give
`Drive A: is empty`, `22934ae1…`). Both report `cart request 3 "BOOT.WSM" (on
the disk)` at frame 32. A bootable disk given as `--data-disk` is refused by
both. **The board-SoC sim** (`tools/hp_sim_run.py gem --frames 12 --every 2
--data-disk st_replay --pointer 2:40:30:0,3:40:30:1,4:40:30:0,5:40:30:2,6:40:30:0,8:75:65:0,9:75:65:2,10:75:65:0`,
`tools/hp_sim_variant.py`: ST Replay's disk in DDR where ZWINDOW puts it, the
image built with `ZM_SIM_POINTER`, the references with `--data-disk` and the same
mouse, run id `gemdisk-b`, 2026-10-11): `ok`, no underrun, frames 2/4/6/8/10/12
`71dbd6ea…`, `51dfe723…` (icon selected), `9fb30d47…`, `bd591683…` (the window
opening), `9f51b9ac…`, `9f51b9ac…` (the listing, `BOOT.WSM` double-clicked), total
`fdeb2e45…` = `scene_hash.mjs --data-disk` = the native host, byte for byte. The
UART says `ZM GEMDISK data 2` at boot and `ZM CARTREQ 9 3 BOOT.WSM 1` at frame 9.

## Programs off a data disk

Double-clicking `BOOT.WSM` in GEM's floppy window makes `pollCartRequest()`
return 3 with the file's name at `getCartTagPtr/Len`. The browser then runs that
FAT file's wasm as the next cart over the same memory, the disk still mounted;
the program quits with request 4 (ST Replay's `X`), and the browser brings GEM
back over the same disk and hands it the listing again (`sealed-loader.js`
`swapCart`). On the board a cart is native code, so the swap is a load by
ZWINDOW of a board image built beforehand. **No register and no RTL change**:
everything below is software over what the PL already has.

**The program's board image** (`tools/glass_shelf.py`). For every program
(type-0 FAT file) on a shelf data disk, the shelf depacks it with the machine's
own depacker (`tools/zx0unpack.zig`, `libs/zig/depackers/zx0.zig`) and finds the
cart whose `docs/demo-<cart>.wasm` has the same bytes (`mkdisks.sh` writes
`BOOT.WSM` from `demo-st_replay.wasm`: they are identical). That cart's board
image (`board/st_replay/fw.bin`, which `make board-shelf` builds) goes into a fat
disk of the **same data disk** at `zigmachine/progs/demo-<tag>/<NAME>.zmd`:
outside the shelf's scan, so the menu never lists it. A program that is no cart
of the matrix, or whose firmware is not built, is `MISSING` in the manifest.

**ZIGGY asks** (`cycles/bdiskapp.c`, `cycles/bcartreq.h`). On request 3 for a
program that is on the disk (type 0; anything else fails in the browser too, and
the cart keeps polling), or on request 4, the firmware writes the **request
block** at window offset `DDR_CART_BYTES - CART_REQ_FROM_TOP` (CPU
`0x41FF_FD00`, between the disk descriptor and the diagnostic's control in the
top 4 KiB the link keeps free), then sets `CART_STATE = CART_REQUEST (4) |
request << 8`. The block (`glass/src/map_cart.zig`, exported to
`gen/glass_cart.{py,h}`): `CART_REQ_MAGIC` ("ZMRQ"), the request, the name's
bytes, `~(magic ^ request ^ bytes)`, then the name (the FAT name it matched, at
most 48 bytes). The name words go first and the magic last; the D-cache is
write-through. The cart keeps running until ZWINDOW holds it. Sim line:
`ZM REQBLOCK magic req bytes check`.

**ZWINDOW swaps** (`glass/src/app_request.zig`, from the watchdog's poll).
While `CART_STATE` says `CART_REQUEST` it reads the block; a block whose check
does not hold yet is polled again, and refused (`BadRequestBlock`) after
`BLOCK_POLLS`. Request 3: the name must be a FAT name (1 to 16 of
`[A-Za-z0-9._-]`, no leading dot: the cart wrote it, so it never becomes a path
of its own, CWE-22), its fat disk must exist under `progs/`, and carry a type-0
file of that name (`NotAProgram`). It is then loaded like any cart (`loader.load`,
the window rewritten, the CPU booted cold), with the descriptor's magic
`DISK_MAGIC_PROGRAM` ("ZMDP"): the same disk is back in DDR, and the program's
firmware (`bdisk_role == BDISK_PROGRAM`) tells it the disk is in but hands no
listing, as the browser's `diskDirSet` is already true then. Request 4 reloads
the shelf entry (GEM over its disk, `DISK_MAGIC`), which hands the listing
again. The shelf entry stays current throughout, so `R` brings back GEM. A
request that fails leaves the cart running with `<name>: <error>` on the status
line, and is not retried until the cart stops asking (a reload).

**What differs from the browser.** The browser runs the program over the SAME
memory (only `hwInit()` again); the board boots it cold over a zeroed window.
Nothing the program reads survives a swap in the browser either (it is a fresh
instance whose `boot()` initialises its statics), but a program that read
memory GEM left behind would see zeros here.

**Proof.**
- `tests/test_board_cartreq.py`: the firmware's block writer (`bcartreq.h`, run
  natively) gives the words of `map_cart.zig`'s rule for request 3 and 4 and a
  name cut at 48 bytes; the block sits between the descriptor and the
  diagnostic; the shelf prebuilds `progs/demo-st_replay/BOOT.WSM.zmd` from
  `board/st_replay/fw.bin` (the same data disk, plus `CART.RV32`), says
  `MISSING` without the firmware or for a program that is no cart; a program's
  sim image carries `DISK_MAGIC_PROGRAM`; ST Replay run as GEM launched it
  (`--data-disk ... --program`, `X` at frame 10) asks for request 4 in the
  native host and `scene_hash.mjs` alike, hashes equal.
- `tests/test_board_disk.py`: ZIGGY takes `DISK_MAGIC_PROGRAM` as a program's
  descriptor and refuses it with the other magic's check.
- `glass/src/app_request_test.zig` (`zig build test`), against the simulated
  glass and DDR: GEM asks for `BOOT.WSM`, the window then holds exactly the
  program's fat disk's plan with `DISK_MAGIC_PROGRAM`; the program asks for 4
  and the window holds the shelf entry's plan with `DISK_MAGIC`; a name with a
  path in it, a missing program disk, a data file, an unknown request and a block
  that never checks each leave the cart running with the reason, handled once.
- The board-SoC sim of GEM opening the floppy and double-clicking `BOOT.WSM`
  (above), rebuilt with this firmware (run id `gemdisk-c`): `ok`, the same hashes
  (total `fdeb2e45…`), and at frame 9 `ZM CARTREQ 9 3 BOOT.WSM 1` then
  `ZM REQBLOCK 51524d5a 3 8 aeadb2ae`: the block read back from DDR through HP0
  with "ZMRQ", request 3, 8 name bytes and the check `~(magic ^ 3 ^ 8)`.

**Not proved without the board:** the ARM reading the block a CPU wrote through
HP0 (the order of the CSR write and the DDR write as the ARM sees them, which is
why the glass waits for the check), and the swap's timing.

## Error handling

| Failure | Detected by | What you see | State left |
|---|---|---|---|
| No or wrong bitstream | `ID` ≠ `ZMGL` | `glass: NoGlass` on the UART, and `S99glass` retries every second | nothing driven |
| `/dev/mem` refused | `open`/`mmap` errno | logged, `glass` exits and is restarted | — |
| Disk unreadable, not a disk, no board image, bad ZX0, too big, a board image that is not the last file (`BadFat`), a shelf disk that does not fit below the pictures (`DiskTooBig`) | parse/depack | the status line shows `<file>: <Error>` | the old cart keeps running |
| CPU will not stop | `STATUS.RUNNING` | `WontStop` | the bitstream is wrong |
| DDR read-back differs | full read-back | `DdrMismatch` | CPU held |
| A lean cart for another system table, or no `system.rv32` on the card ("System image and lean carts") | the cart's header against the system's version | `needs system a.b, card c.d` / `no system.rv32 on the card` | the old cart keeps running |
| The firmware refuses the cart's table, or finds no cart at `CART_IMG_AT` | `CART_STATE` = trapped, `TRAP_CART_ABI` / `TRAP_NO_CART` | `SystemRefused` / `NoCart`; the sim prints `ZM CARTABI ...` | CPU held |
| Firmware traps while booting | `CART_STATE` = 3 | `CartTrapped`, with the code | CPU held |
| Firmware never reports | 2,000 polls of 1 ms | `CartSilent` | CPU held |
| Cart traps later | the watchdog poll | the menu reopens, `cart trapped (code N)` | CPU held |
| Keys arrive faster than the cart drains them | FIFO full | `KEY_OVERFLOW` sticky, the newest key dropped | flushed at the next load |
| A USB device is unplugged | `read` error | dropped, then found again by a rescan every 2 s (`event0`..`event31`, up to 16 nodes) | devices still present stay open (no lost releases) |
| Mouse events faster than the cart polls | — | the newest position wins; a press shorter than a poll is latched | nothing to repair |
| A file on the shelf is not a disk | header parse | listed as `?name` | — |
| Warm reset with no memory to keep | `CART_STATE` = trapped, `TRAP_WARM_LOST` | `warm reset: memory lost, use R` | CPU held; R reloads |
| Reset with no cart loaded | — | `no cart to reset` | nothing touched |
| Cold reset of a disk since removed from the card | file read | `<file>: FileNotFound` | the cart keeps running |
| A cart's swap request it cannot serve (a bad block, a name with a path, no `progs/` disk, not a program, an unknown request) | `app_request.zig` | `<name>: <Error>` on the status line | the cart keeps running; not retried until it stops asking |
| `glass.cfg` bad line | parse | `glass.cfg: bad line N` | that key's default, the rest applied |
| `glass.cfg` cannot be saved | remount / write error | `not saved: <why>` | the change applies, the save stays pending |
| No `shelf.txt`, or bad lines in it | file read / parse | `no shelf.txt: titles only`, `shelf.txt: N bad lines` | titles from the disks' own descriptors |
| No XADC, no `/proc` | file read | `n/a` on the debug page | — |
| Power cut | — | nothing to repair | the SD card is mounted read-only, except during a settings save (`glass.cfg.new` + rename) |

## How it is tested (without the board)

- `make -C fpga check` runs all of the following:
  - `tests/test_rtl_glass.py`: both RTL blocks under CXXRTL.
    - The register testbench drives GP0 the way the PS does, with AW and W in
      every order, B and R back-pressured at random, and garbage on any channel
      whose VALID is low.
    - The OSD testbench sends 8 whole VESA frames (off, centred, a text
      rewrite, the `OSD_STATS` overlay centred and in the corner, a window
      clipped by the right and bottom edges, and windows wholly right of and
      below the screen) and checks every pixel against
      a model built from the font **file**, not from the generated ROM.
  - `tests/test_glass.py`:
    - the Zig tests (`zig build test`), against `sim.zig`, a register file with
      the RTL's rules and a stand-in firmware that boots, traps or stays silent;
    - the cart-side routing (C), including the pointer poll and a cart with no
      `pointer` export;
    - the fat disk;
    - the SD staging;
    - **the load path end to end**: shelf disk + `fw.bin` → zx0pack → fat disk
      → `glass sim-load` → the window must equal `fw.bin`, the shelf disk, its
      descriptor and zeros. It runs on every cart with an `aligned` board image
      (9 today, or about 85 with `ZM_GLASS_ALL=1`), plus a synthetic image.
  - `tests/test_board_disk.py` (the drive, "The disk in DDR"):
    - `host/disk.h` against the browser's own `diskReadBlock`, cut out of
      `sealed-loader.js` and run in node, over 80 (block, dst) pairs on a disk
      with a partial last block and on stniccc's: every answer and the whole
      memory after each call; no disk;
    - `scene_hash.mjs`'s drive is the browser's function, text for text;
    - the firmware's descriptor check, on the descriptor `glass sim-load` writes
      and on six it must refuse;
    - every shelf disk in `docs/` comes back byte for byte through the glass;
    - the glass and `tools/ddr_init.py` put the disk in the same place;
    - the native host with `--disk` equals `scene_hash.mjs --disk` on stniccc,
      and the run without a disk differs.
    - the console page (`console_test.zig`, `menu_test.zig`): cold reset clears
      the window, warm reset keeps it, a warm reset with no memory to keep, a
      reset with no cart and with its disk gone, the volume reaching
      `AUDIO_VOL` and `glass.cfg` and coming back at start, a bad `glass.cfg`, a
      card that will not go read-write, the debug page's live rows;
    - the cart CPU's warm-boot hook (`tests/tb/glass_boot_test.c`);
    - `shelf_meta.py` over the real catalog, and `glass sim-menu` showing a
      `shelf.txt` description;
    - the board device tree compiled with `dtc` (Ethernet node), and the
      Buildroot config carrying DHCP, dropbear and avahi.
- `ZM_RTL_BREAK=1` adds 37 RTL break tests (7 for `AUDIO_VOL` and `CTRL.WARM`,
  12 for `OSD_POS`, `OSD_STATS` and transparency) and
  `tests/test_glass_input.py`'s 43 (the mouse, the pad, the OSD's release, the
  firmware's pointer poll; the console page's 12; the F11 overlay's 9; the
  warm-boot hook's 4),
  each required to fail **at run time**: a mutant that does not compile is
  refused, as it proves nothing.
- The end-to-end test was itself broken once (one word of the image dropped)
  and failed on all 10 images.

## Open: the SoC with the PS7 does not route under openXC7

On 2026-10-02 a full `--target z7 --toolchain openxc7 --build` packed the PS7
(`Created 1 PS7_PS7 cells`) and placed the design. Then nextpnr logged `Tieing
unused PS7 inputs to constants`, and the router's overuse grew every iteration,
from 730 to 1,830 wires over 51 iterations. The run was stopped after 33 minutes.

The same SoC without the glass routes (`f685ee5`). So the suspect is the
hundreds of PS7 inputs, tied to constants through fabric routing into the one
PS7 site.

There are three ways forward:
- tie them in the netlist, so nextpnr has nothing to route;
- find how openXC7's own Zynq examples instantiate the PS7;
- build this one bitstream with Vivado (the documented fallback).

Until then `glass_sd.py` marks the old `platform_z7.bit` STALE, because it has
no glass. `--no-glass` builds the previous SoC.

## Remote shell over Ethernet (near-term)

ssh to the board over its RJ45; no Wi-Fi dongle is needed.

- **Hardware.** The PHY is a Realtek **RTL8201F** (10/100, MII + MDIO; the
  reference manual says "Giga ETH" and "RGMII", but the part and zeST's pinout
  are 10/100 MII). It sits on **PL pins** (`vendor/zest/xdc/z7lite.xdc`: TXD
  M14/L15/M15/N15, TX_EN N16, TX_CLK L14, RXD J14/K14/M18/M17, RX_DV K18, RX_CLK
  K17, MDC G14, MDIO J15; `nRST` H20 in `Z7_LITE.xdc`). zeST reaches it from the
  PS's GEM0 through **EMIO**, and so must we.
- **Linux side (written).** `linux.fragment`: `MACB` (the GEM driver),
  `REALTEK_PHY`, `INET`, `PACKET`, `IP_MULTICAST`. The defconfig:
  `BR2_SYSTEM_DHCP="eth0"` (ifupdown + busybox `udhcpc`, started by
  `S40network`), dropbear (`S50dropbear`) and avahi-daemon (`S50avahi-daemon`):
  Buildroot's own init scripts start them. The DTS enables `&gem0` with
  `phy-mode = "mii"` and no `phy-handle`, so `macb` scans MDIO for the PHY
  whatever its strapped address.
- **PL side (to do).** The bitstream must wire the PS7 cell's ENET0 EMIO ports
  to those pins: `EMIOENET0GMIITXD[3:0]` and `GMIITXEN` out, `GMIIRXD[3:0]`,
  `GMIIRXDV`, `GMIITXCLK`, `GMIIRXCLK` in, and MDIO through one IOBUF
  (`ENET0MDIOMDC`, `MDIOO`, `MDIOTN`, `MDIOI`), plus `nRST` held high. That goes
  into `ps7_gp0` (`soc/zm_glass.py`) and the z7 platform's pins, after the PS7
  routing problem above. zeST's FSBL already enables ENET0 on EMIO. Until then:
  plan B (zeST's own bitstream and Linux) has working Ethernet for a shell.
- **Logging in.** Keys only: root has no password, and dropbear refuses an
  empty one. Put your public key on the card as `authorized_keys` (next to
  `boot.scr`); `S99glass` installs it at boot. Then
  `ssh root@zigmachine.local` (avahi answers mDNS for the hostname
  `zigmachine`), or find the address in your router's DHCP leases, or on the
  UART (`ip addr show eth0`).
- **Cart upload over the network** comes nearly free with it:
  `ssh root@zigmachine.local mount -o remount,rw /mnt/sd`, then `scp
  demo-x.zmd root@zigmachine.local:/mnt/sd/zigmachine/` and remount read-only.
  What is missing is a shelf **rescan** in `glass` (today the shelf is read at
  start: restart `glass` or pick it up on F12), keeping the loaded cart's
  index stable across it.
- Unverified until Buildroot builds the image and the bitstream carries the
  EMIO wiring.

## Future work (recorded, not implemented)

Matt's list (2026-10-03), roughly by value for the effort, with how each would
work on this board:

1. **Cart upload without removing the SD card.** After the remote shell: `scp`
   (above) plus a rescan; later a tiny HTTP upload page served by `glass`, or a
   USB gadget mode (the one USB port is a host, so gadget means a second port).
   The uploaded `.zmd` joins the shelf and loads at once.
2. **Hard-drive emulation.** An ACSI/IDE-like block device for carts, backed by
   an image file on the SD card (as zeST does with `hdd.img`), through the
   existing disk/drive ABI (`diskReadBlock` etc.): the ARM serves blocks into a
   DDR mailbox the firmware maps to the drive ABI. The floppy half is done:
   the cart's own disk is in DDR ("The disk in DDR"). A hard drive too big to
   copy whole needs the mailbox.
3. **CRT screen effects** like Leonard/Oxygene's SC1425 emulation
   (http://leonard.oxg.free.fr/SC1425/SC1425.html): scanlines, shadow mask,
   bloom/glow, curvature, as a post-process in the PL between the mixer and
   TMDS. Line buffers in BRAM, the weights in DSPs; bloom and curvature are the
   expensive parts, so presets that drop them fit the 7010. A menu toggle and
   presets in `glass.cfg`.
4. **An Adebug-like debugger on the ARM** (Brainstorm's ST debugger) for a
   running cart: halt/step the cart CPU, breakpoints, registers, memory view and
   edit, disassembly (rv32, mapped back to the wasm and Zig source), in the OSD
   or over the network. It needs debug support in the cart CPU (VexRiscv's
   debug plugin, or a halt-and-step interface through GP0), and the seal must
   still hold: the debugger sees the machine through the same windows a host
   does, never a cart's private state by a side door.
5. **USB floppy disk support.** A USB floppy drive read by Linux: `.st`,
   `.msa` or `.zmd` image files, or real ST floppies. Limit: USB floppy drives
   speak UFI and read only PC formats (9 sectors, 80 tracks); an ST disk with 10
   or 11 sectors a track, or copy protection, is unreadable this way and needs
   a flux converter (Greaseweazle and the like) instead.
6. **Ethernet for the console, bridged by the ARM.** Carts see a network device
   (a register/FIFO interface in the machine, mirrored in the wasm machine
   first); the ARM bridges it over the wired Ethernet first, Wi-Fi optional
   later through a USB dongle on a hub with its kernel driver in the fragment.

The NICE-TO-HAVE list:

- **Display:** scanlines, scaling, 50/60 Hz, border on or off.
- **Key and joypad remap**; **mouse speed** in the menu (today `--mouse-scale`).
- **Shelf:** favourites, recently played, folders.
- **Screenshot to SD:** the ARM copies the physical framebuffer out of DDR.
- **Save states:** hold the CPU, copy the cart window and the PL's state out;
  restore the same way. Needs every PL register a cart can set to be readable.
- **Settings beyond volume** in `glass.cfg` (the parser already skips unknown
  keys, so an older `glass` reads a newer file).

## What needs the board

1. **GP0 answers.** Run `devmem 0x43C00000` (expect `0x5A4D474C`), then write
   and read back `SCRATCH`. This proves zeST's FSBL leaves GP0 usable with our
   bitstream, and that openXC7 routes the PS7 cell.
2. **The OSD on HDMI.** Set `CTRL` = 2, then write a few text words.
   Steps 1 and 2 have their own bitstream, without the SoC: `make -C fpga osd-test`
   (the OSD over the HDMI test pattern, the register block on GP0), driven from the
   U-Boot prompt by `fpga/tools/osd_uboot_demo.sh` (`md.l`/`mw.l` in place of `devmem`).
3. **The cart CPU running from DDR.** This needs work that is not done here:
   - the HP-port master (today the SoC's `main_ram` is 64 KiB of BRAM);
   - a board firmware: `fpga/cycles/main.c`'s loop, plus `CART_STATE`,
     `CART_BEAT` and `glass_input.c` on the CSRs. The loader waits for
     `RUNNING`; until that firmware exists, run `glass run --no-wait`.
4. **USB:** the ULPI PHY reset on MIO 46 (taken from zeST's PS7 configuration),
   and the HID keyboard mapping on a real keyboard. On real devices:
   - the mouse speed (`--mouse-scale`): a 1,000 DPI mouse moves about 40 counts
     per centimetre;
   - the 400 ms double-click time;
   - a combo receiver, and pads (Xbox, DualShock 4, DualSense, Switch Pro,
     8BitDo) plugged in alongside them. In particular, check the kernel
     fragment's driver names against the kernel Buildroot actually builds.
   A touchpad (absolute `ABS_X` + `BTN_TOUCH`) is not a mouse to `glass`. It is
   ignored.
5. **Plan A:** run Buildroot once (`make BR2_EXTERNAL=… zigmachine_z7lite_defconfig`;
   it needs network access and about an hour). The DTS and the kernel fragment
   are unverified until then.
6. **Timing:** the measured refill and posted-write costs (`FPGA_STEPS.md`).
7. **The console page:** that `AUDIO_VOL` reaches the mixer (once the audio
   path is in the SoC), that a settings save can remount `/mnt/sd` read-write
   and back, and the XADC's iio name (`xadc`) on the kernel Buildroot builds.
8. **Warm reset for real:** a board firmware linking `glass_boot.c` with the
   arena at a fixed address; then W on a cart that keeps state (the Union
   demo's doors) shows it kept.
9. **Joysticks:** the checklist under "The joypad".
10. **Ethernet:** the PL's EMIO wiring, then DHCP, `ssh root@zigmachine.local`.
