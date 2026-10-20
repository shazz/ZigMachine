# MicroPhase Z7-Lite, XC7Z010-1CLG400

`tools/fetch_board.sh` fetches everything below, pinned to commits and
checksummed. **None of it is committed:** MicroPhase's XDC carries "Publication
of this design is not authorized without written consent from MicroPhase", and
zeST is GPL-3. `.gitignore` keeps `board.xdc`, `vendor/` and any `ps7_init*`
out of git.

| File | Source | Used for |
|---|---|---|
| `board.xdc` | MicroPhase's `Z7_LITE.xdc` (Vivado 2018.3, 2022), via `leecurrent04/MicroPhase-Z7-Lite-Board` | every PL pin. `soc/platform_z7.py` reads it, so no pin is typed anywhere else |
| `vendor/Z7-LITE_R11.pdf`, `vendor/Z7-Lite_Reference_Manual.md` | MicroPhase's own `fpga-docs` on GitHub | the schematic and the manual: clocks, DDR part, pin tables |
| `vendor/xc7z010clg400pkg.txt` | Xilinx's package file | maps a pin *function* (as the schematic names it) to a ball |
| `vendor/zest/` | [zeST](https://codeberg.org/zerkman/zest) (GPL-3), an Atari ST on this exact board | its Z7-Lite XDC and its Vivado PS7 configuration (`zest_z7lite.tcl`) |
| `vendor/zest-bin/…/boards/z7lite_7010/boot.bin` | zeST release 20260518 | **a working PS7 init (DDR3, clocks, MIO) without Vivado:** its FSBL and U-Boot bring up the ARM side |

## Verified

- **Three public copies of the MicroPhase XDC have the same pin map** (103 ports):
  `leecurrent04`, `hw/Microphase-Z7-Lite`, `tcmichals`.
- **Every HDMI pin was re-derived independently from the schematic** and the
  Xilinx package file, and matches the XDC: CLK U18/U19, D0 V20/W20, D1 T20/U20,
  D2 N20/P20, HPD P19, SCL R19, SDA T19 (TMDS_33). zeST's own XDC agrees.
- **Clocks:** `PL_CLK_50M` is on N18 (50 MHz, PL). The PS crystal is 33.333 MHz
  on E7.
- **DDR3:** one 16-bit MT41J256M16 (512 MB). The manual's pin table has D0–D15
  only, and zeST's PS7 config says `16 Bit`, `MT41J256M16 RE-125`. One community
  `preset.xml` claims 32 bits: it is wrong for this board.
- **UART:** PS MIO14/15 only, so the ARM owns it. The VexRiscv console on the
  `z7` target is `jtag_uart`, over the board's USB-JTAG.
- **`make soc` and `--target z7`** elaborate against this XDC. A Yosys synthesis
  of the whole SoC gives 2,408 LUTs (13.7 %), 1,874 FF, 4 DSP and 19 + 8 BRAM.

## The ARM side (`ps7_init`)

There is no `ps7_init.c` for the **7010** in any public repo:
`BeatSkip/Z7-Lite-Z7020-Linux` has one for the 7020 with a different DDR part.
Two routes:

1. **No Vivado (recommended first):** boot zeST's `boot.bin` for the 7010. Its
   FSBL initialises DDR, clocks and MIO, and U-Boot can then load our bitstream
   (`fpga load`) or Linux can, through the FPGA manager.
2. **Our own FSBL:** generate `ps7_init` once with Vivado or Vitis `xsct` from
   zeST's `zest_z7lite.tcl` PS7 block (zeST's `setup/recipes/fsbl.sh` does
   exactly this).

## Programming the PL over JTAG (openFPGALoader)

The board's USB-JTAG is an FT232HL (USB `0403:6014`) with a 93LC56 EEPROM,
wired like a Digilent JTAG-HS2. openFPGALoader names that cable `digilent_hs2`
(`src/cable.hpp`: `FTDI_SER(0x0403, 0x6014, FTDI_INTF_A, 0xe8, 0xeb, 0x00, 0x60)`).
The bitstream goes to the PL's SRAM only (lost at power-off); the PL clock is the
board's own 50 MHz oscillator, so `blink_top.bit` needs nothing from the ARM side.

1. **Boot mode:** set jumper **J1 to JTAG** (the manual's *Boot Config* table,
   `vendor/Z7-Lite_Reference_Manual.md`). In QSPI/SD mode a FSBL on the card or
   flash may reconfigure the PL behind you.
2. **udev, once:** openFPGALoader ships `99-openfpgaloader.rules` (group
   `plugdev`) and `70-openfpgaloader.rules` (no group, use `dialout`):
   ```sh
   sudo cp 99-openfpgaloader.rules /etc/udev/rules.d/
   sudo udevadm control --reload-rules && sudo udevadm trigger
   sudo usermod -a -G plugdev $USER   # then log out and back in
   ```
3. **See the chain:** `openFPGALoader -c digilent_hs2 --detect` should list the
   xc7z010 (and the ARM DAP). If the cable is not found, check `lsusb` for
   `0403:6014`; if it is found but the chain is empty, check J1 and the power.
4. **Load:**
   ```sh
   openFPGALoader -c digilent_hs2 fpga/build/blink/blink_top.bit
   ```
   PL_LED1 and PL_LED2 then alternate, 0.5 s each. **Second step, HDMI:**
   `make -C fpga hdmi-test` (`rtl/board/hdmi_test_top.v`; `make -C fpga hdmi-test-sim`
   checks the pattern in CXXRTL and writes it as PNGs), then
   `openFPGALoader -c digilent_hs2 fpga/build/hdmi_test/hdmi_test_top.bit` with HDMI1
   on a monitor: 800x600@60 colour bars, castellations, a bouncing orange box and
   four 8-bit ramps inside a 1-pixel white frame; PL_LED2 lit (PLL locked), PL_LED1
   blinking at 1 Hz off the 40 MHz pixel clock. Bring-up variants of it,
   `make -C fpga hdmi-test-{oddr,clkonly,lvcmos,rev,inv}` (the Makefile says what
   each changes), land in `build/hdmi_test_<variant>/`. The full SoC loads the same
   way: `openFPGALoader -c digilent_hs2 fpga/build/soc_z7/gateware/<name>.bit`.

The `.bit` files come from `make -C fpga blink` / the SoC's `--toolchain openxc7
--build`, through `tools/openxc7.sh` (openXC7 in Docker, pinned in
`docker/openxc7/`). openFPGALoader is not in that image: it needs the USB device,
so install it on the host (`apt install openfpgaloader`, or a release build).

## Running a cart from U-Boot (the cart CPU in PS DDR)

The glass SoC (`soc/zm_z7.py`, `--target z7`) keeps no RAM of its own: the cart
CPU's 32 MiB main RAM **is PS DDR at `0x0400_0000`**, reached over **S_AXI_HP0**,
and the video DMA uses **S_AXI_HP1** (`soc/zm_board_mem.py`, `soc/zm_hp.py`). The
CPU's reset vector is the first word of that window, and the glass holds the
CPU in reset until CTRL.RUN. So U-Boot alone (zeST's `BOOT.BIN`, no Linux) runs
a cart: put the image in DDR, set the HP ports, load the PL, release the CPU.

```sh
make -C fpga board-fw CART=tutorial    # -> fpga/build/hcycles/board/tutorial/fw.bin
make -C fpga hp-sim CART=tutorial      # the same SoC + image in Verilator, hashes vs scene_hash
```

Order matters: **load the PL first**. The AFI registers (`0xf800_8000`,
`0xf800_9000`) answer only while the PL drives the HP ports' clocks; touching
them before hangs the ARM (found on the board, 2026-10-03).

| # | Where | Command | Expect |
|---|---|---|---|
| 1 | host | `openFPGALoader -c digilent_hs2 fpga/build/board_hp/zm_hp_wr32_s5_comp120.bit` | HDMI 800x600 comes up (noise or black: nothing is drawn yet) |
| 2 | U-Boot | `dcache off` | the ARM's caches flushed and off: U-Boot's writes reach DDR, its reads see it |
| 3 | U-Boot | `md.l 0xf8000240 1` · `md.l 0xf8000900 1` | FPGA_RST_CTRL `00000000` · LVL_SHFTR_EN `0000000f`. If RST_CTRL is not 0: `mw.l 0xf8000008 0xdf0d; mw.l 0xf8000240 0` |
| 4 | U-Boot | `mw.l 0xf8008000 0; mw.l 0xf8008014 0xf01; mw.l 0xf8009000 0; mw.l 0xf8009014 0xf01` | HP0/HP1: **reads 64-bit, writes 32-bit** (`soc/zm_hp.py` "WR32") |
| 5 | U-Boot | `md.l 0xf8008000 6` · `md.l 0xf8009000 6` | word 0 = `00000000`, word 5 = `00000f01` on both. **Check it**: a 64-bit write channel loses no data now, but a WRONG value here is the first suspect |
| 6 | host | `uv run --with xmodem --with pyserial python fpga/tools/uboot_loadx.py fpga/build/hcycles/board/tutorial/fw.bin 0x04000000` (or `fatload mmc 0 0x04000000 fw.bin`) | the byte count (loadx rounds up to 1 KiB) |
| 7 | U-Boot | `crc32 0x04000000 <size in hex>` | equals the host's `crc32` of fw.bin |
| 8 | U-Boot | `md.l 0x43c00000 8` | ID `5a4d474c`, CTRL (word 2) `0` |
| 9 | U-Boot | `mw.l 0x43c00008 1` | CTRL.RUN: the CPU boots from DDR `0x0400_0000` |
| 10 | U-Boot | `md.l 0x43c00010 2` | CART_STATE `1` then `2` (running), CART_BEAT counting ~60/s; `3 \| code << 8` = trapped |
| 11 | host | `sg dialout -c "uv run --with pyserial python fpga/tools/board_shot.py --out fpga/build/shots/tut"` | freezes the cart after a whole frame, dumps the shown picture (~40 s), PNG + .bin, resumes |

**The debug mailbox** (`cycles/bmailbox.h`) is at DDR `0x05ff_ff00`:
`md.l 0x05ffff00 10` shows its magic `424d4d5a`, the two pictures (fixed: DDR
`0x04c0_0000` and `0x04d0_0000`), the frame count and the PFB's address.
`board_shot.py --what pfb --expect <file>` dumps the machine's PFB instead and
compares it with the native host's (`HOST_DUMP_PFB=<file> fpga/build/host/<cart>/host
docs/demo-<cart>.wasm <N> <N>`, N = the frozen frame it printed): a difference
there is the compositor's or the CPU's, a clean PFB under a bad picture is the
scanout's.

**The video DMA's write mode** is a run-time choice (CSR `video_hp_cfg`, set by the
firmware at reset from DDR `0x05fffe08` when it reads `c0f0000c`): `c` = 0 4-byte
beats, AWCACHE 0, the AFI expands them (the default); 1 the same with AWCACHE
0b0011 (the AFI may upsize: what corrupted the rows on 2026-10-03); 2 whole
8-byte beats, for a **64-bit** write channel (`WRCHAN_CTRL = 0xf00`). Both halves change
together or every other word is lost: `board_run.py --w64` sets HP1 to 0xf00 and `hp_cfg` 2 for
a diag run, and under Linux `glass run --fw-opt=2` holds the cart, sets HP1's width (read back)
and writes the tag word for every cart it loads (`fpga/glass/src/afi.zig`; a glass run without
it, or a reboot, puts 0xf01 back). The write-path
diagnostic (`cycles/bdiag.h`, magic `47414944` at `0x05fffe00`, mode at `+4`) runs
in place of the cart: 1 CPU stores, 2 CPU loads, 3 BG + MIX passes, 4 a MIX pass
from a PFB row the ARM wrote.

To restart: `mw.l 0x43c00008 0`, reload the image (the CPU's reset does not
reset its memory), `mw.l 0x43c00008 1`.

## hp-test: the HP ports from U-Boot, no CPU, no compositor

`make -C fpga hp-test` (`soc/zm_hp_test.py`; ~7 min, once: it changes only with the bridges) builds a bitstream with only the
PS7's HP0/HP1, the board SoC's own HP masters (`WishboneHP`, `ZMVideoAXI`, imported as
they are) plus a raw AXI engine per port, and registers on GP0 (`0x43c0_0000`). Load it,
then steps 2-5 of the table above (the AFI widths), then:

| Offset | Port bank (HP0 `+0x100`, HP1 `+0x200`) |
|---|---|
| `+00` CTRL | write: bit 0 GO, 1 WRITE, 2 CHECK (compare reads with the pattern), 3 BRIDGE (the SoC's own master instead of the raw engine; change only while idle), 4 LINE (HP0 bridge: 8-word line-refill bursts), 5 LANE (narrow beats: STRB[3:0] and the compared word in the lane the address picks, as a 64-bit channel wants) |
| `+04` ADDR `+08` LEN `+0c` SIZE `+10` CACHE | DDR byte address; AxLEN (beats-1, ≤15); AxSIZE (3 = 8 bytes); AxCACHE. HP1 bridge: CACHE[1:0] is `hp_cfg` (UPSIZE, W64). Bridges fold ADDR into the cart window `0x0400_0000-0x05ff_ffff` |
| `+14` COUNT `+18` STRB `+1c` SEED | raw: bursts, back to back; HP0 bridge: 32-bit words; HP1 bridge: 64-bit beats (≤1023). WSTRB / read-compare byte mask. Beat k = SEED+2k (low word), SEED+2k+1 (high; the low word again for SIZE < 3) |
| `+20` STATUS `+24` BEATS `+28` ERRS | [0] busy [1] done [2] a non-OKAY response [5:4] the last one; data beats; mismatches (CHECK) |
| `+2c` CYCLES `+30` FIRST `+34/38` D0 `+3c` BADIDX | cycles of the run and to the first beat/response (at `MHZ`); the first beat (low, high); the first bad beat |

Global: `+00` ID `48505431`, `+04` scratch, `+08` MHz, `+0c` a free-running counter.
PL_LED1 blinks (~0.75 Hz) when the PL runs, PL_LED2 is lit while a run is in flight.

```
md.l 0x43c00000 4                     # 48505431 00000000 00000064 <counting>
mw.l 0x43c00104 0x05000000; mw.l 0x43c00108 0xf; mw.l 0x43c0010c 3; mw.l 0x43c00114 4
mw.l 0x43c00100 3                     # HP0 raw: WRITE|GO, 4 bursts of 16 x 8 bytes
md.l 0x43c00120 8                     # STATUS 2 = done, BEATS 0x40, ...
md.l 0x05000000 8                     # 10000000 10000001 ... (64-bit channel) or every odd word stale (WR32)
mw.l 0x43c00100 5; md.l 0x43c00120 8  # CHECK|GO: ERRS (+28) 0 if what was written reads back
mw.l 0x43c0010c 2; mw.l 0x43c00110 3; mw.l 0x43c00100 3   # 4-byte beats, AWCACHE 0011: the upsizing question
mw.l 0x43c00214 0x190; mw.l 0x43c00210 0; mw.l 0x43c00200 0xb; mw.l 0x43c00200 0xd   # HP1: ZMVideoAXI row write, then check
mw.l 0x43c00114 0x40; mw.l 0x43c00100 0xb; mw.l 0x43c00100 0x1d   # HP0: WishboneHP stores, then line refills
```

## Lessons (2026-10-03)

- **Load the PL BEFORE touching the AFI registers** (`0xf800_8000`, `0xf800_9000`): without
  the PL's HP clocks they never answer and the ARM hangs on the access.
- **Never change an AFI width (RDCHAN/WRCHAN_CTRL) while PL traffic runs on that port**: it
  hangs the port (and the ARM with it). Set the widths with the PL idle (cart CPU held in
  reset, no hp-test run in flight), then start traffic.
- **RST KEY recovers** a hung PS/ARM: a full reset, then U-Boot again from step 1.
- **Never reload or replace the PL while an HP DMA may be mid-burst.** First `mw.l 0x43c00008 0`
  (CTRL.RUN off: the SoC's video DMA then takes no new request and finishes the one in flight,
  `soc/zm_video_axi.py` `enable`), wait a moment (`sleep 1`), then load. An hp-test run must
  be idle too (`md.l 0x43c00X20` STATUS bit 0 clear).
- **A write channel's width can go 64 -> 32 at run time, never 32 -> 64** (2026-10-19). A channel
  that has carried 32-bit writes and is then set 0xf00 reads back 0xf00 but writes only words 0 and
  3 of every 16 bytes; set 0xf00 before its first write it writes every word. W64 therefore needs
  HP1 0xf00 from boot (`prototypes/w64_re/boot_w64.py` replays boot.cmd that way), and glass
  refuses `--fw-opt=2` on a 32-bit channel.
- **A wedged HP AFI survives PL reloads.** A burst cut by a reload leaves the AFI (PS side)
  waiting for its data: every later write on that port hangs (no WREADY/B), on any bitstream,
  while the other port works (2026-10-03: HP1 hung on hp-test's raw engine, HP0 fine). **RST
  KEY clears it.** The SLCR route, unlock `0xf8000008 = 0xdf0d`, pulse FPGA_RST_CTRL
  `0xf8000240` bits 20/21 (FPGA_AXDS0/1_RST, named in Xilinx's ps7 register database; this
  TRM copy calls them reserved), lock `0xf8000004 = 0x767b`, then the AFI widths again, is
  **unverified**.
- **The SoC's video DMA idles until CTRL.RUN**, so a fresh bitstream sends nothing on HP1
  before U-Boot has set the AFI widths.

## Tools: preflight and board runs (automate the manual procedure above)

Both drive the U-Boot console through `tools/uboot_serial.py` (waits for the `Zynq>` prompt; a
missing prompt is an error) and need `sg dialout`, pyserial, and for the upload xmodem. **Never run
them while another session uses the board**: a reload mid-burst wedges an AFI.

```sh
sg dialout -c "uv run --with pyserial python fpga/tools/board_preflight.py"
sg dialout -c "uv run --with pyserial --with xmodem python fpga/tools/board_run.py \
    --bit fpga/build/board_hp/zm_hp_gated_s1_sys80.bit --fw fpga/build/board_hp/fw_tutorial_diag5.bin \
    [--diag 3|4] [--hp-cfg N] [--shot name] [--preflight] [--secs 5]"
```

- `board_preflight.py [--bit X] [--tty T]`: Ctrl-C every 0.1 s to the prompt, `CTRL 0` + 1 s, loads
  `build/hp_test/gateware/zm_hp_test.bit`, `dcache off`, AFI widths, checks the hp-test ID, then on HP0
  and HP1 a raw 4 x 16 x 4-byte write burst + CHECK readback (STATUS/BEATS/ERRS and the first DDR
  words), and a ZMVideoAXI row write on HP1. Prints PASS/FAIL per port; exit 0 only if both pass,
  1 on a failed port, 2 if the console/hp-test ID is wrong. A port busy with 0 beats prints
  `HP<n> WEDGED: press RST KEY`.
- `board_run.py`: `CTRL 0` + 1 s, loads the PL, AFI widths, uploads the firmware to `0x04000000`
  unless the crc already in DDR matches (saves ~25 s), then checks DDR's crc32 against the file's
  (mismatch aborts, exit 2). Then the cart (CART_STATE 2, CART_BEAT and FRAMES advancing over `--secs`)
  or `--diag 3|4` (mailbox resets, RUN, wait for `CART_STATE 0x<mode>44`, rows and the probe at
  `0x05f80c00` compared to the values in `build/board_hp/MORNING.md`; a hang is reported with its
  wait# and AXI STATUS). `--shot` runs `board_shot.py`, `--preflight` runs the above first.
  Exit 0 PASS, 1 FAIL, 2 board/console error.
- Tests: `tests/test_board_tools.py` (in `make -C fpga check`) run both against a pty fake U-Boot
  (`tests/fake_uboot.py`) with openFPGALoader and the XMODEM upload mocked.

## prim-test: every primitive mode, checked on silicon

`make -C fpga prim-test` (`rtl/board/prim_test_top.v`) builds a bitstream with no CPU and no video:
45 lanes, one per block-RAM / LUTRAM / SRL / DSP48E1 / CARRY4 / MUXF mode the SoC uses (plus the
suspect ones: RAMB18 SDP x36 at 512 and 256 words and in the upper half, x72, byte enables, TDP at
every width, whole-word and per-byte write enables). Each lane writes an LFSR pattern and its inverse, reads them back and compares with a
reference built in the fabric. They run once at load (~3 ms at 50 MHz); results on GP0. Lane list
and what each maps to: `tools/prim_test_read.py` `LANES`. Clock: PL_CLK_50M, so no FCLK is needed.

| step | where | command | expect |
|---|---|---|---|
| 1 | host | `openFPGALoader -c digilent_hs2 fpga/build/prim_test/prim_test_top.bit` | PL_LED2 blinks (~1.5 Hz); PL_LED1 lit only if EVERY lane passed (x72 is expected to fail, so dark) |
| 2 | U-Boot | `md.l f8000900 1` | `0000000f` (PS-PL level shifters on). If not: `mw.l f8000008 df0d; mw.l f8000900 f`. **Never touch 0x43C0xxxx otherwise: the ARM hangs** |
| 3 | U-Boot | `md.l 43c00000 9` | word 0 `5052494d` ("PRIM"); +08/+0C PASS mask, +10/+14 DONE mask (`ffffffff 00001fff`: 45 lanes), +18 = `0000002d`, +1C runs, +20 seed |
| 4 | U-Boot | `md.l 43c00800 168` | 45 lanes x 8 words: STATUS (`c00000nn` = done+pass, `800000nn` = FAIL), ERRORS, FIRST_IDX, FIRST_GOT, BAD[31:0], BAD[63:32], BAD[95:64], CHECKS |
| 5 | host | paste steps 3-4's output into a file: `uv run python fpga/tools/prim_test_read.py dump.txt` | the PASS/FAIL table (or `--uboot` to send the two `md.l` itself) |

- **Restart:** `mw.l 43c00004 1` (clears, new seed). **Soak:** `mw.l 43c00004 3` loops with the results
  accumulating; `mw.l 43c00004 0` stops after the run in progress; `md.l 43c0001c 1` is the run count.
- **FIRST_IDX** = `{pass, write-phase, ..., address}` of the first wrong word for a RAM lane, the
  vector number for the others. **BAD** = the OR of `got ^ expected` over every error: which bits ever
  went wrong (for x72, bits 0-35 = the A half); for a byte-enable lane the table also names the byte
  lanes that failed (`[bytes 1,2 of 4]`).
- Then update `fpga/silicon_prims.json` (`proven` / `bad`) from the table: `make -C fpga prim-allow`
  checks the board SoC's netlist against it, and `make check` runs the same (`tests/test_prim_allowlist.py`).
- Not covered: ODDR and the PLL (proven by every HDMI bitstream; an ODDR can only drive a pad, and no
  board wire loops one back), the PS7, OSERDESE2 (not used: its 10:1 cascade never worked).
