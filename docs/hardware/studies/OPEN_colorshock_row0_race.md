# OPEN: tcb_colorshock's row 0 differs from the browser under plane-major firmware (2026-10-24)

**Status: open, not chased.** Found while proving 3a's pixels (FRESCO_OPTIONS.md 3a,
tools/board_pic.py). To be looked at after 3b.

## What

The card's firmware (system.rv32 53c7a3d1, bitstream d649cd0e, plane-major for a handler plane):
tcb_colorshock's presented picture at frames 150 and 600 differs from the browser's, and the board's
own picture changes from boot to boot. Frames 300 and 900 match.

- Where: raster row 0 only, x 480..793 (picture words 480..793 of row 0).
- What: the blue byte, 0xb4 on the board for the browser's 0x98 (green and red equal).
- How it varies: three boots gave three md5s at frame 150 (242dd3c96904, d175f2d27f41,
  c7225dbc6a1a); two runs within one boot agreed.
- With the 3a firmware (the planes in one line-major group, the pure handlers between passes), the
  same frames equal the browser on every run (f621e5818115 at 150, ee3c7eac78a6 at 600).

A race, then, in today's plane-major path on a handler-heavy cart: panHbl writes ~86 palette words a
line (two planes, the bottom one overscan scroll). Suspects: a palette write of line 0's handler (or
of the previous frame's last lines) not yet in the compositor's palette RAM when the first pass of
the frame reads it, despite the drain rule (cycles/vseq.c drain(); rtl/video/README.md "The drain
rule"; the no-drain mutant never failed on the corpus); or the frame's first PLANE pass right after
LATCH with the clear fused (FILL, no row LOAD to hide behind).

## Repro

On the card image (no bind mounts), from fpga/:

    uv run --with pyserial python tools/board_pic.py --frames 150,300,600,900 tcb_colorshock

Expect frames 150 and 600 to say DIFFER. Reboot the glass (`killall glass`) and run again: the
board's md5 changes. Then, with a 3a system.rv32 bind-mounted, all four frames equal the browser.
Next steps: the same with ZM_NO_FUSE (no CLEAR fusion), and a ZM_VSTAT count of `undrained` on this
cart; an hp_sim run (<= 6 frames) of tcb_colorshock with ZM_VSEQ_CHECK if the board cannot tell.

## 2026-10-24, card update from main f33ce327 (3a in, colorshock now one plane)

tcb_colorshock is one plane since main merged its planes, and its handler is flagged pure (3a), so its
passes run as a one-plane line-major group. `board_pic.py --frames 150,300,600,900 tcb_colorshock` on
the updated card: frame 150 DIFFERED on 1 of 3 runs (equal on the other two), the rest equal. So the
race is not plane-major's: it shows whenever panHbl's ~86 palette stores a line race the frame's first
passes. With 3b (perf/fresco-copper) colorshock makes no palette store at all (its raster is a PALREF
list): run the same check on that bitstream; if it is clean there, the race is in the CPU store path to
the palette (the snoop / drain), not in the compositor.
