# Bubble Bobble (Atari ST, Firebird 1987): how it works, and how the cart runs it

Analysis + port, 21 Nov 2026 (roadmap R77). Taito's 1986 arcade game converted by Software
Creations for Firebird / British Telecom: code David J. Broadhurst, graphics Andrew R. Threlfall,
music Tim & Mike Follin. Cart 97 (`bubblebobble`) replaces the opencode/Go draft (its gap report:
`prototypes/opencode_revisit/bubblebobble.md`).

## Short answer

- **One 60 KB program, plain** (no packer, no protection) and eleven data files in `GRAPHICS\`.
  Compiled-looking 68000 (move/branch/bsr, 65 mnemonics, no self-modifying code, no `move sr`);
  the game state lives in 27 object records of `$23E` bytes from `$20E80` (Bub, Bob, then the
  rest), dispatched through two 115-entry jump tables indexed by the object type (`$3D34`
  behaviour, `$5A64` collision).
- **Frame sync is MFP Timer B, not the VBL.** The VBL (`$EB0`) programs Timer B in event-count
  mode for 200 lines; its handler (`$E84`) sets `$1054` at the bottom of the picture and the main
  loop's wait (`$AFE`) spins on it, then flips the two screens (`$B12`, `$FF8201/03`).
- **The playfield is a 32 x 25 grid of 8-pixel cells** expanded from 100 bytes a round
  (`BDATA.DAT`): bit 0 a block, bits 7-6 the air current. Air comes from each row's two spare
  bits plus per-round rectangles and a "mirror the left half" op (`AIRFLOW.DAT`).
- **The program fixes its own data after loading it** (`$A2`-`$136`): 14 bytes of `BDATA.DAT`
  (a floor, three map rows moved up a row...) and 4 of `AIRFLOW.DAT`. The files on the disk are
  not quite what the game plays.
- **Sprites are pre-shifted**: every 16 x 16 frame is stored four times, at 0/4/8/12 pixels, in a
  32-pixel field, 16 bytes a line (`BUBBLE.SPR`, `FRUIT.SPR`...).
- **The round-to-round scroll is a beam-synced split with real rasters** (`$2D96`): a VBL
  (`$FA4`) and Timer B (`$F74`) pair recolour colours 11-14 and 2 at a split line that climbs 4
  lines a frame, while the main code waits on the video counter (`$FF8207` = `$FA`) and moves the
  old round up 4 lines a frame: 50 frames. Below a split of 2 lines Timer B re-fires every 2
  lines, ~500 colour writes a frame.
- **The music is a small 3-voice byte-code player** written for the game (`$A7AE`-`$AFC9`,
  2 KB) over the Follins' `MUSIC.DAT` (nine tunes); the six sound effects are procedural code on
  voice C. Tune 0 (the round theme) plays at 2/3 speed unless the hurry flag `$AC08` is set: the
  arcade's "music speeds up" when Baron von Blubba comes.

## 0. Getting at the code

- `disks/DEEP1.ST` (Deep Thought #1 compilation, plain FAT; `DEEP1.MSA` the original download)
  holds `BUBBLE.PRG` (60,241 B, md5 `7df2d261...`) and `GRAPHICS\`. The original Firebird disk is
  the Pasti image `disks/Bubble Bobble.stx` (md5 `f9d87179...`), not used yet (no Hatari run).
- GEMDOS header: TEXT `$E206`, DATA 0, **BSS 0**, 2,311 relocations. The game nevertheless uses
  absolute RAM from `$1EE76` to `$4C200` (the loaded files, the object table) and two screens at
  the absolute `$6E200` / `$78000` (no Malloc, no BSS), so it only works if TOS loads TEXT below
  `$10C70`. The cart loads it at `$10000`.
- Static recursive descent (`tools/bubblebobble/st_prg.py`, Capstone 5) from the entry, the six
  interrupt handlers it installs (`$70`: `$EB0` `$F28` `$FA4`; `$120`: `$E84` `$E96` `$F74`), the
  Kbdvbase joystick callback `$3C86` (joyvec) and the jump tables (`$3D34`, `$5A64`: 115 entries;
  `$7692`): **6,953 instructions, 33,356 bytes of code**; the other 24.5 KB of TEXT are
  variables, tables, texts, the stack (`SP` = `$79E`) and the font.
- `prototypes/bubble_re/tools/`: `codemap.py` (labelled listing in `work/code.lst`), `view.py`
  (pictures and sprite banks as PNG), `airrec.py` (a round's air record), `abs_refs.py`,
  `explore*.mjs` (dev probes of the cart), `fnames.mjs` (wasm function names for frame_cost).

## 1. The files

| File | Loaded at | Bytes read | What |
|---|---|---|---|
| `MUSIC.DAT` | `$1EE76` | 4,864 | the nine tunes' byte code; patched after loading (`$1EE7A` = 13, `$1F14E` = 31, `$370C`) |
| `SPIC.PI1` | screen - 34 | 32,802 | the title picture (Degas, read straight onto the screen) |
| `BUBBLE.SPR` | screen 2 - `$4000` | 53,248 | dragons, enemies, bubbles, specials, EXTEND letters: 16 x 16, pre-shifted x4 |
| `UNSHIFT.SPR`, `FRUIT.SPR` | `$3660` / `$3688` | 16,640 / 51,200 | unshifted frames; the items and food |
| `AIRFLOW.DAT` | `$20876` | 1,545 (of 1,792) | a 300-byte table, then the air records from `$12C` |
| `BBLOCKS.PI1` | `$28080` | 14,080 (of 16,384) | Degas header + 87 lines: the rounds' 8 x 8 blocks, the 16 x 16 wall blocks, the font |
| `BDATA.DAT` | `$25080` | 12,288 | 100 maps x 100 B, the enemy lists from 10,000, extra maps from `$2E38` |
| `DWARF.SPR` | `$43100` | 37,120 | more sprites |
| `SECRET.PI1`, `EXTEND.PI1` | screen - 34 | 32,802 | the secret-room and EXTEND pictures |

The game loads them while the title shows (done by VBL ~100); the cart's Fread is instant, so the
title stays up as long as the game's own timer says, not as long as the disk took.

## 2. The round format (`BDATA.DAT`, `AIRFLOW.DAT`)

Built by the game at `$1092` (blocks) and `$10EA` (air) into the grid at `$2854` (32 x 25 bytes,
with four copies of the top row above it and of the bottom row below it, for the wrap-around).

- **Map**: round `r` at `r * 100`, 25 big-endian longs; bit 31 = column 0; a set bit is a block
  (cell bit 0). The game forces columns 0, 1, 30, 31 to walls (`$114C`), so a row's bits 1-0 are
  free: they are **the row's default air current** (cell bits 7-6, `$1368`).
- **Air records** (`AIRFLOW.DAT` from `$12C`, one per round, walked by `$1304`): a first byte
  with bit 7 set means "use round `b & $7F`'s record and its row defaults"; 0 means none; anything
  else is the record's length, followed by entries: a byte with bit 7 clear = **mirror** (`$129A`:
  the left 16 columns' currents copied into the right half, reflected, left <-> right, 24 rows),
  or a 3-byte **rectangle** `1dd xxxxx`, `yyyyy www`, `ww hhhhh` (direction, column, row,
  width-1, height-1; a rectangle may run past the grid's last row, harmlessly).
- **Round 99** (`$62`) also opens a vent: cells (10-13, rows 0-2) = `$80` (`$1180`).
- **Enemies** (`$95D0`, from offset 10,000, cursor `$5090`): 3 bytes each, a 0 ends a round:
  byte 0 `xxxxx ftt` (column, a flag, type 0-7 -> object type 1-8), byte 1 `yyyyy bbb` (row,
  behaviour bits), byte 2 `s ddddddd` (bit 6 the facing, the low bits x2 a drop-in delay). 575
  enemies in 100 lists; round 1: three Zen-Chans dropping in at column 15.
- `apps/bubblebobble_headless.mjs` holds an independent decoder of all this (with the start-up
  fixes) and checks it against the grid the game's own code builds, for all 100 rounds.

## 3. The program

| Address | What |
|---|---|
| `$0`-`$150` | start-up: Super, Setscreen, the files, the data fixes, the interrupts, Kbdvbase (joyvec `$3C86` stores the two sticks at `$3CA2` / `$3CA3`), IKBD joystick event mode (Bconout `$14`) |
| `$2F6`-`$426` | the main loop: ~50 calls, round logic to sprite drawing, the frame wait `$AFE`, the flip `$B12` |
| `$484` | restores the playfield background on the back screen each pass (3 x `movem.l` a line) |
| `$3CA6` | object update: for 27 objects from `$212FC`, `$3D34[type]` |
| `$5376` | collision: `$5A64[type]` |
| `$7CC6`-`$80B0` | title / attract loop: Crawio '1' / '2' or fire on a stick starts (port 1 = Bub, port 0 = Bob); `$58A` = 1 while it runs |
| `$AFCA` | in a game: '1'/'2' or fire joins a player (both at once) |
| `$3A72` | the jump (stick up, `$3CA4` bit 0) and its effect 5 |
| `$2CCC`, `$2D96` | next round: the grid, the enemies, the raster scroll |
| `$3B10` | F1 pauses (wait for release, press, release), F10 quits (`$57A`) |

## 4. The sound

- Driver: start tune `$A7AE` (tune # in `$AC06`; 12-byte entries at `$AB76`, three voice
  pointers into `MUSIC.DAT`), VBL tick `$A810` = music `$A81A` + effect `$AC5A`. Byte code: `$FF`
  restart, `$02 n` / `$01` repeat, `$03 r v ... $03` raw YM writes (register 7 keeps the port
  bits), `$04` toggles... `$AC0B` is set when a tune starts; the game clears it and polls it to
  wait for a jingle's end, so the game's timing depends on the driver.
- Effects: start `$AC12` (effect 1-6 in `$AC10`), each a little routine on voice C (`$ACAA`,
  `$AD1A`, `$AD9A`...). The game starts tunes from 14 places and effects from 11.
- Grazey's SNDH (`sndh_lf/Follin_Tim/Bubble_Bobble.sndh`, 9 subtunes) contains `MUSIC.DAT`
  verbatim and the player relocated; it has no effects. The cart builds its own SNDH from the
  game's driver bytes and `MUSIC.DAT` (`apps/zig/assets/screens/bubblebobble/sound.s`).

## 5. How the cart runs it

- **A translation of the program, not a remake** (as Rick Dangerous's port is a transcription):
  `tools/bubblebobble/st_recomp.py` writes every reachable instruction as Zig
  (`apps/zig/scenes/bubblebobble/gen/`, 34 files, each instruction under its own comment): a
  labelled `switch` per routine (a branch inside it is a `continue`), calls are native calls that
  push the 68000 return address on the 68000's own stack (so the main loop's SP resets and the
  table calls work unchanged), anything else returns the target to `dispatch.zig`. The flags are
  five booleans set as the 68000 sets them (`st/alu.zig`), and only where a later instruction
  reads them (`st_flags.py`, a liveness pass: calls, returns and indirect jumps count as reading
  everything). Each straight run adds its approximate 68000 cycles to a clock.
- **The machine around it** (`st/`): 1 MB RAM (the game occasionally draws a sprite past the
  bottom of the screen at `$78000`); the Shifter (video base latched at the VBL, the video counter
  from the cycle clock, the palette with a per-line log of writes); MFP Timer B in event-count
  mode over the 200 picture lines; the ACIA byte; Kbdvbase / joyvec; GEMDOS Fopen / Fread /
  Fclose of the files and Crawio; XBIOS Setscreen. A 50 Hz frame (`st/frame.zig`) = the VBL
  interrupt, the code to line 0, each picture line's Timer B event, the bottom border; a loop that
  only polls RAM (the frame wait, the pause) skips to the next interrupt.
- **Data, not code, in the repo**: `text.bin` is TEXT with every translated instruction zeroed
  (the game runs identically on it); the `GRAPHICS\` files as far as the game reads them.
- **The rasters are real**: the per-line log is replayed by the plane's HBL handler into the
  plane's palette (`present.zig`); a frame without one runs no handler.
- **Sound**: every call the game's code makes to its driver is mirrored on
  `bubble_bobble_st.sndh` (a load first, then `zg.sndhCall` on the running driver); the hurry flag
  is followed every frame. The game's own copy keeps running silently in the cart, so its jingle
  waits last as on the ST. The harness checks both copies' driver RAM stay equal tick for tick.
- **Not cycle-exact**: the clock is an estimate (4 cycles a word, 4/8 a memory access, the slow
  instructions' extras), interrupts land at the next loop or return, no bus contention. Nothing
  has been compared with Hatari yet: the timing of the round-to-round scroll and of the game's
  pace against the real machine is the first thing to check there.
- **Checked** (`apps/bubblebobble_headless.mjs`): the 100 rounds against the decoder; title,
  hi-scores, story, '1' -> round 1 with 3 Zen-Chans, walk, bubble, jump + effect, round won ->
  the raster scroll -> round 2; two 20,000-frame soaks with no unknown jump, unmodelled hardware
  access, unanswered TOS call or stuck interrupt, and equal RAM; the 9 tunes and 6 effects; the
  plane = the ST screen; 50 Hz on a 60 Hz host; the keys. Four `--break` modes.

## 6. Cost on KESTREL (apps/frame_cost.mjs, in round 1)

- est. ~3.1 Mc a host frame (~32 fps): FRESCO 0.7, I$ misses ~1.1 (27 KB of rv32 run a frame:
  the translation is ~100 bytes of rv32 a 68000 instruction), the screen compare ~0.5, the bus
  calls ~0.4. The title alone ~1.9 Mc. Over the 1.67 Mc budget: not board-ready yet.
- Done: bus accesses and the add/sub/cmp flag helpers out of line (I$), the flags only where
  read, one cycle add a straight run, direct native calls, a dispatch table, the plane converted
  only where a screen line changed (u32 compare), palette writes only on change.
- Left: registers and flags in locals inside a routine (the biggest code-size lever), `movem` as
  one bulk copy, the screen compare from write tracking instead of reads.

## 7. The ZIG mode (Z) and what KESTREL could lift next

- **Done (first step)**: Z toggles a 24-bit copper sky: the plane's HBL rewrites colour 0 on
  every line (a ramp from one of eight hues to black, a new hue each round) wherever the game
  leaves its background black. The game's code, pixels and timing are untouched (the harness
  checks the plane is still the ST screen with it on).
- **Next**: open borders with the side bar moved out of the playfield picture, the round-to-round
  scroll as a hardware scroll of the plane, the background drawn once and the sprites as CHISEL
  bobs on a second plane (what would also cut the board's cost), 60 Hz presentation.
