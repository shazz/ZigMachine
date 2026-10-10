# Draft bug reports for openXC7 / Project X-Ray (NOT posted)

Drafts only. Matt decides whether and where to post them (openXC7's nextpnr-xilinx, or f4pga/prjxray for
bitstream database issues). Each one comes from `make -C fpga prim-test`: 45 self-checking lanes, read
with `tools/prim_test_read.py --uboot`. The same RTL passes in simulation (`tests/test_rtl_prim_test.py`)
and, for the RAM and SRL cases, in the full SoC built with Vivado 2026.1.

**Common environment**
- Board: MicroPhase Z7-Lite, xc7z010clg400-1.
- Toolchain: openXC7 toolchain-nix `092acc1e` (nextpnr `c68c1358`, prjxray `3bfaec76`, prjxray-db
  `517d66a3`, nixpkgs `241313f4`, which also pins yosys).
- Flow: `yosys synth_xilinx -flatten -arch xc7` → nextpnr-himbaechel (xilinx) → fasm2frames → xc7frames2bit,
  loaded with openFPGALoader.

Before posting, each should be cut down to a standalone single-primitive top (the lane modules in
`rtl/board/prim_test/` are already close), and the result checked against a Vivado build of the same top.

---

## 1. RAMB36E1 in simple-dual-port 72-bit mode: the low 36 bits read back wrong

**Observed:** an inferred 72-bit-wide, 512-deep simple dual-port memory, written with LFSR data and read
back. On silicon 1024 of 1024 checks fail; the first bad word is `a954aa55`; the bad-bit mask covers bits
2-35 (the A-port half of the 72-bit word). The same happens with 256-deep use and with 8 byte enables.
**Expected:** the data written. The same design passes in simulation (including Yosys's gate-level
netlist with the unisim model), and a Vivado-built SoC with this memory shape works on the same board.
**Impact:** any Yosys-inferred RAM wider than 36 bits is mapped this way. Our workaround: slice wide
memories into ≤ 32-bit RAMs.
**Suspect:** the prjxray-db bits or the nextpnr bel/pin mapping for RAMB36E1 in SDP x72 (the A port's
DIADI/DOADO halves).

## 2. RAMB36E1 in true-dual-port x9 mode: the parity bit (bit 8) is lost

**Observed:** a 9-bit-wide inferred memory mapped to RAMB36E1 TDP x9. 2048 of 8192 checks fail, always on
bit 8 (`0x100`, the DIP/DOP parity bit). RAMB18E1 TDP x9 passes, and so does RAMB36E1 at x1/x2/x4/x18/x36.
**Expected:** all 9 bits.
**Suspect:** the parity-bit (DIPADIP/DOPADOP) routing or init database for RAMB36 at width 9.

## 3. SRL16E / SRLC32E with a clock enable: data wrong

**Observed:** inferred N-deep (16 and 32) delay lines with a clock enable driven by a pseudo-random bit,
no reset; Yosys maps them to SRL16E/SRLC32E. 8050 of 8065 (SRL16E) and 7986 of 8030 (SRLC32E) checks fail,
all 8 data bits.
**Expected:** the delayed data. The same design passes in simulation. In our SoC, synthesising with
`-nosrl` (flip-flops instead of SRLs) removed a picture corruption, and Vivado-built SRLs work.
**Caveat:** this is the least isolated of the three. Before posting, re-test with CE tied high, and with
an SRL instantiated directly rather than inferred, to tell a CE problem from an SRL configuration problem.

## 4. (earlier) OSERDESE2 10:1 master/slave cascade gives no output

**Observed:** an OSERDESE2 10:1 DDR cascade driving a TMDS pair (HDMI): no signal at the monitor, although
the routing was checked in the FASM. A fabric shifter into an ODDR works on the same pins.
**Status:** not isolated further. A single OSERDESE2 (8:1, no cascade) has not been tested.

## Not a bug, but worth a note to openXC7

nextpnr-xilinx does not time paths through the PS7 hard block (the HP AXI ports), so timing-clean builds
can fail on silicon by placement. We register every HP channel at the PS7 boundary.
