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
| `zm_glass_regs` (AXI3 slave, key FIFO, pointer, cart reset, reports) | **done**, 254 LUT | CXXRTL testbench; 13/13 break tests caught |
| `zm_glass_osd` (32×16 text, ST system font, 2×) | **done**, 45 LUT, 2 BRAM | 3 whole 800×600 frames checked pixel by pixel; 6/6 break tests caught |
| In the z7 SoC (PS7 GP0, OSD hook, CPU reset) | elaborates and synthesises; **does not route yet** | whole SoC 4,424 LUT (25.1 %), +355 for the glass. openXC7 packs and places the PS7, but routing diverges (below) |
| ARM program `glass` (loader, menu, keymap, mouse, pad, evdev, `/dev/mem`) | **done**, host-tested | 37 Zig tests, 15 break tests caught; static `arm-linux-musleabihf` binary 4.0 MB |
| Load path, end to end | **done** | the 9 board images `fpga/cycles` links land byte for byte in the fake DDR |
| Cart-side input routing (`glass/firmware/glass_input.c`) | **done**, not yet linked into a firmware | 19 key cases + 7 pointer polls against `sealed-loader.js`'s rules; 3 break tests caught |
| SD card staging (`tools/glass_sd.py`), U-Boot script, DTS, Buildroot tree | **written** | `boot.scr` is byte-identical to `mkimage`'s; the DTS compiles against a stub dtsi |
| Anything on the board | **waiting for the board** | below, "What needs the board" |

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
| `0x04` | `VERSION` | ro | 1.1.0 (1.1 added `POINTER`) |
| `0x08` | `CTRL` | rw | bit 0 `RUN`: 0 holds the cart CPU in reset, and 0 is the reset value. bit 1 `OSD`: show the overlay. bit 2 `KEY_FLUSH`: a strobe that empties the FIFO and clears the overflow flag. |
| `0x0C` | `STATUS` | ro | bit 0 `RUNNING`, bit 1 `KEY_FULL`, bit 2 `KEY_OVERFLOW` (sticky) |
| `0x10` | `CART_STATE` | ro | Written by the cart CPU's firmware: 0 reset, 1 booting, 2 running, 3 trapped (bits 31:8 = the trap code). Cleared while the CPU is held. |
| `0x14` | `CART_BEAT` | ro | The firmware's frame count: the ARM's watchdog |
| `0x18` | `LOAD_BASE` | rw | The DDR address of the cart CPU's RAM (reset value `0x1E00_0000`) |
| `0x1C` | `LOAD_SIZE` | rw | The bytes of image the ARM placed there |
| `0x20` | `KEY_PUSH` | wo | One key event into the 16-entry FIFO. A push into a full FIFO is dropped and sets `KEY_OVERFLOW`. |
| `0x24` | `KEY_LEVEL` | ro | Events waiting |
| `0x28` | `JOY` | rw | Held directions and fire (`JOY_*`) |
| `0x2C`, `0x30` | `OSD_FG`, `OSD_BG` | rw | Ink and paper, `0x00RRGGBB` |
| `0x34` | `SCRATCH` | rw | For bring-up: proves the bus before anything else |
| `0x38` | `POINTER` | rw | The mouse: x (bits 9:0), y (19:10), buttons (23:20). Reads back the cart's view, with SEQ in 31:24. Below, "The mouse". |
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
`glass_pointer`. There are three more that the firmware writes:
`glass_pointer_ack`, `glass_cart_state` and `glass_cart_beat`.

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

## The DDR layout (512 MiB, one MT41J256M16)

| PS physical | Size | Who | What |
|---|---|---|---|
| `0x0000_0000` | 480 MiB | Linux | The kernel, the rootfs in RAM, and `glass` |
| `0x1E00_0000` | 32 MiB | **the cart CPU** | Its whole RAM, seen at `0x4000_0000` (LiteX `main_ram`). Reserved with `no-map` (`zigmachine-z7lite.dts`); plan B uses `mem=480M`. |

Inside the cart window, the layout is exactly the one `fpga/cycles` links
(`cycles.mk`):

- the image (`fw.bin`): code, constants and `.data`'s load copy, from offset 0,
  in 16 MiB;
- `.data`, `.bss`, the heap and a 1 MiB stack, from offset 16 MiB.

The machine's 7 MiB shared memory (cart window, VRAM, PFB, ROM window) is
`calloc`'d from that heap by the firmware, as on the native host. The ARM writes
the image and zeroes everything after it. It never touches anything else.

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
  256 pixels at (144, 172), centred on the 800 × 600 output.
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
- **The menu:**
  - Row 0 is the title bar and rows 2..13 list the disks, the cursor's row
    inverse.
  - Row 15 is the status line: a hint, `loading…`, or the last error.
  - Keys: ↑/↓ move, Enter or Space loads, R reloads the current cart.
  - A joypad works too: the d-pad moves and fire loads.

## Cart load sequence (`fpga/glass/src/loader.zig`)

1. Read `ID`. If it is wrong, stop with `NoGlass`.
2. Parse the `.zmd` (v1 or v2), and find the FAT file of type 3 (`CART.RV32`):
   `NoBoardImage`.
3. Depack it with the machine's ZX0 depacker (an unpacked image is taken as it
   is), and check the result fits the window: `BadImage`, `TooBig`.
   **Steps 1 to 3 touch neither DDR nor the CPU**, so a bad disk leaves the
   running cart running.
4. Clear `RUN`, and check that `STATUS.RUNNING` dropped: `WontStop`.
5. Write the image into the window one word at a time, zero the rest, then read
   the whole window back: `DdrMismatch`. The mapping is uncached, so nothing is
   left in a cache when the CPU starts.
6. Write `LOAD_BASE` and `LOAD_SIZE`, and strobe `KEY_FLUSH`, so no keys typed
   for the menu reach the new cart.
7. Set `RUN`. Poll `CART_STATE` until it reads `RUNNING`: `CartTrapped` with the
   code, or `CartSilent` after 2 s. Either way the CPU goes back into reset.
8. Close the OSD. From then on `glass` polls `CART_STATE` about ten times a
   second. A trap holds the CPU and reopens the menu with the trap code.

Reset (R) is a reload of the same disk. The image in DDR may have been written
by the cart, so re-running it in place would not be a clean reset.

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

## Error handling

| Failure | Detected by | What you see | State left |
|---|---|---|---|
| No or wrong bitstream | `ID` ≠ `ZMGL` | `glass: NoGlass` on the UART, and `S99glass` retries every second | nothing driven |
| `/dev/mem` refused | `open`/`mmap` errno | logged, `glass` exits and is restarted | — |
| Disk unreadable, not a disk, no board image, bad ZX0, too big | parse/depack | the status line shows `<file>: <Error>` | the old cart keeps running |
| CPU will not stop | `STATUS.RUNNING` | `WontStop` | the bitstream is wrong |
| DDR read-back differs | full read-back | `DdrMismatch` | CPU held |
| Firmware traps while booting | `CART_STATE` = 3 | `CartTrapped`, with the code | CPU held |
| Firmware never reports | 2,000 polls of 1 ms | `CartSilent` | CPU held |
| Cart traps later | the watchdog poll | the menu reopens, `cart trapped (code N)` | CPU held |
| Keys arrive faster than the cart drains them | FIFO full | `KEY_OVERFLOW` sticky, the newest key dropped | flushed at the next load |
| A USB device is unplugged | `read` error | dropped, then found again by a rescan every 2 s (`event0`..`event31`, up to 16 nodes) | devices still present stay open (no lost releases) |
| Mouse events faster than the cart polls | — | the newest position wins; a press shorter than a poll is latched | nothing to repair |
| A file on the shelf is not a disk | header parse | listed as `?name` | — |
| Power cut | — | nothing to repair | the SD card is mounted read-only |

## How it is tested (without the board)

- `make -C fpga check` runs all of the following:
  - `tests/test_rtl_glass.py`: both RTL blocks under CXXRTL.
    - The register testbench drives GP0 the way the PS does, with AW and W in
      every order, B and R back-pressured at random, and garbage on any channel
      whose VALID is low.
    - The OSD testbench sends 3 whole VESA frames and checks every pixel against
      a model built from the font **file**, not from the generated ROM.
  - `tests/test_glass.py`:
    - the Zig tests (`zig build test`), against `sim.zig`, a register file with
      the RTL's rules and a stand-in firmware that boots, traps or stays silent;
    - the cart-side routing (C), including the pointer poll and a cart with no
      `pointer` export;
    - the fat disk;
    - the SD staging;
    - **the load path end to end**: shelf disk + `fw.bin` → zx0pack → fat disk
      → `glass sim-load` → the window must equal `fw.bin` and then zeros. It runs
      on every cart with an `aligned` board image (9 today, or about 85 with
      `ZM_GLASS_ALL=1`), plus a synthetic image.
- `ZM_RTL_BREAK=1` adds 19 RTL break tests and `tests/test_glass_input.py`'s 18
  (the mouse, the pad, the OSD's release, the firmware's pointer poll), each
  required to fail.
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

## What needs the board

1. **GP0 answers.** Run `devmem 0x43C00000` (expect `0x5A4D474C`), then write
   and read back `SCRATCH`. This proves zeST's FSBL leaves GP0 usable with our
   bitstream, and that openXC7 routes the PS7 cell.
2. **The OSD on HDMI.** Set `CTRL` = 2, then write a few text words.
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
