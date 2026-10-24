# mpp_truecolor as copper lists: study (2026-10-24)

Study only: nothing here is built. Question: can mpp_truecolor's per-line palettes (today an HBL
handler that copies up to 256 palette words a line per plane) become 1.9.0 copper lists, and what
does that buy per mode?

**Answer: yes, with no hardware change.** Every picture's palette in every mode fits in VRAM next to
the four planes (worst 214 KB of the ~760 KB left). The lists are static per picture and mode (built
once at a switch, never touched per frame), so the CPU makes no palette store per frame. Expected: 60
fps in all three modes (today 60.4 / 53.1 / 27.6). One format detail: PALREF's k is 8 bits (1..255),
so a 256-entry line takes two ops.

## 1. Where the time goes today (board, card_190, 2026-10-24)

board_fps per mode (CYCLE_FRAMES = 480: modes at 2-7 s, 10-15 s, 18-23 s after load):

| mode | fps | missed | passes | seq/pass (sys) | hbl (Mc) | comp/pass (comp clk) |
|---|---|---|---|---|---|---|
| 1 GLOBAL | 60.4 | 0 | 200 | 8192 (paced) | 0.07 | 1879 |
| 2 PER-LINE, 1 plane | 53.1 | 34 | 270 | 6069 | 0.60 | 1344 |
| 3 4 PLANES | 27.6 | 159 | 1120 | 2943 | 1.04 | 2139 (770 grouped) |

The cart's own frame is ~1 Kc: everything is the handlers. What sets the pace is the stores, not the
handler's instructions: the sequencer issues a pass only after every CPU store has landed, so a line
costs its palette stores at the board's store rate.
- Mode 2: 43,019 words stored a frame (p0), 215 a line -> 6069 / 215 = 28 sys a store.
- Mode 3: 54,889 words a frame over 180 lines, 305 a line over 4 passes -> 11,772 / 305 = 39 sys a store.
Both match the measured DDR store cost (18-27 sys, CLAUDE.md "Board speed") plus the handler loop.

Flagging the handler pure (tried, 2026-10-24, not committed) proves this: 4 PLANES then groups
line-major (comp/pass 2139 -> 770, video_order_pure MATCH at 600/1000/1200/1400, board_pic equal),
and the fps does not move (27.8, 53.1). The compositor is not the limit; the stores are.

## 2. The data (apps/zig/assets/screens/mpp_truecolor/p*_m*.bin, measured)

Map: per plane, per line (H = 200) a record {off, first | count << 16}; then the indices; then the
palette (RGB deltas, widened to RGBA by blob.load). Rows 180..199 are the caption (plane 0 only).

| picture | mode 2: colours (KB RGBA) | mode 3: colours (KB RGBA) | mode 3 records (planes 0..3) |
|---|---|---|---|
| p0 | 43,019 (168.0) | 54,889 (214.4) | 200, 180, 180, 180 |
| p1 | 45,063 (176.0) | 53,056 (207.2) | 200, 180, 180, 180 |
| p2 | 40,025 (156.3) | 51,325 (200.5) | 200, 180, 180, 180 |
| p3 | 18,161 (70.9) | 18,161 (70.9) | 200, 180, 180, 180 |
| p4 | 19,097 (74.6) | 19,032 (74.3) | 200, 180, 180, 180 |

Mode 1 (GLOBAL) is one 256-entry record repeated on every line: 1 KB. Mode 2's longest record is 256
entries; mode 3's is 80 (the most a line takes over 4 planes: 320). 181 of mode 2's 200 records
differ from the line above, 716-721 of mode 3's 740.

## 3. VRAM footprint (1 MiB, memmap VRAM_BYTES)

| item | bytes |
|---|---|
| 4 planes 320x200 (ZigOS default, mpp uses all 4 in mode 3) | 256,000 |
| palette table, worst picture and mode (p0 mode 3) | 219,556 |
| 4 lists, 3 words a line (HEAD, PALREF, src) + 2 for a k=256 line + END | 4 x ~3.2 KB = ~13 KB |
| **total** | **~489 KB of 1,048,576** |

It fits, every picture and mode, with ~550 KB to spare: no hybrid, no palette-stream op from cart
RAM, no smaller list format is needed. (Had it not fit, the order would have been: a smaller list
format no, PALREF already is one word a line; a hybrid with plane 0 on PALREF and planes 1-3 on the
handler; last a FRESCO op reading palette runs from cart RAM, which needs a second read window in
zm_video_copper.v and is the only option that costs LUT.)

Only one picture's table is resident: a switch replaces it (the depack buffer on zg.mem stays, as
today, for the map and indices).

## 4. The lists

One list per enabled plane, built at a switch (and at init), never per frame:

    for each line y the plane has a record (count > 0):
        HEAD(y, n)
        PALREF(first, min(count, 255)), src = table + 4 * off/4
        [PALREF(first + 255, 1), src + 1020]        # only a 256-entry line (modes 1 and 2)
    END (line 511)

- Every record line gets its PALREF, including one equal to the line above (the handler skips
  those): cheap (a burst of k words, see 5) and it keeps a frame's first line writing every slot
  after WRITEBACK, the rule zg.copper already follows. Skipping repeats is a later refinement.
- The plane covers logical lines 0..199 (a normal plane): HEAD lines are the record's y. Lines
  without a record (planes 1-3, rows 180..199) get none.
- GLOBAL mode: one record at line 0 (a 256-entry line = two ops), nothing else: the palette holds.
- The handler goes (setFrameBufferHBLHandler is not installed; publishing a list clears the HBL id,
  as zg.copper does). The plane is then handler-free: 4 PLANES groups line-major with no pure flag.
- Filling the table: blob.load decodes the palette in cart RAM as today; then one CHISEL copy (cart
  RAM -> VRAM, ~1 c/B: ~0.22 Mc for 214 KB, `chisel.copyRect` with a 1-row stride) at the switch,
  not 55 K CPU stores (~1.2 Mc). A switch already costs a depack frame; this adds a fraction of one.
- The table and lists are `zg.vramWords` allocations made once at init at the largest picture's size
  (as the depack buffer is), so a switch never allocates.

## 5. Expected cost and fps (FRESCO side; the CPU side goes to ~1 Kc in every mode)

Copper engine cost per record (COPPER_LIST.md, zm_video_copper.v): HEAD+record burst, then the
PALREF burst: ~130 comp clocks of read latency + k/2 beats + k palette writes; on a first-layer pass
with FILL it overlaps the fill, on a held group pass it is serial.

| mode | per line | extra comp clk a frame | today's comp a frame | expected frame (sys) | fps |
|---|---|---|---|---|---|
| 1 | one 256-word load at line 0 | ~0.6 K | 0.30 Mc | ~0.3 Mc | 60 |
| 2 (1 plane, first layer) | 130 + 108 + 215 = ~450, half under FILL | ~65 K (~0.05 Mc) | 0.29 Mc | ~0.35 Mc | 60 |
| 3 (4 planes, grouped) | 4 x (130 + 38 + 76) = ~980, serial | ~176 K (~0.14 Mc) | 0.69 Mc (grouped) | ~0.85 Mc | 60 |

Budget: 1.65 Mc a frame (60 Hz at 100 MHz). Mode 3 is the tight one at ~52 % of it; even if every
PALREF paid the full latency twice over it stays under 1.1 Mc. The dirty-line planner will not help
(vdlist.h counts a PALREF line as changed: its table could change under an unchanged list) and is not
needed.

## 6. Hardware

None. PALREF, the 2 KB fetch buffer and WRITEBACK are in c72c58ca. LUT/BRAM: +0. A 9-bit k (one op
for 256 entries) would save one record word on mode 1/2 lines and is not worth a bitstream.

## 7. Exactness and tests (for the build step)

- The browser applies the same list (machine/copper.zig) after the plane's handler (none) and
  before the line: the per-line palettes are identical to the handler's. scene_hash and the mpp
  harness must stay IDENTICAL (gate `--only mpp_truecolor`), including the frame after a switch and
  the caption band.
- The handler's dedupe (`loaded[]`) becomes moot; its "a repeated record changes nothing" proof is
  replaced by the list's (machine/copper.zig) first-line rule.
- A test that the list carries every record line (apps/copper_lines.mjs reads it back) and a
  `--break` that drops the k=256 tail op (entry 255 then differs on a 256-entry line).
- Board: board_pic at frames in each mode (600, 1000, 1200), board_fps per mode as in section 1.
- Risk: a switch must rebuild table and list before the frame's LATCH reads them; the cart does it in
  update(), the list is read at LATCH after frame(): the same order zg.copper relies on.

## 8. Effort

Cart-only: mpp_truecolor.zig (install/switch: table copy + list build, ~60 lines, a `cop.zig` beside
it as tcb_colorshock has), the harness check, one board A/B. About half a day with the gate.

## 9. Built and measured (2026-10-24, review/mpp-copper, board c72c58ca + card_190 system)

Cart-only, as designed (`apps/zig/scenes/mpp_truecolor/cop.zig`). One correction to section 5's
list: a list names RASTER lines, so a normal plane's line y is HEAD line 40 + y. Proof: scene_hash
IDENTICAL over 7400 frames (every picture, mode and switch); the harness reads every mode's lists
back against the converter's records; `--break k1tail` caught; board_pic equal at 600/1000/1200.

Board, bind-mounted disk, windows placed INSIDE each mode (load + 2 s, then 8 s a mode). Section 1's
windows straddled a switch, and a switch's ZX0 depack costs dozens of frames: PER-LINE's "53.1" was
the depack, not the handler (re-measured inside the mode, the handler cart runs 60 too).

| mode | card (handler) | lists | lists: passes, comp/pass, hbl, swap |
|---|---|---|---|
| 1 GLOBAL (5-10 s) | 60.2 | 60.2 | 280, 1698, 0, 1.13 Mc |
| 2 PER-LINE (13-17 s) | 60.2 | 60.4 | 280, 1655, 0, 1.14 Mc |
| 3 4 PLANES (20-25 s) | 30.1 (147 missed) | 57.7 (11 missed) | 1120, 937, 0, 0.47 Mc |

4 PLANES' FRESCO cost is 1.05 M comp clocks (0.84 Mc), as predicted (0.85). Its remaining misses
are the dirty-line planner's probes (vadapt: 4 PROBE frames every 120; the 25 s sample caught one,
frame 2.06 M with plan 0.35 Mc): every PALREF line counts as changed (vdlist.h), so a probe compares
the whole frame and can never pay. Follow-up (firmware, not done here): do not probe a frame whose
lists name PALREF on most of their lines; that should take 4 PLANES to 60.
