# Other FPGA boards on the shelf, and ideas for them

Matt's boards besides the KESTREL board (MicroPhase Z7-Lite, Zynq XC7Z010) and PEREGRINE (the Zynq 7020 big
brother, ordered 14 Nov 2026). Nothing here is planned work: ideas to remember (Matt, 21 Nov 2026: "nothing to do
now"). The roadmap rows are R74 (these ideas) and R75 (the BeMicro sound-chip lab, Matt: "a good idea, i like it").

**The figures below are from memory (lead, 21 Nov), not checked against the boards' manuals**: check the exact
board and chip markings before any work. The Spartan-3E board is assumed to be an XC3S500E one (Starter Kit /
Nexys 2 class).

| | Z7-Lite (XC7Z010), KESTREL | MAX 10 NEEK (10M50) | BeMicro MAX 10 (10M08) | Spartan-3E (XC3S500E?) |
|---|---|---|---|---|
| Logic | 17,600 LUT6 (~28K logic cells) | 50K LE (LUT4), ~ the 7010's fabric | 8K LE | ~9.3K LUT4 |
| Block RAM | 2.1 Mb | ~1.6 Mb | ~0.4 Mb | 0.36 Mb |
| Multipliers | 80 DSP48 | 144 18x18 | 24 18x18 | 20 18x18 |
| Hard CPU | 2x Cortex-A9, Linux (glass) | none (Nios II soft core) | none | none |
| Memory | 512 MB DDR3, shared with the ARM | DDR3 on board | 8 MB SDRAM | DDR (64 MB on the Starter Kit) |
| Video / IO | HDMI out, USB host, SD, Wi-Fi via the ARM | **~5" 800x480 touch LCD**, HDMI TX, Ethernet, audio codec, SD | headers | VGA, PS/2 |
| Tools | Vivado (free) | Quartus Prime Lite (free) | Quartus Prime Lite | ISE 14.7 (frozen) |
| Our cores' clock | 100 / 125 MHz, met | ~60-80 MHz expected | same | ~50 MHz |

Why none runs KESTREL as is: KESTREL leans on the Zynq: the ARM + Linux (glass: OSD, USB, Wi-Fi, SD, the cart
loader), the four HP ports into shared DDR, and Xilinx primitives (PLLE2, ODDR, RAMB36, PS7).

## Ideas

### Portable KESTREL (the easy way): Z7-Lite + a small HDMI LCD + a power bank
- A 5-7" HDMI LCD (800x480 or 1024x600, USB-powered), a USB-C power bank, a pad or a mini keyboard on USB, in one
  case. No port: today's 800x600 output scaled by the LCD; later a 1024x600 output mode for 1:1 pixels.
- PEREGRINE can take the same case. A good prop for the VCF Montreal presentation (KESTREL on a battery).

### Portable KESTREL Lite on the NEEK (the hard way)
- Its screen fits our pictures: 320x200 doubled = 640x400 inside 800x480; 400x280 overscan doubled is 800x560
  (80 lines too tall: crop the overscan or scale it 1.7x).
- The port: ZIGGY + FRESCO + CHISEL + CHORUS on Intel primitives, a DDR3 controller of its own, no ARM side (the
  cart loader, the OSD and input on a Nios or a small RISC-V), ~30 % slower fabric. A large port for a step
  sideways: PEREGRINE is the step up.

### A transportable Atari ST on the NEEK (Matt, 21 Nov: "maybe a day")
- Port zerkman's **zeST** (an Atari ST on Zynq boards; GPLv3, a separate project from ZigMachine) to the NEEK and
  its LCD. zeST also uses the Zynq's ARM (floppy images, configuration, input), so on the NEEK that part moves to
  a Nios II; the ST core itself (fx68k, the custom chips) is plain HDL.
- Alternative base: the MiSTer Atari ST core (`third_party/AtariST_MiSTer`) is already Intel (Cyclone V) HDL,
  but it leans on MiSTer's HPS framework the same way.
- Check the NEEK's DDR3 / SDRAM against the ST core's memory timing, and the 10M50's size against the core
  (fx68k alone is a few thousand LE).

### BeMicro MAX 10: a sound-chip bench
- One chip core alone on real gates, fed by a register dump (the "one dump-player bitstream per chip" idea):
  YM2149, POKEY, a SID, later our own YM2612 (R12) before it goes into KESTREL.

### Spartan-3E
- Retro shelf piece: old tools, little RAM; at most one small chip core.
