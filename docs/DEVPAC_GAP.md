# A Devpac-like IDE on KESTREL: gap analysis

Study of 7 Nov 2026 (branch `study/devpac-gap`, docs only, no code). Matt, 7 Nov: *"based on your TOS 4 /
MultiTOS analysis, the goal is not to steal it but to improve our Zig version in terms of widgets, features
and possibly like MiNT, multi-app support. I'd like to 'port' Devpac 3.1 (in the spirit, to get a windowed
assembler but for the KESTREL), can you do a gap analysis between our Z-GEM and what is needed to have our
own Devpac 3.1-like."* Then: *"it is a little weird in 2026 to not do cross-assembling but still nice to
have some local dev tools"* and *"I guess it has to run in our ST medium res"*.

So the brief is a period-spirit tool that **runs alongside** cross-development. Zig and C on the PC stay
the main way to build carts. The native IDE is for writing and running small programs on the machine
itself, the way people used Devpac on an ST. Companion documents: [GEM5_PLAN.md](GEM5_PLAN.md) (the
P-numbers below refer to it) and [prototypes/tos4x_re/ANALYSIS.md](../prototypes/tos4x_re/ANALYSIS.md).

## Summary

- **The question that decides everything: which CPU does it assemble for?** A KESTREL cart cannot run machine
  code that it builds itself. Code is sealed: a cart is wasm. In the browser the page instantiates that
  wasm. On the board the PC turns it into ZIGGY code ahead of time (wasm2c + GCC), and glass places the
  result. Neither host has a way to say "run these rv32 bytes I just wrote". So the IDE's output must run
  **inside the IDE, on an emulated CPU**. That CPU is the real choice.
- **Recommendation: a 68000 target, run inside the IDE on the Musashi core we already ship**, with a small
  "KESTREL 68k" system-call ABI (draw, keys, sound, GEMDOS) that still has to be designed. Musashi is already
  in the tree (`libs/c/musashi`) and in the SNDH player. It has an instruction hook (`zm_musashi.h:27`,
  `sndh_player.zig:237`), so MonST-style breakpoints and single-step come almost free. It behaves the same in
  the browser and on the board. Devpac syntax, the ST sources Matt already reads and the vasm/shirazmcp tools
  all carry over. Native RV32 is the "real KESTREL" target, but it stays on the PC (GNU as / Zig), where it
  already works.
- **One assembler, two hosts.** The assembler is a pure Zig library with no I/O. A PC command-line tool and
  the IDE cart both link it, so a file assembles to the same bytes on the PC and on the machine. Native
  tests pin it against vasm as an oracle.
- **The UI gap is the ROM ABI, not the widgets.** ZigGEM already has windows with sliders, sizing and topping,
  pull-down menus, medium res, a file selector and real C: writes. But carts only get `rom_sdk`'s flat ABI,
  which exports primitives, alerts and the file selector. The window manager and the menu bar are not
  exported (`build.zig:619-625`, `rom_main.zig:235-423`). Exporting them, plus a general text field and
  menu keyboard shortcuts, is the core of the MVP.
- **Medium res works today.** The desktop switches between low and medium (`gem_desktop.zig:44-63`). In
  medium the 8x8 font gives 78 columns by about 20 lines in a full-screen window, which is what Devpac
  showed on a colour ST. A full redraw of the text area is an estimated ~0.1-0.2 Mc against a 1.67 Mc
  frame. For Matt's next GEM-only 640x480 mode (80x60 cells), §3b gives the gap table. Before both modes
  can work, ZigGEM must stop assuming a 200-line screen: 200 is a literal in 9 places, the metrics are
  constants, and the pointer is mapped in the shell cart.
- **MVP: about 15 agent-days.** One to four editor windows, load and save on C:, Find, Goto, block
  operations, assemble to memory, an error list that jumps to the line, run in the sandbox and return.
  The debugger is about 8 more days. Multi-app follows GEM5 phase 3 (cooperative accessories), not MiNT.

## 1. Devpac 3.1: what it is (in our words)

Source: `devpac31.zip` from files.dhs.nu, unpacked into `prototypes/devpac_re/dl/` (untracked, study only).
The archive has no manual, only a short read-me of 3.10 changes. The inventory below comes from that
read-me, the program's embedded strings (menus, dialogs, alerts), the saved preferences file and the file
list. Nothing from it (code, resources, text, icons) enters the tree. Commercial software, HiSoft 1993.

**The package.** A GEM editor that is the IDE shell, plus separate tools it launches:

- the macro assembler (`GEN.TTP`, plus a 68030 build);
- a GEM debugger (`MON.PRG`, plus a 68030 build);
- a resident debugger (`AMON`);
- a linker for Lattice/DRI objects, a symbol stripper and an S-record splitter;
- GEM/GEMDOS/BIOS/XBIOS include files, AES/VDI call libraries, examples (a desk accessory, a GEM demo);
- a menu-to-assembler converter, a RAM disk, and HiSoft's replacement file selector.

**The editor.**

- **Windows.** Several files open at once, one per GEM window. Arrange (tile, stack or overlap) and cycle
  the top window. A warning when the same file is opened twice. Read-only windows.
- **File.** New, load, insert a file at the cursor, revert, close, save, save as, delete a file, change
  directory, quit. A warning before unsaved changes are lost. Backup files are optional.
- **Edit.** Cut, copy and paste. An ASCII table to insert any character. Top, bottom, goto line.
- **Blocks** on function keys: mark the start and end, then save, copy, delete, remember, paste or print
  the block. Shown as a flashing or still block or line.
- **Search.** Find, find next or previous, replace, replace all. Case sensitivity is an option.
- **Bookmarks.** Nine numbered marks, set and recalled with Ctrl + a digit.
- **Preferences.** Tab width, auto-indent, cursor style, numeric-keypad cursor mode, buffer size, save
  on quit or run, and a font choice (the TOS or the GEM system font). They are saved to a text file of
  three-letter key/value records (`hisofted.inf` in the archive, e.g. a 256 KB edit buffer and an editor
  tab of 8).
- **Help.** Keyboard shortcuts on most items (Ctrl + letter, F1-F5 for blocks, Alt for menus). A free
  memory readout. We found no online help in the strings.

**Assembling.**

- Assemble the top window to memory (fast, no disk) or to a file. Check only (syntax pass). Write a
  symbol file.
- Output types: Atari executable, linkable objects (DRI, GST, Lattice), S-records. Code can go to ST
  or TT RAM.
- Options in dialogs:
  - debug symbols: none, normal or extended;
  - listing: to a file, the printer or the screen, with macro expansions, conditionals and the symbol table;
  - automatic optimisations (backward branches, short forms), with a report of the bytes saved;
  - the CPU (68000-68040), case-insensitive labels, warnings on or off.
  - All of it can also be set in the source with `OPT` lines.
- The assembler itself: macros (nesting checked), `REPT`, conditional assembly, nested includes with an
  include path, `XDEF`/`XREF` (a label ending in two colons is also exported), phase-error detection. A
  `WITH` file and environment variables (`GEN_OPT=`, `INCLUDE=`) set options.
- **Errors**: the assembler reports file and line. The editor steps through them ("previous error",
  "jump to error") and puts the cursor on the line. This is the feature that made Devpac an IDE rather
  than an editor next to an assembler.

**Running and debugging.**

- Run the assembled program (as a TOS or GEM program) and come back to the editor with everything still
  open. An end-of-program alert.
- Debug: run it under MON with its symbols. Run MON alone. Run any other program, or one of 20
  configurable tool slots, each with its own directory and command-line rules.
- MON (from its strings): separate windows for registers, disassembly and memory. Breakpoints with
  conditions and counts, plus GEMDOS-call breakpoints. Trace and step. History. Symbols in the
  disassembly. Register and memory editing. Memory compare. A resident version survives the program it
  debugs.

**What matters for a KESTREL IDE**, in order:

1. edit, assemble and run without leaving the window;
2. errors that jump to the line;
3. several files open (main source + includes);
4. Find, Goto, blocks;
5. preferences saved;
6. a debugger with symbols.

Linkable object formats, printing, S-records, the RAM disk, TT RAM and the replacement file selector do
not matter here.

## 2. Which CPU does "an assembler for the KESTREL" target?

### What can run on KESTREL today

| Fact | Evidence | Consequence |
|---|---|---|
| A cart is wasm. On the board it is turned into ZIGGY rv32 by wasm2c + GCC **on the PC**. glass checks the result against the system's ABI and places it | `fpga/tools/kos_rv.py` (the `.RV` container: wasm hash + packed board image), docs/PERF_AUDIT.md | There is no compiler on the board. A cart cannot jump into bytes it wrote: wasm has no such operation |
| The browser runs only wasm. There is no rv32 emulator in the page | `docs/sealed-loader.js` | Any rv32 output needs an emulator in the browser too |
| A small sandboxed wasm interpreter exists on the board: integer MVP, 1 KB modules, no `call_indirect`, a fuel budget | `fpga/host/wint.h:1-30` (777 lines of C), `fpga/host/bootsec.h` | A seed for running wasm on the board. Far from a general engine, and it lives in the firmware, not in a cart |
| A 68000 core (Musashi) is in the tree, built for wasm and for BARD, with an instruction hook | `libs/c/musashi/`, `config/zm_musashi.h:27` (`M68K_INSTRUCTION_HOOK`), `libs/zig/players/sndh_player.zig:237` | A complete, tested CPU we can link into a cart. Single-step and breakpoints are already plumbed |
| ZM-X custom instructions have a C twin with the same integer results | `fpga/cycles/zmx_twin.h` | An rv32 emulator could run ZM-X too |
| Today's GEM-launched programs (GrafX2, klystrack, pt2, MP3 PLAYER) are full-screen carts: the C ports draw through `kestrel_sdl2`, and none uses a ZigGEM window. The only `rom_sdk` users (sysinfo, ST Replay) draw with primitives | `apps/zig/scenes/sysinfo/menu.zig`, `st_replay_ui.zig:16`, docs/KOS_GEMDOS.md §1 | No cart uses GEM windows because none can (§4, the ROM ABI row) |
| ZIGGY traps misaligned and illegal instructions to a C handler | `fpga/cycles/trap.c` | A native debugger hook exists in principle, but only for system code, not for a cart's sandbox |

### The options

**(a) RV32 for ZIGGY (rv32im + ZM-X).** This is the most literal "KESTREL assembler".

Pros:
- GNU as is a perfect oracle;
- the ZM-X ops are a fun showcase.

Cons:
- The output cannot run natively. It needs either a new firmware path ("place and run this rv32 image",
  with ABI checks, glass's side, board only) or an rv32 emulator in the cart for both hosts.
- An rv32im interpreter is small, about 1,000 lines of Zig, and S-M to write. We estimate ~20-40 ZIGGY
  cycles an instruction, so 2.5-5 MIPS: comfortably faster than an ST.
- Nobody in this project writes RV32 by hand today. Cross-development already covers real rv32 code, through
  wasm2c, better.

**(b) 68000, an ST-style environment inside the IDE.**

- Musashi in the cart runs the program. Its 68k memory is a block of the cart's RAM.
- `trap` instructions map to a small KESTREL 68k ABI, to be designed. Draw into a FRESCO plane (chunky
  8-bit, no planar emulation), read keys and the mouse, play a sound, wait for VBL. GEMDOS calls go to KOS
  GEMDOS on C:.
- Speed, an estimate derived from the SNDH figures (docs/FPGA_SOUND_CPU.md). On BARD, Beat Dis costs 3.85 Mc
  a frame through Musashi against 0.71 Mc native. The glue around each interrupt costs 14.6 kc through
  Musashi against 2.2 kc native. Musashi does about 20 stores per 68000 instruction (same doc, line 236). At
  ~2.3 cycles a posted store that is ~50 cycles of stores alone. We estimate 150-300 ZIGGY cycles per 68000
  instruction, so **0.3-0.7 MIPS**: about an 8 MHz ST, or up to half its speed. Measure it with a bench cart
  before relying on it.
- Pros:
  - the CPU is done and tested;
  - the debugger hook exists;
  - Devpac's own syntax (`OPT`, macros, `XDEF`, `::`), so period sources and books apply;
  - vasm (which shirazmcp already uses) is the oracle;
  - it matches the project's ST soul (SNDH, `/convert_st`, shirazmcp).
- Cons:
  - **the ABI is undesigned**, and it is the real cost;
  - the programs are not ST programs (no Line-A, no real Shifter), only "68000 on KESTREL";
  - a full ST is out of scope, since Hatari exists.

**(c) wasm text, so the output is a real cart.**

- In the browser the output is the real thing: a `.WSM` runs at full speed.
- On the board it cannot run without a wasm engine in the cart, or without growing `wint` from 1 KB boot
  sectors to programs. Both are M-L, and wint is firmware, not cart code.
- Hand-writing a stack machine is not Devpac's spirit: there are no registers to watch in a debugger.
- It is the right format for "native tool makes a cart". It is the wrong language to write.

### Recommendation

Make **(b) the first target**, designed so the CPU sits behind one interface (`Cpu`: step, registers,
memory, breakpoints). That lets **(a) be a second back end later**: an rv32im interpreter running the same
syscall ABI with a new instruction set, and the same editor, error list and debugger.

Keep (c) out of the IDE. A future "export as cart" could wrap a 68k program in a tiny runner cart (the
Musashi runner + the program as data), once the desktop can pass a document to a program (GEM5 P1.6
command tail). Then a native program can also be launched from the desktop.

### How the native IDE and cross-development meet

| Need | How |
|---|---|
| One assembler, two hosts | `libs/zig/asm68k/` (name to be set): a pure library (source bytes in, object + errors + symbols out, includes through a callback). `tools/zasm` (a PC command line, `zig build`) and the IDE cart both link it. Native `zig test` runs a corpus that is assembled by vasm as well, byte-compared |
| PC sources to C: | Page: the `?c=` image is in memory and lost on reload. Add "download C: image" and a dev-server image (S). Board: C: is the SD card's `/HD`. Copy on a PC, or push over the serial console (the base64+md5 path already used for SD updates). Later over Ethernet (ROADMAP "Ethernet for ssh") |
| C: binaries to the PC | The same paths. Programs are files on C:, so the PC tool runs them too: `zasm --run` runs the program in the same Musashi + ABI, natively, for tests and CI |
| Remote MonST from the PC | Phase D2. A debug mailbox in the IDE cart (registers, memory, breakpoints, step) speaks one protocol. Browser: DevTools/a page panel through a cart export. Board: glass relays it to the serial console or a TCP port, sharing the protocol with the KOS v2 tool-cartridge freezer (ROADMAP P1 row), so one PC client serves both |

## 3. Medium res (640x200): what we have, and the cost

| Area | Today | Evidence |
|---|---|---|
| Desktop in medium | Yes. Preferences switch low/medium, `#E 01` is saved, one 640-wide plane is allocated once and serves both | `gem_desktop.zig:44-63`, `prefs.zig:64-65`, `deskinf.zig:35`, `desktop.zig:111` |
| Pointer | The host sends physical 0..640 coordinates; the desktop maps them | `gem_desktop.zig:111` |
| Windows, menus, dialogs, file selector | Laid out in 8 px cells against `screen_w`; dialogs centre at 640 (the file selector at x 160) | `core.zig:22`, `filesel.zig:15` |
| A cart in medium | Yes. ST Replay is a 640x200 cart over `rom_sdk` | `st_replay_ui.zig:1-20` |
| Fonts | 8x8 system font and 6x6. No 8x16 (that is GEM5 P2.5) | `zigos.zig:1047-1060` |
| Switching cost | Per cart. The IDE is a cart, so it sets medium itself at start and leaves the desktop's setting alone. No whole-desktop switch is needed | — |

**Text layout.** On a colour ST, Devpac ran in medium with the 8x8 system font, like every GEM text window.
That is 80x25 cells on the screen. (This is period knowledge; we did not measure it in Hatari.) Here a
full-screen window takes the menu bar (11 px), a title (11), an info line (10, used for "line/col,
insert, modified") and a horizontal scroll bar (11). That leaves ~157 px = **19 lines of 78 columns**
(640 minus the 12 px vertical bar). Without the info line it is 20 lines. Medium pixels are twice as tall
as wide, which is the authentic look.

**Text scrolling cost on the board** (estimate from CLAUDE.md's board model; measure with
`apps/frame_cost.mjs`):

- The glyph writer stores a word at a time (`zigos.zig:921-925`, `glyph_line.zig`): 2 word stores per 8 px
  glyph row, so 16 stores a cell.
- A full window repaint is 78 x 19 = 1,482 cells, ~24 k stores = ~55 kc of stores. With glyph lookup and
  loop overhead it comes to roughly **0.1-0.2 Mc**.
- Scrolling by one line = a full repaint of the text area, so no copy is needed. Never copy within the
  plane on CHISEL: in-plane copies run ordered and slow (`zigmachine-chisel-inplane-copy-ordered`). A CPU
  move costs about the same as the repaint.
- The editor uses one enabled plane: the desktop's, ~0.59 Mc of compositing. The total stays well under the
  1.67 Mc frame.
- Typing repaints one line (~5 kc). The desktop's dirty rule (`deskdirty.zig`: draw only on change) applies
  as is.
- Hardware scrolling (`FB_BASE` per plane) helps only a full-screen editor. A GEM window is a sub-rectangle,
  so we skip it.

### 3b. A GEM-only 640x480 mode (Matt's next ask), and what ZigGEM must abstract

Matt wants a minimal 640x480 mode next: one 8-bit plane, shown 1:1 in the 800x600 output, with no rasters,
copper or overscan, only for GEM apps and TUIs. It gives **80x60 cells of 8x8** (or 80x30 of 8x16). For
the IDE that is a full-screen window of **78 x 54 lines** (480 - 11 - 11 - 10 - 11 = 437 px). Pixels are
square, so 8x16 (GEM5 P2.5) becomes the readable choice. 8x8 at 1:1 is small but crisp. The RTL side is a
separate study. This section is the software side.

| Area | 640x200 medium (today) | 640x480 GEM mode (new) | Evidence |
|---|---|---|---|
| Plane buffer | 128,000 B (`MEDIUM_FB_BYTES`), allocated by `setMediumPlane` | 307,200 B. Fits in the 1 MiB VRAM pool (`memmap.zig:72`) beside little else. `vramAlloc` has no overrun guard, so add one first | `memmap.zig:43`, `zigos.zig:759-768` |
| Composite / host | Physical FB 800x280 u32 (`memmap.zig:54-61`, 896 KB) | Not representable: the physical raster is 280 lines. The page needs a second canvas geometry (or a plane presented directly, skipping the 800x280 composite). The native host and the board scanout need the same | the RTL study |
| Mode switch API | `FB_MODE_MEDIUM`, `RES_MEDIUM`, `setResLow/Medium` at run time | A new `RES_` / `FB_MODE_` value, a `setGemPlane()` twin, and a capability bit so a cart can ask whether the mode exists (HW API bump) | `zigos.zig:759-800` |
| Screen height in ZigGEM | `Gui.screen_h` exists (`core.zig:23`), but **200 is hard-coded in 9 places**: `window.zig:293` (full box), `deskwin.zig:118` (window fit), `deskdraw.zig:19` (desk fill), the centring of `about.zig:35`, `prefs.zig:45`, `trash.zig:29`, `info.zig:105`, `filesel.zig:64` | Replace them all with `g.screen_h`. Dialogs (`dialog.zig:76`) and the icons (`desk_icons.zig:35-38`) already use it | grep `200` in `rom/gem` |
| Desktop init | `desktop.zig:111` fixes 640x200; `deskSetScreen(w, h)` exists | `deskInitPlane(plane, 640, 480)` must reach the buffer size; DESKTOP.INF `#E` needs a third resolution code (02) | `deskinf.zig:35` |
| Mouse | The host sends 0..640 x 0..200; the desktop halves x in low (`gem_desktop.zig:111-114`); "Y is 200 in both" | A 0..479 y range from the page and from glass's evdev mapping. The cart maps by its mode, not by a `desk_medium` boolean. The cursor sprite (`bcursor.c`) must clamp to 480 | `gem_desktop.zig:111` |
| Fonts / metrics | 8x8 / 6x6. Metrics are constants: `MENU_H 10`, `TITLE_H` = 11 from `gem_glyphs.GH`, `CELL 8` (`types.zig:70-80`) | With 8x16, the menu bar (char height + 3 = 19), title, info line and item heights follow the font, as GEM's `gl_hchar`. Today's 12x11 gadgets stay as they are (TOS used 16x16 gadgets in high res: optional art) | `types.zig:70-80`, `menu.zig:6` |
| Coordinates | `Rect` is i16 | Fine up to 32767 | `types.zig:61` |
| Board cost | One plane ~0.59 Mc; a full text repaint ~0.1-0.2 Mc (§3) | The text area is 2.4x larger: a full repaint is ~0.25-0.5 Mc (estimate). Compositing a 307 KB plane: the RTL study must measure it. The dirty-only rule matters more | CLAUDE.md board model |

**What ZigGEM must abstract so both modes (and low) work**, a refactor that is worth doing before the IDE's
M4:

1. **One `Screen` description**, set by the cart or the desktop at init and on a mode change: `w`, `h`, the
   pixel aspect (2:1 medium, 1:1 GEM mode), and the font (cell w/h). Every layout reads it; no literal 200
   or 640.
2. **Font metrics as data**, not constants: `CELL_W`, `CELL_H`, and the menu bar / title / info / item
   heights derived from `CELL_H`, as GEM's `gl_wchar` / `gl_hchar` / `gl_hbox`. The grid (`grid.zig`) is
   built on them.
3. **Pointer mapping in one place.** The ROM gets logical coordinates; one function maps the host's
   physical range to the mode (halve x in low, 1:1 elsewhere, y range by mode). Today that mapping lives in
   the desktop's shell cart.
4. **Plane allocation by mode**, including the "does this mode exist" capability, so a cart built for 640x480
   falls back to medium on an older system, with an alert rather than garbage.
5. **The DESKTOP.INF resolution code** gains a value. Window rectangles saved in one mode are clamped when
   loaded in another (the icons already do this, `icon.zig:112`).

## 4. Gap table: ZigGEM today vs what the IDE needs

Sizes are agent-days including the proof harness: S <= 1 d, M 2-4 d, L 5+ d. "GEM5" = the item in
docs/GEM5_PLAN.md that already covers it.

| Area | Exists (file:line) | Missing for the IDE | Size | GEM5 |
|---|---|---|---|---|
| **ROM ABI for apps** | Carts get `rom_sdk` only (`build.zig:619-625`): primitives, `dialog*` (alert), `fileSel*` (`rom_main.zig:235-423`, `sdk/rom.zig:77-109`) | Export the window manager (open/close, top, geometry, sliders, the content rect, redraw-needed), the menu bar, a text field and a check/radio group as handle-based calls, like `dialogOpen`. Same-commit rule for `rom_main.zig` + `sdk/rom.zig`. **Gates the MVP** | M (3 d) | P2.6 is the nearest (event layer); this is the plain export it presupposes |
| Windows: several, topping, sizing, full, sliders | `gui/window.zig:19-330`: 7 windows (`types.zig:78`), outline move/size, z-order, close/full/size boxes, arrows, live sliders (`types.zig:134-158`), info line | Page up/down on a click in the slider track (only arrows step by 1 today); a redraw/dirty flag per window for the owner; a Cycle Windows call; Arrange (tile/stack) is IDE-side | S | P2.3 (8 windows, bottoming) is a bonus, not needed |
| Text in windows | 8x8 and 6x6 fonts, a per-character clip (`core.zig:73-100`), word-store glyphs | A text-view helper: draw lines `[top, top+n)` from a line index at a column offset, cursor block, selection inverse. A per-line repaint. Tabs expanded on draw | M (2 d) | P2.5 only for 8x16 (not needed) |
| Menus | `gui/menu.zig:62-150`: drop on hover, ticks, disabled, separators | **Keyboard shortcuts**: `MenuItem` has no key field (`menu.zig:31`) and the label doesn't show one. Add a key, its display, and a "which item does this key pick" lookup. Alt + the title letter is optional | S | P1 "Keyboard shortcuts" (desktop side) |
| Dialogs | `Dialog` = alert (5 lines) + an open-files list (`dialog.zig:39-72`); prefs fakes radios with buttons (`prefs.zig:64`) | A form runner: an editable free-text field (`NameField` is 8.3 upper-case only, `namefield.zig:35`), a numeric field, checkbox, radio group, Tab between fields, Enter = default, Esc = cancel. Needed by Find/Replace, Goto, Options, Preferences | M (3 d) | P2.6 (`form_do`-style runner) |
| Scrollable lists | `filesel_list.zig` (9 rows, a slider), inside the selector only | A reusable list for the error list and a symbol list | S | — |
| File selector | `filesel.zig`: TOS 1 look, the caller supplies names, 8.3 field | Folder navigation (double-click a folder, `..`), an editable Directory line, drive A:/C:, more than **32 names** (`filesel_list.zig:17`), a `*.S` mask. It does not touch the disk: the IDE fills it from `Fsfirst`/`Fsnext` | M (2 d) | P1.1 shares the folder walking |
| Clipboard | None anywhere in `rom/` or `libs/zig` | IDE-internal (blocks, cut/copy/paste) is enough for the MVP. A shared one (a file on C:, as GEM's `\CLIPBRD`) only with multi-app | S (internal) | — |
| GEMDOS on C: | Read: `Fopen/Fread/Fseek/Fsfirst/Fsnext/Dsetpath` (docs/KOS_GEMDOS.md). Write: `Fcreate/Fwrite/Fclose/Fdelete/Frename/Dcreate/Ddelete/Fattrib` (docs/KOS_GEMDOS_WRITES.md), a safe save through a temp name, the path gate (`rom/kos/kfs_path.zig`) | Enough for load, save, includes and outputs. Missing: `Fdatime` (rebuild only when changed, file dates in the list), `Dfree` (free space), `Fopen` modes 1/2 (not needed: an editor rewrites the whole file). A: stays read-only (EWRPRO) | S | P1.1 uses the same calls |
| The IDE on C: | Only drive A launches (`desktop.zig:171`); programs are `.WSM` + `.RV` on a floppy | Launch from C: (`C:\DEVPAC\ZIDE.WSM` + its `.RV`), and the document as an argument (double-click a `.S`) | M | P1.6 (Install Application, command tail) |
| Memory for large files | 2 MiB cart window; GEM's ~525 KB statics live in `rom.wasm`, not the cart, since phase 2; `hwRamFree()` (docs/MEMORY.md:34) | A gap buffer per file, pooled (e.g. 4 x 256 KB, like Devpac's 256 KB default), the assembler's tables, the 68k RAM (1 MB?). Budget it with `hwRamFree()` at start, and refuse a file that doesn't fit with an alert, never a silent cut | S (design) | — |
| Keyboard | `key(cp)`: printable characters, Backspace, Enter, F1-F10, Insert, Delete, Undo, Help, Esc; modifiers by side as press codes (`sealed-loader.js:854-866`); arrows as `input(dir)`; board through `binput.c` / `input_bridge.c` | **Tab, Home, End, Page Up/Down, Clr-Home** codes. **Ctrl/Alt + key chords**: today only the modifier's press is sent, so a cart must track the held state through `keyUp`. Arrows as key codes with Shift (select). Same on the board's evdev map. Watch for the browser eating Ctrl+W/T/N: the page must `preventDefault` when the cart owns the keyboard | M (2 d, page + board) | — |
| Events / timers / messages | Immediate mode. Pointer and keys per frame, the frame is the timer, `ownsKeyboard` | Nothing for a single-app IDE: it owns its loop. Double-click timing is IDE-side. AES messages matter only with multi-app | — | P2.6 (optional) |
| Run a child and come back | Request 3 = swap to a program, request 4 = back to **the desktop**. No command tail, and the caller's state is lost (`demo_main.zig:316-327`) | With option (b) the program runs **inside the IDE** (no swap): nothing is needed. A real Pexec ("run X, come back to me with my state") stays useful for "run a real cart from the IDE"; it is GEM5 P3.4 generalised | — (b) / L (Pexec) | P3.4 |
| Debugging hooks | Musashi's instruction hook (`zm_musashi.h:27`); ZIGGY's trap handler (`trap.c`); the KOS v2 tool-cartridge freezer is planned on glass's side (ROADMAP P1) | A `Cpu` interface: step, run to an address, breakpoints (address, count, condition), registers, memory read/write, a VBL stop. Disassembler (68k, ours; vasm/shirazmcp as test oracles). Symbol table from the assembler | M (core) + M (UI) | KOS v2 tool cartridge (shared protocol) |
| Preferences | `deskinf.zig`: a text record writer/reader for DESKTOP.INF | The same pattern for `C:\DEVPAC\ZIDE.INF` (tabs, auto-indent, backups, window rectangles, last files, assembler defaults). Written through `Fcreate` | S | P1.2 (INF) |
| Help | None (no text pager) | A Help key that opens a read-only window over a shipped `ZIDE.HLP` (our own text): the same text view, read-only | S | P1 "Show/print text" pager |
| Multi-app / accessories / processes | None. One cart owns the machine | Not for the MVP. Later: the IDE as a desk-accessory host (a calculator, an ASCII table, a jukebox) under GEM5 P3.1's cooperative model. MiNT-style processes stay skipped (GEM5 "What we skip") | L | P3.1-3.2 |

## 5. Phased plan

**Phase M: MVP, a windowed editor + assembler (~17 d with M0).**

| # | Item | Effort | Proof |
|---|---|---|---|
| M0 | Screen abstraction (§3b: no literal 200, metrics from the font, one pointer mapping, the INF code) | 2 d | scene_hash of the desktop in low and medium unchanged byte for byte; a native test lays out at 640x480 |
| M1 | ROM ABI exports: windows, menu bar (+ keyboard shortcuts), free text field, checkbox/radio, list | 4 d | A sample cart drives them through the harness; scene_hash pins; `rom_abi_check` passes |
| M2 | Keyboard: Tab/Home/End/PgUp/PgDn codes, chords with Ctrl/Alt/Shift, page + board | 2 d | Harness types chords on the page; `binput` sim keys (`ZM_SIM_KEYS`) show the same codes |
| M3 | Editor core (pure Zig, native tests): gap buffer, lines, cursor, blocks, find/replace, goto, tabs, bookmarks, undo of one step | 3 d | `zig test`: edits, a 200 KB file, break: a buffer full refuses with an error |
| M4 | The IDE cart at 640x200: up to 4 windows, File/Edit/Search/Program/Options menus, load/save on C: through KOS GEMDOS, the file selector with folders | 3 d | `apps/zide_check.mjs` (gated) over a C: image: open, type, save, re-read through KFS byte-exact; break: a full disk keeps the old file |
| M5 | Assembler library (68000, Devpac-like syntax: labels, `EQU`, `DC/DS`, all addressing modes, includes, macros, `REPT`, `IF`, `OPT`) + `tools/zasm` on the PC | 4 d (+ macros 2 d, can follow) | A corpus assembled byte-identically against vasm; errors carry file:line |
| M6 | Assemble in the IDE: to memory, error list window, jump to the line. Run in the sandbox (Musashi + the first ABI calls: plane draw, key, VBL wait, exit) and return | 3 d (+ the ABI design note, 1 d) | Harness: assemble a sample with one error, jump to it, fix, run, the plane's hash matches; break: an endless loop is stopped by the frame budget, not a hang |

**Phase D: the debugger (~8 d).** D1, MON-like windows in the IDE (4 d): registers, disassembly with
symbols, memory, breakpoints, step/trace, run to the cursor. D2, the remote link (4 d): the debug mailbox,
page and board transports, a tiny PC client, sharing its protocol with the KOS v2 tool cartridge.

**Phase X: extras and multi-app (later, sized when wanted).** An RV32 back end with the same `Cpu`
interface (rv32im + ZM-X twin, GNU as oracle), ~6 d. Export a program as a runner cart (needs GEM5 P1.6),
~3 d. A listing to a file, a symbol output, optimisation reports, ~2 d. Desk accessories inside the IDE
and the desktop: GEM5 P3.1-3.2.

**Order.** M1 and M3 can run in parallel; M5 is independent of the UI and can start first. M2 before
M4's shortcuts. A board check after M4 (frame cost of the text view in medium) and after M6 (Musashi
speed on ZIGGY, the estimate in §2).

## 6. Risks

- **The 68k syscall ABI is the real design work.** If it grows toward an ST (Line-A, planar screen,
  XBIOS), it never ends. Keep it to a page of calls and chunky planes.
- **Musashi's speed on ZIGGY is an estimate** (§2). If it is far below 0.3 MIPS, demos written in the IDE
  won't feel like an ST. Measure with a bench cart before M6.
- **Musashi in a cart.** It is C, built into `demo-audio.wasm` today. A cart linking C through Zig's
  build, and wasm2c on the board, should work (the C ports do it), but its size and the cart's RAM must be
  checked.
- **Keyboard chords in the browser.** Ctrl+W, Ctrl+N and Ctrl+T are taken by the browser and cannot be
  stopped. Pick bindings that survive, or use Alt.
- **The ABI exports grow `rom.wasm` and the system table.** Batch them with the next table change
  (P1.6's command tail).
- **Licence hygiene.** Devpac is commercial. Features are inventoried in our words. The syntax is a
  convention (Devpac and vasm share it), not code. No menu text, resources or icons are copied.

## 7. What Matt must decide

1. **The target CPU:** 68000 in a sandbox (recommended), RV32 in a sandbox, or both behind one interface
   from the start.
2. **The scope of the 68k ABI:** "chunky KESTREL 68k" (recommended), or a partial ST (planar screen,
   some XBIOS) so period sources run unchanged.
3. **Whether the ROM ABI exports (M1) are worth doing for the IDE alone.** Every future windowed cart
   gains from them, but they enlarge `rom.wasm`.
4. **The name** (ZIDE, ZigPac, KPAC...) and where it lives (C:\ folder layout).
5. **Which screen first:** medium 640x200 now (works today), with the IDE moving to the 640x480 GEM mode
   when the RTL lands. M0 makes that a setting, not a port.
6. **Priority against GEM5 phase 1.** P1.6 (launch from C: with a document) makes the IDE launchable from
   the desktop. Without it the IDE ships on a floppy like the other programs.
