# Transmission64 2021 invitation — how it works, and how the port does it

**Transmission64 Invitation**, Padua, C64, released 19 February 2021 (invitation to the
Transmission64 online party, 24 April 2021). Code Anonym, Dano, Doomed, Hoogo ("hidden" part);
graphics Sander; music Toggle ("Transmission 64"). CSDb release 200255, demozoo 290038.
Cart `c64_transmission64` (120), `apps/zig/scenes/c64_transmission64*`.

**Permission.** Padua's crew gave Matt the go-ahead to port it ("go ahead"), in person at VCF
Montreal.

## The short answer

- **Three parts and two wipes, one file.** The PRG is Bitnax-crunched; the program inside
  decrunches parts 2 and 3 itself, in memory, while a border-bar wipe plays.
- **Part 1** (frames 1-726): rings of dither characters ripple out over the very screen you
  typed RUN on. 24 rings, a character code each; a 17 KB generated routine writes every ring's
  cells, or puts the boot screen back where a ring is empty, **racing the beam** for most of a
  frame.
- **Wipe 1** (727-865): screen off; seven border colour bars, 1 to 8 lines thick, slide down an
  easing curve (128 steps), purple above them, light blue below.
- **Part 2** (866-3012): the Transmission64 logo, a multicolour bitmap drawn all in purple: it
  appears only through colour. Radio rings around the antenna (a generated 561-store routine),
  shifted out every 6 frames and flashed in time with the tune (the player's `$0C1E`, `$0C22`);
  the big arc coloured band by band, then faded, by the main loop rewriting rows 10-19 of screen
  and colour RAM — again racing the beam, interrupted halfway by the IRQ.
- **Wipe 2** (3012-3150): the same code, which patched its own colours: purple to black.
- **Part 3** (3151-, forever, a 969-frame cycle): 35 points on Lissajous sums of sines (ten
  shapes), drawn as depth-sized dots into a 256x192 charset "bitmap" (four charsets, an NMI
  switching them every 64 lines), double-buffered in VIC banks 0 and 3, the nearest dots as
  sprites; between shapes, a border flash and the info panel rolled in and out row by row.

## Getting at the code

| | |
|---|---|
| File | `transmission64-2021.prg`, 34517 bytes, md5 `6885aa9f4f78111565cb2eff9ad1d201` (CSDb 200255) |
| Load | `$0801`, BASIC `SYS 2078` |
| Packer | Bitnax; `exomizer desfx` emulates the stub all the same: `$0801-$FEE8`, entry `$2800` |
| Music | PSID Transmission_64.sid (HVSC `/MUSICIANS/T/Toggle/`), byte-identical at `$0C00` |

`$2800` first sends M-W commands to drive 8 (code uploaded into the 1541: Hoogo's "hidden"
part lives there; part 2 later sends it `U3`). That serial transfer takes 33 or 34 frames
depending on the run, so the port's frame clock starts at **part 1's first IRQ ($2B7B, line
248) = frame 1**; from there VICE's runs agree frame for frame, except right after part 2's
drive command (see below).

Main sequence (`$080E`): wait for part 1, `$D011 = $0B`, decrunch `$A800..` (in-memory, routine
at `$0200`), wait for the wipe, `JSR $4000` (part 2), decrunch `$DBF8..`, wait, `JMP $3808`.
The tools dump RAM where each part starts (`$2B7B`, `$4062`, `$3808`) rather than decrunch.

## Part 1 ($2800; IRQ $2B7B on line 248)

`$2966/$2978/$29AE/$2A24/$2B45`: the character ROM's upper case set copied to `$2000`, 8
characters redrawn (dithers), 8 screen codes of the boot screen swapped for them, the screen and
colours saved to `$7400/$7800`.

IRQ: the music (`$0C03`), then `$2C80` (the rings), then `$2C00` (the step):
- **`$2C80`** (generated, `$2C80-$73C2`): for each ring from `$27` (outermost) to `$10`: `LDX
  ring; BNE draw; JMP restore`; draw = `STX cell / STY colour` (`LDY #$0E`, light blue) for every
  cell of the ring; restore = `LDA $74xx / STA $04xx / LDA $78xx / STA $D8xx`. 1000 cells over
  24 rings (parsed by the rip tool, which checks both paths cover the same cells in the same
  order). It runs from line ~258 to line ~216 of the next frame (~17000 cycles).
- **`$2C00`**: every 3rd frame every ring's code moves one ring out and the centre takes the next
  of 242 codes (`$7C00`); after the last, `$0F` is set: the IRQ hands over to `$0986`.

**The race.** A cell shows its new code in a frame only if both stores land before the VIC
fetches it on its row's bad line (the c-access of cell c is at cycle 15 + c; the 6510 stops on
reads from cycle 12 to 54 of a bad line, a store at 12-14 still goes through). The port times
every store with a bus-cycle clock (`clock.zig`): **every one of ~1700 stores a frame lands on
VICE's traced cycle** (`tools/rings.py`, frames 600-602; the one missing in each trace is
`capture.py`'s own line-10 break swallowing a store). Where `$2C80` starts depends on how long
the SID player ran: measured in VICE for the 726 frames (`part1.bin`), +1 cycle (VICE's break
stops one cycle before the opcode fetch).

## The wipes ($0986, $0861, $08CB, $09CE)

`$0986` (line 248): music, screen off, ten frames. Then two IRQs a frame:
- `$0861` at line L: seven `STA $D020`, each followed by a delay routine `$0A9D..$0AE6` taking
  exactly 1..8 lines (63n cycles; the JSRs' low bytes patched from `$0A0D`): bars 1..8 lines.
- `$08CB` at line 292 (308 when L >= 256, 300 the first time): two border colours off screen,
  the music, then the next L from `$0B00/$0B80` (an easing curve, 128 steps) and the next delay.
  Its `$D012` write lands ~12 lines in; the first time (line 300 + 12 = the next frame's line 0)
  it misses L = 0, so frame 738 has no bars at all.
- After 128 steps `$09CE` (line 251) releases the main loop, and `$08CB` has patched its own
  colours (`$0877 $087F $08A7 $0902 $0912 $0917`): the second wipe runs purple to black.

## Part 2 ($4000; IRQ $4175 on line 248)

Init: bitmap at `$2000`, screen `$0400`, purple everywhere (`$44`), its tables (`$411A`),
`$D011 = $3B` (frame 870), the logo overlaid from `$6000` (non-zero bytes only, ~8 frames,
invisible: every colour is purple), the antenna sprite (block `$80` = the bitmap's first 64
bytes, multicolour, at `$B8,$89`), then `$43FA`: `U3` to drive 8 with the IRQs off (frame 874
has no IRQ).

IRQ: music; frame counter `$8240`; **`$4700`** (generated: LDA/ORA/AND/LDX + STA/STX, 561
stores) paints the radio rings from 25+25 colour nibbles (`$4500` low, `$4600` high); every 6th
frame `$434F`: when the tune's `$0C1E` is `$B2` or `$A0` (its second time, then every other)
the centre takes 8 flash colours (`$43F2`), then `$4391` shifts every ring one out (its loop's
`BNE` jumps into the middle of the fade subroutine `$43BA` and returns from there: one pass of
four, the outer ring fading 1-7-3-E-4); `$41FE` sets `$D025/$D026` from `$0C22`. From counter
`$076A` only the shift, from `$0838` nothing (`$41D0` patched to 0).

Main loop: 16 times, `$421B` (then `$42AD`) builds 256 colours from a 16-byte window of `$7900`
(low nibble `tbl[x & 15]`, high `tbl[x >> 4]`) and copies them through the maps `$7000/$7200`
into rows 10-19 (256 + 144 cells): the arc's bands appear, then fade. The copy runs ~200 lines
and **the IRQ interrupts it** (~100 lines from line 248): the port's clock jumps from the IRQ's
entry to its RTI, both measured per frame. Also modelled: sprite 0's DMA on lines `$89..$9D`
(the antenna: reads wait from cycle 55 to 60), and `$42AD`'s second loop's BNE crossing from
page `$43` back to `$42FC` (4 cycles). With those, every store of the copies lands on VICE's
cycle.

Measured in VICE (`part2.bin`): per frame the IRQ's entry, its `$4700` start and RTI, the two
music flags; the frames and start cycles of the 16 copies. The first copy (frame 876) follows
the drive command, and VICE itself differs by 3 cycles there from run to run (the 1541
handshake): that frame depends on the run.

## Part 3 ($3808)

IRQ chain (VICE's probe, `tools/probe3.py`):

| Handler | Line | Frames (first cycle) | Does |
|---|---|---|---|
| `$3D30` | 248 | 3152-3155 | music, while the main loop generates the shape's code |
| `$3D79` | 49 | dots frames | screen on, charset 0, CIA 2 timer B: NMI (`INC $D018`) every 64 lines |
| `$40AA` | 248 (242 once) | 3156-3628, then every 969 | invalid mode (black), the bank of the buffer drawn last, music, sprites, the dots |
| `$3DC1` | 248 (writes at next line 0) | 3629-3640 | border flash `$3E43`, screen off |
| `$3E52` | 248 | 3641-4014 | panel rolled in (5 frames a row: codes +4..+0), held 250 frames |
| `$3F3D` | 248 | 4015-4114 | panel rolled out (+1..+4, then the row cleared) |
| `$4016` | 248 (writes at next line 0) | 4115-4125 | flash back, the dots' colours restored |

**The charset bitmap.** Screen `$0800`/`$C800`: 32 columns x 24 rows, each 8-row band using
chars 0..255 (column 36 repeats the next row's first char, in black). `INC $D018` reads bit 0 as
1, so each NMI adds 2: charsets `$2000, $2800, $3000, $3800` (bank 0) or `$E000..$F800` (bank 3)
for the bands starting at lines 51, 115, 179, 243.

**The dots.** `$41BD` is generated by the main loop (`$3A64`) from a 24-byte shape record
(`$C600`, ten of them): for each of 35 dots, x = `(T0[a + i*sa + X] + T0[b + i*sb + Y]) >> 1`
(a 9-bit sum, CLC/ROR per dot), y the same from `T1`, depth from `T2` with one CLC for the axis
and LSR, so each dot's low bit carries into the next; then the phases X, Y move on. The record's
`$C610` and `$C611` are both stored into `$14`: `$15` is never set and runs on from its value at
entry. Plot (`$4630/$4685`): depth page `$BA + z (+ carry)`; `$C0` = a sprite (`$3991`, up to 8:
X `$38 + x`, Y `$32 + y`), else routine `(x & 7) | ((y & 7) << 3)` of that page: 768 routines
`$46DA-$B91C` of `LDY/LDA/ORA ($16),Y/STA/INY/INC $17` (parsed into stores by the rip tool), the
matching erase routine and address remembered per dot (`$0400-$05FF`). The dot count follows
`$C780` while zooming in or out (`$24`, 111 frames each way: `LDA #n / BPL`, so 110 + 1).

**The half-generated code.** When a zoom-in ends, the IRQ releases the main loop to generate the
next shape; the next IRQ runs `$41BD` while the generator is only 18-21 dots into the depth
section: x and y are the new shape's, depth the old one's for the dots not yet rewritten (and the
old phase step). That frame's sprites survive the panel (they show on the first frame after it)
and the depth phase of the whole next shape changes. Measured in VICE: the generator's write
pointer and Y at that IRQ for 20 shape changes (`part3.bin`; beyond, the table repeats).

## Music

Transmission 64, Toggle (Tobias Göhlke), 2021 Padua. PSID v2, load/init `$0C00`, play `$0C03`,
1 song, PAL, 8580 (flags `$24`). HVSC `/MUSICIANS/T/Toggle/Transmission_64.sid` = CSDb's
`Toggle_-_Transmission_64_8580.sid` (md5 `53b214e31189106ecfb556fe05e15935`), byte-identical to
`$0C00` of the program (the rip asserts it). Played once a frame by every IRQ chain; frame 874
misses one (part 2's drive command). Licence: as the ST ports ship SNDH from the archive, the
port ships the HVSC file. Played from the cart's memory by the `.sid` player (cRSID,
`requestSongBytes(.sid)`) on its own 50 Hz clock: the part-2 flashes keyed to `$0C1E/$0C22`
follow the original's frame count, so they can drift from the audio by the difference between
the cart's 6/5 frame step and the player's rate.

## The port

**The C64 is modelled, not imitated.** `vic.zig` (+ `vic_line.zig`, `vic_sprite.zig`,
`vic_store.zig`) draws what the VIC-II shows from a 64 KB copy of the C64's memory, a frame's
register writes and the CPU's timed stores: text, multicolour text, (multicolour) bitmap, ECM,
the invalid modes, eight sprites, the vertical border flip-flop with DEN/RSEL, a border colour
split mid-line; a row's screen bytes and colours latched on its bad line, as the VIC does. Each
part's IRQ chains are ported as the writes and stores they make (`part1.zig`, `wipe.zig`,
`part2*.zig`, `part3*.zig`, sequenced by `show.zig`/`show_seq.zig`), the racing ones timed by
`clock.zig` (6510 bus cycles: bad-line and sprite-0 stalls, an IRQ taken at an instruction
boundary). What part 3 does after the window (drawing into the hidden buffer, the panel's rows)
runs straight into the RAM copy after the frame is drawn. No float anywhere; the generated code
is folded back into loops over the parsed operands.

On the machine: one 400x280 overscan plane (as 1988), physical row = line - 11, column = X + 16,
so the C64's window is the machine's window. **No border is ever opened here**, so no flicker;
the border colour is a real raster, per line BACKGROUND (global HBL) and the plane's colour 0
(its HBL). The wipes' bars are those border colours changing between lines (their writes land
at cycles 6-8: whole lines). 50 Hz on 60: C64 frame n on machine frame ceil(6n/5). Palette:
colodore (VICE's `colodore.vpl`), C64 colour c at index c + 1.

### How exact (measured)

- **The port vs VICE 3.9 x64sc**, frame by frame (`tools/c64/t64_show.zig` + `compare.py` over
  `capture.py` shots in `vice/`): part 1 **25/25**, wipe 1 **151/152**, part 2 **41/43**, part 3
  **52/52** (two shape cycles sampled: dots, flashes, panel in/held/out, flash back, the second
  and later shapes). The misses: the same single pixel twice, VICE's 8565 "grey dot" where `$D020`
  changes mid-line at part 2's start (line 265); and frame 876, the run-dependent first copy.
- **The stores**: part 1's ring routine and part 2's copies land on VICE's traced cycles, store
  for store.
- **The VIC model alone** (`tools/c64/t64_snap.zig` on VICE's own memory and traces): every
  static frame identical; the racing ones too once VICE's traced stores are fed in at their cycle.
- **The cart through the machine**: `apps/c64_transmission64_headless.mjs` pins C64 frames from
  every part to VICE's SHA-256; side by side shots in `compare/`.

### Gaps (documented, not hidden)

- The tune's CPU time, the drive's IRQ-off frame and the generator's progress at a shape change
  are measured, not computed: they come from the 6510 running the SID player, the 1541 and the
  generator against the IRQs. Past the 20 measured shape changes (~5 min into part 3) the table
  repeats: a shape's depth phase may then differ slightly from a real C64's.
- The 1541's hidden part (drive code) is not ported: the port has no drive.
- The boot screen is VICE's autostart (`READY.` / `RUN`); on a real C64 it shows your LOAD.
- Music: see above.

## Files

- `tools/c64_transmission64_rip.py` (+ `tools/c64_transmission64_parts.py`): one VICE run (cached
  in `scratch/rip_run.pickle`, `--fresh` to redo): RAM where each part starts, the measured
  starts, IRQ times and generator progress; writes `apps/zig/assets/screens/c64_transmission64/`
  (`part1.bin`, `wipe.bin`, `part2.bin`, `part3.bin`, `transmission_64.sid`)
- `tools/c64/capture.py` (now `C64_ENTRY`, `C64_TRACE`, colour RAM, the shot at line 300 — at 288
  VICE's canvas still holds the last frame's lines 248-250 — and `-initbreak`'s checkpoint
  deleted), `tools/c64/t64_snap.zig` (the model on VICE's memory), `tools/c64/t64_show.zig` (the
  port's frames and stores)
- `prototypes/transmission64_re/` (local except this file and `compare/`): `orig/`, `rip/`
  (dumps, disassembly), `vice/` (captures), `scratch/`, `tools/` (`starts.py`, `probe2.py`,
  `probe3.py`, `genptr.py`, `rings.py`, `sbs.py`, `showcheck.sh`, `cap.sh`)
