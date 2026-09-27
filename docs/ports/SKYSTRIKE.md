# SKYSTRIKE: how the port was reverse-engineered

SKYSTRIKE (Aaron Fothergill, graphics Adam Fothergill, Shadow Software, 1989) is
one of the four STOS game-writing competition winners published on *Games Galore*
(Mandarin Software). ZigMachine runs it as cart 79 (`apps/zig/scenes/skystrike/`).
It was ported from the copy on Automation Menu Disk 258 (1990) by a Claude agent.
This is the agent's own log, lightly edited. The reusable method is the `stos-port`
skill (`.claude/skills/stos-port/SKILL.md`).

The short version: the game on the disk is a *compiled* STOS program with no source
inside. Its original tokenised source `SKYSTRKE.BAS` turned up in a local clone of
ggnkua's [Atari_ST_Sources](https://github.com/ggnkua/Atari_ST_Sources)
(`STOS/Aaron Fothergill/`), proven identical to the shipped program by its strings
and banks, detokenised with a keyword table read out of the STOS interpreter, and the
655-line listing became the spec. An Atari-Forum thread had said the source "has never
been seen publicly"; it has since landed in that archive.

The RE workspace (tools, dumps, the listing) lives in the gitignored
`prototypes/skystrike_re/`; paths below are relative to it.

This is a log of what was actually done, in order. The tools it mentions are in `tools/` here. The disk is
`prototypes/Automation Menu Disk 258 (1990)(Automation)[a].st`.

## 1. The disk and the packers

- `fat.py` reads the FAT12 BPB (512 B sectors, 2 per cluster, 112 root entries, 1640 sectors) and extracts
  every file into `files/`. The game's files are `STRIKE.VAP`, `STRVAP` and the folder `SKYSTRKE/`.
- `STRIKE.VAP` is a `$601A` PRG whose strings read `strvap` and `EVAPOUR PRESENTS . . .`. That makes it
  the menu's loader for `STRVAP`. The disassembly (`strike_vap.dis`) shows it hooking GEMDOS through
  `$84`: when the program opens a file, the hook depacks it if it is `LSD!`-packed. The depack routine is at
  TEXT+$42E.
- Every file in `SKYSTRKE/` starts with `LSD!`. `tools/unlsd.py` transcribes that routine; its output is in
  `unlsd/`. `DATA.DAT` depacked to 1209 bytes of CR-separated numbers.
- `STRVAP` is an Automation-packed PRG. It is depacked by running its own depack stub
  (`d68.py` disassembly at TEXT+0) in `em68.py`, the Python 68000 interpreter copied from
  `prototypes/rick_re/harness/`. `tools/unauto.py` does this: 3,419,343 instructions, 232,206 bytes from
  `$10500`, saved as `strike.prg`.

## 2. How STRVAP turned out to be compiled STOS

The task brief already said it was a STOS game, but not which kind. `strings -t x strike.prg` settled it:
`Stos basic compiler V 1.0 by Francois Lionet` at offset `$70`, followed by the runtime's editor strings
(`listbank`, `fload"*.bas"`, `accnew:accload"*"`, ...). There was no tokenised program in the file. The
game's own strings sit together from `$21F92`: `\SKYSTRKE`, `DATA.DAT`, `You Managed to Crash Land !:`,
`No More Aircraft !`, `You Were Killed !`, and so on. The program is a compiled STOS program with its
runtime linked in.

## 3. How SKYSTRKE.BAS was found in Atari_ST_Sources (ggnkua's archive)

I searched `Atari_ST_Sources` because the `atari-st-packers` skill names it as the
source of citeable depacker code. The first search, before the unpack, was for an Automation depacker
source and the STOS material:

    find Atari_ST_Sources -iname "AUTO*.S" | head
    find Atari_ST_Sources -maxdepth 4 -ipath "*stos*" | head -30

Next, a search of file contents for the game by name and by its file names, plus a listing of the STOS
directory:

    cd Atari_ST_Sources
    grep -ril "sky *strike\|skystrike\|spitfire.hsc\|skypic" .
    ls STOS

The grep found only two unrelated files:

- `ASM/The Medway Boys (TMB)/SKY_STRK.S`, a 1139-byte crack intro;
- `ASM/Lemmings/MENU_5/MENU5.S`.

The `STOS` listing had a directory named `Aaron Fothergill`.

After the unpack, the program's strings named the author. The credits text says
`Game + Music : Aaron Fothergill .. Graphics: Adam Fothergill ... A Shadow Software Production`. So I
looked in that directory:

    cd "Atari_ST_Sources/STOS/Aaron Fothergill"; find .

It contains `SKYSTRKE.BAS/`, a folder that holds `SKYSTRKE.BAS` (114,340 B, a `Lionpoulos` tokenised
source) and the banks `PKTSPRT.MBK`, `SAMPLES.MBK`, `SKYMUSIC.MBK` and `SKYSCRNS.MBK`. These are copied to
`bas/`. The earlier grep missed the folder because the pattern `skystrike` does not match the 8.3 name
`SKYSTRKE`.

## 4. Proving the source is the compiled program

- **Strings.** Every string constant in the listing (more than 3 characters) must occur byte for byte in
  `strike.prg`. The first run found two that did not: the credits text and `(3) Hard  . 200,000 pts bonus`.
  Both were my detokeniser's fault. It collapsed runs of spaces inside string constants. After that was
  fixed, every string matched.
- **Banks.** The body of each `.MBK` (after its 18-byte header) was searched for in `strike.prg`:
  - `SAMPLES` at `$36C0A`, identical;
  - `SKYMUSIC` at `$3530A`, identical;
  - `SKYSCRNS` at `$35C0A`, identical;
  - `PKTSPRT` at `$2E20A`, with **367 bytes different**. They cluster at offsets 9236-9280 and
    17138-17853, which are image data only; the header and table are identical. The compiled program's
    copy is the one that shipped, so the port uses the sprite bank ripped from `strike.prg`
    (`sprites.bnk`), not the source's.
- **The music.** `sndh_index.py skystrike` found `Fothergill_Aaron/Sky_Strike.sndh` (TITL `Sky Strike`, COMM
  `Aaron Fothergill`, 3 subtunes, `~y`), Grazey's rip of the same STOS music bank.
- **Behaviour.** Later, Hatari RAM dumps of the running original were compared screen by screen, and a
  98-pass variable trace of a takeoff was compared value by value against the port (section 8).

## 5. The detokeniser (`tools/stostok.py`, `tools/detok.py`)

- **The keyword table** was not in the compiler folder: a grep for `gosu` found nothing in the
  compiler's `.LIB` files. It came from the interpreter,
  `Atari_ST_Sources/STOS/STOS_LAN/STOS/BASIC.BIN` (78,776 B), found with `find ... -iname "BASIC*.PRG"`
  next to it. `stostok.py` parses the table into token -> keyword: `$A0xx` instructions and `$B8xx`
  functions. The extension keyword names come from each extension's header:
  - `COMPACT.EXA` (slot 0: `unpack`, `pack`), from `STOS/Fang Die Ratte/STOS/`;
  - the compiler extension (slot 2: `comptest off/on/always`);
  - `MAESTRO.EXD` (slot 3: `sound init`, `samplay`, `samspeed`, ...).
- **The file format:**
  - a `Lionpoulos` header;
  - program lines from `$4E`, each `word length, word line number, tokens, 0`, padded to even;
  - extension calls: `$A8 ext token`;
  - constants:
    - `$FE` + long: an integer;
    - `$FC` + long length + string;
    - `$FA`: a variable, word-aligned, then a type|length byte, a byte, a word and the name;
    - `$FF`: a float, 4 bytes of FFP followed by `$12345678`.
  - `goto`, `gosub`, `then`, `else`, `for`, `while` and `repeat` are followed by an aligned long (the
    interpreter's jump cache).
- **Two bugs found by later cross-checks:**
  - At first I also treated `wend` and `until` as cached, which garbled the rest of any line that
    contained them. Every such line was re-checked; lines 712, 726, 1420/1421, 1571, 1904, 1915, 2291,
    2311, 2314 and 2321 changed.
  - The whitespace collapse inside strings (section 4).
- Floats print with `.0`, so `SKYSTRKE.LST` shows which divisions are floating point (`/ 3.0` in 252,
  `/ 6.0` in 255). The listing has 655 lines.

## 6. The picture, sprite and bank decoders

- **PAC (`tools/stospac.py`).** The `.PAC` pictures (magic `$06071963`) are STOS COMPACT's format.
  `COMPACT.EXA` was disassembled (`compact.dis`; the magic is written at `$33C` and checked at `$488`) and
  `unpack` was transcribed from that code. The four pictures are in `png/`. The port uses a Zig version
  (`scenes/skystrike/pac.zig`).
- **Sprites (`tools/stosspr.py`).** The bank starts with `$19861987`. Its table gives, per image, an offset,
  a width in words, a height and the hotspot; the palette follows the table. My first guess, an
  interleaved mask+4 planes per 16 pixels, rendered garbage. The layout that renders correctly is the
  whole mask block first, then the plane data (`png/sprites.png`).
- **MBK.** An 18-byte header before the bank body. The banks the program reserves itself (`reserve as
  work 7,307`, screens 5/6) are modelled in `scr.zig`, with `START(n)` and the PEEK/POKE offsets the
  listing uses.
- **Files.** `MISSIONS.DAT` records are 301 bytes. `DATA.DAT`, `SCRNDATA.DAT` and `SPITFIRE.HSC` are
  read as the listing's `input #1` does (`files.zig`). `tools/skystrike/extract_assets.py` writes them all
  under `apps/zig/assets/screens/skystrike/`.

## 7. How the STOS runtime commands were transcribed

- **The listing is the program.** Each Zig module cites the lines it transcribes.
- **The flow machine.** Wherever the program waits (WAIT, key loops, the end of a main-loop pass), it
  becomes a step in `flow.zig`.
- **Commands and their semantics** came from three sources:
  - the compiled runtime in `strike.prg`: its trap #3/#5/#6/#7 dispatchers and float helpers were
    disassembled from the RAM dump;
  - the extension code: `compact.dis` and `maestro.dis`;
  - measurements on Hatari (TOS 1.02 FR, ST, 1 MB): a custom floppy `hatari/sky.st` with
    `AUTO/STRIKE.PRG` (= `STRIKE.VAP`) + `STRVAP` + `SKYSTRKE/`.
- **What was established that way:**
  - AND binds tighter than OR, and both are bitwise on -1/0;
  - every AND term is evaluated, so RND is always drawn;
  - FFP truncation to integers and the float constants;
  - `rnd(n)` is TOS Random masked, inclusive;
  - the SCREEN$ paste is floored to 16 pixels with colour 0 transparent;
  - SCREEN COPY is 16-aligned and opaque;
  - `set paint 2,4` is a checkerboard;
  - sprite priority, restore and `put sprite` into the back screen;
  - zones: the lowest one that holds the hotspot, bounds inclusive, `x1 >= x2` refused;
  - `collide` is a box test;
  - `OFF` and trap 5 function 7 turn every sprite off and clear the movements;
  - fades step one level per `speed` VBLs;
  - APPEAR's effect table and its speed;
  - SQUARE's frame sits 3 px inside the cells with the corners left out (measured with `square 29,3,1`);
  - `change mouse 82` = sprite image 79;
  - the right mouse button acts as fire.
- **Variable addresses.** The compiled program's variables were mapped by their first appearance in the
  tokenised source (`tools/trace_vars.py`, e.g. `x` at `$4062A`, `sp#` at `$40616` in FFP). That made the
  per-pass trace possible: a `:trace` breakpoint at `$1762C` (line 128) dumping `$405C0-$4065F`.
- **Timing.** One main-loop pass is about 2.8 VBLs (the game's own `z2` counter reads 3,3,3,2,...). A
  screen redraw costs about 21 more. The title scroller runs 6.5 passes a VBL (TI from 9264 to 9589 in
  50 VBLs).
- **Sound.** `apps/zig/assets/screens/skystrike/sound.s` holds:
  - Grazey's STOS-music rip;
  - Maestro's digi player, transcribed from `maestro.dis` (Timer A at the sample's speed-table rate, a
    256x16 volume table);
  - the STOS PSG commands `volume`, `noise` and `envel`, transcribed from the runtime.

  Everything but MUSIC n is a `zg.sndhCall` on the running image.

## 8. Checks against the original

Hatari RAM dumps were taken at the title, the difficulty menu, mission 1's briefing, the first frame of
play, a crash landing (`cl` poked to 1) and the hall of fame. The port's screens match them pixel for pixel,
apart from sprite rows and the scroller's newest letter.

For the takeoff, `th` was poked to 9. The 98-pass trace of x, y, heading, SP# and fuel is identical. Both
references now live in `apps/skystrike_fixture.json` (`tools/skystrike/make_fixture.py`) and are checked
by `apps/skystrike_headless.mjs`.

## 9. Dead ends and surprises

- **Booting the game in Hatari took several attempts:**
  - The original floppy stopped at the Automation menu.
  - A hard-drive boot kept drive A.
  - TOS 1.62 is an STE TOS and bus-errored at `$FC0002` on an ST.
  - Running `STRVAP` directly gave STOS `Error #13` (the loader's GEMDOS depack hook was missing).
  - What worked was TOS 1.02 and a floppy built with mtools, with `STRIKE.VAP` as the AUTO program.
- **Input could not be scripted:**
  - The joystick could not be injected into the running game.
  - In-game keys sent through the emulator were not received.
  - A long stretch of IKBD / Kbdvbase / trap-dispatcher disassembly failed to find a way round it.
  - Game states were reached by poking variables (e.g. `th` at `$405E2`) and by using the right mouse
    button as fire.
- `tools/dis.py` shadowed Python's standard `dis` module; it was renamed `d68.py`.
- The worktree guard refuses shell loops, `$HOME`, and paths with `SOURCE`/`source` in them, so the bank
  copies went to `bas/`.
- **The sprite bank in the source is not the one that shipped** (367 bytes differ).
- **The digi that would not stop.** Maestro stops a sample by clearing Timer A's IERA/IMRA bits. The sealed
  SNDH player's MFP ignores those bits and runs a timer on its control register alone, so SAMSTOP, and the
  end of a one-shot sample, left the digi running. The harness's sound check found this. `sound.s` now
  also writes TACR = 0, which makes no audible difference on an ST. The player's MFP has since been fixed
  to honour IER/IMR (`libs/zig/players/mfp.zig`, decisions.md 2026-09-27): SAMSTOP now stops the digi
  without the TACR write. The write is kept anyway.
