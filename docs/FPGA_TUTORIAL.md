# Running your Zig screen on the real ZigMachine (the FPGA board)

A walk from "I have a scene in `apps/zig/scenes/`" to "it is on a monitor, driven by a RISC-V
core in a Zynq". Every command below was run on the dev box on 2026-10-09 except the ones that
touch the board (it was in use); those are copied from the tools' own headers and
`fpga/boards/microphase_z7_7010/README.md`, and marked **(board)**.

Companion docs: [`fpga/README.md`](../fpga/README.md) (the tree, the Makefile targets),
[`docs/FPGA_STEPS.md`](FPGA_STEPS.md) (the plan and the measurements),
[`fpga/boards/microphase_z7_7010/README.md`](../fpga/boards/microphase_z7_7010/README.md) (the board, the U-Boot
procedure, the lessons), [`fpga/CYCLES.md`](../fpga/CYCLES.md) (which carts fit).

## 1. What the board is

A **MicroPhase Z7-Lite** (Zynq XC7Z010, 512 MB DDR3 on the PS side).

- **The PL (FPGA fabric) runs the machine.** A VexRiscv RISC-V core (the "cart CPU", rv32im, no FPU)
  runs your cart; the video (800x600 HDMI scan-out, compositor, blitter) is RTL. It is built with
  **Vivado**. The cart CPU has no RAM of its own: its 32 MiB main RAM is **PS DDR at `0x0400_0000`**,
  reached over the AXI HP0 port; the video DMA writes pictures over HP1.
- **The ARM (PS) only does I/O, and for now it only runs U-Boot** (from the SD card, zeST's
  `BOOT.BIN`). You type at U-Boot's prompt over the serial console to put the firmware in DDR and
  release the cart CPU. The Linux "glass" program (keyboard, menu, disk loading) is written
  ([`docs/FPGA_GLASS.md`](FPGA_GLASS.md)) but is not what runs today.
- **Carts stay wasm.** A scene is built to `docs/demo-<name>.wasm` exactly as for the browser; the
  FPGA flow translates it with wasm2c to C and compiles that for RISC-V together with the machine
  and the ROM.

## 2. Prerequisites

| Need | Check |
|---|---|
| Vivado ML Standard 2026.1 at `/opt/vivado/2026.1`, licence in `~/.Xilinx/Xilinx.lic` (node-locked to the wired MAC) | `ls /opt/vivado/2026.1` |
| Vivado wants `libncurses.so.5`/`libtinfo.so.5` (Ubuntu dropped them): symlinks to the `.so.6` in `~/.local/lib/vivado-compat`, put it in `LD_LIBRARY_PATH` | `ls ~/.local/lib/vivado-compat` |
| `openFPGALoader` (it loads the bitstream over JTAG; cable name `digilent_hs2`) | `openFPGALoader -c digilent_hs2 --detect` should list the xc7z010 |
| RISC-V toolchain `riscv64-unknown-elf-gcc` + picolibc (the firmware) | `make -C fpga setup` reports what is missing |
| Zig 0.16 (`~/.local/zig/0.16.0`), `uv`, `clang`, node | for the cart and the host reference |
| Your user in the `dialout` group (the CH340 console `/dev/ttyUSB*`) | `id -nG`; the tools below are run under `sg dialout -c "..."` |

Cables and jumpers:

- **JTAG: USB-C `J6`** (FT232HL, loads the PL). **UART: `J3`**, a CH340 at **921600 baud**: this is
  U-Boot's console (PS MIO14/15). Both to the PC.
- **Jumper `J1` on SD** (boot from the card). In JTAG mode no FSBL runs and DDR is never initialised.
- **SD card** with zeST's `BOOT.BIN` for the Z7-Lite 7010 (its FSBL brings up DDR, clocks and MIO and
  starts U-Boot). `fpga/tools/fetch_board.sh` fetches it pinned and checksummed (under
  `fpga/boards/microphase_z7_7010/vendor/zest-bin/`); copy `boot.bin` to the card as `BOOT.BIN`.
- HDMI1 on a monitor.

Setup, once: `make -C fpga setup` (submodules, uv env, sv2v and wasm2c pinned).

## 3. From a scene to a firmware image

### 3.1 The cart

A scene `apps/zig/scenes/<name>.zig` (registered in `catalog.zig`, see `docs/BUILDING.md`) is built by
the normal build into **`docs/demo-<name>.wasm`**. While iterating, `./build.sh --only <name>` (under
`flock prototypes/_gate_logs/build.lock`, as the repo's `CLAUDE.md` demands) rebuilds just it. That
`.wasm` is the cart; the FPGA flow never reads the Zig. The cart name is the file name without
`demo-` and `.wasm`: `union_beatdis`, `tutorial`, ...

### 3.2 The firmware

```sh
make -C fpga board-fw CART=union_beatdis ZM_BLIT=sw ZM_AUDIO=0
# -> fpga/build/hcycles/board/union_beatdis/fw.bin
```

The real variables are in `fpga/cycles/board.mk`:

| Variable | Default | Meaning |
|---|---|---|
| `CART` | none | the cart name, as above |
| `ZM_BLIT` | `hw` | `hw`: `hwBlit()` runs on the RTL blitter over HP2 (`cycles/bblit.c`), so the **bitstream must have been built with `--blit`**. `sw`: the machine's software blitter on the cart CPU; works with a bitstream without it. The blitter bitstream is `build/board_hp/zm_blit_vivado_100.bit` (2026-10-10: `--blit --vivado-explore`, 100 MHz, with audio); run it with `board_run.py --blit`, which also sets HP2's AFI width |
| `ZM_AUDIO` | `1` | `1`: the SNDH players run on the cart CPU into the audio core (`cycles/baudio.c`). `0`: no music. The SoC's audio core is work in progress (section 6), and the current bitstream predates it: **use `0` with it** |

What `fw.bin` contains (one flat image, linked at the start of the cart CPU's RAM window, whose
first word is the reset vector):

1. the **cart**, wasm2c'd then compiled for `rv32im` (`-DZM_NO_BOUNDS -DZM_ALIGNED`: no per-access
   bounds check, because on the board the bus window seals the cart; aligned wasm accesses become one
   `lw`/`sw`);
2. the **machine** (`machine.wasm`: video model, blitter, HW registers) and the **ROM** (`rom.wasm`:
   the GEM/helpers the carts call), same treatment;
3. the **sequencer firmware** (`cycles/bmain.c`, `vseq.c`, `bboard.c`, `bmailbox.c`, `bdiag.c`,
   `bblit.c`, `host/boot.c`): it calls `cart.frame()` once per VBL, drives the machine's render, tells the video
   RTL what to scan out, and reports to the glass registers and the debug mailbox. With
   `-DZM_BOARD` it runs forever and prints nothing.

Rules the build enforces: the image must stay under 12 MiB (above, it would overlap the pictures at
DDR `0x04c0_0000`), and `tools/cycles_csr.py --hp-check` **refuses to link if the firmware's CSR map
differs from the bitstream's** (the header comes from the simulation's `csr.json`). If you change the SoC, you
rebuild the firmware.

Takes about 1 minute (the first time per cart a native audio host also runs to pack the songs; with
`ZM_AUDIO=0` its output is unused). Use `flock fpga/build/fable_timing3/.container.lock` in front if
another session may be building (the shared build tree).

### 3.3 Check it in simulation first

```sh
make -C fpga hp-sim CART=union_beatdis ZM_BLIT=sw ZM_AUDIO=0
```

This runs the **board SoC** (`soc/hp_sim.py`: the same VexRiscv, glass and video DMA, with a model of
the PS's DDR behind HP0/HP1) in Verilator, 10 frames hashed every 5, and compares the frame hashes
with `apps/scene_hash.mjs` and the native host. Verdict printed at the end (see the result in
section 9). It is slow: the simulator runs about 0.7 M cycles per second.

## 4. The bitstream

The current board bitstream is **`fpga/build/board_hp/zm_hp_vivado_100.bit`** (Vivado, SoC clock
100 MHz, no blitter, no audio core). Rebuild it with the exact command of `fpga/README.md`,
"Bitstreams" (about 3 minutes; the free licence, no ILA):

```sh
cd fpga
export PATH=/opt/vivado/2026.1/Vivado/bin:$PATH LD_LIBRARY_PATH=$HOME/.local/lib/vivado-compat
uv run python -m soc.zigmachine_soc --target z7 --build --toolchain vivado --sys-mhz 80 --comp-mhz 80 --out build/soc_z7_vivado
```

That command is the README's 80 MHz one; for the 100 MHz bitstream change `--sys-mhz`/`--comp-mhz`
(the `*_100.bit` and `*_80.bit` files in `build/board_hp/` were produced that way and copied there;
the bitstream lands under `build/soc_z7_vivado/gateware/`). Add `--blit` for the hardware blitter
(then build the firmware with `ZM_BLIT=hw`) and `--no-audio` to leave the audio core out. A firmware
built for one CSR map only runs on a bitstream with that map: if you change the flags, rebuild
`board-fw` too.

Do **not** rebuild if you only changed a cart or the firmware: that is "seconds", not "minutes" (the
table "When is a full rebuild needed" in `fpga/README.md`).

## 5. Running it **(board)**

State of the world before you start: SD in, `J1` on SD, USB-C JTAG and UART connected, HDMI on a
monitor, board powered.

1. **Get the U-Boot prompt.** Open the console (`picocom -b 921600 /dev/ttyUSB0`, or let the tools
   do it) and press **RST KEY** on the board; U-Boot waits a moment at autoboot, so hit Ctrl-C to
   get `Zynq>`. The tools do this for you: they send Ctrl-C every 0.1 s until the prompt shows (a
   missing prompt is an error, exit 2).
2. **Optional health check** (loads the `hp_test` bitstream and bursts on HP0/HP1):
   ```sh
   sg dialout -c "uv run --with pyserial python fpga/tools/board_preflight.py"
   ```
   Exit 0 = both ports pass; `HP<n> WEDGED: press RST KEY` = an AFI is stuck, reset the board.
3. **Upload the firmware by hand first** (see the traps: `board_run`'s own upload can fail). From the
   host, with U-Boot at its prompt:
   ```sh
   uv run --with xmodem --with pyserial python fpga/tools/uboot_loadx.py \
       fpga/build/hcycles/board/union_beatdis/fw.bin 0x04000000
   ```
   It types `loadx 0x04000000`, sends the file by XMODEM-1K and prints U-Boot's byte count (rounded
   up to 1 KiB). (The DDR content survives a PL reload.)
4. **The run**, one command: load order, CRC check, run, verdict, screenshot:
   ```sh
   sg dialout -c "uv run --with pyserial --with xmodem python fpga/tools/board_run.py \
       --bit fpga/build/board_hp/zm_hp_vivado_100.bit \
       --fw fpga/build/hcycles/board/union_beatdis/fw.bin --shot union_beatdis --secs 5"
   ```
   Flags: `--bit` and `--fw` (required), `--shot <name>` (a `board_shot.py` dump to
   `fpga/build/shots/<name>.*.png`), `--secs` (how long to watch the frame counter, default 5),
   `--preflight`, `--diag 3|4`, `--hp-cfg N`, `--tty`. What it does, in this order: `CTRL 0` + 1 s,
   load the PL with openFPGALoader, set the AFI widths, **skip the upload if the CRC already in DDR
   matches** (that is why step 3 comes first) and abort if the CRC after upload is wrong, release `CTRL.RUN`, watch
   `CART_STATE`/`CART_BEAT`/`FRAMES` advance, print the verdict. Exit 0 PASS, 1 FAIL, 2
   board/console problem. The picture is on the monitor from this point.
5. **A screenshot** at any time (the cart is frozen after a whole frame, the picture dumped with
   `md.l`, ~40 s, then resumed):
   ```sh
   # at the U-Boot prompt first:  dcache off
   sg dialout -c "uv run --with pyserial python fpga/tools/board_shot.py --out fpga/build/shots/mine"
   ```
   `--what picture|fb0|fb1|pfb` (default `picture`: what is shown; `pfb`: the machine's palette-frame
   buffer exactly as `scene_hash` sees it, and `--expect <file>` compares it with a native-host dump
   `HOST_DUMP_PFB=<file> fpga/build/host/<cart>/host docs/demo-<cart>.wasm N N`), `--keep-frozen`.
6. **By hand, from U-Boot** (what `board_run` does; the manual table is in the board README,
   "Running a cart from U-Boot"):
   ```
   dcache off
   mw.l 0xf8008000 0; mw.l 0xf8008014 0xf01; mw.l 0xf8009000 0; mw.l 0xf8009014 0xf01   # AFI widths, PL loaded first
   md.l 0x43c00000 8        # ID 5a4d474c, CTRL (word 2) 0
   mw.l 0x43c00008 1        # CTRL.RUN: the cart CPU boots from DDR 0x04000000
   md.l 0x43c00010 2        # CART_STATE 2 = running, CART_BEAT counting ~60/s; 3 | code<<8 = trapped
   mw.l 0x43c00008 0        # stop;  reload the image, then mw.l 0x43c00008 1 to restart
   ```

## 6. What works, what does not (2026-10-09)

Works:
- A cart with a **picture only and no input** runs: the first cart on a real monitor was shown on
  2026-10-09 (commit `f01b5b7`), the board SoC closes at 100 MHz under Vivado.
- Overscan/rasters (HBL is an interrupt of the cart CPU), the compositor, 800x600 HDMI.
- Hashes in simulation equal `scene_hash.mjs` (section 9).

Does not (yet):
- **Sound.** The audio core and the SNDH players on the cart CPU are in progress
  (`docs/FPGA_AUDIO_CPU.md`, `cycles/audio.mk`, `soc/zm_audio_soc.py`; uncommitted work). The current
  bitstream has none, so build the firmware with `ZM_AUDIO=0`: the screen is silent.
- **Keyboard and joypad.** Input comes from the ARM-side glass over GP0 (`docs/FPGA_GLASS.md`), which
  needs Linux on the ARM. With U-Boot only, a cart that waits for a key (gem, st_replay, fullscreen,
  north_south, dhs_0pxl0reg, ulm_dsots, the menus) stays on its first screen.
- **Disk streaming.** `diskReadBlock` returns 0, so stniccc (`SCENE1.BIN`) and stream-based carts
  show nothing useful; the `.zmd` loading belongs to the glass too.
- **The hardware blitter** runs on the board since 2026-10-10 (`zm_blit_vivado_100.bit`, `ZM_BLIT=hw`,
  `board_run.py --blit`): `blitter` ~45 fps and `tsl_hybridglenz` ~38 fps, both pixel-exact against the
  native host (`board_shot.py --what pfb`, 0 pixels off). If an op never finishes, the cart traps with
  `CART_STATE` = `0xB1xxxx03`: `xxxx` is the engine's state (`cycles/bblit.c`). The one cause seen so far is
  a **wedged HP2 AFI** left by an earlier hang: it survives PL reloads, a board reset clears it, and
  `board_preflight.py --ports 4` (the `hp_test --ports 4 --toolchain vivado` bitstream) tests HP0-HP3.

**The budget.** The SoC is at **100 MHz**, so a 60 Hz frame is **1.67 M cycles** (the board counts a
wasm2c'd cart's cycles with the HP-DDR penalties; the table "MHz soft+DDR" and the
`aligned`/`hp_wc` columns in `fpga/CYCLES.md`). Rough fit, from the p95 MHz needed at the board's
memory model (`fpga/CYCLES.md`, "Sim fidelity"): **tutorial** (~26-36 MHz), **union_beatdis**
(~55-93 MHz sustained, 122 on its worst frame: it fits at 100 with little room), **ulm_dsots**
(~100, needs input), **skystrike** (~115-120, does not fit steadily at 100). **polkadots**
(2262 MHz) and **replicants_emlyn** (550) do not fit; **stniccc** costs almost nothing on the CPU
but needs the disk. When a frame overruns, the cart simply runs below 60 fps (the picture is still
correct). Re-measure with `make -C fpga cycles CARTS="..."`.

## 7. Traps

1. **Load the PL before touching the AFI registers** (`0xf800_8000`, `0xf800_9000`): they answer only
   while the PL drives the HP clocks; before that the ARM hangs.
2. **Never reload the PL mid-DMA.** `mw.l 0x43c00008 0` (CTRL.RUN off), wait 1 s, then load.
   `board_run` does this; by hand you must. A cut burst leaves an AFI wedged, which survives PL
   reloads: only **RST KEY** clears it.
3. **Never change an AFI width while traffic runs on that port.**
4. **After a bitstream without GP0 (blink, hdmi_test, edid_test, ym_test, hdmi_audio) never touch
   `0x43c0_xxxx`:** the access hangs the ARM until RST KEY. `board_run`/`uboot_serial.py` track the
   last bitstream they loaded in `fpga/build/.board_pl` and skip the `CTRL 0` quiesce for those; if
   you loaded one by hand (openFPGALoader directly), the tool does not know.
5. **Catching the prompt.** U-Boot autoboot is short: RST KEY, then Ctrl-C every 0.1 s. The tools do
   it; by hand, hold Ctrl-C.
6. **`board_run`'s own xmodem upload can fail** (timing on the 921600 console): upload with
   `uboot_loadx.py` first and let `board_run` skip it on the CRC match. If the CRC check after its own
   upload aborts, that is this.
7. **`dcache off`** before any `md`/dump of DDR the cart wrote, otherwise the ARM reads its cache.
8. **A firmware is tied to its bitstream's CSR map** (the link refuses otherwise), and `ZM_BLIT=hw`
   needs a `--blit` bitstream: a mismatch traps the cart (`CART_STATE` `3 | code << 8`).
9. **RTL portability (Vivado and Yosys both read it):** no `wire a, b = expr;`; no identifiers that
   are Verilog-2001 keywords (`cell`, `config`, `design`, `instance`, `library`, `use`, ...); Yosys lets
   them pass and Vivado does not. Reset-less data slots in queues are required for 100 MHz closure
   (commit `e6fa662`). The free licence **refuses ILA**.
10. **One build at a time on the box** (the repo gate lock, and `fpga/build/fable_timing3/.container.lock`
    for the shared container), and no `pkill -f`.
11. **Do not run any of the `(board)` commands while another session uses the board.**

## 8. Debugging

- **Diag modes** (`fpga/cycles/bdiag.c`): the same `fw.bin` runs a write-path diagnostic *instead of*
  the cart when the ARM has put `47414944` at DDR `0x05fffe00` and a mode at `0x05fffe04` before
  `CTRL.RUN`: 1 CPU stores, 2 CPU loads, 3 video DMA BG+MIX passes, 4 a MIX pass from a PFB row the
  ARM wrote. `board_run.py --diag 3|4` automates 3 and 4; `0x05fffe08 = 0xc0f0000c` selects the video
  DMA write mode. `CART_STATE = 0x44 | mode << 8` when done, `CART_BEAT` the result.
- **The mailbox** at DDR `0x05ff_ff00` (`cycles/bmailbox.h`): `md.l 0x05ffff00 10` shows magic
  `424d4d5a`, the two pictures (`0x04c0_0000`, `0x04d0_0000`), the presented/frame counts, the PFB
  address and size. `board_shot.py` reads it to freeze and dump.
- **The GP0 glass registers** at `0x43c0_0000` (`docs/FPGA_GLASS.md`): `+00` ID `5a4d474c`, `+04`
  VERSION, `+08` CTRL (bit 0 RUN, 1 OSD, 2 KEY_FLUSH, 3 WARM), `+10` CART_STATE, `+14` CART_BEAT, ...
  `md.l 0x43c00000 16` is the first thing to look at.
- **Observing a signal with no ILA:** route it into a glass register (**`SCRATCH`, `0x43c0_0034`**
  or a new read-only CSR), rebuild the bitstream, read it with `md.l 0x43c00034 1` from U-Boot (or
  poll it from `board_diag.py`). Count events with a counter in a register rather than trying to
  catch a pulse.
- **PFB vs picture:** `board_shot.py --what pfb --expect <native dump>`: a difference there is the
  compositor's or the CPU's; a clean PFB under a bad picture is the scan-out's.
- **HP-port questions without the CPU:** `make -C fpga hp-test` (bitstream with raw AXI engines,
  ~7 min once), then the table in the board README.

## 9. Verification log (dev box, 2026-10-09)

- `make -C fpga board-fw CART=union_beatdis ZM_BLIT=sw ZM_AUDIO=0`: OK, 56 s,
  `fpga/build/hcycles/board/union_beatdis/fw.bin` 282,768 bytes.
- `make -C fpga hp-sim CART=union_beatdis ZM_BLIT=sw ZM_AUDIO=0`: `hp union_beatdis rc=0 ok`, 21 min
  (the command-line variables reach the sub-makes through MAKEFLAGS; the UART log shows `ZM BLIT 0 0 0`,
  i.e. the software blitter). Frame hashes from the board SoC in Verilator:
  frame 5 `1ad76fb0...2165`, frame 10 `abd24953...9ccc`, total `d088f0e4...f97e`.
  `node apps/scene_hash.mjs docs/demo-union_beatdis.wasm 10 5` prints the **identical** three hashes.
  The log also reports `ZM VSTAT 0 0 9 152 0` (no video underrun) and `ZM END 0`.
- No step failed, so no workaround is needed. Note that `hp-sim` takes the same `CART`/`ZM_*` variables as
  `board-fw` but builds its own `sim` image (`build/hcycles/sim/<cart>/fw.bin`); it does not test the
  `board` image byte for byte (the board one is compiled with `-DZM_BOARD`: run forever, report to the glass).
