# KESTREL boot screen: a design study

2026-11-13. Matt: "make analysis and study for a small boot screen similar to the dreamcast or ps1…
iconic!". Original design only: no Sony, Sega, Nintendo, Commodore or Atari logo, sound or animation
is copied; section 1 studies *why* theirs work and keeps only principles.

Companion study: `prototypes/zest_splash_re/STUDY.md` (how a picture can be on screen while Linux
boots; recommendation C = a U-Boot OSD banner now, B = a splash cart U-Boot starts on ZIGGY). The
design below is built for B and degrades to C. Prototype: cart `kestrel_boot` (129),
`apps/zig/scenes/kestrel_boot/`, harness `apps/kestrel_boot_check.mjs`, frames in this folder.

## 1. What makes a boot screen iconic

Only widely documented facts are used here; no timings to the frame are claimed for the consoles.

| Machine | What you see | What you hear | Why it sticks |
|---|---|---|---|
| PlayStation (1994) | a white screen, then the company wordmark and a diamond-shaped mark assembling, then a dark screen with the console's logo | a soft swelling tone, then a deep, long, reverberant chord on the logo | two beats (maker, then machine); the sound is slow and "expensive", it promises power; a few seconds |
| PlayStation 2 (2000) | dark space, abstract towers/particles, then the logo | an ambient, airy pad | mood over brand: the machine as a place; longer, but the second boot (the logo alone) is what people remember |
| Dreamcast (1998) | white background, an orange spiral drawing itself in one stroke, the name under it | a short bright rising figure with a resolving chord | **one gesture** (the spiral draws once), one colour on white, about 3 s; the mark *is* the motion |
| GameCube (2001) | a small cube rolls/tumbles across the screen and folds into the logo | a playful jingle synced to the cube's moves; a hidden variant when a button is held | motion and sound are the same event, note for note; an easter egg rewards the curious |
| Nintendo 64 | the company logo (a rotating 3D N on some games) | none at system level | shows off the hardware (real-time 3D) in the logo itself |
| Amiga Kickstart 1.x | a hand holding a floppy disk, drawn as filled vector shapes on white | silence | it is not a brand moment but an *instruction* (insert a disk), and the drawing by vectors shows the machine's own blitter fill |
| Atari ST / Falcon TOS | the green/white desktop arrives; later TOS shows a logo and a memory-test bar | no chime (the keyclick) | the memory count is the reassurance: the machine checks itself in front of you |

Principles taken (and only these):

1. **One gesture.** One motion that finishes: Dreamcast's swirl, GameCube's cube. Nothing loops.
2. **The mark is born from the motion**, then holds still long enough to be read (≥ 1 s of stillness).
3. **One sound event, tied to the arrival**: a single chord at the moment the mark lands. Before it at
   most a short anticipation (rising, airy), after it a long decay. The chord is the "it works" signal:
   a broken console boots silent, so the chord is reassurance even with the screen off.
4. **Short**: 3 to 6 s in all. A long boot plays the splash once and then holds, never loops.
5. **Few colours**, one accent. A dark field makes the accent read on a TV across a room.
6. **Show the hardware** (N64, Amiga): the effect itself is a demonstration of the machine.
7. **The machine's lineage** (Atari's self-test, the Falcon's true colour) is part of the story KESTREL
   tells; a kestrel is a small falcon.
8. **Ends on black** so the next thing (KOS's POST, the desktop) starts from a clean field.

## 2. Three concepts for KESTREL

All three: 60 Hz, 400x280 raster, fade to black at the end and a black hold until glass hands off.
Costs use the board model of 23 Oct (CLAUDE.md "Board speed"): ~0.59 Mc a frame per enabled plane,
store ~2.3 cycles, a CHISEL op ~800 cycles fixed; the board drops below 60 fps at ~1.75 Mc.

### Concept 1: WINDHOVER (the hover)

A kestrel is the bird that **hovers**: it holds perfectly still in the wind, head locked, then
stoops. The concept is that one gesture: the bird stoops into frame and stops dead, hovering.

| Frames (60 Hz) | Picture | Sound (YM2149) |
|---|---|---|
| 0-19 (0.33 s) | black | silence |
| 20-79 | a dawn sky fades up from black: indigo top, ember glow on a low horizon, a few stars | f20, f28, f36: the kestrel's call, three short high notes ("klee-klee-klee"), each a quick fall in pitch and volume |
| 50-94 | **the stoop**: the emblem enters from the upper right, three times its size and banked, and dives to the centre, braking with a small overshoot (a 45-entry ease table), landing at exactly 1:1 | a wind rush: noise on channel B, rising in pitch and volume as the bird comes in |
| 95 | arrival: a flash on the sky, a highlight runs down the bird | **the chord**: a strummed open D major (D2 on the envelope "buzzer" in triangle, A3, F#4: root, fifth, tenth), 0/1/3 frames apart |
| 100-160 | the wordmark KESTREL lights letter by letter (6 frames apart), then "ZIGMACHINE" under it | the chord rings and decays |
| 160-249 | still: the bird hovers (no pixel moves) | the bass leaves the buzzer for a plain tone and decays to nothing |
| 250-289 | fade to black, sky and bird together | silent by f260 |
| 290- | black hold | silence |

- Palette: the bird in the kestrel's own colours (rufous back, slate-blue head and tail, black wing
  tips and tail band, a cream rim), sky indigo (#080A1E) to ember (#F0A060), wordmark cream.
- Hardware: plane 0 is an **RGB565 true-colour plane** (400x280, borders open: the Falcon's
  hi-colour) holding the sky, drawn once at init; its fade in, flash and fade out are the
  **TC_FADE / TC_OFS registers**, one write a frame, no pixel touched. Plane 1 is an 8-bit plane: the
  bird is a 128x128 texture drawn by **CHISEL AFFINE** (a span a row, only the rows the bird covers)
  during the 45-frame stoop and never again; the highlight sweep is a **copper list** (four palette
  entries changed per line: a real raster, not pixels); the wordmark appears by **palette** (each letter
  its own entry, zero pixel writes). The 8-bit plane fades with the TC rule in integers, so both
  planes reach black on the same frame.
- Cost: 2 planes = ~1.3 Mc a frame of compositing; CPU: during the stoop ~200 spans (a few Kc) + one
  FILL + one AFFINE; during the glint ~1.1 K copper words; otherwise a few register writes. ~1.5 Mc
  peak: under the 1.75 Mc line. Memory: VRAM 224 KB (TC) + 64 KB (plane) + the list; RAM 16 KB texture
  + 4.8 KB spans, both made at init (the bird is polygons, the sky a formula): **nothing to load** but
  the code. Data in the image: the polygon list, 6 glyphs, a 45-entry ease table, the jingle's few
  register events: well under 4 KB.
- Hand-off: ends black at f290 (4.8 s) and holds; sets a FINISHED word (section 4).

### Concept 2: SIX CHIPS (the self-test as the show)

The Atari ST counted its memory in front of you. KESTREL has six named chips; the boot is them
answering, one by one, and the answers are the jingle.

| Frames | Picture | Sound |
|---|---|---|
| 0-29 | black, a thin white rule across the middle | silence |
| 30-119 | six horizontal **raster bars** light one after another, 15 frames apart, each with its chip's name (ZIGGY, BARD, FRESCO, CHISEL, CHORUS, ZWINDOW) | each bar one note of a rising arpeggio (D3 F#3 A3 D4 F#4 A4), YM channels in turn, a short blip each: six notes = six chips answered |
| 120-160 | the six bars slide together (a copper **line list**, LBASE per line: the picture is not redrawn) into the six strokes of a K monogram | the last note sustains, the bass enters under it |
| 160-240 | the K holds, the name under it | the chord decays |
| 240-280 | fade to black | silence |

- Hardware: one 8-bit plane, colour 0 bars from the copper (or BEAM for split colours), the merge by
  LBASE line lists (HW 1.10.0), the fade by palette. The cheapest: **1 plane, ~0.7 Mc**, no CHISEL.
- The strength: it can be **honest**. Driven by a real check (each chip's ID register read before
  its bar lights; a chip that does not answer leaves its bar dark and its note missing), it is a POST
  you can hear. The weakness: it is information more than emotion, close to a POST; a missing chip
  is also a missing note, which a user may not notice.

### Concept 3: FALCON LINE (the lineage)

A single white line on black (the ST's high-resolution white), which tilts and becomes a horizon;
a feathered floor races toward you under it (Mode 7 on CHISEL), and the emblem rises from the
horizon as the ground stops.

| Frames | Picture | Sound |
|---|---|---|
| 0-40 | the line draws from the centre outward | a Paula sine "ping", rising |
| 40-150 | the line tilts into a horizon, the feather floor (AFFINE, a span a row below it) rushes in and decelerates | YM noise rush, then a bass |
| 150 | the emblem rises above the horizon | a bell chord on the four **Paula** channels (a bell synthesised at build: 4 KB of 8-bit PCM) over a YM bass |
| 150-270 | hold, wordmark | decay |
| 270-320 | fade | |

- Hardware: two 8-bit planes, AFFINE over ~100 rows x 320 px every frame for 2 s (CHISEL busy,
  ~1.4-1.6 Mc), Paula PCM needs the sound CPU's path (on the board: BARD, or CHORUS's PCM registers
  written by ZIGGY). The most spectacular (the Dreamcast-like energy) and the heaviest: it needs the
  whole audio stack in the splash image, which B's first version wants to avoid.

## 3. Recommendation: WINDHOVER

1. It is **one gesture** that means something: the kestrel's hover is its signature behaviour, and
   "stop dead and hold still" is exactly what a boot screen must do (finish, then hold).
2. It **shows the lineage and the hardware** in four seconds: Falcon true colour (the sky and its
   register fade), ST copper rasters (the highlight), Amiga-style palette tricks (the wordmark), and
   KESTREL's own CHISEL (the stoop).
3. It is **cheap where it matters for B**: everything is made at init (no picture, no sample, no
   SNDH to load), the jingle is ~30 YM register writes, the per-frame cost is under the board's line,
   and after the stoop nothing is drawn (the hold costs only compositing). The image is just code.
4. The sound is **YM only**, which on the board has a short path (below), and degrades: in C (the
   OSD banner) the same wordmark can be OSD text; with no sound it still reads.
5. Concept 2's honesty is kept as a variant for later: the six notes of the call/strum could be gated
   by real chip-ID reads (a missing chip = a missing note), but that is a POST, which KOS already has.

## 4. Implementation plan for option B (zeST study §3 B)

Step 0 of the zeST study (measure the boot) still comes first: it says whether the 4.8 s splash plus
its hold covers the kernel, or whether the hold is most of it.

1. **The splash as a flat image.** Build `kestrel_boot` as a monolithic board image (no `system.rv32`,
   no ZX0, no disk descriptor: `cycles/bdisk.c` answers "no disk"), `make board-fw` style, written as
   `splash.bin` on the card by `glass_sd.py`. It must be independent of the ROM (it imports nothing
   from `rom_sdk`: true of the prototype) and of the drive.
2. **Sound without BARD.** On the board a cart's `zg.ymWrite` is an effect the firmware drains
   (`fpga/host/audio_bridge.c`) and hands to the players, either on ZIGGY (`host/audio.c` FX_YM ->
   `audioSfxYm` -> `zma_*` writes into CHORUS's YM, `host/audio_imports.c`) or forwarded to BARD by the
   mailbox. The splash should not carry the players: give its firmware a 20-line path that writes each
   drained YM effect straight into CHORUS's YM write port (what `zma_*` does), stamped at the frame.
   The jingle is a register stream, so nothing is lost. **To verify on the board**: CHORUS's YM is
   reachable and clocked with no BARD image loaded (the BARD core held in reset).
3. **U-Boot** (zeST study §3 B steps 2-4): hide the top 32 MiB from U-Boot, then after `fpga loadb` and
   the AFI widths (unchanged): CTRL=0, LOAD_BASE = 0x1E00_0000, `fatload splash.bin 0x1e000000`,
   LOAD_SIZE, RUN; then the kernel as today. Move it to `preboot` so it plays during `bootdelay`.
4. **The hand-off word.** The splash writes, at a fixed spot of the window top (beside the FW_OPT
   word), a magic + state: `KSPL` + 0 playing, 1 FINISHED (faded to black, holding), and keeps
   CART_BEAT ticking. Glass at start: if CART_STATE is RUNNING with `KSPL`, it does its card work first
   (mount, shelf, `system.rv32` parse) **without `hold()`**, then waits for FINISHED (or a 6 s cap),
   then `loader.start` as today. The screen is already black, so the ~2.5 s BOOTING gap reads as a
   designed pause, not a failure.
5. **A long boot.** If Linux needs longer than the splash, the splash simply holds black (FINISHED):
   it never loops. If the measurement shows a long kernel phase (> 8 s), a variant holds the bird on
   screen (skip the fade until glass asks for it through a ZWINDOW register write, then fade in 0.66 s);
   the hand-off becomes "glass writes FADE, splash answers FINISHED".
6. **C as the fallback.** Without a splash image on the card, `boot.cmd` writes the OSD banner (zeST
   study C): KESTREL in the OSD's 32x16 text in the same cream on black.
7. **Docs and proofs.** FPGA_GLASS.md boot flow, decisions.md (U-Boot owns the window, the splash is
   part of the card), the board check: the splash visible from U-Boot through `bootz`, the kernel's
   `printk.time` with and without it (DDR sharing), glass adopting it with no flash.

Effort: M (the zeST estimate, 3 to 5 days) once step 0 is measured; the cart itself exists.

## 5. The prototype

`apps/zig/scenes/kestrel_boot/` (cart 129, tag `kestrel_boot`): WINDHOVER as specified above, in the
browser. Integer-only per frame (`zg.fixtrig`, Q16.16, the ease table built at compile time), sky and
bird made at init. Frames (cart frame numbers; the PNGs are the 800x280 physical raster, pixels
doubled across, so they look wide): `f0055_stoop.png` (the bird entering at ~3x, banked),
`f0060_sky.png` (the sky fading up, the bird braking), `f0100_glint.png` (after the flash, the copper
highlight on the head), `f0130_wordmark.png` (letters lighting), `f0200_hold.png` (the still mark),
`f0270_fade.png`, `f0320_black.png`.
Proof: `apps/kestrel_boot_check.mjs` (and `--break`), `scene_hash.mjs` (no zg.mem refusal). The cart
is 61 KB of wasm, 14.8 KB as a packed `.zmd`: nothing but code and a few tables.

What the prototype does not yet do: the `KSPL` hand-off word (a board-firmware matter, step 4), and
on the board its YM writes still go through the effects queue (step 2).
