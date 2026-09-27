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

The level data (the world strip, the mission records, what is code and what is
random) and editing missions as Tiled maps: [SKYSTRIKE_LEVELS.md](SKYSTRIKE_LEVELS.md).

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

## 10. ZIG mode

The cart has two modes, switched by **Z** at any moment, mid-flight included (as
`replicants_emlyn` switches its own). **ORIGINAL** is everything above: the ST's
320 x 200 screen, the pause while a new screen is drawn, Maestro's digis. **ZIG**,
the default at power-on, is the same game shown another way. It changes the
presentation and the pacing, never the rules: the logic, scores, collisions, AI and
RND draws are the original's, and the harness proves it pass by pass
(`apps/skystrike_zig.mjs`, check (c)), with one exception that is a setting: a crashed
enemy's crater fills in after 30 s (see "Craters"). The title, the menu, the briefings,
the verdicts and the hall of fame are the original's screens in both modes; ZIG shows
them scaled to fill the open frame. A notice in the game's font says which mode is on
for two seconds after a switch. In the hall of fame's name entry, Z is a letter.

Every value ZIG can be tuned by is in one file, `zig_settings.zig`: the power-on
mode, fullscreen screens on or off, the HUD and bar margins, the camera's glide, the
tracers, the crater lifetime, the weapon keys and the effect-to-sample table.

The code is in `apps/zig/scenes/skystrike/zig_*.zig`. The game's own modules carry
only small hooks (`zig_hooks.zig`), none of which changes what the game does in
ORIGINAL; `apps/skystrike_headless.mjs` still passes unchanged.

| | ORIGINAL | ZIG | why |
|---|---|---|---|
| a new screen (line 1000 from 40 or 213) | 21 VBLs of pause | none | the scroll shows the next screen before you reach it |
| the view | 320 x 176 of one screen, flipped | 400 x 256 of the world, scrolled by the hardware | see more of the world around the plane |
| the frame | 320 x 200, borders shut | 400 x 280, all four borders open | fullscreen |
| title, menu, briefing, hall of fame | 320 x 200 | the same screen scaled 5/4 into the open frame | fullscreen |
| the panel, the bonus bar | on the screen | in the bottom / top border, fixed, 20 lines in from the edge | HUD |
| the guns | nothing drawn | tracers | show the bullets |
| the weapons | FIRE, FIRE + left (bomb), FIRE + right (rocket) | also Ctrl, Space, Shift: one key each | |
| a crashed enemy's crater | stays | fills in after 30 s | a setting |
| the ammo | not shown | a counter in the game's font | |
| effects | Maestro digis and PSG noise on the YM | synthesized samples on the Paula channels | the YM keeps the music |
| P (pause) | the music until a key | the same, and the key help over the game | |

### The scroll: a ring of screens in the scroll plane

The world is a strip of 51 sectors (`sx`), each a 320 x 176 screen, and layers of
sky above it (`al`; layer al's line y lies 160 lines above layer al - 1's). ZIG keeps
the 3 x 3 screens around the plane: sectors `sx - 1 .. sx + 1` across, layers
`b .. b + 2` up, where `b` is the live layer less one, never below the ground.

- **Where they live.** In the world plane's own VRAM buffer, 960 x 520: three
  columns of 320; rows of 160 (the ground row keeps all 176 of its lines, and 24
  lines of black lie under it for the HUD band to cover). The plane is an overscan
  scroll plane (`setOverscanScrollPlane`), so the hardware pans this buffer
  (`setScroll`): the ring *is* what is shown, and no frame is copied.
- **How a screen is drawn.** By the port's own line 1000 (`scene.draw`), in a sandbox
  (`zig_sandbox.zig`). Line 1000 is not a pure function: it sets zones and sprites,
  scores a building found destroyed, pokes the gun bits and spends clock cycles. So
  every piece of state it can touch is saved, the physic and back screens are swapped
  for two scratch screens, the draw runs for that sector and layer, and everything is
  put back. The scenery is therefore exactly what the original draws on arrival,
  damage included (craters, destroyed buildings, captured bases). The bonus bar is
  left out, since in ZIG it is HUD.
- **The live screen.** The game still draws its own screen into back exactly as in
  ORIGINAL (POINT and the zones read it). ZIG copies back into the live slot every
  frame, so smoke, craters and messages appear as they happen, except the bonus bar's
  box, which keeps the clean draw under it.
- **Crossing.** When the live screen moves one sector or one layer, the buffer moves
  one slot (a `memmove` of 499,200 bytes) and three slots are left to draw. They are
  drawn one a frame, nearest the view first. A slot the window touches is drawn at
  once, which only happens after a jump. A sector is 320 wide and the window reaches
  200 px past the plane, so the new slots are ready long before they are in view. The
  screen just left keeps its live look (trails, messages).
- **Staying true.** Each ground slot has a signature: the sector's type, its gun and
  building bits, its base, and the few globals the builders read. A bomb in a
  neighbouring sector changes it, and that slot is drawn again.
- **The camera** is the window's top-left in the world. It follows the plane's
  sprite (or the pilot's), a third of the way a frame and at most 16 px, so the world
  glides between the game's passes (the plane itself moves once a pass, as on the
  ST). It stops where the ground's last line meets the HUD. A jump too big to glide
  (a new plane, the autoland) is a cut.

Each sprite remembers the screen it was placed on (`Spr.fx, fy`, set from
`zig_hooks.frame()`), because between a wrap (56) and the redraw (40), and while the
pilot drifts down a layer (213), the game's `sx, al` name a different screen from the
one on show.

### What the neighbouring sectors show

The original draws only the current screen's sprites, but it moves many things
everywhere, every pass, because they carry their own sector and layer: the two enemy
fighters (`esx, eal`), the vehicles (`vsx`), the bomb, the rocket, the bonus crate,
the enemy pilot's chute, and the empty plane after a bail-out. ZIG draws those where
they are now, in whichever ring sector that is. Off the world's ends the game's sector
numbers are not the wrapped world's: an enemy is spawned at `sx - 3 .. sx + 3` (line
73), so below 0 at sector 0, and move255 wraps it from -1 to 400 and from 50 on to 51.
Such an enemy is drawn in the sector just past the end it left (400 is -1), and only
beside that end: the game shows it once it flies back into 0 .. 50. ZIG first drew
none of them, so near sector 0 (every mission-1 start) enemies coming from the left
were missing from the left border while those on the right showed (`zig_ring.seat`).
Line 1000 makes two things sprites on
arrival: an airfield's flag (sprite 5) and the bridge's arch (the mouse pointer). ZIG
draws those as the sandboxed draw left them. A sector's wrecks are drawn from its
wreck table (`so9`, `snox`). So a neighbour shows its current state for what moves,
and its state when last drawn for the rest. Nothing here is simulated that the
original does not simulate.

### The frame

- **Planes.** 0 is the original's screen (320 x 200), shown in ORIGINAL whenever the
  world is not. 1 is the world. 2 carries the sprites, tracers and HUD (400 x 280, index
  255 transparent) and, in ZIG off the world, the other screens (`zig_screens.zig`): the
  physic screen scaled 5/4 to 400 x 250 (nearest pixel, every fourth column and line
  doubled), at line 15, the 15 lines above and below in the colour most of the screen's
  top and bottom line is. 3 carries the mode notice.
- **Borders.** Planes 1 and 2 open all four with the earned trick: `flickerBorder()`
  from each plane's HBL at `OVERSCAN_MAGIC_X` on every line (`zg.flickerAllHbl`).
- **Allocation.** Both planes are allocated once, at the cart's init. `vramAlloc` has
  no guard, so `zig_scroll.zig` checks the total at comptime: 4 x 64,000 (the boot
  planes) + 518,400 (960 x 540) + 112,000 = 886,400 of 1,048,576 bytes.
- **HUD.** The panel is the game's own lines 176-199 of back, centred on the frame's
  lines 236-259, with black either side, and 20 lines of black under it: a monitor's
  frame covers the bottom of the picture, and at lines 256-279 the panel was hard to
  read. The world's view is lines 0-235, and the camera stops where the ground's last
  line meets the panel. The ammo counter sits in the black on the right. The bonus
  bar's box (14,2 to 306,12) keeps its columns and moves down 20 lines, to lines
  22-32. Both margins are settings (`hud_bottom_margin`, `bar_top_margin`).
- **Messages.** "Press 'S' to Launch", "BAD LANDING !" and the boxed verdicts are
  written into the screen by the game, so they sit in the world where the original
  puts them and scroll with it.
- **Colours.** No raster: the game changes no colour per line, and ZIG adds no such
  change. Every plane's palette is the ST's 16 colour registers each frame, so fades
  work.

### Tracers and the ammo counter

The original's guns (350-359) take a round and test each enemy's direction; they
draw nothing. ZIG *sees* a round taken (a hook in 350 counts each one) and sends
three streaks from the plane's nose along its heading (the listing's `dx()/dy()`
table). They travel twice the table's step a frame (up to 12 px). Each has a head in the palette's
most fiery colour and a tail in the next. A streak vanishes at the view's edge or at
an enemy fighter. The game never reads any of it; the ammo count and the hit dice are
the original's. The counter shows `ammo` in the game's font.

On the home airfield, stopped, there were no tracers. ZIG first watched the ammo go
down, but there line 101 rearms (532) in the same pass as the guns take their round,
so the count never moves: the counter rightly stays at 50 + b(2) and no round was
seen. The hook sees every round, landed or not.

### The weapon keys

In ZIG, left Ctrl fires the guns, left Shift a rocket and Space a bomb
(`zig_keys.zig`). Each is exactly the chord it stands for (FIRE, FIRE + right, FIRE
+ left) held, so the game sees the joystick and nothing else; the harness proves it
by CRC. Space still goes into the key buffer and is still FIRE, so with the pilot out
(`bale`) it lands his chute (155) and drops nothing. Ctrl is a fire button for the
old chords (Ctrl + left a bomb, Ctrl + right a rocket); Space + an arrow is a bomb.
ORIGINAL ignores Ctrl and Shift, and its Space is FIRE as on the ST.

### Craters

An enemy that hits the ground (316) may leave a hole where it fell: 920 sets a gun
bit of that sector (the crater image 73) and 930 adds its wreck to the sector's wreck
table. In the original they stay for the rest of the game. In ZIG, after
`crater_life_vbls` (1502 VBLs, 30 s; 0 = never) the sector's ground is put back
exactly as before that crash (`zig_craters.zig`): the bits the crash set are cleared
and the wreck slots it added are taken off. This is gameplay: a gun bit is what 1030
stamps and 945 counts. So it waits while the sector is on screen (its screen, zones
and sprites were drawn from the hole, and only line 1000 redraws them), and the ring
slot redraws by itself, since the gun bits are part of its signature. The harness runs
every ORIGINAL-against-ZIG comparison with the setting at never.

### Sound

The effects are synthesized by `tools/skystrike/make_sfx.py` (stdlib only, fixed
seeds): filtered noise and a few sines under envelopes. They are signed 8-bit at the
STE DMA rates, 28 KB in all (`apps/zig/assets/screens/skystrike/sfx/*.raw`). They ride
in `skystrike.sndh` (`sound_zig.s`, included by `sound.s`). Its new op 9 (ZPLAY)
starts one on the STE DMA sound chip, which this machine plays on its Paula sample
channels (`libs/zig/players/ste_dma.zig`), and op 10 (ZSTOP) stops it. The YM is not
touched, so the music and the engine's PSG note go on underneath. No host or machine
change was needed.

Each of the original's effect routines (sfx.zig, lines 990-998) marks its commands.
In ZIG the Maestro and PSG commands inside a routine are not sent, and its sample is:

| routine | when | ORIGINAL | ZIG sample |
|---|---|---|---|
| 995 | our guns, an enemy's guns | sample 1 looped | `gun` (75 ms, looped) |
| 998 | an enemy hit, flak, a flak hit | sample 2 | `bang` (airburst, 450 ms) |
| 994 | a crash, an enemy set on fire, a vehicle strafed | sample 2 | `crash` (1 s) |
| 993 on land | a bomb or a rocket reaching the ground | sample 2 (via 994) | `bomb` (900 ms) |
| 993 on water | the same over the sea | PSG noise, envelope 9 | `splash` (550 ms) |
| 997 | a scrape, the catapult | sample 2 + noise 5 | `hit` (220 ms) |
| 990 | the engine | PSG noise under envelope 10 | the same, on the YM |

The engine's SAMSTOP stops only a looping sample (the gun burst ends where the
original's did), and one-shots play to their end. A SAMSTOP elsewhere (the pause, the
verdicts) stops any sample. MUSIC OFF inside an effect is not sent, since the YM is no
longer needed for it. The game's own command log is the same in both modes. A rocket's
launch makes no sound in the original, so it makes none in ZIG.

### The key help (P)

While line 151 waits for the key that ends the pause, ZIG draws the key help over the
game (`zig_help.zig`). It is framed like the game's boxed messages (SQUARE's frame,
pen 1 on paper 14, the text in pen 0) and uses the game's font. The pause's random
tune and the "M" free-memory message are the original's.

Every binding was checked against the listing, and three differ from the list first
proposed:

- **F / F8 is not a refuel.** Landed and stopped (156), it sets `cl`. Line 68 then
  charges a plane for it and gives a new one at the main base, with "You Managed to
  Crash Land !".
- **Autoland works on Medium as well as Easy.** `atlf` is cleared only on Hard (2133).
  The sector must be a multiple of 10, and the autoland costs 500 x 4^lvl points.
- **Three bindings were missing from that list:**
  - W / F7 waggles the wings (106);
  - left / right steer the open parachute (82-83);
  - the left arrow lowers the throttle only down to 4 (120).

`keys.zig`'s own header called F a "refuel stop" too, and has been corrected.

### Memory

- **VRAM:** see above.
- **zg.mem:** allocated once per load. The sandbox's two scratch screens (128,000
  bytes) and its saved state (about 17 KB). The harness's capture screen (64,000) is
  allocated only when the harness asks for it.

### The proof (`apps/skystrike_zig.mjs`, tag `skystrike`)

- **(a) Crossings.** Left and right across sectors, up and down across layers. The
  pass at the new screen takes 2-4 VBLs (ORIGINAL: 25). The camera moves every frame
  by at most 4 px.
- **(b) Ring = redraw.** Each screen entered equals its ring slot, pixel for pixel,
  outside the bonus bar's box.
- **(c) Logic unchanged.** Three 170-pass flights with crossings, firing and a bomb:
  ORIGINAL; switched by Z four times; ZIG throughout. After every pass the logic CRC
  (`zig_crc.zig`) is the same in all three. The CRC leaves out only TIMER and the
  variables that copy it (`z2`, `t`, `fps#`, `lxt`), the flow's waits, and where an
  OFF sprite stands (a MOVE program left running keeps moving it by the VBL).
- **(d) The frame.** It equals the ring at the pan plus the overlay in all 112,000
  pixels, and the border pixels are lit. The panel and the bar are the game's. The
  ammo counter is in its font.
- **Tracers.** The streaks lie within 3 px of the heading line; ORIGINAL draws none.
  FIRE takes the same rounds in both modes.
- **Sound.** Each event sends its ZPLAY, and on the sealed audio machine the Paula
  channel starts on exactly that sample's bytes (looped for the gun). The music moves
  the YM as often with the samples as without. ORIGINAL starts no channel.
- **The pause.** The help shows in ZIG's pause only, and the CRC is the same in both
  modes before, during and after it.
- **(e) Memory.** No zg.mem allocation is refused.
- **Screens** (`skystrike_zig_screens.mjs`). The title, menu, briefing, hall of fame and
  name entry fill the open frame in ZIG, every pixel the physic screen scaled; ORIGINAL
  shows plane 0 alone. Z typed in the name entry does not switch.
- **Edges** (`skystrike_zig_edges.mjs`). Tracers on the heading when firing on the
  runway; an enemy in sector -1 and 400 drawn in the left border at sector 0, as one in
  sector 1 is in the right; no ghost plane where a bomb bursts (both modes).
- **Keys** (`skystrike_zig_keys.mjs`). Ctrl / Shift / Space = their chords by CRC;
  bailed out, ZIG's Space = ORIGINAL's; ORIGINAL ignores Ctrl and Shift.
- **Craters** (`skystrike_zig_craters.mjs`). A hole made next door is there a pass
  before its time, and by its time the ground bytes and the ring slot are what they
  were before the crash. ORIGINAL keeps it.
- **(d)** also checks that the panel ends 20 lines above the frame's bottom (those
  lines black) and that the bar is at lines 22-32.
- **Break modes.** Each check has a `--break` mode that must be caught by that check.

### The ghost plane (a port bug, both modes)

A bomb bursting on the plane's own screen left a copy of the plane in the back
screen. The original does not: at 1950 it turns the sprites OFF, and 993 starts with
WAIT VBL, during which STOS's VBL redraws the sprites (the listing never turns
automatic UPDATE off), so they are off the physic screen before 1956 copies it to back
(`gosub 192`, SCREEN COPY LOGIC TO BACK, logic being physic). The port's WAIT VBL only
counted the time, so the sprites were still drawn when the copy was made. WAIT VBL now
runs the sprite redraw at once (`clock.waitVbl`). The ST reference screens and the
takeoff trace still match. The Hatari check was not repeated for this: the game reads
no injected joystick, and the bomb's variables are not yet mapped to addresses.

### Music

ZIG was to play three ProTracker modules from The Mod Archive (battleship 1, 99351;
spitfire by Jonte, 106646; glory by dalmet, 165443). All three are under the "Mod Archive
Distribution license": the original file may be redistributed unmodified, but that
"does not cover inclusion in a packed/bundled application or game", which needs the
artist's permission. None is shipped; both modes play skystrike.sndh.

### Compromises

- **Frozen neighbours.** What the original does not simulate outside the current
  screen stays as the sector was last drawn: the flag does not wave, a wreck's fire
  does not flicker. The ships settling as they sink are animated only on their own
  screen.
- **Messages.** They are the game's pixels, so they scroll with the world rather than
  staying on screen.
- **The sprites' pace.** The plane and the sprites still move once per main-loop pass
  (about 2.8 VBLs), as on the ST. Only the camera glides.
- **Short glitches.** For the one to three VBLs between a wrap (56) and line 40, a
  bomb or rocket placed in the new sector's coordinates is drawn against the old
  screen, as the ST drew it.
- **Up and down.** Going down a layer, the original puts the plane at y = 0 of the
  layer below rather than at y - 160, so the world jumps a few pixels there; the
  camera glides over it.
