# GEMTEST: every GEM 5 component on one disk

Status: **built on `feat/gem5-gemtest`** (9 Nov 2026). Matt: "did you create a GEM test cart to show all
the GEM 5.0 components? so I can see the bugs". Cart `gemtest` (index 128), `apps/zig/scenes/gemtest.zig`
+ `gemtest/`; proof `apps/gemtest_check.mjs` (gate `gemtest`); shots `apps/gemtest_shots.mjs`.

A GEM program as [NOTEPAD](NOTEPAD.md) is: a data disk (`demo-gemtest.zmd`) whose `BOOT.WSM` the desktop
runs, in the desktop's resolution; ^Q (or Test > Quit) goes back. It uses ONLY the program API
(`rom/sdk/rom.zig` + `rom/sdk/aes.zig`). What the API lacks is shown in the window as a grey line
"not in the API yet: ..." instead of being faked by reaching into the ROM: those lines are findings.

## The menu bar

| Title | Items |
|---|---|
| Desk | About GEMTEST... (form_alert) |
| Test | the eight areas, each with its ^key (W E D A F T I R); Close windows ^K; Quit ^Q |
| Menus | the menu test: a plain item, a disabled one, separators, two checked items that toggle (menu_icheck), Shortcut ^L, a disabled ^U (must do nothing) |
| Alerts | form_alert with each icon (0 none, 1 note, 2 wait, 3 stop) and 1, 2, 3 buttons; Malformed alert (must open nothing): the Alerts window shows the answer (G18) |
| Mode | Low, Medium, Desk (the current one checked; Desk greyed where the machine has no desk mode). Keys 1 2 3 do the same |

## The areas (one shown at a time: the API has 7 windows)

| Area | Window(s) | What it checks |
|---|---|---|
| Windows (^W) | GADGETS, OVERLAP A, OVERLAP B, LARGER THAN THE SCREEN | every gadget (closer, title/mover, fuller, info line, sizer, both sliders with arrows and tracks); a numbered grid to scroll both ways; overlapping windows, a click tops one; each window shows its stack position and how many moves, sizes, tops and scrolls it got; the last is larger than the screen. Any change of the stack repaints every window back to front |
| Menus (^E) | MENUS | what the Menus title did: the two checks, the last pick, picks and shortcuts counted |
| Dialogs (^D) | DIALOGS (OBJECTS) | the ROM's buttons (default border 3: Return fires it; exit 2; plain 1); a radio group, two check boxes, an editable field (template `__/__/__`, digits only, a caret), boxes with insets 1 2 3, an 11-stop slider: these four built by the program from the ROM's button, frame and fill |
| Alerts (^A) | ALERTS (FORM_ALERT) | a button per icon x buttons; the last answer (form_alert's 1-based return); the malformed alert's answer (nothing opened: right) |
| File selector (^F) | FILE SELECTOR (FSEL_INPUT) | the ITEM SELECTOR on `A:\*.*`, `C:\*.*`, `C:\*.TXT`, its list from Fsfirst / Fsnext (KOS GEMDOS); shows how many names, Fsfirst's code, the button and the name returned |
| Text and fonts (^T) | TEXT AND FONTS | the system font's cell (guiCell), a 200-column ruler (horizontal scroll), 100 lines (vertical scroll) |
| Icons (^I) | ICONS | none: the API cannot draw an icon (the shots tool shoots the desktop's instead) |
| Screen modes (^R) | SCREEN MODES | Getrez at launch (deskScreenMode), the mode now, whether the desk mode exists; Low / Medium / Desk buttons |

## Not in the API yet (the findings)

Each is a grey line in its window.

1. **Windows**: no WM_REDRAW rectangle list and no wind_get WF_FIRSTXYWH / WF_NEXTXYWH, and no stack
   query beyond WF_TOP: a program keeps its own order from EV_TOPPED and repaints every window back to
   front after any change, unclipped.
2. **Dialogs**: no disabled button state; no radio buttons (RBUTTON / objc_change); no check boxes; no
   editable text (G_FTEXT, form_do, objc_edit); no slider object; no popup menus (menu_popup); no 3D
   (TOS 4) look for a program's objects (its Gui is TOS 1's flat path: the engine is the desktop's).
3. **Menus**: the ^key is part of the label (no shortcut field, menu_keys); no submenus; no
   menu_tnormal.
4. **Alerts**: no custom icons (a program's own art), no form_error. Since `feat/gem5-program-objects`
   (S1, G19) a program's form_alert is an object tree drawn by the GEM 5 engine: TOS 4's layout, the
   icons NOTE / QUESTION / STOP (the asset set's, else our own TOS 1-style drawings in
   rom/gem/gui/alert_art.zig), the flat look or TOS 4's 3D rules (gui/proglook.zig).
5. **File selector**: no path: the selector has no drive or folder of its own, the program lists the
   names and the Directory line is only the mask (fsel_exinput).
6. **Text**: one size (no vst_height), no 8x16 system font through the API, no styles (vst_effects),
   no other fonts (vst_font, GDOS).
7. **Icons**: no icon call (G_ICON, objc_draw) and no access to the desktop's icon table.
8. **Screen modes**: no Setscreen for a program (it switches its own plane).
9. **The look**: a ROM built with Matt's TOS 4 set (`-Dgem_assets`, `-Dgem_trees`, `-Dgem_engine=true`)
   draws every GEMTEST component byte for byte as the TOS 1.0 ROM does (the shots, 9 Nov: 56 of 57
   PNGs identical; only GEM's own desktop in the desk mode differs, by its drive icon, the same with
   the engine's 3D look asked for explicitly, `ZM_ENGINE=2`). A program's windows, menus and ITEM
   SELECTOR do not take the set at all; its ALERTS do since S1 (the set's NOTE / QUES / STOP images,
   3D when the desk's engine is: `-Dgem_engine=true` with a set, or deskSetEngine(2)).

## The known board bugs it shows

- The ITEM SELECTOR lists nothing on C: (File selector area: `C:\*.*` shows the count, and Fsfirst's code).
- A click on the selector's path / wildcard line does nothing (finding 5), and the selector does not use
  the TOS 4 look (compare `fsel_c` with the reference in the shots).
- The desktop's icons in low res differ from the desk mode's (the shots' `desktop` row).
- A program launched from the desk mode opens in medium (Screen modes area: Getrez and the mode now;
  fixed on `fix/board-prog-deskmode`, not merged).

## Component ids (gemtestShow, for the shots)

`gemtestShow(id)` (a cart export, GEMTEST's only) opens a component at the next frame: 1..8 the areas
(Windows, Menus, Dialogs, Alerts, File selector, Text, Icons, Screen modes); 10..21 form_alert icon
(id-10)/3 with (id-10)%3+1 buttons over the Alerts area; 22 the malformed string; 30..32 the ITEM
SELECTOR on `A:\*.*`, `C:\*.*`, `C:\*.TXT` over the File selector area.

## Shots

`node apps/gemtest_shots.mjs <outdir> [--assets <dir>]` writes each component (and the menu drop-downs,
and GEM's own desktop with A:\ open) in low, medium and the desk: `<component>_<mode>.png` at 1:1
framebuffer pixels, `_2x.png` for low and medium as the screen shows them (640x400), and `index.html`, a
contact sheet. `--assets prototypes/gem_reconstructed/gem_assets` (Matt's LOCAL TOS 4 page) puts that
mode's reference (st_low / st_medium / st_high) under each shot. `ZM_ROM=<rom.wasm>` runs another ROM (a
`-Dgem_assets` build into a scratch prefix). Shots made with Matt's set are local only: write them under
`prototypes/` (git-ignored), never commit them.

## Proof

`apps/gemtest_check.mjs` (gate `gemtest`, + `--break ctrl|click`): see its header. Each area drawn,
distinct, deterministic over two runs, an idle frame painting nothing and the incremental screen equal to
a whole repaint, in the three modes; a click on each kind of control does what it should.

`apps/gemtest_alert_check.mjs` (gate `gemtest`, + `--break icon`): a program's form_alert on the engine,
flat and 3D, in the three modes: four icons four alerts, icons 1-3 inked in the icon's box, TOS 4's
layout (the second button where the layout puts it answers 2), Return the default, an alert left up
redraws the same screen, Alerts > Malformed alert opens nothing and the Alerts window says so.
