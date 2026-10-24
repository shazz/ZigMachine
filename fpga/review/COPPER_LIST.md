# FRESCO copper list (3b): design (2026-10-24)

Matt's decision (2026-10-23) and Fable's review (FRESCO_OPTIONS.md, "Decision 2026-10-24"): a
per-plane list of per-line register writes that FRESCO applies as it composites each line, so the CPU
runs no handler and makes no palette stores for it. The HBL handler stays for racing the beam. Both
machines implement the list: video.zig in the browser, the compositor on the board, same pictures.

## What it buys (board, 3a firmware)

The `hbl` column where it is exposed: tcb_colorshock 0.86 Mc a frame (86 palette words a line from
panHbl, ~28 sys a posted store), swedish_newyear 0.46, union_intro's main screen 0.30, dune_gen4 /
snyd_90 / replicants_emlyn (16-149 entries a line), plus every zg.copper cart's handler calls
(~160-320 sys a line each, mostly hidden under the pass before). A plane whose only handler was its
copper becomes handler-free: it groups without the pure flag, and the dirty-line planner may skip
its lines again (the list is data: a changed list row bumps its line).

## ABI (HW 1.9.0)

`REG_FB_COPPER`, u16 x 4 at 0x78..0x7F (the register block's last free bytes): plane p's list is at
region offset `OFF_VRAM + 16 * v` (VRAM, so the CHISEL and vramAlloc rules apply; 16-byte aligned);
`v = 0`: no list. Latched at the plane's LATCH like FB_BASE. The cart writes the list in frame(); the
drain rule (every store landed before a pass) already covers it.

**Words** (u32, little-endian). A list is a run of LINE RECORDS in increasing raster line:

| word | bits | meaning |
|---|---|---|
| HEAD | `[31:28]=0xF`, `[27:19]` line y (0..279; 511 = end of list), `[9:0]` n | the record of line y has n body words, then the NEXT record's HEAD |
| PAL | `[31:28]=1`, `[27:20]` first entry, `[19:12]` k (1..255) | then k palette words (RGBA, the palette's own format) into entries first..first+k-1 of THIS plane |
| REG | `[31:28]=2`, `[27:20]` register byte offset, `[15:0]` value | a u16 register of THIS plane: HSCROLL+2p only in 1.9.0 (others refused, counted) |
| FLICK | `[31:28]=3` | this plane flickers the border on this line: video.zig's overscan "flick", as if its handler had called flickerBorder(); RES_FLICKER and RESOLUTION are untouched (they stay the handlers' own, so no copy-back is needed and the firmware's group store is unchanged) |
| PALREF | `[31:28]=4`, `[27:20]` first entry, `[19:12]` k | then 1 word: the region offset (VRAM, 4-aligned) of k palette words: a per-row palette table the cart keeps in VRAM (tcb_colorshock's 86 words a line become one changed word a line) |
| NOP | `0` | padding (a record may end on a beat) |
| 5..14 | | reserved: a list that uses one is refused whole (counted), so later ops never change an old list's meaning |

Lines with nothing to write have no record. Why HEAD carries the next record's length: the
compositor fetches a record and the next HEAD in ONE burst (n + 1 words), so a line costs one read
latency, not two; the list's first HEAD is fetched at LATCH.

**When it applies** (both machines): on line y of plane p, AFTER the plane's HBL handler (if any)
and before the line is composited: the board's handler runs before its pass is issued, so the pass
can only apply the list after it. A handler may still write the same entries; the list wins on that
line, as a later write would.

**Region memory**: the browser writes the palette (and HSCROLL) in memory as it applies them, so a
handler or frame() reads them back. The board writes its palette RAM and register copies, and writes
them back to the region at the end of the frame (a WRITEBACK pass: 4 KB of palettes, 512 beats,
~0.5 Kc, only in a frame where a list was active; HSCROLL through the sequencer's copy-back). So
inside a frame, a handler of plane p reading an entry p's list wrote sees it on the browser and not
on the board: ZigOS's copper and linepal install no handler beside their list (FLICK replaces
flickerBorder), and the gate (below) refuses a cart whose plane has both a list and a handler that
reads that plane's palette in a recorded frame.

## RTL (`zm_video_pass.v`, `zm_video_comp.v`, new `zm_video_copper.v`)

- Per plane, latched at LATCH: the list pointer and the next HEAD (fetched then: one beat).
- A pass on line y of a plane whose next HEAD says y: a COPPER phase fetches n + 1 words into the
  fetch buffer (u_fbuf, 2 KB: n <= 511), applies PAL words to the palette RAM (one word a clock),
  REG to the register copy, FLICK to the plane's flick bit, and keeps the new HEAD. On a first-layer
  pass with `fill` (no row LOAD on the read port) the burst and the writes run during FILL; on a
  LOAD pass the burst queues behind the row reads, its writes overlap the load's tail; a held group
  pass pays it serially (~130 comp clocks of latency + n/2 beats + n writes).
- The palette RAM's one write port: the copper phase has it; the snoop cannot write a palette then,
  because the sequencer issues a pass only after every store has landed and runs the next handler
  only after `painted` (which the copper phase precedes). A sticky `collision` status bit counts a
  CPU palette write that arrives during a copper phase (the break test makes one).
- Overscan flick for the pass = the RES_FLICKER rule (zm_video_plane.v) OR the list's FLICK (a bit a plane, set by the record, read at the pass's start).
- WRITEBACK (cmd op 6): the palette RAM out through the row store path (st source mux: 512 beats).
- Estimate: +200-300 LUT, 0 BRAM (u_fbuf and u_pal exist). Baseline zm_video_comp OOC synth 1,775
  LUT, WNS +1.03 ns at 8 ns: OOC synth and the comp-domain timing (125 MHz) before any bitstream.

## Firmware, library, machine

- vseq: a plane whose only handler is gone (the list replaces it) groups as handler-free; WRITEBACK
  after the plane phase when any LATCHed plane had a list; vdirty: a list row that changed bumps
  its line (the planner compares the list's bytes like a plane row).
- ZigOS: `zg.copper` builds a list each frame from its tables (only the rows that change, as the
  hbl dedupes today) and installs no handler (FLICK for `.flicker`); `zg.linepal` the same from its
  colours; a raw `fb.copperList()` for carts that hand-write (colorshock's per-row palette block).
  Carts using zg.copper / linepal do not change.
- video.zig: per line, after hblDispatch: apply plane p's record (the same parser, `machine/copper.zig`,
  natively tested against the RTL's on recorded lists).

## Tests (each with its break)

- RTL replay (tests/test_rtl_video.py): synthetic frames with lists (PAL blocks of 1..255, REG
  HSCROLL, FLICK on mixed lines, lines without records, an end in the middle) against vsynth's
  pictures; breaks: a record applied one line late, FLICK ignored, the next HEAD not kept, a refused
  op applied.
- Exactness gate: video_order_pure.py extended: a cart with a list replays in the board's order.
- Board: tools/board_pic.py on tcb_colorshock, swedish_newyear, union_intro@3000 and two zg.copper
  carts (A/B pictures equal the browser's), then board_fps A/B.
- One hp_sim slot (<= 6 frames) on tcb_colorshock with a list, for the drain/collision path.
