# Mind Rewind (Reservoir Gods, EIL 2003): how it works

Analysis only, 31 Oct 2026. No port yet. Source: fujiology `MINDWIND.ZIP` (md5 `6277e0a0…`),
`MINDWIND.TOS` (93,580 B, md5 `dffacb35…`). A 96k STE intro (1 MB): code Griff and Pink, music Count
Zero, SFX Damo, graphics Sh3 and Master. "ALL FX ARE RUNNING IN FULL OVERSCAN".

## Short answer

- **One engine runs the whole demo: a 280-entry line list.** On every scanline a sync-locked
  fullscreen kernel loads `{video address, HSCROLL, colour 0}` and writes it during the right border
  and blanking: `movep.l` into the STE video counter `$FF8203/05/07/09`, a word to `$FF8264`, a word
  to `$FF8240`.
- **Chrome bars and the "VHS rewind" white lines are REAL rasters:** colour 0, one write a line,
  through both borders. **No mid-line colour changes anywhere** (BEAM is not needed). The only other
  palette write is one 16-colour reload at line ~208 for the scroller.
- **Stripes and the picture are pixels moved by per-line pointers;** the colours are in the bitmaps.
- **The rainbow part is palette cycling** of three images generated at start-up.
- **All four borders open** (280 lines x 416 px). **Music: STE DMA**, a custom 4-voice tracker mixed
  in software at 12,517 Hz stereo, **not an SNDH**.
- Halfway the demo "rewinds": a 1.38 s tape-rewind sample, every instrument sample reversed in place,
  a second song, the scroller backwards, the parts replayed in reverse with rolling white VHS lines.

## 0. Getting at the code

- A GEMDOS PRG wrapping a Pack-Ice stream (`ICE!` at file offset 442, unpacked `$4BFC8`), depacked
  statically with `libs/zig/depackers/ice.zig` (`scripts/unice.zig`).
- Unpacked: TEXT `$1EDC2`, DATA `$2C71A`, BSS `$713B8`, 1,640 relocations (md5 `b15f60c2…`).
  `scripts/dis.py` (Capstone) writes `rip/text.dis`, 40,357 lines (2,851 NOPs).
- Addresses below are TEXT-relative. In Hatari (STE, TOS 1.62, 4 MB) TEXT loads at `$AA9A`.
- The `movem.l (d16,PC)` off-by-2 trap hit once: the VBL's field palette is at `$5A4`, not `$5A2`.

## 1. Parts

`main` (`$0`-`$EC`) calls each part; every part waits on the song position word `$771E`.

| VBL | Code (kernel) | On screen | Shot |
|---|---|---|---|
| 570-1370 | `$75FE`, `$3298`, `$44A4`, `$2056` | precalc on a blank screen, ~16 s | - |
| 1370-2110 | `$BAE8` (`$768`) | intro: a 48-line scroller mid-screen; after 550 frames it slides to line 210 while bars and field open | `shots/00b`, `00c` |
| 2110-4846 | `$340C` (`$9BC`→`$C10`→`$E96`→`$111C`→`$13A2`) | A, purple stripes: chrome bars 0-13 and 194-207, a 180-line field, the scroller 210-256. The field picks rows from a pre-rendered bank (512 rows x 208 B, 16 zoom passes x 32 rows, integer perspective by `$3298`); first every line the same row (zooming stripes), then each line its own row from a sum of 4 sines (`$39C0`; circles, moire). HSCROLL = 0 here | `01`, `02`, `02b`, `03` |
| 4846-7119 | `$8ACC` (`$9BC`, `$1628`) | B, picture: Sh3's 320x200 picture, 160-byte rows shown 416 px wide (wraps); a sine wobble (`$8CC2`, 208-entry ring of {address, HSCROLL}); a vertical flip (90 frames x 200 row indices at `$3E496`) | `04`, `05`, `06` |
| 7119-8667 | `$44D6` (`$18AE`) | C, rainbow interference: three 448x207 4-bpp images generated at init (`$51B8`, `$51C6`, `$51DA`, table `$271C8`), revealed from the centre, animated by palette cycling (VBL hook `$4818`) | `07` |
| 8667-8771 | `$2A4`, `$16EB8` (`$1BA6`) | D, rewind: music stops, 1.38 s DMA tape-rewind sample, the picture cut into four 42-line bands sliding 3/1/4/2 px a frame | `08` |
| 8771-8800 | `$80E8`, `$2F2`, `$BA90` | every sample reversed in place, song 2 starts, scroller right to left | - |
| 8800-~10400 | `$45AE`, `$8C00`, `$3606` | C', B', A' in reverse order; VHS overlay (`$16A48`): one line in 32 blank with colour 0 = `$0FFF`, rolling | `09` |
| end | `$418`, `$1AA` | system restored; a plain 320x200 Reservoir Gods logo, borders closed, faded from white, until Space | `10` |

## 2. Colour effects

The line slot, repeated every line (e.g. static `$1EA0`):

- `move.b d0,$820a` / `move.b #2,$820a`: the right-border 60/50 Hz switch;
- `move.l (a5)+,d6` / `move.l (a5)+,d7`: load the record (video address; HSCROLL<<16 | colour 0);
- `move.b #1,(a6)` / `move.w d7,(a0)` / `move.b d0,(a6)`: the stabiliser (medium/low on `$FF8260`)
  with the **colour-0 write** squeezed between;
- `movep.l d6,-$5d(a6)`: the **video counter** write;
- `swap d7` / `move.w d7,$8264.w`: the **HSCROLL** write;
- `move.b #2,(a6)` / `move.b d0,(a6)`: the next line's left border.

The colour-0 write lands at line cycle **444 of 512**: right border / blanking.

- **Chrome bars: REAL raster.** Colour 0 per line from 14 words at `$38F6`: `$0001 $0002 $0113 $0224
  $0335 $0446 $0556 $0667 $0777 $0666 $0444 $0333 $0111 $0000`, on lines pointing at an all-zero
  buffer, through both borders.
- **VHS lines: REAL raster.** `$0FFF` on a blank line, one in 32, rolling.
- **Stripes and picture: pixels plus per-line pointers;** colour 0 constant (0 stripes, `$0777`
  picture).
- **Rainbow: palette cycling.** 16 STE words at `$2F934` (`$0600 $0F00 $0F10 …`), rotated each VBL.
- **Scroller:** palette `$C59A` reloaded once mid-screen at `$A34`.
- **Palette grid:** pictures, stripes, bars and scroller use nibbles 0-7 (ST-legal); the rainbow and
  `$0FFF` use the STE's 4th bit. Every colour comes from a palette word in the binary.

## 3. STE hardware

- **Video counter written every line:** the core of the demo (~150 `movep.l` sites).
- **HSCROLL `$FF8264/65`** every line (138 sites).
- **4096-colour palette:** part C and the VHS lines.
- **DMA sound:** music as a 500-byte stereo frame a VBL at 12,517 Hz (`$7F9E`), double-buffered
  (`$59C`/`$5A0`); the rewind sample a mono one-shot (`$2A4`, `$8921` = `$81`).
- **Microwire (`$FF8922/24`):** once at music init (`$7602`, words `$0486 $0446 $0001 $00D4`; treble
  and bass flat).
- **Not used:** blitter, `$820F` line offset, `$820D` video base low byte.
- **STE check:** `_MCH` must be STE (`$00010000`) or Mega STE (`$00010010`), else "THIS DEMO ONLY
  RUNS ON STE".

## 4. Borders and sync

- **All four borders open.** The VBL (`$506`) arms MFP Timer A (`$FA1F` = `$62`, prescaler `$FA19` =
  4, ~32 lines); its handler (`$5C8`) does `stop #$2100` to land on an HBL and removes the top border
  with `$820A` writes (`$644`/`$666`).
- **Cycle lock:** classic STE `$FF8209` sync (`movea.w #$8209,a0`, wait for the low byte to move,
  `sub.b d0,d1` with `d1 = $2F`, `lsl.w d1,d0`; `$65E`-`$672`).
- **Per line:** left border high/low on `$8260`; right border 60/50 on `$820A`; stabiliser
  medium/low on `$8260`. Bottom border: 60/50 + high-res on one line (`$8AC`).
- **Locked from Timer A to the last line;** the kernel returns into the Timer A handler, which clears
  the palette, swaps the DMA buffers, runs the music tick and the frame hook (`$318C`).

## 5. Music

- **Not an SNDH:** `sndh_index.py` finds nothing for "mind rewind", "rewind", "reservoir", "count
  zero", "eil"; the archive's 24 Count Zero tunes are all YM. The YM is silent (mixer `$C0`, volumes
  0); `rip_sample` shows DMA at 12,517 Hz stereo, 500-byte frames.
- **Sequencer** (`$75FE`-`$8ACC`): 4 voices (records `$7706`, `$772E`, `$7756`, `$777E`), bit-coded
  commands (sample, period<<9, slide, wait), `$D8F1` end/loop, song position `$771E`.
- **Mixer** (`$51F0`-`$75FA`): ~100 slices welded into the fullscreen lines; each output byte
  `move.b (a1),d1 / add.b (a2),d1 / move.b d1,(a7)+` (two voices summed); pitch step tables at
  `$4B4DC` (built by `$88C4`).
- **Data** (`scripts/rip_music.py`): sample table DATA `$1EDC4` (6 x {offset.l, length.w, loop.w});
  samples `$1EDF6`-`$265D3`, 30,686 B, unsigned→signed at init (`$897C`); song 1 at `$265D4`, song 2
  (the rewound half, `$8918`) at `$26BCE`. Rewind sample `$47136`-`$4B4CE`, 17,304 B, 12,517 Hz mono.
- Open: gaps between sample offsets and the end of song 2 (`$271C8`) not fully explained.

## 6. CPU budget

`profile_frame`, 10 frames each, bucketed by address (`evidence/profile_buckets.txt`):

| Bucket | Part B (`$1628`) | Part A' (`$13A2`) |
|---|---|---|
| Kernel (switches, NOP padding, record loads) | 42,344 (26.4 %) | 47,464 (29.6 %) |
| Mixer, interleaved into lines | 37,204 (23.2 %) | 37,204 (23.2 %) |
| Effect work, interleaved into lines | 56,924 (35.5 %) | 46,932 (29.3 %) |
| Scroller (VBL) | 3.4 % | 3.4 % |
| Sequencer, VBL, Timer A head/tail | ~2.9 % | ~2.9 % |
| **Idle** (wait-for-VBL `$4EA`) | **8.0 %** | **11.0 %** |

89-92 % of the frame is used, nearly all inside the sync-locked fullscreen interrupt: hence nine
kernels (`$768`, `$9BC`, `$C10`, `$E96`, `$111C`, `$13A2`, `$1628`, `$18AE`, `$1BA6`), the same line
skeleton each with different work interleaved.

## 7. KESTREL mapping

- **Today:** the copper list (PAL / PALREF / REG / FLICK) applies before each line, no x position;
  `REG` = HSCROLL only (`machine/copper.zig`). `renderPlaneOverscan` takes the buffer pointer once a
  pass and reads no HSCROLL; `renderPlaneScroll` re-reads HSCROLL per line but only in the 320x200
  window; `FB_BASE` is not re-read per line. BEAM exists, not needed. Physical frame 400x280 vs the
  demo's ~416x276: crop 8 px a side.
- **Bars, VHS lines:** copper `PAL` entry 0 on one overscan plane with `openBorders(.all)`.
- **Palette switches:** copper `PALREF` (16 entries) at lines 0 and 208; one plane.
- **Rainbow:** 16 palette entries rewritten each frame.
- **Line list (choice 1 for Matt):**
  - (a) no machine change: the CPU copies each line's 400-byte window into one overscan plane each
    frame, ~0.15-0.25 Mc. Odd x → misaligned u32 loads trap on the board: copy with aligned loads and
    funnel shifts.
  - (b) a new copper op for a per-line base, with HSCROLL honoured in overscan: STE-faithful, serves
    future distorters; an HW 1.10 change (machine, RTL, proofs, gate).
  - Recommended: (a) for this demo, (b) only if more line-list screens are queued.
- **Music (choice 2):** wrap the original sequencer and data with a non-interleaved mixer as an SNDH
  (flag `~e`, the existing 68000 player with STE DMA); or a native Zig/BARD player; or stream the
  recorded PCM (~5.2 MB, reversal baked in). An SNDH must expose the reversal, the rewind sample and
  `$771E` (subtune or `zg.sndhCall`).
- **Start-up data (choice 3):** embed the ripped buffers, or regenerate at init with the original
  integer formulas (no float needed).

## 8. Files

- Pictures: `girl.pi1/.png` (palette DATA `$31756`, pixels `$31776`), `rg_end.pi1/.png` (`$27BD4` /
  `$27BF4`).
- Generated buffers: `rainbow{1,2,3}_448x207.bin/.png` (BSS `$9A934`, `$A5E54`, `$B1374`, RAM dump at
  VBL 7319), `stripes_bank_512x208.bin/.png` (BSS `$7C624`).
- Palettes `pal_*.pal`; tables `stripes_linesel_128ptr.bin` (`$42A4`), `sine_208c_1024w.bin`,
  `wobble_sine_b61a.bin`, `flip_rows_3e496_90x200w.bin`, `bars_colour0_gradient.bin`.
- Scroller: `font_48x48_glyphs.bin`, `font_sheet.png` (16-px columns of `$180` bytes, 3 a char; char
  table `$C42E`), `scrolltext.txt`.
- Music: `music_*` (table, samples raw+WAV, songs 1 and 2), `rewind_sfx_12517_mono.wav/.raw`.
- Evidence: `evidence/linetab_f{3219,4219,5419,9715}.bin` (280 x {address.l, hscroll.w, colour0.w}),
  `evidence/profile_buckets.txt`. Screenshots `shots/`. Scripts `scripts/` (`unice.zig`, `dis.py`,
  `planar.py`, `rip_assets.py`, `rip_music.py`, `prof_buckets.py`, `raw2wav.py`).
- Not committed (13 MB, rebuildable from the zip): `rip/`, `hatari_work/`, `dl/`, `zip/`, `hd/`.

Open: the music table's gaps and song 2's end; the intro not profiled.
