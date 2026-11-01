# NATRIUM (RNO, 96k intro): how it works

Written 1 Nov 2026, reconstructed from the port. The RE workspace (`re/<part>/SPEC.md`, the Python
reference models such as `re/envmap/envmap_ref.py`, the Hatari snapshots) was lost with a scratchpad.
What survives: the port's comments (`apps/zig/scenes/rno_natrium.zig`, `apps/zig/scenes/rno_natrium/`),
its tests (`verify_test.zig`, `apps/rno_natrium_headless.mjs`), the commit messages (`2ce46a6f`,
`8d1d6efb`, `240e4b17`, `18bd2479`, `8574a604`) and a session note of 24 Sep 2026
(`zigmachine-rno-dhs-ports-2026-09-24`). Every claim below comes from one of those; inferences are
marked **(inferred)**.

RNO (Rave Network Overscan), NATRIUM, a 96k intro for the Atari ST (1 MB, 8 MHz). Code Britelite
(the env-mapped objects are his), music 505 ("Triplex"), graphics Bracket, Britelite and Fragment.
Port: cart 68, on main since `2ee745ba` (24-25 Sep 2026).

## Short answer

- **One straight-line program on one VBL counter.** The VBL bumps a global long `$144AC` and a
  per-part word `$144A0`; each part busy-loops on `$144AC` against a constant (cues are multiples of
  `$40`), calls an effect, waits for a VBL. 153.6 s, `$1E00` VBLs, then it quits to the desktop.
- **No rasters, no borders.** The intro installs only a VBL (no HBL, no Timer B; checked on part 1).
  Low res, 320x200, 16 colours, one palette per part.
- **Everything is plane tricks.** Effects write only the bitplanes they own: the dot tunnel is plane 0
  under plane-1 curtains; the chunky box and the env objects write planes 2 and 3 only, beside or over
  a 4-plane picture. Two 32000-byte screens, but only the twister swaps them.
- **Interlaced updates.** Most effects refresh ONE line parity a call, and the parity comes from a
  shared long `$144B8` that the routines read three different ways.
- **The env-mapped objects** (a chamfered cube, a pentagonal prism) are rendered into a 128x128 chunky
  buffer by an affine sphere-map filler, converted to planes 2,3 with a 2x2 ordered dither, one new
  frame every 3 VBLs.
- **Lookup tables everywhere:** a 160x100 offset map drives both tunnels, a precalculated 256 KB pair
  of tables drives the twister, generated code (1000 blocks) drives the dot tunnel.

## 0. Getting at the code

- Source: fujiology `ST/R/RNO/NATRIUM.ZIP` (session note). `NATRIUM.PRG` is UPX-packed (UPX 3.03;
  unpacked with `upx -d`, session note).
- Addresses below are the unpacked program's as loaded in Hatari: **TEXT at `$AA9A`** (the same base
  as RNO SODIUM and VEX).
- Data: 8 IFF ILBMs embedded in the program (session note); the port's assets are cut from TEXT by
  `tools/private_tools/rno_natrium_assets.py`, each checked against the RE artefacts. Main tables:
  sine `$CA72` (1280 s16, amplitude 256, period 1024, cos at +256), palettes `$14360..$1449F`, tunnel
  map `$144C8` (160x100 words), cube `$14128`, prism `$13F38`, env texture `$52492` (128x128, levels
  0..12), skin `$201C8` and face `$1C1C8` textures (128x128, 0..6), chunky-box LUT `$56492`, dither
  `$EE1A`, chrome strip `$243C8+$8C` (512x64x4), greetings `$4F7D4+$4A` (224x128x1), credit strip
  `$5061E+$74`, pictures `$37F54` (grey girl), `$3FCD4` (reclining girl), `$47A54` (red-scarf girl).
- Generated at init by the original and rebuilt by the port at comptime: the bit-doubling LUTs
  `$B751A` / `$B771A` (built at `$C348`) and the reciprocal table `$13D38` (built at `$C454`:
  `[0]=$4000`, `[1]=$7FFF`, `[n]=$8000 divs n`).
- Not recorded in the surviving sources: the PRG's size and md5, TEXT/DATA/BSS sizes, the
  disassembly listing.

## 1. Parts

Sequencer `$AA9A..$BEB8` (parts 1-3 and the shared loops `$AB88..$B35E`, parts 4-7 `$B360..$BEB8`).
VBL handler `$C04E`: `$144A0 += 1`, `$144AC += 1`, then the SNDH play call. Counters are `$144AC`.
Rows marked `~` are derived from the state machine (a zoom is 52 calls, one a VBL), not measured.

| `$144AC` | Code | On screen |
|---|---|---|
| 0-`$BF` | `$C90C`, `$C47E` | both screens cleared, black palette; NATRIUM converted into the back buffer |
| `$C0`-`$17F` | `$D670` + `$ABEC` | dot tunnel (plane 0); plane-1 curtains close, 100 steps |
| `$180`-`$2FF` | `$D670` + `$ACC2` | RNO logo revealed row by row (rows 72..127) |
| `$300`-`$47F` | `$D670` + `$AEA8` | NATRIUM revealed bottom-up from the back buffer |
| `$480`-`$53F` | `$D670` + `$AFAC` | logo erased row by row |
| `$540`-~`$5A4` | `$D670` + `$B0B8` | curtains open again (ends on a step count, 100, not the counter) |
| ~`$5A4`-`$5FF` | `$E828`, `$C722`, `$C06E` | set built in the back buffer: blue bands, white-outlined box, grey-girl crop |
| `$600`-~`$633` | `$D472` | vertical zoom-in (52 calls) |
| ~`$634`-`$8FF` | `$DDEC` | chunky box, left: skin tunnel |
| `$900`-`$BBF` | `$C06E` (19 VBLs), `$D7F6` | chunky box: face wobble |
| `$BC0`-~`$BF3` | `$BED8`, `$D570` | zoom-out |
| ~`$BF4`-`$BFF` | `$C47E`, `$F020`, `$EE5A`, `$EB42` | grey girl in the back buffer, first cube frames |
| `$C00`-`$EBF` | `$D472`, then `$EE5A` + `$EB42` | env-mapped chamfered cube over the grey girl |
| `$EC0`-~`$EF3` | `$D570` | zoom-out |
| `$F00`-`$11FF` | `$D472`, `$B41A`/`$B616`/`$B812`, `$BA0E` | reclining girl; credit rows at `$FC0` ("Code.Gfx britelite"), `$1080` ("Gfx bracket"), `$1140` ("Music 505"); white blinds from `$1190` |
| `$1200`-`$17EF` | `$E7C2`, `$E094`, `$BEBA` | chrome twister and greetings, double buffered; palette fade in, fade out from `$17D0` |
| `$17F0`-`$17FF` | `$BBE6`, `$BFB4`, `$C47E` | colour-12 screen; red-scarf girl and prism frames in the back buffer |
| `$1800`-`$1ABF` | `$BC62`, `$EE5A` + `$EB42` | curtain (100 steps) onto the env-mapped prism, then the prism |
| `$1AC0`-~`$1AF3` | `$D570` | zoom-out |
| ~`$1AF4`-`$1B0E` | `$C06E`, `$E980`, `$C722`, `$BF1A`, `$DB14` | set rebuilt, box on the right, red-girl crop (init overruns `$1B00`) |
| `$1B0F`-`$1DBF` | `$D472`, `$DB14` | chunky box, right: skin rotozoom |
| `$1DC0`-~`$1DF3` | `$D570` | zoom-out |
| `$1E00` | `$BEAE`, `$CA1A` | machine restored, SNDH exit, `rts` to the desktop |

Music sync: the sources record only that one VBL drives both the SNDH and the timeline; the parts
start on multiples of `$40` VBLs. No per-part song cue (pattern position, sync byte) is recorded.

Evidence base: Hatari RAM snapshots at counters `$435`, `$700`, `$A00`, `$D00`, `$1100`, `$1500`,
`$1900`, `$1C00` (both screens, the front-buffer pointer `$CA5C`, and `$144A0`). The port reproduces
all eight byte for byte (`verify_test.zig`).

## 2. The effects

### 2.1 Shared machinery

- **Two screens** at `$5F400` and `$67400`. `$CA5C` is the "front" pointer, `$CA60` the other. Only
  `$BEBA` (twister) ever swaps them; every other part draws into the screen being shown and lets the
  interlace hide the tearing **(inferred)**.
- **The field-parity long `$144B8`** is read three ways, and the disagreement is part of the
  sequence:
  - `$D670`, `$D472`/`$D570`, `$EB42`: the high word = (word + 1) & 1, and that is the parity;
  - `$DDEC`: parity = word & 1, then `addq.w #1` with no mask;
  - `$D7F6`, `$DB14`: the LONG = (long + 1) & 1, which zeroes the word the others read and toggles
    `$144BA` instead.
  The port keeps all three (`st.Flag`); the snapshots only match if it does.
- **Palettes** are `movem.l` from a block at `$14360 + 32n` into `$FF8240`. Colour 0 stays `$000`
  throughout.

### 2.2 Part 1: the dot tunnel `$D670`

- A lookup-table tunnel: each map entry `(u, v)` samples a 16x32 one-bit blob texture (`$241C8`)
  with v scrolled by `$144A0 & 31`. One texel = 2 pixels (the `$B751A` bit-doubling LUT).
- `$C2DC` derives `(u, v)` from the `$144C8` source word: u = low nibble, v = 5 bits that an octant
  term twists into a spiral.
- **Plane 0 only**, one line parity a pass: the top half from map rows 0..49; the bottom half is the
  same byte **bit-reversed, doubled and inverted** (`$B771A`), written mirrored from `$7C58`. The
  two-tone split at line 100 is that inversion, not a raster.
- The original runs it as generated code at `$C391A`: 1000 unrolled 48-byte blocks. The port is the
  loop.
- Between passes the sequencer runs one row operation a VBL on the other planes: plane-1 curtains
  (`$ABEC` with `$FFFF`, `$B0B8` with 0; step n = rows 2n and 199-2n), the RNO reveal (`$ACC2`,
  planes 1..3 from the ILBM body), the NATRIUM reveal from the back buffer (`$AEA8`, rows 127-n,
  bottom-up) and the erase (`$AFAC`: plane 1 = `$FFFF`, planes 2,3 = 0).
- Measured: one pass a VBL (F = 19, 20, 21 in consecutive snapshots).

### 2.3 Parts 2 and 7: the chunky box `$DDEC`, `$D7F6`, `$DB14`

- An 80x80-cell box, a cell 2 px wide and 2 lines tall, lines 20..179, at x = 16 (part 2, group 1)
  or x = 144 (part 7, group 9). **Each call writes ONE field** (lines `20 + 2r + p`), so the two lines
  of a cell are one call apart.
- **Planes 2 and 3 only:** seven shades from pens 0/4/8/12 by horizontal dither, via the `$56492`
  table (4 x 8 words: cell k of a `movep` byte). Writes are `movep.w d,4(a5)` (left byte) and
  `movep.w d,5(a5)` (right byte).
- `$C06E` converts a texture into four 64 KB C2P arrays before a part (19 VBLs; the port computes the
  same pixels directly, `writeRow`). What the four arrays hold exactly is not recorded.
- **Tunnel `$DDEC`** (part 2, skin texture): the `$144C8` map after the `$C308` conversion is a byte
  offset `v*256 + u*2` (0 = the hole). The 80x80 window pans across the 160x100 table: x from
  `SIN[3f]`, y from `SIN[4f]`; the texture base moves `v += 1, u += 0.5` a frame. For the hole the
  original zeroes the four arrays' word at the base for the call, so offset 0 reads black. The window's
  last cell lands on entry 15999 of 16000: in bounds with nothing to spare (proved at comptime,
  `8d1d6efb`).
- **Wobble `$D7F6`** (part 2, face texture): per-column displacement from two summed sines (steps
  `$0A`, `$16`, x12) and per-row shift from two more (steps `$0E`, `$12`, x24, logical shift 0..254).
  It builds its tables, waits for the VBL, then draws.
- **Rotozoom `$DB14`** (part 7, skin texture): angle `3f`, zoom `SIN[12f]*4 + $480`, `muls.w` +
  `lsr.l #8` keeping the low word; 80 column offsets, then a per-row start. **Original bug, kept:**
  `d7.w` is set to `$4000 - 32X`, then `bsr $DD84` does `move.w #$7FFE,d7`, so V0 is always `$7FFE`
  and only U is centred.

### 2.4 Parts 3 and 6: the env-mapped cube and prism (Britelite)

Objects: chamfered cube `$14128` (568 bytes), pentagonal prism `$13F38` (496 bytes); format
`nv, nf`, 6 header words, vertices, faces (three even vertex offsets), per-vertex normals. At most 24
vertices and 44 faces. The object only rotates: no translation, no path.

- **`$F27A` rotation:** a 3x3 matrix from angles f, 2f, 3f (indices into the 1024-step sine),
  `muls.w` + `asr.l #8` everywhere, each term truncated to a word.
- **`$F34A` / `$EEF0` projection:** R = M.v; `x = divs(Rx, Rz/256 + 800) + 63`, same for y; the 16-bit
  depth key is `Rz/256 + $8000`. The port proves at comptime that for both objects the divisor stays
  positive and the quotient fits a word (otherwise a 68000 `divs` overflows and leaves the register
  alone).
- **`$F38C` sphere map:** per-vertex normal rotated by the first two matrix rows, `>> 2`, `+ $4000`:
  U and V in 8.8 on one 128x128 tile. No lighting: the texture is the light.
- **`$EF22` back-face cull:** a 2D cross product compared on **16-bit** words (each product truncated
  before the `cmp`).
- **`$F070` sort:** two-pass stable LSD radix sort on the face key (sum of three vertex keys; low
  byte, then high byte), drawn **reversed**, largest key (farthest) first.
- **`$F3D0` affine filler:**
  - constant gradients per triangle, from `hiword(2 * num * RECIP[n])` (the `$13D38` table);
  - the texture position is **one packed long, V high word, U low word**, stepped by one 32-bit add a
    line, so a carry out of U leaks into V. Kept;
  - the per-pixel steps are baked by `$F61C` into a **128-entry displacement table**, which the
    original patches into an unrolled `move.b d16(a1),-(a4)` span. The table is built for the
    triangle's middle width; spans wider than that read **stale entries** from the previous build.
    Kept. `$EE5A` clears the table to 0 per frame;
  - the texture is read through `$6F81A`, a 256x256 tiling of the 128x128 map at a flat 16-bit offset;
    texel values are the levels doubled (`$C2DC`).
- **`$EE5A` frame:** clear the visible 80x80 window (rows and columns 24..103 of the 128x128 buffer
  `$B791A`) to 8 (level 4), render.
- **`$EB42` C2P:** chunky rows 24..103 to **planes 2 and 3** of lines `2j + parity`, x from 0; each
  chunky pixel becomes 2 screen pixels through the 2x2 ordered dither `$EE1A` (16 levels x 4 bytes,
  picked by the line parity). So each render updates one field: 160x80 pixels of a 160x160 area.
  **Quirk:** window rows 72..79 convert only 9 of 10 groups, so x 144..159 of the last 16 lines is
  never written.

### 2.5 Part 4: credits `$B41A` / `$B616` / `$B812`, `$BA0E`

- The strip ILBM is the reclining picture's own lines 182..197 three times, each with one credit burnt
  in. Right after a VBL the sequencer overwrites those 16 lines with row k (three identical unrolled
  blocks).
- `$BA0E` white blinds: 100 steps, lines 2n and 199-2n set to `$FF` (colour 15 = `$777`).

### 2.6 Part 5: the chrome twister `$E094`

- The texture is the 512x64 chrome strip: 64 "angles" of an 8-px slice.
- Each 4-px screen column picks an angle from two sines (`SIN[7f/2 + 2i]`, `SIN[-2f + i]`) and a
  "pass" (0..7) from their difference.
- **`$E6D4` precalc** (~42 VBLs, run during the credits) merges pixel PAIRS from two neighbouring
  angles into two 128 KB tables (T1 for pixels 0-1 / 2-3, T2 for 4-5 / 6-7), so a `movep.l` blit
  assembles 8 pixels from 4 table longs. The port evaluates the same tables per long instead of
  holding 256 KB.
- Vertical bob: `y = (SIN[4f]*55 + $4000) >> 8`, lines 9..119 over 256 frames; 4 erase lines (`$FF`)
  above and below the 64 texture rows.
- Greetings: slot `(counter - $1200) / 96`, 8 lines of a 224-px 1-bit bitmap into all four planes,
  top on even slots (lines 1..8), bottom on odd (191..198). **Nothing erases a name but the next.**
- Double buffered: draw into `$CA5C`, `$BEBA` shows it and swaps; `$E7C2` first fills both buffers
  with colour 15.
- Palette fade (`$BB32..$BBA8`, `$BB3C`/`$BB7A`): a 16-word window slides along the 32 words at
  `$14420` (in: one step every 2 frames while f <= `$20`; out from `$17D0`), colour 0 forced black.

### 2.7 Transitions and the set

- **`$D472` / `$D570` vertical zoom:** a 200-entry line table (`$6F41A`), the picture squashed into a
  band of 2n lines about line 100, step `200/(2n)` in 16.16 from a `divu.w`, the integer part ANDed to
  a byte. Black lines point at **"line `$7D00`"**: back buffer + 32000, the zeroed gap after the
  buffer. 52 calls (`$144A4` += 2 until `$68`); each builds the table, waits for the VBL, copies one
  field. Zoom-out's n is a signed word compare, `max(100 - step, 0)`.
- **`$BC62` / `$BC6E` curtain** (part 6): 100 steps, back lines 2n and 199-2n onto the front.
- **`$E828` / `$E980` set** (differ only in the box x): seven blue bands (pens 1/2, planes 0,1, a line
  filled by 20 x `move.l d1 / move.l d2`), the box cleared, a pen-3 outline.
- **`$C722` crop:** 48x100 pixels of a girl picture, pixel-doubled to 96x200, with a 1-px pen-15
  border ORed down both sides.

## 3. The budget

The figures come from the snapshots; the port's sequencer is a state machine and has to be told what
a 68000 cycle count decided (`timeline.zig`).

| Routine | ST cost | Source |
|---|---|---|
| `$D670` dot tunnel pass | 1 VBL | measured (F = 19, 20, 21) |
| `$DDEC` box tunnel | **~1.10 VBL a call**: 186 calls in 205 VBLs (its call-count word reads `$BA` at `$700`); about 1 frame in 10 skipped | measured; port: `DDEC_COST` = 1129/1024 VBL, first call at phase 205 |
| `$D7F6` wobble, `$DB14` rotozoom | 1 VBL, one call each | measured; the field each frame lands in says an ODD number of wobble calls overran before `$A00` (where: not recorded; the port takes the first), and an EVEN number of rotozoom calls before `$1C00` (port: none) |
| `$EE5A` + `$EB42` env objects | **a new frame every 3 VBLs** (f = 198/201/204, 150/153/156) | measured |
| `$C06E` texture to four 64 KB C2P arrays | **19 VBLs** (`$144A0` = 237 at `$A00`); the box shows the last tunnel frame meanwhile | measured |
| `$E7C2` fill both screens | crosses one VBL (counter = `$1201 + f` in the twister) | measured |
| `$E094` twister | 1 VBL; one call overran (the `$1500`, `$1900`, `$1C00` screens are one swap away from draw-every-VBL) | measured; which call: not recorded |
| `$E6D4` twister precalc | ~42 VBLs | port comment |
| part 7 init | reaches `$1B0F` (`$144A0` = `$BD` at `$1C00`): 21 VBLs of explicit waits + 4 more (`$E980`, `$C722`, `$BF1A`, the back-buffer rotozooms) | the 4 are **calibrated** (`P7_COPIES`), not cycle-counted |

What the budget forced (mechanisms from the code; the reasons are **inferred**):

- **The env objects at 16.7 fps, one field a frame:** a frame is 3 VBLs of transform, sort and
  filling; each C2P writes one line parity, so a full 160x160 picture is 6 VBLs old at its oldest
  line. The angle steps 3 a frame (f is the VBL counter, sampled every third VBL).
- **A 128x128 chunky buffer with an 80x80 window, two planes, a 2x2 dither:** the filler writes bytes
  (`move.b d16(a1),-(a4)`, one instruction a pixel); the C2P only fills two planes, and the dither
  stretches 13 levels over 4 pens. The other two planes keep the picture.
- **The chunky box at 80x80 cells, one field a call, two planes, seven shades:** `$C06E` precomputes
  four C2P arrays (19 VBLs) so the per-frame loop is lookups and `movep`, and even so the tunnel
  misses ~1 VBL in 10.
- **The twister's 256 KB tables:** 42 VBLs of precalc, hidden under the credits, so the per-frame
  draw is 4 table longs and a `movep.l` per 8 pixels.
- **The dot tunnel as generated code:** 1000 unrolled blocks to fit a 320x100 one-plane pass (mirrored
  to 200 lines) in one VBL.

## 4. Music

- "Triplex" by 505, an SNDH **ripped out of NATRIUM.PRG itself**: init `$564D2`, exit `$564D6`, play
  `$564DA` (called from the VBL). 36,424 bytes, `rno_natrium.sndh`, verified on the sealed YM
  (`apps/sndh_headless.mjs`: mode 4, peak 0.56).
- The archive's `prototypes/sndh_lf/505/Triplex.sndh` is a **different build** flagged `~a`, which
  this machine plays as silence, so the intro's own copy ships. (The port's header reads `~a` as STE
  DMA; a later memory note says `~a` is an MFP timer flag and only `e` is DMA. See open questions.)
- The intro calls the SNDH exit at `$1E00` (`$BEAE`). No sync between song and parts beyond the
  shared VBL is recorded.

## 5. What the port does differently, and why

- **The ST screens are kept as the ST had them:** two 32000-byte interleaved-bitplane buffers that
  every effect writes word for word, so "which planes an effect touches" survives and a buffer can be
  compared with a Hatari RAM dump. The shown one is expanded to palette indices on ONE plane
  (`st.toChunky`, what the shifter did), 0.6 ms a frame at port time; since `18bd2479` with u32
  stores and only when a VBL has run (`dirty`).
- **The effects are the RE models' integer math,** not the 68000's code shape: no generated code, no
  `movep`, no C2P arrays, no 256 KB twister tables (`writeRow`, per-long `table()`). Byte-identical
  output, checked by CRC against the models and the eight snapshots (`verify_test.zig`), and on the
  displayed frame through the palette at six counters (`apps/rno_natrium_headless.mjs`, gated in
  `build.sh`).
- **The VBL clock is not the host frame.** The timeline is music-synced, so `update` accumulates real
  time and ticks one VBL per 20 ms (`VBL_US`), at most `MAX_VBLS_PER_FRAME` = 3 a host frame after a
  stall ("catch up a little, not all of it"). The host runs at a fixed 60 Hz (session note), so the
  screen changes on about 50 of 60 frames **(inferred)**.
- **The cycle-count timing is modelled:** `stall` for multi-VBL routines (`$C06E`, `$E7C2`, part 7
  init), a 1/1024-VBL budget for `$DDEC`, explicit overruns for `$D7F6` and `$E094`.
- **Unchecked indices proved at comptime** (`8d1d6efb`): ReleaseSmall does not trap, so the sine
  range (-256..256), the tunnel window, the object face indices and the projection divide are proved
  against the only data that reaches them.
- **Memory:** the screens (64,000 B) and the chunky buffer (16,384 B) come from `zg.mem` once per cart
  load (`240e4b17`): cart RAM 723 KB to 645 KB.
- **Ending:** at `$1E00` the intro starts over, music restarted; the harness checks frame `$150` of
  the second run equals the first. Escape leaves (Space quit the original).
- **Board:** 60 fps (`fpga/review/ZIGGY_ISA_EXTENSIONS.md`), the planar expansion ~0.46 Mc a frame
  there. Two dated regressions were recorded: 60 to 47 with the dirty-line compositor (18 Oct, adaptive
  bypass requested) and 60 to 55 with the combined-bitstream firmware (`PERFORMANCE_REVIEW.md` row 9,
  not merged until bisected).

## 6. What KESTREL could lift: the ZIG mode

Matt's request (`docs/ROADMAP.md`, `8574a604`): a key toggles a KESTREL mode, the original stays the
default (harness-pinned): fullscreen (open borders), the env-mapped cube and prism rendered every VBL
with no dither, the tunnels and the rotozoom at 1 VBL and full screen. A showcase for the 16 KB D$,
ZM-X (`tex2d`, `mulsh`) and CHISEL v2 (AFFINE / MAP). Figures below are from
`fpga/review/KESTREL_NEXT_ISA.md` and `docs/HW_API.md`, not measured on this cart.

- **Drop the ST screens in ZIG mode.** Render chunky straight into an overscan plane; the planar
  buffers and `toChunky` (~0.46 Mc on the board) go. The original path stays for the default mode.
- **Env cube / prism, every VBL:**
  - The 1/3-step comes for free: `matrix(f)` already uses angle indices f, 2f, 3f with f the per-VBL
    counter, and the original only samples it on `f % 3 == 0` (`env_loop`). Rendering every VBL at the
    current f is a third of the original step a VBL, the same motion. To go finer than a VBL, keep the
    angle in fixed point (e.g. a Q16 index) and interpolate the sine table **(inferred)**.
  - Transform: ~24 vertices, trivial; `mulsh` + a 256-entry reciprocal table + one Newton step is ~50
    cycles a vertex (ISA §1.2) against the 68000's `muls`/`divs`.
  - Fill: CHISEL AFFINE span lists (24-byte spans `x0, x1, y, u0, v0, du, dv`, wrapped by
    `U_MASK`/`V_MASK`) take the per-pixel work off the CPU; or `tex2d` in a CPU span loop. The 128x128
    env texture (16 KB at one byte a texel) fills the 16 KB D$ exactly **(inferred)**.
  - Full-res, full-colour: no 2x2 dither, no plane limit: the 13 levels can become a 256-colour ramp,
    or a per-face `shade[light][texel]` LUT (which `tex2d` addresses, ISA §1.4).
  - The original's quirks (U-to-V carry leak, stale span-table entries, 16-bit back-face compare)
    belong to the faithful mode; whether ZIG mode keeps the look or corrects them is Matt's call.
- **Tunnels, 1 VBL, full screen:** CHISEL MAP fills a `W x H` box from a u16 `(v<<8|u)` map plus
  `U_OFF`/`V_OFF`, ~0 CPU (ISA §2: tunnel + roto overlaid at 60 on 2 planes). The `$144C8` table after
  `$C308` is already `v*256 + u*2` byte offsets, one shift from MAP's format **(inferred)**; but it is
  160x100, so a full-screen tunnel needs a new map built at init (integer, or init-time float per the
  float rule). The pan (`SIN[3f]`, `SIN[4f]`) becomes the box origin or `U_OFF`/`V_OFF`; the hole
  (offset 0 = black) needs a key or a black texel. The `$DDEC` 1-in-10 skipped frame disappears.
- **Rotozoom, 1 VBL, full screen:** CHISEL AFFINE with one span a line (Mode 7 shape); or the CPU
  with the 16 KB D$ + `tex2d` (ISA table: 128x128 rotozoom 320x200 from 1.6-2.2 Mc to ~0.7 Mc,
  60 fps). The 128x128 skin texture fits the D$. The V0 = `$7FFE` bug is the faithful mode's.
- **Wobble:** per-row and per-column offsets into a 128x128 texture: a CPU loop with `tex2d`, or MAP
  with a map rebuilt per frame **(inferred)**.
- **Twister:** the 256 KB `movep.l` tables exist only because of planes; chunky, it is a CPU loop with
  `tex2d` over the 512x64 strip **(inferred)**.
- **Dot tunnel:** the same MAP op on the one-bit blob texture, full screen, both halves; the
  inverted, mirrored bottom half is a palette swap below line 100 (copper `PAL`) rather than an
  inverted LUT **(inferred)**.
- **Timeline:** unchanged; the ZIG mode replaces renderers, not the sequencer, so the music sync
  holds.

## 7. Files

- Port: `apps/zig/scenes/rno_natrium.zig`; `apps/zig/scenes/rno_natrium/` (`timeline.zig`,
  `parts_a.zig`, `parts_b.zig`, `tunnel_dots.zig`, `chunky_box.zig`, `envmap.zig`, `envfill.zig`,
  `twister.zig`, `credits.zig`, `transitions.zig`, `decor.zig`, `st.zig`, `assets.zig`,
  `verify_test.zig`).
- Assets: `apps/zig/assets/screens/rno_natrium/*.bin` (19 files, addresses in `assets.zig`); music
  `rno_natrium.sndh`.
- Harness: `apps/rno_natrium_headless.mjs` (`build.sh` line `gate rno_natrium ...`); catalog entry
  "RNO NATRIUM".
- Lost: `re/<part>/SPEC.md`, the Python reference models, the Hatari snapshots. The models survive
  only as CRC32s in `verify_test.zig`; the snapshots as CRCs there and SHA-256s in the harness. Tools
  named by the port (`tools/private_tools/rno_natrium_assets.py`, `rno_natrium_expect.py`,
  `rno_natrium_screens.py`) are in the untracked private tools, if they survive.

## Open questions

- Where the odd `$D7F6` overrun and the `$E094` overrun happen; the port places them by assumption.
  A live log of `$144A0` at each call's entry would replace every calibrated number.
- `P7_COPIES` = 4 is calibrated to the `$1C00` snapshot, not cycle-counted.
- What `$C06E`'s four 64 KB C2P arrays hold, exactly.
- Is the archive's `505/Triplex.sndh` `~a` flag STE DMA (the port's header) or an MFP timer (later
  note)? Either way it was silent here; the reason is not settled.
- Any music-to-part sync beyond the shared VBL (none found in the sources).
- The original file's size and md5, and TEXT/DATA/BSS sizes: not recorded.
- How the cube's planes 2,3 combine with the grey girl's planes 0,1 on screen: which palette entries
  `$143C0` (`PAL_CUBE`) and `$14480` (`PAL_PRISM`) give the overlap is not documented.
- The env texture's level range (0..12, doubled) against the dither's 16 entries: whether levels 13..15
  are ever reached.
