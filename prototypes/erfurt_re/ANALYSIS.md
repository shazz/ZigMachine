# The Erfurt Megademo, main menu (Atari Scene Collective, 31 Oct 2026): how it works

Analysis of the ORIGINAL disks, 7 Nov 2026. Source: demozoo 399907, `ERFURT1.ST` (sha256
`e63053ec…`) and `ERFURT2.ST` (sha256 `6229e707…`), 80 tracks, 2 sides, 10 sectors, both bootable.
ST/STE, 1 MB, colour 50 Hz. Put together by 505, Slippy and Jade. Only the MENU is ported
(cart `erfurt_menu`); the 14 screens are not.

## Short answer

- **Protected disks.** No file system: a protected loader of Slippy's brings each part in by
  track/side/sector (details in local notes only).
- **The menu is a drum.** The titles of both disks sit on a cylinder spun with Cursor Up/Down: the
  front face in bitplane 0, the back face (upside down, seen through) in bitplane 1, colours per two
  scanlines. A damped spring brings the drum to rest under the marker.
- **The rasters are real.** Three horizontal rainbows (42 colour-0 writes along a line, 12 cycles =
  12 pixels each, two lines each, borders included) at lines 42, 167 and 197, beam-synced on the
  video counter, and a colour 0-7 record every two lines between them.
- **The ST spends about half a frame on it** with the drum still (`tools/budget.py`); the rest is idle.
- **Music: an SNDH**, "Low Signals" by Doclands (Rhyme Tracker pre-release, YMXR converter), YM + MFP.

## 1. Getting at the code

The disks are protected: no file system, every sector encrypted, a custom loader that brings each part
in by track/side/sector. How it works is kept in local notes beside this file (PROTECTION_NOTES.md, not
committed), as are the extraction scripts and the decrypted menu: only what the port needs is committed
(the assets in apps/zig/assets/screens/erfurt_menu, ripped from the menu and from a RAM dump of it).
The menu is the directory's first entry, loaded and relocated to `$10000`; every address below is a run
address there.

## 2. The menu

The menu is the directory's entry 0 (`menu`, flags $17): 54,109 bytes packed, 137,205 depacked, text+data
$2138E, BSS $5331A, loaded at `$10000`. Scrolltext: "USE CURSOR UP AND DOWN TO SPIN THE DRUM, SPACE
STARTS WHAT IS UNDER THE MARKER". Slippy writes that "the menu wasn't written entirely from scratch
either. There's some old code in there, mixed with new ideas".

### Parts of the frame

| Lines | What | Planes | Code |
|---|---|---|---|
| 0-42 | Jade's ERFURT / ATARISCENE MEGADEMO logo, 16 colours | 0-3 | logo `$2E61E`, palette `$2E5FE` |
| 42-43 | rainbow line (colour 0, 42 writes, borders included) | - | Timer B `$102B2` |
| 44-166 | the drum: front face, back face seen through, the marker band | 0, 1 | `$11D38` |
| ~45-166 | the scroller, 40 lines, bobbing round the drum's middle | 2 | `$13D0E` |
| 167-197 | the chequered floor, the drum's shadow | 0, 1 | `$11F66`, `$1221A` |
| 197-198 | rainbow line, running the other way | - | `$1068A` |

Two screens (`$31400`/`$39100`), swapped every VBL; everything is redrawn into the back one at 50 Hz.

### The VBL and the Timer-B chain (all real rasters)

- VBL `$1024E` steps a timeline (24-byte entries from `$1F99A`: frame count + routines); the running phase
  calls `$10FEE` (VBL) and `$1135A` (main loop). The VBL loads the logo palette and rebuilds the line
  records.
- Timer B fires at line 38 (`$FA21` = $26) -> `$102B2`: wait for the line ($1085A, on the video counter),
  sync on `$FF8209` (`lsl.w d2,d0` with d2 = 16 - the counter's low byte delta: the classic shifter sync),
  NOPs, then **42 `move.w (a1)+,(a0)` to `$FF8240`**, 12 cycles = 12 low-res pixels each, for two lines
  (`lea -$54(a1)` rewinds the table). That is a horizontal rainbow in colour 0 across the whole line,
  borders included. `move.w #1,(a0)` puts colour 0 back to navy.
- `$10488` loads the first record and arms Timer B every 2 lines (`$FA21` = 2) -> `$104FE`: four `move.l`
  of colours 0-7 from a record list held in **USP** (`move usp,a0` / `move a0,usp`: a free address register
  in an interrupt), then two links on (`+$10` = next). 58 events cover lines 44..160.
- `$1057C`/`$105B2`: the 59th record held to line 166; at line 167 colours 0-3 for the floor, then 13 floor
  records; `$10654`/`$1068A`: the third rainbow at line 197.
- The rainbow table: 35 ST hues at `$140C8` repeated into 77 words at `$843DE`; a counter mod 70 (`$13FEA`),
  the top line reads from counter/2, the bottom one from 35 - counter/2: opposite directions, one colour
  every two frames.
- `tools/reconstruct.py` walks this chain in a RAM dump and renders the frame: it matches Hatari's capture.

### The drum

- **Texture**: 12 faces x 24 lines, 256 px, 1 plane (two copies at `$5B374`, double-buffered so a face can be
  redrawn while the other is shown). Text centred, 4 lines down, 16x16 font (`$60CB0`, generated at init),
  12 px advance; `@` is the font's small "STE" tag. Faces are filled lazily, 2 characters a frame
  (`$117B0`), only on the hidden side.
- **Geometry**, built at init (`$109FC`) for 33 configs: a half-cylinder of radius r = 30..50; line t = -r..r
  shows texture line `angle + profile[45 + t*45/r] >> 5`, front from `$31022`, back from `$310D8` (two
  91-word tables), the back switched off for t = -9..7 (bit 15). A pointer table (`$5FB74`, 576 entries)
  maps texture lines to addresses and folds blank and duplicate lines onto one: `$11D38` copies a line
  only when its pointer changed since that screen's last frame, 12 `move.w` into plane 0 (front) and
  plane 1 (back), x 64..255.
- **Upper and lower halves** (`$1215A`): the drum is an upper half of radius r_a over a lower half of
  radius r_b, so it can squash and bulge.
- **Jelly** (`$12A5A`): top, bottom and middle are masses in 24.8 fixed point: gravity $18, a spring
  holding top-to-bottom at 90 lines (force = (gap - 90<<8) >> 5 + damping (v_bot - v_top) >> 4), the
  middle trailing the midpoint (>>4, then 3/4), the bottom on a floor at line 166. Every 350 still
  frames a 21-step impulse (`$1F91A`, a half sine up to 160) kicks the top: the drum hops and wobbles.
  Height and middle pick r_a/r_b (`$12BB4`); the hop lifts the drum and thins its shadow.
- **Spin** (`$113A6`): the angle is 24.8, wrapping at 4608 lines. Up/Down HELD (make/break flags)
  ease the speed toward +-512 an eighth of the gap a frame (min 1); on release the next face in the
  direction of travel is chosen, separators skipped (`$12EAA`), and a spring (vel = vel/2 + gap/16)
  lands the drum on it, snapping within 16.
- **Marker and colours** (VBL `$12784`): each drum line's record gets the front/back colours from a ramp
  (`$4E462`) and the scroller's from another (`$4DD36`), both scrolled by a phase that speeds up and
  slows down on a sine (`$4EB8E`). Lines t = -10..8 of the drum's middle get colour 0 = $012 (the band,
  borders included), the front $777 and the back $012 (hidden).
- **Keys** (`$11ABA`): scancodes from an ACIA ring. Space (on a still drum) checks the entry's flags:
  bit 5 separator, bit 7 STE only ("STE ONLY" replaces the title for 75 frames), bit 6 2 MB only. Typing
  **ERFURT26** (`$11A9E`, the scancodes of E R F U R T 2 6, Shift ignored) opens the hidden part
  "WHAT? YOU FOUND IT!".
- **Exit** (`$1157A`): a fade step every 3 VBLs (each channel whose low 3 bits are not 0 loses one), 7
  steps over every colour, the records, the rainbow table and the two `move.w #1` immediates in the
  code (`$11680` lists them), then the screen is cleared and the menu returns the entry to the loader.

### The scroller (plane 2)

- 16x16 font at `$308A2` (60 glyphs), text at `$1FB31` (4,150 characters: Doclands, Exocet, Jade, Slippy).
- A ring of 32 columns x 40 lines, 16 times, each copy shifted one more pixel (`$703DC`, 16 x $1400: the
  ST cannot shift for free, so it stores the 16 shifts). Each 16-px column is a character drawn through
  a baked wave W[x] = (9 sin x + 3 sin 2x)/2048 + 12 (`$64CB2`), so the letters ride a wave that travels
  with them; the column drops by its own minimum, the pixels by the rest (max 8).
- Each frame: 2 px; line L reads the ring from `16*first + sub + h(L)`, h(L) = sin(p + 2L)/256 + 8 with
  p += $260 a frame (a pointer per line from 32 pre-shifted starts, `$64F00`): the strip shimmies.
- The strip's top = 3 sin(a)/512 + sin(b)/512 + the drum's middle - 16 (a += $120, b += $B0), clamped
  45..127. A new column is built over 16 frames (`$13EC8`), one 16th of the shift copies a frame.
- Colours 4/6 (scroller) sit under 5/7 = front colour: the front face covers the scroller, the scroller
  covers the back face.

### The floor, shadow, glint, sparkle

- Floor (`$11F66`): 31 lines, each owning 16/32/64 ready 320-px chequer rows (`$4EDCE`, 50 KB generated at
  init, nearer lines with fewer, wider squares). Line i shows row ((pan >> s) + (z_i + depth crossing
  $100 ? half : 0)) & mask, pan = sin(a+90 deg)/16 + 5 sin(b)/16, depth += sin(a)/128. Only changed rows are
  copied. Colours 0-3 per 2 lines from the floor records (purple bands, borders included).
- Shadow (`$1221A`): 12 dithered rows in plane 1 under the drum, 8 sizes (`$14130`) by hop height.
- Glint (`$126E8`): every 322 frames, 66 steps of **generated code**, `eori.l/eori.w #imm,d16(a1)` lists
  (`$14A40` -> `$14B48..$1F918`, 44 KB of code), XORing a shine across the logo. Each screen takes every
  other step.
- Sparkle (`$12350`): every 450 still frames, a band of 8 lines sweeps down the drum for 64 frames, ORing
  each line with itself shifted 1-2 px right (planes 0+1 as one long, `ror.l` with carry masks); the
  original words are saved and put back next frame.

### The budget on the ST (Hatari, STE, drum still; `tools/budget.py`)

| Part | Cycles a frame | of 160,256 |
|---|---|---|
| Timer-B chain (3 rainbow lines + 61 records) | 21,100 | 13.2 % |
| scroller draw (40 lines x 20 words from the shift copies) | 16,700 | 10.4 % |
| floor (31 lines, only changed rows) | 16,500 | 10.3 % |
| VBL colour records (`$10FEE` + `$12784`) | 11,100 | 6.9 % |
| beam waits before the rainbows | 5,300 | 3.3 % |
| scroller columns (shift copies) | 4,600 | 2.9 % |
| music (YMXR SNDH) | 3,800 | 2.4 % |
| everything else | 8,500 | 5.3 % |
| idle (main loop waiting for the VBL) | 72,700 | 45.3 % |

Half a frame is spare with the drum still; spinning adds the drum copy (12 words a changed line). What the
budget forced: one plane each for front, back and scroller (so priorities are palette tricks, not masks),
the 16 shift copies, the pointer cache that copies only changed lines, records every 2 lines rather than
every line.

## 3. Music

"Low Signals", Doclands (`SNDH` at menu `$20B68`: `TITL Low Signals`, `COMM Doclands`,
`CONV YMXR (ym-to-ymxr)`, `##01`, `!V50`, `FLAG ~acdy`). Not in the SNDH archive (searched by title
and composer). The menu calls init `$20B68` (d0 = 1), exit `$20B6C` and play `$20B70` from the VBL.
The SNDH proper is `$582E` bytes, but the YMXR player uses the `$8266` zero bytes after it as a work
buffer (watched in RAM), so the shipped file is `$DA94` bytes with that zero tail.
Verified: `node apps/sndh_headless.mjs` PASS, peak 0.99, three voices.

Shipped as `docs/music/erfurt_menu.sndh` (the scrolltext names the tune and the tool).

## 4. What the port does differently, and why

- One overscan plane, 400 x 280 raster, the ST screen kept as 200 lines of 80 interleaved words and
  collapsed into palette indices a frame (`erfurt_menu/screen.zig`). ST colour 0 is index 16 (opaque), the
  42 rainbow colours 17..58; the plane's HBL installs each line's colours (only those that changed) and,
  on the 4 rainbow lines, opens the side borders (`flickerBorder`) and paints the rainbow across them; a
  global HBL paints the closed border with the line's colour 0. The rasters stay real: colours per line,
  not pixels.
- The ZigMachine border is 40 px to the ST's 48 (in Hatari's capture), so the rainbow's phase is kept by
  content x (segment boundaries at content x = 9 mod 12), and the outermost 8 px a side are not shown.
- The chain is not interrupt-driven: `palette.zig` builds what it leaves on each line (same records, same
  ramps, same marker rule). Faithful to reconstruct.py's walk of the original's chain.
- Done at once instead of spread over frames (same picture): the face texture (2 characters a frame on the
  ST, always on the hidden side), the scroller's columns (16 frames), the pointer cache (only changed
  lines). The drum and scroller rows are recomposed every frame.
- One screen, but the logo is kept twice so the glint's every-other-step XOR stays as it was.
- Generated-at-init tables (drum font, the two colour ramps, the floor's patterns) are ripped from a RAM dump
  of the running menu (they never change after init) instead of re-running the generators; the drum's
  geometry IS regenerated from the two 91-word profiles exactly as `$109FC` does (checked equal to the
  live tables: 0 differences).
- No integer is a float; every word wraps as the 68000's did.
- Space: the menu's exit fade, then 50 dark frames where the part would run, then the menu restarts on that
  entry with the scroller where it was (the real menu is reloaded after each part and told both). ERFURT26
  does the same for the hidden entry. The "STE ONLY" / "2 MB ONLY" refusals never trigger (the machine is
  an STE with more than 2 MB). Escape leaves.
- Approximated: the hop's start also waits for the ST's precache (`$12876`) to finish, a few frames; the port
  does not. The rainbow's first visible colour can be one entry off (the capture's frame vs the dump's).

## 5. What KESTREL could lift (a ZIG mode, not built)

- Open all borders and run the drum, scroller and rainbows across the full 400 x 280.
- The drum's 1-bit faces could be the 16-colour, anti-aliased versions, the back face blended instead of
  dimmed; per-LINE records instead of every 2 lines (smoother ramps); the copper could replay the records.
- CHISEL could draw the drum lines straight from the texture (it is a span copy per line) and the floor
  rows, leaving the CPU nearly idle.
- The 16 pre-shifted scroller copies are unnecessary on ZIGGY (a shift is free); a 2-frame-per-step
  scroller could run at 1 px a frame.
