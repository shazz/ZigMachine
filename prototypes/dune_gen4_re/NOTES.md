# Dune — Gen4 Demo (1990-06-29) — RE notes (cart 82, tag dune_gen4)

Demozoo 178058. Credits per Demozoo: Music 520, Graphics Black Eagle, Code Hades.
Source: https://fujiology.org/ST/D/DUNE2/DUNEGEN4.ZIP (DUNEGEN4.MSA, 9 spt, 2 sides, 80 tracks).
Everything below was read from the disk and the depacked program, then checked in Hatari.

## Tools (this directory)
| tool | does |
|---|---|
| `msa2st.py`, `fatx.py` | MSA -> .ST, list/extract the FAT12 (from snyd_re) |
| `unjek.py` | JEK Packer 1.3 depacker, transcribed from the stub |
| `m68dis.py`, `relocs.py` | Capstone disassembly; the GEMDOS fixup list (relocated vs absolute longs) |
| `words.py` | dump TEXT words/bytes of the depacked program |
| `tny.py` | Tiny decoder (transcribed from DUNE.PRG's own $3D6A) |
| `mkassets.py OUTDIR` | the cart's assets: disk files + `tables.zig` (every table, by TEXT offset) |
| `mklaunch.py` | the AUTO launcher (see "Running it in Hatari") |
| `run.sh`, `keys.sh` | headless Hatari run with a png-codec AVI; keys into its --cmd-fifo |
| `avi2png.py`, `sheet.py` | AVI -> frames, contact sheets |
| `fadesteps.py` | which fade step each Hatari frame shows |
| `mkref.py` | Hatari frames -> `apps/dune_gen4_ref.bin.gz` (ST colour words) |

## Disk
- `python3 msa2st.py DUNEGEN4.MSA DUNEGEN4.ST && python3 fatx.py DUNEGEN4.ST files`
- Plain FAT12 (media F9). Boot sector not executable ($1235 sum). Volume label DUNE.BRU.
  DESKTOP.INF names drive A "DUNE" and drive B "3615 GEN4"; the demo is run from the desktop.
- Files: DUNE.PRG (32744, JEK-packed), MUSIQUE.PRG (6905), SINGSONG.PRG (16060), TETEDEAD.PRG (640),
  DUNE.TNY, INTRO.TNY, MENU.TNY, SOUND.TNY, ALPHA.DAT, BLACK.DAT, BLACKEAG.DAT, FONTE.DAT, FONTEH.DAT,
  XYEAGLE.DAT, SOUND2.SET (65704), ACCUEIL.MBS + GEN4.MBS (STOS banks, never named by DUNE.PRG),
  GEN4.DAT (0 bytes).
- Which files the program really reads: ALPHA.DAT, INTRO.TNY, DUNE.TNY, MENU.TNY, SOUND.TNY, BLACK.DAT,
  MUSIQUE.PRG, SINGSONG.PRG (Pexec mode 3), SOUND2.SET, and "A:blackeag.tny" (see F1). FONTE.DAT is
  byte-identical to TEXT+$EC40 (the menu font, used from the program); XYEAGLE.DAT = TEXT+$10EFE (F1's
  path); TETEDEAD.PRG = TEXT+$86FE (F2's skull sprite). FONTEH.DAT is never used.

## DUNE.PRG = JEK Packer V1.3
- `python3 unjek.py files/DUNE.PRG dune_unpacked.prg` -> 71305 bytes, a GEMDOS PRG, TEXT $1148C,
  checksum residue 0. Stub transcribed from TEXT+$16C..$246; the stream is read backwards from the end
  of TEXT and runs below TEXT+$300 (output base), so the whole TEXT is input.
- The depacked program is position-dependent in two ways: relocated longs (231 fixups, `relocs.py`) AND
  absolute addresses: MUSIQUE.PRG is loaded raw to **$10000**, pictures to $50000/$60000, fonts
  pre-shifted to $5CE00.., F1's background copy at $47D00. So it only runs where the desktop loads it.
- **Capstone trap**: `movem.l (d16,PC)` (at $3D28) is shown 2 bytes early ($11A8); it reads $11AA.

## Running it in Hatari (no shirazmcp: the server's one session belonged to a sibling)
- TOS **1.02** (fr) is required: the keyboard handler at $50E ends `jmp $FC29CE`, TOS 1.02's IKBD
  routine. Hatari's GEMDOS HD needs TOS >= 1.04, so the program runs off the floppy.
- From AUTO it crashes (its TEXT lands ~$9000; MUSIQUE.PRG at $10000 overwrites it: bus error in the
  player). `mklaunch.py` writes an 80-byte AUTO/LAUNCH.PRG that Mallocs $14000 and Pexecs A:\DUNE.PRG,
  so TEXT lands at **$21006** (as from the desktop). `DUNE_AUTO.ST` = the disk + that launcher.
- `run.sh NAME VBLS --frameskips 0 ...`: with frameskips 0 the AVI holds one frame per VBL.
- Debugger traces: `b pc = <TEXT+off> :trace :file <abs path of a file with "e VBL">` logs the VBL of
  any routine (the file path must be absolute: it is resolved again when the breakpoint fires).

## The program (TEXT offsets)
1. $0: Super, Mshrink, Pexec(3) SINGSONG.PRG, load SOUND2.SET, Setscreen, own IKBD handler, load
   MUSIQUE.PRG to $10000.
2. **Intro** $24C: INTRO.TNY decoded to $60000 (not on screen), faded in on a cleared screen; VBL $35E
   copies picture lines 0..115 to line DROP[i] ($1D7E bytes) of the hidden screen, i = 1..$21 and back
   ($29E), turn-round VBLs swap without drawing. Main loop: 19 x 65536 dbra.
3. **Main part** $4448 (after: black, clear, picture lines 10..110 -> screen 0..100, fade-in):
   `jsr $10000` (music init, d0 cleared by the tune itself), load ALPHA.DAT, pre-shift the font 4 x
   ($5834), VBL $44C4: palette $11EA; $4194 letters; $5056 + $465C scroller; `jsr $10064` (play).
   Timer B from line 100 ($455E): colour 0 = $1CB8[i], colour 8 = $1BF0[i] until the 0 at $1CB4 (line
   198); $45AA: colour 3 = 0, 60 Hz/50 Hz at line 199/200 = **lower border open**; $4618: colour 3 =
   $122A[j] from line 201. Ends when the text's $FF is read or on Space ($FFFC02 = $39).
   - Letters: 8 x 32x32 in plane 3 at $17CC, columns $8,$18,$28,$38,$58,$68,$78,$88; index $163C,
     direction $164C, table $166C (176 heights, 100 + v); each letter puts BAR ($1BCC, 16 words) into
     the colour-0 table at $1CB6 + 2(y-100) (= one line above its top). Erase on the hidden screen,
     draw on the shown one.
   - Scroller: 11 characters kept ($12E0..), 4 pre-shifted fonts (12/8/4/0 px), columns alternating
     ($13AE / $13C4) every 4 VBLs: one rule, x_k = 316 - 32k - 4f. Line 200 ($1320). Drawn into the
     hidden screen: shown one VBL later.
   - Text at $13DA, 590 characters (0..25 = A..Z, 26.. digits, 36 '.', 38 '(', 39 ')', 40 '-', 41 ' ').
4. **Title** $13C..$1B4: stop the tune ($10004), DUNE.TNY decoded into the screen, faded in, SingSong
   plays Quartet song $3316 from SOUND2.SET until Space.
5. **Menu**: poke $10024..$1002C over $1000C..$10014 (three of the tune's sequence pointers), `jsr
   $10000` again, then $1018A: MENU.TNY, fade, VBL $101E6: palette $10486, Timer B at line 10: colour 15
   from $10318 (lines 11..147), 0 on 148, palette $10466 from 149, colour 8 from $1042C (150..177);
   scroller $FFA8: FONTE glyphs rolled into plane 3 of lines 150..176, 4 px a VBL. Keys: F1 -> $10A06,
   F2 -> $59CC, F3 -> $3DE; after F1/F2 `jsr $10004` and the menu is loaded and faded in again.
6. **F1** $10A06: loads "A:blackeag.tny" ... (see below), BLACK.DAT pre-shifted x16, five letters on
   XYEAGLE's path (628 steps, indices $113E8 = 20,15,10,5,0, not reset between visits), masked by the
   OR of their planes; Space returns.
7. **F2** $59CC: the HADES screen (starfield, a moving HADES logo, a chain of five TETEDEAD skulls,
   a magenta-raster scroller in the lower border). ~8 KB of code. NOT PORTED (see open questions).
8. **F3** $3DE: SOUND.TNY + SingSong, F3..F6 pick Quartet songs $1DF2/$24F2/$2A1E/$3316. NOT PORTED.

## Measured in Hatari (`ref2`: AVI one frame a VBL + traces)
- A screen address written in a VBL is shown from the NEXT frame (AVI frame k = after VBL k shows the
  base written in VBL k-1, plus what VBL k drew into it). The intro's turn-round VBL therefore shows
  the screen from two VBLs back for a frame.
- Intro VBLs 1247..1475 = **229** bounce VBLs; main part's first VBL 1657 = **182** later.
- Fade-in ($3CD2): steps visible at last-bounce + ceil(4.26 + 3.12 s) — a step every **3.12 VBLs**
  (dbra arithmetic: 3.09) and the clear/copy before it takes 4 VBLs (`fadesteps.py`).
- Main part letters and colour-0 bars equal the model exactly (VBL n uses index start + n - 1).
- Timer B latency: in some frames a line's first ~45 pixels keep the line above's colour (an interrupt
  waiting for a long instruction). The harness counts these, it does not fail them (max 3 lines).

## Music
- MUSIQUE.PRG == `prototypes/sndh_lf/Mr_X/Gen4.sndh` (TITL "Gen4 Demo", COMM "Mr X", RIPP/CONV
  Grazey, ~y, one subtune) at a constant offset of 514: 6614 of 6905 bytes equal, the rest relocated
  addresses. `docs/music/dune_gen4.sndh` = that file; `node apps/sndh_headless.mjs` PASS, peak 0.4228.
- Init = $10000 (`jmp $10030`: `clr.l d0` then the song set-up): subtune 0 whatever d0 holds (Hatari:
  d0 = $FFFF at the call). Play = $10064 from each part's VBL. Stop = $10004 (volumes to 0).
- The menu's tune: DUNE.PRG pokes $10024/$10028/$1002C over $1000C/$10010/$10014 before the second
  init; song 0's voice table is $10008, so voices B and C get other sequences. 
  `docs/music/dune_gen4_menu.sndh` = Gen4.sndh with the same 12 bytes copied (at SNDH offset
  $202 + ...). The SNDH's own relocator moves them like the originals (they lie in its range). PASS.
- **Credit discrepancy**: Demozoo says music by 520; the SNDH says Mr X. The demo's own scroller lists
  several tunes: "THE MUSIC (SOUNDTRACKER) BY S20 [=520]", ... "I HATE LIES ... BY MR X". The YM
  tune is Mr X's; 520's are the Soundtracker (Quartet) tunes.
- SINGSONG.PRG = Quartet SingSong (4-voice samples) + SOUND2.SET: title screen and F3. Out of scope.

## The cart
- `apps/zig/scenes/dune_gen4.zig` + `dune_gen4/`: one overscan plane of palette indices 0..15 and the
  16 colour registers of every physical line (st.zig): every raster is a register written between
  lines, edge to edge (the plane flickers its borders open every line; the original opened only the
  lower one — the top/side borders show colour 0 either way).
- Harness `apps/dune_gen4_headless.mjs`: 17 Hatari frames (intro, fade, main part) as ST colour words
  over x -40..359, y -29..239; all equal.

## Open questions for Matt
1. Title (DUNE.TNY) and F3 play Quartet SingSong tunes (SOUND2.SET): silent in the cart. Port a 4-voice
   sample replay, or render them, or leave them silent?
2. F1 asks for "A:blackeag.tny" but the disk has BLACKEAG.DAT (a valid Tiny file of Black Eagle's face):
   on this disk the load fails and the letters fly over the menu picture (no rasters). The cart shows
   the intended picture (`black.zig` SHOW_DISK_BUG = false). Keep that, or show the bug?
3. F2 (the HADES screen) is not ported yet — a big part of its own.
4. The original stops the tune while a part loads and fades (VBL = rte); ZigMachine has no pause, so
   the menu tune runs on across F1 and back.
