# NOTEPAD: a GEM 5 program, and what writing it found in GEM 5's API

Status: **built on `feat/gem5-notepad`** (9 Nov 2026). Matt: "To validate the gem 5.0 can you write a
window notepad like application?" Cart `notepad` (index 127), `apps/zig/scenes/notepad.zig` +
`notepad/`; proof `apps/notepad_check.mjs` (gate `notepad`).

## What it is

A TOS-style Notepad, written the way a GEM program is: everything GEM is the ROM's, reached through
the app-facing ABI (`rom_sdk`, and its new half `rom_sdk.aes`), the files are KOS GEMDOS's.

- **A window** with every gadget (closer, title, fuller, both sliders and their arrows, sizer) from the
  ROM's window manager: move and size as GEM's dotted outline, track clicks page, arrows repeat while
  held. The title is the file's name, with ` *` while it is modified. No word wrap: a long line scrolls
  sideways.
- **A menu bar**: Desk (About Notepad...), File (New ^N, Open... ^O, Save ^S, Save As..., Quit ^Q),
  Edit (Cut ^X, Copy ^C, Paste ^V, Select All ^A, Find... ^F). Cut and Copy are disabled with no
  selection, Paste with an empty clipboard. Control + letter is the shortcut, as on TOS (the page and
  glass send Control as its own key, 0xE014, and its release through `keyUp`).
- **Editing**: typing, Backspace, Delete, Return, Tab, the arrows (Shift extends the selection), Home,
  End, PgUp, PgDn, a click places the cursor, a drag selects (Shift+click extends). Find... is
  case-insensitive, from the cursor, wrapping once; "Text not found." otherwise.
- **Files**: `C:\*.TXT` through KOS GEMDOS, in any folder of C:. Open and Save As use the ROM's ITEM
  SELECTOR, filled with `Fsfirst`/`Fsnext` (the folder's sub-folders, then the files the mask matches):
  a folder row opens it, the close box goes up, the Directory: line can be edited (`C:\*.*`), and the
  file opens or saves in the folder shown; a typed name gets `.TXT`. Saved with CR LF (as ST editors wrote), read with LF or
  CR LF. New, Open and Quit (and the closer) on a modified text ask form_alert's
  `[2][Save changes to|NAME.TXT?][Yes|No|Cancel]`: Yes saves first (through Save As when the text has
  no name), No goes on, Cancel stops. A failed read or write is an alert with GEMDOS's error code.
- **Limits**, each an alert, never a silent cut: 64 KB of text (LF), 16,384 lines, a file of 128 KB at
  most on disk (CR LF), 32 files in the selector (its list's size).
- **Resolutions**: the desktop's. A program cannot read it off the machine (each cart swap resets
  `RESOLUTION`), so the ROM tells it (`deskScreenMode`, Getrez; on the board the mode crosses the
  program's load in a word the glass carries, docs/GEM_DESK_MODE.md §5). Low (320x200), medium (640x200) and the
  desk (640x480, where the machine has it). `setShadeMode(0..2)` switches at run time (the harness and frame_cost call it; on the page the digits are typed, Notepad owns the keyboard). The font is
  the system 8x8 in every mode: the 8x16 one exists only in Matt's local asset set (`-Dgem_assets`) and
  the app API has no text call for it. The view asks the ROM for the cell (`guiCell`), so an 8x16 system
  font would change the line height and nothing else.
- **Board speed**: the program draws only the rows the edit touched (a bit per row, notepad/view.zig):
  typing a letter repaints one row, an idle frame paints nothing; the sliders and the title are set and
  redrawn only when they change; menus, the outline and the desk's arrow are put back from save-under
  (the program redraws nothing for them). No float. A whole repaint only at start, after a dialog, a
  move or a size.

## The API findings

What a program needed that GEM 5's ABI (Phase 2's `rom_sdk`) did not have. "Fixed" = in the ROM on
this branch, appended exports (**system table 1.17**), the app half in `rom/sdk/aes.zig`, the ROM half
in `rom/rom_app.zig` and `rom/gem/gui/app*.zig`.

| # | Gap | What | Status |
|---|---|---|---|
| 1 | **No windows** | The window manager (`gui/window.zig`) was the desktop's only. `winOpen/Close/Title/Info/Scroll/Set/Process/Events/Draw/DrawBars/Get` give a program the same windows, with the AES's messages as event bits: EV_WORK (a press in the top window's work area: the program's), EV_HIT, EV_CLOSED (a request: the window stays until the program closes it, after "Save changes?"), EV_MOVED, EV_SIZED, EV_SCROLLED, EV_TOPPED | Fixed |
| 2 | **No menu bar** | `menuTitle/Item/Flags/Process/Draw/Busy` (menu_bar, menu_ienable, menu_icheck). The desktop repaints its bar every frame; a program's is drawn only when the open title or the hovered row changes (a logic pass with the Gui muted, GEM 5's clip), and the screen under a drop-down is saved and put back, as TOS's AES did | Fixed |
| 3 | **Alerts had one OK button** | `dialogFormAlert(h, default, "[icon][lines][buttons]")` parses TOS's form_alert string (rom/gem/gui/formalert.zig, native test), up to 3 buttons, the default one thick; `dialogChoice` is form_alert's 1-based return. One icon only (the warning sign) for 1, 2 and 3 | Fixed (icons: open) |
| 4 | **Return did nothing in a program's dialogs** | `Gui.enter` (Return fires the default button) was set only by the desktop. `guiKey(h, cp)` | Fixed |
| 5 | **The host's pointer was the program's problem** | The desktop maps it in one place (`Screen.fromHost`: low res halves x) and drops the page's double-click pulse; `guiSetPointer` took it raw, so a low-res program had to know. `guiHostPointer` | Fixed |
| 6 | **No clipped text** | A window's last column is cut by the scrollbar: `guiTextClip` (pixel clip, the ROM's `textClipped`) | Fixed |
| 7 | **No arrow in the desk** | In the desk no host draws the pointer (GEM_DESK_MODE.md §4); the desktop draws its own, a program had nothing. `guiMouse(h, 0/1)`: graf_mouse M_OFF / M_ON, TOS's ARROW drawn save-under, the desk only | Fixed |
| 8 | **A program could not learn the desktop's resolution** | `deskScreenMode()` (Getrez): the ROM keeps the desktop's screen across the cart swap; 0xFF when no desktop ran. On the board each load is a fresh ROM: it said 0xFF and Notepad opened in medium over the desk (Matt, 9 Nov); the firmware now carries the mode through the glass (`deskSetScreenMode`, table 1.18), and the desktop comes back in it at Quit (`deskReturnMode`) | Fixed |
| 9 | **`guiResize` did not re-bind the plane** | After a program changed resolution the context kept the old base and stride (the desktop re-binds in `deskSetScreen`; programs had no way). `guiResize` re-binds now (no program called it before) | Fixed |
| 10 | **fsel_input's initial name** | `fileSelSetName` (Save As shows the current name) | Fixed |
| 11 | **Arrows did not repeat; the desktop's still do not** | A program's arrows repeat after 18 frames, every 3 (appwin.zig). The desktop's windows are unchanged (byte-identical rule) | Fixed for programs |
| 12 | **Save-under memory** | A wasm module that imports its memory ships its zero-initialised statics as data: the ROM's buffers for the save-unders (43 KB) would have grown rom.wasm and every card's system.rv32 by that. The program lends them (`guiScratch`, 43 KB, checked to lie in the cart window) | Fixed (a contract: a program must lend it) |
| 13 | **No editable text field, no form_do** | The Find box is the program's own field drawn with the ROM's box/text/button | Open (worked around) |
| 14 | **The ITEM SELECTOR has no folders** | Board, 9 Nov: on Matt's card (C:\ = MUSIC\ PICTURES\ NET\ ECHO.REQ) the selector was empty. Not a read failure: the list was `C:\*.TXT`'s files only, and the card's C:\ has none (the browser's image has README.TXT, so it showed one). TOS lists a folder's sub-folders whatever the mask. Now a name added with a trailing `\` is a folder (TOS's diamond), a click on it opens it, the list's close box goes to the parent, and the Directory: line is the spec, EDITABLE (click it, type, Return or a click in the list re-reads it). Each answers `relist` (rom.Result 3) with the list emptied; the program reads the spec with `fileSelSpec` (system table 1.18) and adds that folder's names. Notepad lists folders then `*.TXT` (or the typed mask), and opens and saves in the folder the selector was in. 32 names at most, folders included. Drive buttons (A: / C:) still absent | Fixed (folders, path); drives open |
| 15 | **No clipboard (scrp_read / scrp_write)** | The clipboard is Notepad's own (64 KB), lost at Quit | Open |
| 16 | **No 8x16 text through the API** | `guiText` draws the system 8x8; the 8x16 font is a local asset only | Open |
| 17 | **The engine (`deskSetEngine`) is the desktop's** | A program's Gui is the old immediate-mode path; objc_draw and the object trees are not exported. Since `feat/gem5-program-objects` a program's form_alert (S1) and ITEM SELECTOR (S2) are drawn by the engine in the program look (flat, or 3D as the desk's engine) | Partly fixed (alerts, selector; windows and menus still the old path; objc_draw for programs: S4/S5) |
| 18 | **A program's windows redraw their whole chrome for a title change** | No WF_NAME-only redraw: a new title repaints the window (Notepad: when the text becomes modified, and on save) | Open (rare) |
| 19 | **Browser shortcuts** | On the page Control+N/T/W are the browser's (cannot be prevented); Control+S/O/F reach the cart but the browser acts too (no preventDefault for an owning cart). The board's glass has no such issue | Open |
| 20 | **Launching from C:** | A program still runs only off drive A (a .zmd data disk); Install Application / launch from C: is GEM5_PLAN P1.6 | Open (the plan's) |

## Proof

`apps/notepad_fsel_check.mjs` (gate `notepad`, + `--break spec|relist`): the ITEM SELECTOR over a C:
laid out as Matt's card (folders, ECHO.REQ, no .TXT at the root): the folders listed under `*.TXT`, the
Directory: line edited to `*.*`, a folder opened and left, a file in it opened and saved back there.

`apps/notepad_check.mjs` (gate `notepad`, + `--break write|bytes|ctrl`), over the real machine + ROM,
C: a copy of `docs/gemdos-c.img` with the page's KFS for the writes. See its header for the checks. The
central one: after each step (typing, a save, an alert, a menu, 60 lines, a scroll, a size, a paste, in
low, medium and the desk) the screen as drawn incrementally equals a whole repaint, byte for byte.
Native: `notepad/text.zig`, `doc.zig`, `names.zig` (scene_tests), `rom/gem/gui/formalert.zig`,
`saveunder.zig`.

## Board

Not run on the board here. To check: the arrow and the save-under in the desk (the board scans the
plane live: a program's single buffer may tear for a frame where the desktop double-buffers), the speed
(frame_cost estimates below), Control shortcuts from glass, a save to /HD.
