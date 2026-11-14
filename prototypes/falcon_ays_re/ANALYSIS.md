# Are You Sitting Comfortably? (Reservoir Gods, Falcon 030, 2004): how it works

Analysis for the KESTREL port (cart `falcon_ays`, 116), 3 Nov 2026. Source: fujiology
`FALCON/RG/COMFRTME.ZIP`, `COMFORT.PRG` (958,934 B, Pack-Ice), depacked to `COMFORT_unpacked.PRG`
(TEXT 54,074, DATA 1,863,374, BSS 1,157,434, 1,652 relocations). Credits: Damo code, design and
sequencing; SH3 graphics; MSG music; Mr Pink particle code; EarX screen modes, MOD replay and the
env-mapped ball-oid. Reference capture: Hatari 2.4.1, Falcon, DSP emulated, RGB50
(`video/ays_rgb50.avi`, PNG-coded 640x480; song time 0 = video 28.0 s, the MOD's first sample;
the 200-line screen is scaled x1.2 to the capture's 240 rows).

Method: static disassembly (Capstone 68030 over the relocated TEXT), DATA dumps viewed as
pictures, the EarX sources of Lineout's Delta (`~/projects/Atari_ST_Sources/ASM/Lineout/Delta/`),
and frame grabs at the script's times. **Hatari was not used for profiling**: the cycle figures
below for the Falcon are counted from the loops, not measured. The detailed notes per routine are
`notes_text_accents.txt`, `notes_blobs_credits.txt`, `notes_flames_3d.txt` (this directory).

Scripts (tracked): `scripts/disasm68k.py` (writes `rip/text.dis`), `scripts/rout.py`,
`scripts/fxtable.py` (the 8xx table), `scripts/datamap.py` (DATA map from the relocations),
`scripts/grab.py` (exact frames from the AVI at song times), `scripts/sheet.py` (contact
sheets). Addresses are image offsets (TEXT at 0, DATA from `$D33A`, BSS from `$1D4206`).

## Short answer

- **The MOD is the script.** Damo sequenced the intro in ProTracker: 164 `8xx` commands. The
  replay hands the `xx` to the demo system, which loads that value's routine triple from a
  64-entry table (DATA `$13FD74`): a **timer** routine (run at the replay's 50 Hz tick), a **VBL**
  routine (always a Videl mode setter) and a **main** routine (one frame's drawing). The song runs
  at speed 7 with no pattern break: a row is 0.14 s.
- **Two screen modes only**: 320x200 true colour (804) and 320x200 TC line-doubled (805: the
  effect draws 160x100, each pixel stored twice). Three 217,600-byte buffers rotate.
- **The DSP does two things**: it mixes the MOD (EarX's replay, `RSNDEARX.P56` byte for byte) and
  runs the whole 3D pipeline of the ball-oid (a HumanFly/ufly derivative that also generates and
  morphs the object). **Everything else is the 68030**: table lookups, fills and feedback passes.
- **Almost every 2D effect is a sum-of-two-lookups into a colour table**: blobs (one height field
  read twice), the "reservoirgods" moire (letters + field), chosneck (two flare frames + logo),
  the flames (an offset map into a 256x256 texture). Cheap per pixel on any CPU.
- **Feedback** (the frame drawn last read back) makes the smears: a two-pixel average (825, 816,
  83E), a 1.25x zoom (812), and the blob fades (822/836).
- **Shakes are free**: the VBL adds a table entry a frame to the Videl's display window (HDB/HDE
  sideways, VDB/VDE vertically). On KESTREL: the copper line list's LBASE, no pixel moved.
- **KESTREL plan**: one RGB565 plane (HW 1.15.0) double-buffered, mode 805 by copper line
  doubling, every 2D part on the cart CPU (0.1-0.5 Mc a frame), the 3D on the CPU in fixed point
  (~0.35-0.5 Mc) instead of the DSP. Everything fits 60 fps on paper (one plane = 0.59 Mc,
  budget ~1.67 Mc). **Nothing needs a feature KESTREL lacks**; the one thing that would help is
  CHISEL 16-bit pixels (MAP / AFFINE are 8-bit indexed only), see §5.

## 0. The demo system

- **Main loop `$61E`**: call the main slot (`$14055C`), rotate three 217,600-byte (`$35200`)
  screen buffers (`$7C6`: BSS `$2EE688/68C/690`; `$2EE690` holds the frame drawn last, which the
  feedback effects read), wait for the VBL counter `$468`, until Space.
- **VBL `$68E`**: call the VBL slot (`$140558`), then, while `$2EEB32` / `$2EEB34` is set, add one
  word a frame from the table at `$2EEB3A` to HDB/HDE (`$8288/$828A`) or VDB/VDE (`$82A8/$82AA`).
- **Music interrupt `$75A`** (MFP timer D, vector `$110`): `bsr $128E` returns the replay's sync
  byte (`$FF` = none). For a new value `v` it copies longs 2, 3, 4 of the 32-byte entry at DATA
  `$13FD74 + 32*v` into the **timer slot** `$140554` (called right there), the **VBL slot**
  `$140558` and the **main slot** `$14055C`. The replay itself is EarX's: timer A at ~50 Hz runs
  the 68k sequencer (`$1480`) and streams sample data over the DSP host port (`$246A`), the DSP
  mixes (`RSNDEARX.P56`, TEXT `$279C`, loaded with XBIOS `$6D` at `$143E`).
- **Init list** at `$13FD54`: `$E74` (mode 805), `$7B6` (clear the palette), `$2CA4` (chosneck
  LUT), `$38F4` (blob fields), `$3926` (blob LUTs), `$3152` (noise table), `$4D16` (flame
  textures, each stored twice so the offset add never wraps).
- Three monitor branches everywhere: `$13FD52 != 0` = RGB (key 1 / VgetMonitor != VGA), else
  VGA100, and `$140568 == $3C` = VGA60. **This analysis follows the RGB50 branch only.**
- The 3D parts run EarX's own demo-system screen objects inside this one (200 Hz `$4BA` clock,
  `setZoom`/`stutter`/`turn` identical to `BALLOID.SO`).

## 1. Screen modes (RGB50 branch)

| 8xx | VBL rout | `$8266` | `$8210` (words) | `$82C2` | geometry | used |
|---|---|---|---|---|---|---|
| 801 | `$9A4` | `$10` (8 bpp) | `$A0` | 0 | 320x200, 256 colours | no |
| 802 | `$AD8` | `$10` | `$140` | 6 | 8 bpp | no |
| 803 | `$C0C` | `$100` (16 bpp) | `$140` | 1 | | no |
| 804 | `$D40` | `$100` | `$140` | 0 | **320x200 true colour** | yes |
| 805 | `$E74` | `$100` | `$140` | 1 | **320x200 TC, every line twice**: effects draw 160x100 as pixel pairs | yes |

Every other entry's VBL slot is `$D40`, `$E74` or `rts`: the VBL slot names the part's mode.
KESTREL: one TC plane in `.window` (320x200); 805 = rows 0..99 of pixel pairs, the copper line
list pointing raster line y at row y/2 (`screen.zig`). Zero stores for the doubling.

## 2. The script: 8xx value -> part, with times

Times are song seconds (row x 0.14 s); the capture shows each change ~0.3 s later (the replay's
buffering). `T/V/M` = timer, VBL, main slot addresses. "x N" = fired N times.

| 8xx | T / V / M | part | first at (s) | KESTREL (`fx.zig` part) |
|---|---|---|---|---|
| 804 / 805 | - / `$D40` / - , - / `$E74` / - | mode only, main `rts` (hold) | 0.14 / 17.36 | `.hold` |
| 807 | - / - / `$4A76` | clear 128,000 B | 0.00 (x 8) | `.black` |
| 81D, 81E | `$656C` / `$D40` / `$6404`, `$644C` | "IN AUTUMN 2003.....", ".......WE ARE BACK!" | 8.96, 13.44 | `.text` |
| 80B..810 | `$3C7E` / `$E74` / `$346C`..`$37DC` | blobs, six variants | 17.92 .. | `.blobs` |
| 811 | `$3C7E` / `$E74` / `$388C` | blobs + a 6-line tear band | 58.38 (x 7) | `.blobs` |
| 821 | `$3C7E` / `$E74` / `$38BE` | blobs, inverted LUT | 64.40 (x 3) | `.blobs` |
| 81B, 81A | `$6378` / `$E74`, `$D40` / `$628E` | grey flash to black (0.6 s) | 19.60 .., 75.60 .. | `.grey_flash` |
| 813 | - / `$E74` / `$4790` | copy the last frame = freeze | 21.84 (x 8) | `.hold` |
| 822 | - / `$E74` / `$6CA6` | blob sums pushed to the LUT's top (the "light beams") | 26.32, 33.60 | `.blob_fade` |
| 823 | - / - / `$6FE8` | white screen | 30.80 (x 5) | `.white` |
| 820 | - / `$D40` / `$6B58` | the RG ship picture + vertical bounce | 35.84 | `.ship` |
| 825 | - / - / `$71A8` | jolt + feedback smear, then freeze (once) | 40.32, 41.86 | `.smear` |
| 826 | - / - / `$722A` | jolt, freeze | 42.56 | `.jolt` |
| 809 | `$32EC` / `$D40` / `$3172` | TV static band fading in | 44.10 | `.noise` |
| 814 / 815 | `$49E6` / `$D40` / `$4946`, `$4968` | "reservoirgods" moire strobe | 44.80 (x 26) | `.strobe` |
| 82B, 82C, 832 | `$656C` / `$D40` / `$6494`.. | "PRESENTS", "SOME RANDOM STUFF..", "...FOR CHOSNECK MAG" | 46.34, 48.58, 50.82 | `.text` |
| 836 | - / `$E74` / `$6CC8` | blob sums pushed to black | 69.44, 106.68 | `.blob_fade` |
| 82D..831 | `$D334` / `$D40` / `$D090`.. | credits: the next name picture flies in | 71.68, 76.16, 80.64, 89.60, 98.56 | `.credits` |
| 833 | `$D334` / `$D40` / `$D268` | credits + jolt | 72.52 (x 5) | `.credits` |
| 837, 838 | - / `$D40` / `$ABBC`, `$ABE8` | tiled mask wipe (square / cross) | 80.08, 102.48 | `.credits` |
| 808 | `$30A8` / `$E74` / `$2CC4` | "chosneck" + two flares | 107.52, 116.48 | `.chosneck` |
| 816 | `$30A8` / - / `$4B10` | chosneck band feedback blur | 115.92, 123.20 | `.chos_blur` |
| 812 | - / `$E74` / `$3E1C` | zoom feedback (green streak) | 124.88 | `.chos_zoom` |
| 817, 818, 819 | `$527C` / `$D40` / `$4D6E`, `$4EAA`, `$4FE6` | flames: texA+mapA, texA+mapB, halftone+mapA | 125.44 .. | `.flames` |
| 834, 835 | `$527C` / `$D40` / `$529A`, `$5A96` | torn flames (4 bands) | 834: 132.72, 141.68 (835 is never fired) | `.flames` |
| 824 | - / - / `$70C6` | white, lines 25..174 | 132.58 (x 4) | `.white_band` |
| 81C | `$527C` / `$D40` / `$511A` | halftone flames + "are you sitting comfortably?" | 156.80 | `.flames` |
| 829 | - / `$D40` / `$7A34` | grey ball-oid, right half of a white band | 161.28 | `.grey_obj` |
| 839, 83A | `$822C` / `$D40` / `$7D04`, `$7D4A` | + "thanks for watching!" / "now go read the mag!" | 165.76, 174.72 | `.thanks` |
| 82A | - / `$D40` / `$7B2C` | orange ball-oid zooming in + greetings | 179.20 | `.orange` |
| 83B / 83C | - / `$D40` / `$7D9C`, `$7E18` | greetings + vertical quake on / off | 188.16 .. 210.56 | `.orange` |
| 83E | - / `$D40` / `$AD30` | feedback blur of the whole screen to the end | 215.04 | `.melt` |
| 806, 80A, 81F, 827, 828, 83D | | defined, never fired by the script | - | - |

The table is validated end to end against the capture: 81D 8.96 s = "in autumn" at s9, 820 35.84
= ship at s36, 82D 71.68 = credits s72, 808 107.52 = chosneck s108, 817 125.44 = flames s126,
829 161.28 = grey object s162, 82A 179.2 = ball-oid s180: within a second throughout, so no
pattern break skews the clock.

## 3. The parts (RGB50 branch; DSP only where said)

Every part below runs on the 68030 except where **DSP** is said. "Port" = what `falcon_ays`
does (`apps/zig/scenes/falcon_ays/<file>`), "stand-in" = what the committed cart draws without
the local rip.

### 3.1 The red texts (81D, 81E, 82B, 82C, 832; mode 804)

- Font DATA `$EC1EC` (30,208 B): 59 glyphs ' '..'Z', 16x32, 8 bits a pixel (intensity 0..`$72`,
  the grain drawn into the glyphs). Strings at `$F38EC` + 20 n: "IN AUTUMN 2003.....",
  ".......WE ARE BACK!", "      PRESENTS     ", "SOME RANDOM STUFF..", "...FOR CHOSNECK MAG".
- On entry the line is copied into a 320x42 byte buffer (BSS `$2995EA`) at row 4, x 8, blurred once.
  The timer counts ticks; past a threshold (160 ticks for the first two, 20 for the others) the
  main blurs the buffer **in place** every frame: `p = (UL + UR + DL + DR) >> 2` over 10,140
  bytes. In place it smears toward the start; the truncation darkens it to nothing. 40 rows go
  through a 128-entry palette (`$F37EC`, black -> red -> white) onto the screen at line 80/88/84.
- Port: `text.zig`, the same buffer and blur, one blur a 50 Hz tick (the Falcon's frame rate).
  Cost 0.40 Mc cart (12,800 palette lookups + the 10 K blur). Stand-in: the system font scaled
  to 16x32 with a fixed grain.

### 3.2 The blobs (80B..811, 821; mode 805, 160x100)

- `pixel = LUT[F[a + y*sa + x] + F[b + y*sb + x]]`. **Both windows read the same field** (the
  code loads both pointers from `$215B4C`; the field-A pointer `$215B48` is never used): the
  320x200 height field DATA `$38F2C` (bytes 0..127, five "spotlight" shapes growing left to
  right) or its 180-degree turn (init `$38F4`). The LUTs (`$4992C`..`$4AD2C`, 565) are black up
  to a sum of 128 and white near 255: a **metaball threshold**, the colour only where the two
  copies overlap.
- Windows walk four 512-entry paths, exact sine sums (P0 x = 80 + 40(S2 + S8), y = 50 + 25(S1 +
  S4); P1 the axes' terms swapped; P2 x = 80 + 80 S1, y = 50 + 25(S2 + S4); P3 x = 80 + 40(S1 +
  S2), y = 50 + 50 S4), one entry every 3 ticks. A row stride other than 320 shears the window:
  the "light streaks" (80C 300; 80E 318/322; 80F, 810 312/328).
- Variants: 80B purple, 80C cyan, 80D red, 80E green, 80F gold, 810 purple (table in
  `notes_blobs_credits.txt`); 811 adds a 6-line tear band (rows shifted 2, 6, 14, 8, 4, 2 px)
  moving on y = 45 + 22.5 (sin p + sin 4p); 821 swaps in the inverted LUT (white, pink, black).
- 822 / 836 ("light beams", blob fades): the sums frozen at the command, then +6 / -6 a frame to
  the LUT's top or bottom; after 80F (gold) these are the white-yellow beams before the ship.
- Port: `blobs.zig`, exact (paths generated from the fit, field and LUTs from the rip). Cost
  0.40 Mc cart. Stand-in: five generated spotlight shapes, ramps through the decoded LUT colours.

### 3.3 Flashes, freezes, clears

- 807 `$4A76` clears the 128,000 B (fired 2+ rows so all three buffers are cleared).
- 823 fills white; 824 white on lines 25..174 only; 813 copies the last frame = a 0.56 s freeze.
- 81A/81B `$628E`: the whole screen in one colour from a 64-step ramp (DATA `$EBFEC`, a lilac
  tinted grey), from `$F8` down 8 bytes a tick: 0.6 s to black. The same timer `$6378` also walks
  the flames' offset.
- 809 `$3172`: TV static in lines 75..124, 160x25 cells of 2x2, a PRNG byte (`d0 = d0*d0 ^ d0 + 7`)
  indexing a 256-entry window of a 768-entry grey table (`$3892C`) that slides from black.
- Port: `accents.zig`, fills only on the two frames that need them (both buffers), then nothing.

### 3.4 The ship (820) and its smear (825, 826)

- DATA `$F3950`: a 6-byte header and SH3's rendered 320x200 RGB565 picture (the blue radial
  background baked in), copied every frame. The VBL bounces it vertically: VDB/VDE + the 62-entry
  table `$1D3CD0` (+-16 .. +-1 half-lines, alternating). The white-yellow "light beam" before it
  is not this part: it is 822 over the gold blobs, then 823's white.
- 825: a sideways jolt (HDB/HDE + `$1D3F7E`, ~30 VBLs) and, while it runs, a **feedback blur**:
  back buffer = the frame shown, each pixel averaged with its right neighbour
  (`(a>>1 & $7BEF) + (b>>1 & $7BEF)`), 64,000 px; then the last frame is held. A second 825 does
  nothing (state `$16`). 826: the jolt only.
- Port: `ship.zig` (painted into both buffers once), the bounce and the jolt move the copper line
  list's LBASE (zero pixels), the smear `accents.smear`. Cost: ship 0.01 Mc, smear ~0.3 Mc while
  it runs. Stand-in: the blue rings and a lettered plaque.

### 3.5 "reservoirgods" (814 / 815, mode 804)

- `pixel = LUT[base + letters[x, 8 + y] + field[x + sway, y]]`, 320x51 at line 75. Letters DATA
  `$5B2AC` (320x65, a halftone-dot "reservoirgods"), field `$603EC` (a radial dot screen read 640
  wide), sway `$6AC6C` (1024 offsets), LUT `$6A86C` (black, black -> red -> white, white). The
  base starts 125 entries up and falls 5 a tick: the letters flash out as moire and fade in 25
  ticks; the alternating 814/815 restart it on the beat (a strobe).
- Port: `strobe.zig`, exact with the rip. Cost 0.56 Mc. Stand-in: the font through a dot screen.

### 3.6 The credits (82D..831, 833, 837, 838; mode 804) - Mr Pink's particles

- Each 82D..831 takes the **next** of five pictures (the list at `$13FD1E`): SH3's 3D name
  lettering, Pack-Ice, 320x240 565, and a plaque (CODE 113x40 `$13A606`, GRAPHICS 165x40
  `$13C95C`, MUSIC 131x40 `$137D10`, "G4" + w + h + 565) blitted bottom right.
- The picture is cut into 4x4 blocks; 20 times a frame a random block still to place becomes a
  particle (pool of 256) that **flies in**: with r = L - age, `pos = home + v r + a r^2` (v in
  [-200, 200) px a unit, a_x [-50, 50), a_y [-0.5, 9.5); L = 0.22 + 0.39 rand), landing exactly
  on its home at r = 0, where it is stamped into the background. Three dirty lists (one a screen
  buffer) erase and redraw only the blocks.
- 833 jolts the screen sideways; 837/838 wipe it to black through a 16x16 mask tiled over the
  screen, growing over 8 frames (837 a centred square: the "holes", 838 a cross).
- Port: `credits.zig`, the same model, two dirty lists and a landing log. Cost 0.5 Mc. The time
  unit is fitted (1 s, not the 2 s the timer's rate suggests) to the capture's ~3 s a picture.
- **Picture 4 (MUSIC, file offset 1,270,360) does not depack** with `libs/zig/depackers/ice.zig`:
  the rip build shows its stand-in. Stand-ins: lettered slabs and plaques.

### 3.7 "chosneck" (808, 816, 812; mode 805)

- 808: a 42-row band at row 29: `idx = flareA[x + oA] + flareB[x + oB] + logo[x]`, a 256-entry LUT
  (black under 64, brown -> gold -> white). The flares are 12 frames of a rotating six-point star
  (DATA `$DB24`, 320x43 bytes each), one counting up, one down; their x offsets walk 78 + 26.3
  (sin t + sin 2t + sin 4t) 300 entries apart. The glow is pre-rendered in the flare frames.
- 816: feedback blur of the band (two-pixel average, as 825). 812: a zoom feedback, each pair of
  the next frame read from the shown one through a 1.25x map (`$52DAC`), the RGB path reading its
  rows doubled, past the 100-line picture: the green streak.
- Port: `chosneck.zig`; the zoom map is generated (the doubled-row quirk kept). Cost 0.27 Mc.

### 3.8 The flames (817, 818, 819, 81C, 834, 835; mode 804) - an offset map

- Texture A DATA `$A9C6C`: a 256x256 photographed fireball, exactly 255 colours; texture B
  `$C9C6C`: its pre-rendered halftone, 64 greys. Maps `$6B46C` / `$8A86C`: 320x150 u16 v<<8|u
  (smooth / turbulent warp). Offset path `$E9C6C` (1024 v<<8|u, one a tick, 20 s a lap).
  `pixel = tex[map + off]` at lines 25..174; the texture is stored twice in a row so the add never
  wraps. 817 A + map A, 818 A + map B, 819 B + map A, 81C 819 + "are you sitting comfortably?"
  (`$EA46C`, 320x22 coverage bytes, drawn black), 834/835 the torn version (4 bands, the map read
  back 8 rows a band, white or black lines between).
- Port: `flames.zig`, **CHISEL's MAP op** on plane 1 (8-bit; the textures quantised to their own
  255 / 64 colours at init, exact), swapped in for the true-colour plane while the flames run.
  Cost 0.02 Mc cart + CHISEL 0.07 Mc (the CPU version cost 2.4 Mc: a D$ miss a texel).

### 3.9 The ball-oid (829, 839, 83A, 82A, 83B, 83C) - **DSP**

- EarX's engine (a HumanFly/ufly derivative, DSP program DATA `$1189D6`): the CPU sends a morph
  value (`(sin(t) + $8000) >> 7`, ~10 s period on the 200 Hz clock), three rotation angles (t x
  3/4, 7/4, 11/8) and the position; **the DSP generates the polar mesh (402 vertices = 2 poles +
  40 rings x 10; 410 faces), its normals, transforms, culls, sorts and scan-converts it**, sending
  finished env-mapped texels the CPU writes. Env maps 64x64 565: grey `$11A3BE`, orange `$11C3D2`.
- 829: the grey one at the right of a white band (focal 256, centre (273, 100), z 300); 839/83A
  add "thanks for watching!" / "now go read the mag!" (two 320x8 strips `$1173D6` through a ramp
  `$1187D6` that fades the text into white). 82A: the orange one zooming from z 1500 to 300 in a
  140x140 box, with the greetings: a pre-rendered 1000x8 strip (`$112D56`) copied in 24-pixel
  chunks on a slanted baseline from line 120, its start walking a 1024-entry offset table. 83B /
  83C start and stop a vertical quake (VDB/VDE + `$1D3FBC`).
- 83E: the end, the two-pixel feedback blur over the whole screen (a pass every ~3 VBLs).
- Port: `balloid.zig` + `balloid_rast.zig` on the cart CPU in fixed point (sine table, 16.16
  affine spans, bucket sort), `finale.zig` for the texts, greetings and the melt. **The DSP's
  radius / morph formula is not decoded** (it needs a 56001 disassembly of `$1189D6`): the port's
  morph is an egg whose rings terrace into ribs (fitted by eye to the frames). **Decoded 3 Nov
  (Hatari's DSP disassembler on the running program):** the generator at P:$07E8 walks a
  2048-entry table the CPU uploads (y:$18BD, `0.5 + 0.0625 sin(2 pi i / 2048)`) with a stride of
  the morph value: ring k's radius factor is `f(k) = 0.5 + 0.0625 sin(2 pi (k * morph mod 2048) /
  2048)`, then `rho = 400 f sin(lat)`, `h = 400 f cos(lat)`, `lat = (k + 1) x 24/2048` turn
  (sin/cos pairs at x:$3D55), 10 longitudes (x:$3DA5), poles at +-200. The port now uses it.

## 4. KESTREL plan and costs

One RGB565 plane in the 320x200 window (FB_MODE 5) is the whole show, double-buffered; the
flames alone swap it for an 8-bit plane (one plane enabled at a time: each costs ~0.6-0.7 Mc of
FRESCO compositing). Measured with `apps/frame_cost.mjs` (the calibrated op-count model, not
the board) on the cart built WITH the local rip, 30 frames from each time:

| part (song s) | KESTREL mechanism | cart Mc | total est. Mc | est. fps |
|---|---|---|---|---|
| texts (12) | CPU: 8-bit buffer, in-place diagonal blur a tick, palette to 565 | 0.40 | 1.11 | 60 |
| blobs (20) | CPU: two byte loads + LUT + one u32 pair store, 160x100; copper line doubling | 0.40 | 1.09 | 60 |
| ship (37), bounce (41) | painted once into both buffers; bounce/jolt = copper LBASE | 0.01 | 0.72 | 60 |
| 825 smear | CPU feedback pass, two pixels a word | ~0.3 while it runs | ~1.0 | 60 |
| "reservoirgods" (47.5) | CPU: letters + swaying field + LUT, 320x51 | 0.56 | 1.26 | 60 |
| credits (75, 92) | CPU: dirty 4x4 blocks only (restore, land, plot) | 0.04 | 0.74 | 60 |
| chosneck (110), blur (116) | CPU: 160x42 three-way sum + LUT; feedback blur of the band | 0.27-0.31 | 0.97-1.01 | 60 |
| flames (130, 133.5, 159) | **CHISEL MAP** on an 8-bit plane, textures quantised exactly | 0.02-0.11 (+0.07 CHISEL) | 0.80-0.89 | 60 |
| grey ball-oid (163), + thanks (168) | CPU fixed-point mesh, bucket sort, quads as one polygon, packed-u,v pair spans | 1.10 / 0.87 | 1.81 / 1.58 | 55 / 60 |
| orange ball-oid + greetings (185, 200) | same, 140x140 box | 1.15 | 1.86 | 54 |
| the melt (216) | CPU feedback pass every third tick | 0.4 avg, 1.4 peak | 1.1 avg | 60 (a slow frame a pass) |

The board budget is ~1.67 Mc for 60 fps. Everything is inside it except the two ball-oid parts
(~0.15-0.2 Mc over: ~54-55 fps estimated; the cost is ~3,700 polygon rows a frame at ~100 cycles, the mesh being ~800 small faces: two rasteriser rewrites moved it little); see §5. Two optimisations already paid for themselves: the
flames on the CPU missed the 4 KB D$ about once a texel (2.4 Mc a frame), and copying the
credits' background every frame cost 1.0 Mc (now 0.04).

Things that cost nothing on KESTREL that the Falcon paid for in pixels or registers: the mode 805
line doubling (copper LBASE every line), all four shakes (LBASE offsets from the original tables),
the still pictures (drawn into both buffers once). The DSP's two jobs move to: the MOD to BARD
(`zg.requestSong`), the 3D to the cart CPU.

## 5. What KESTREL lacks / what is approximated

**What KESTREL lacks** (nothing blocks the port):

- **CHISEL 16-bit pixels**: MAP and AFFINE read and write 8-bit indices only. The flames get
  around it exactly (255 / 64 colours, an 8-bit plane swapped in); the ball-oid could too (its
  env maps have 64 / 85 colours) but it shares the screen with the greetings and the thanks texts
  in true colour, so it is drawn by the CPU. With 16-bit CHISEL AFFINE the ball-oid would cost
  ~0.2 Mc instead of ~1.1 (the roadmap's "CHISEL 16-bit pixels" P2 study).
- **No DSP**: the 3D runs on the cart CPU in fixed point (402 vertices, ~800 triangles a frame).
- **A blend op**: the feedback passes (825, 816, 83E: `(a>>1 & $7BEF) + (b>>1 & $7BEF)`) are CPU
  work, ~0.3 Mc per full-screen pass with two pixels a word. Fine here; a CHISEL "average with
  neighbour" or the planned TC hardware fade would make them free.

**Approximated in the port** (the rest is the original's algorithm on the original's data):

- **The ball-oid's shape**: the DSP's ring-radius formula, decoded (3.9). The on-screen size and
  the 5/4 height are fitted to the capture (the DSP's projection was not decoded).
- **Credit picture 4** (MUSIC, MSG's name): its Pack-Ice stream (file offset 1,270,360) does not
  depack with `ice.zig` (the other four do; `scripts/unice_dbg.py` fails 4 bytes in). The picture
  was taken from the running original's depack buffer (`$3A2F4C`, 153,606 bytes, Hatari Falcon,
  RGB50) into `png/ice_1270360.png`, from which the art tool rips it like the others.
- **Timing fits**: the credits' time unit (1 s, not 2 s), the thanks text's fade pace and the
  melt's pass rate (every third tick) are fitted to the capture, not read from the code (they
  hang on clock rates the static read cannot pin down). The capture also shows every part change
  ~0.3 s after its row; the port follows the music exactly (the lag is most likely Hatari's A/V
  offset in the recording).
- The 812 zoom map and the blob paths are generated (exact formulas); the zoom map's RGB-path
  row doubling is kept as the code reads it.
- **Published** (Matt, 3 Nov 2026): the cart carries the original's data
  (`apps/zig/assets/screens/falcon_ays/`, ripped by `tools/falcon_ays_art.py`) and MSG's MOD
  (`docs/music/falcon_ays.mod`). The parts keep generated stand-ins only as a fallback for an
  empty slice: in practice credit picture 4.

**Fixed after Matt's first board run (3-4 Nov)**: the MSG picture (above); the ball-oid morph
(decoded); the thanks strips are 160x16, not 320x8 (they were stretched); the blob rows advance
160 entries + d4/2 (the shear was double) and a variant re-inits only when another part took the
state word `$2EEB26` (813's freezes leave it, so the green streaks keep moving); the credits'
time unit is 80 ticks (the 833 jolt lands mid-build as in Hatari, not after the picture is done);
chosneck's offset path is the ripped table. Open: "the blue chosneck title effect" (Matt's item 4)
was not reproduced in the browser model; the capture (AVI) shows the 804/805 screens ~8 px left of
Hatari's own screenshots, so compare against Hatari screenshots, not the AVI, for x positions.

## 6. Reproducing

- Re-rip (only to change what is ripped): `python3 tools/falcon_ays_art.py prototypes/falcon_ays_re
  apps/zig/assets/screens/falcon_ays` (`prototypes/falcon_ays_re` holds `COMFORT_unpacked.PRG` and
  `png/ice_*.png`). `scripts/unice_dbg.py` shows where credit 4's stream stops depacking.
- Side by side: `python3 scripts/grab.py video/ays_rgb50.avi shots orig <t...>`, `node
  prototypes/falcon_ays_re/scripts/shots.mjs <dir> <t...>` (from the checkout root), `python3
  scripts/compare.py shots <dir> out.png <t...>`. Comparison sheets of 3 Nov (rip build):
  `shots/cmp_rip_A.png` (0-51 s), `cmp_rip_B.png` (57-128 s), `cmp_rip_C.png` (133-220 s).
- The gate: `node apps/falcon_ays_headless.mjs` (+ `--break script`, `--break art`).

## 7. Matt's third board run (4 Nov)

- **Flashes: one path.** Every flash (823 white, 824 white, 81A/81B the grey ramp) now goes through
  `Show.drawFlash`: the border (BACKGROUND) and the screen in one colour together. On the flames'
  8-bit plane the flash fills the plane once with one palette entry and recolours that entry each
  frame, so the plane is not switched mid-part and there is no double-buffer frame between the
  border and the screen (the board showed some flashes on the border only there: the "fingerprint"
  halftone flames). 824 now fills the whole 200 lines (its letterbox-only band left a black frame
  inside a white border). Checked on the full 400x280 raster (`FULL=1 scripts/shots.mjs`) at
  19.7, 30.85, 127.15-127.7, 132.6-132.75, 136.1-136.7 s. The fade length matches Hatari: the
  capture's flash at 127.6 s is dark again by 127.8 s; the port's 81A runs 31 timer calls at 100 Hz.
- **The RG ship "staying"**: in the port and in the capture alike the smeared ship holds until 807
  (43.96 s) clears it (capture frames 40.6-44.0, port 41-44.0 black). Not reproduced; needs the
  board time Matt saw it at.


## 8. Matt's board run of 13 Nov: four bugs

All four showed in the browser too (none was a board-vs-browser difference). Pinned by
`apps/falcon_ays_board.mjs` (+ `--break smear|flash|shake|band`).

- **825's smear too strong, then frozen** (SHOT0006). The port ran a feedback pass every KESTREL
  frame while the jolt ran: 36 passes in 0.6 s, then the hold. The Hatari capture (frame by frame,
  50 fps) shows the picture change every 6th frame from 40.68 to 41.88 s: **11 passes, one every
  6 VBLs** (a 64,000-pixel pass costs the 030 ~6 VBLs on the Falcon's bus), each shifting the
  ship ~half a pixel right, so it blurs lightly and drifts for 1.2 s; then the hold until 807.
  `$72A0` itself is right; only its rate was wrong. The jolt (HDB/HDE) does not show in Hatari's
  capture. Now one pass every 6 ticks, 11 in all (show.zig `smearDue`).
- **White screens in a black border** (SHOT0007 = 821's inverted blobs at ~64.8 s; 822's push
  to white looks the same). The flashes (823, 824, 81A/B) already hit the border in one path
  (§7). Note: on the Falcon the true-colour border is Videl colour 0 (`$FF9800`, Hatari videl.c),
  which the intro never writes (the only store, `not.l $FF9800` at `$CD32`, is the credits'
  particle allocator's failure path): **the original's border is black throughout, flashes
  included**. Matt reads a white picture in a black border as a flash out of sync, so the border
  now follows the blob LUT's entry for an empty sum (the picture's background): white for 821,
  rising with 822, black for every other blob picture (show.zig `backdrop`).
- **The sideways shakes wrapped** (SHOT0011, the credits' 833 jolt). A shake moves each line's
  LBASE; a line starting dx pixels early shows the row above's last dx pixels (the CODE plaque's
  edge down the left). The Falcon moved its display window, its border showing in the gap. Now
  plane 2, an 8-bit mask over the picture (palette 1 opaque black, the rest transparent), covers
  the uncovered columns, enabled only while a sideways shake is off zero (~0.6 s a jolt; +1 plane
  pass, ~0.6 Mc, only then): screen.zig `maskColumns`.
- **829's white band missing on the left** (SHOT0013 is the 839 frame for reference). 829 clears
  only the ball's box (x 160..319, lines 25..175, `$7A5E`); the white left of it is 824's band,
  still in the Falcon's buffers. The port drew 824 on the flames' 8-bit plane (the flames were
  up), so the true-colour buffers held black. Now 829 paints the band (black, white on lines
  25..174) into both buffers before its first ball.
