# Parts 1–6 — native SID-Wizard editor port: STATUS

> Last updated: 2026-11-23
> STATE: Parts 1–5 done; Part 6 (pixel-true screens) done — 74 tests green across nine targets.
> Changes remain uncommitted on the working tree.

## Test state (run from prototypes/swz_gemini)
| target | result | what it covers |
|--------|--------|----------------|
| `zig test out/swm_test.zig` | 8/8 | song model, `.SWM` load/save, `toC64`/`fromC64`, 11 tunes byte-exact |
| `zig test out/display_test.zig` | 16/16 | the 25×40 screen, template, pattern cells, panels, overlays |
| `zig test out/keys_test.zig` | 11/11 | cursor/edit state machine, undo, insert/delete, name mode |
| `zig test out/menu_test.zig` | 17/17 | main menu drawing/actions, prompt, kill tune/inst, help |
| `zig test out/filer_test.zig` | 10/10 | file dialog: listing→load, save round-trip, Escape, empty list, author, auto-dir |
| `zig test out/startup_test.zig` | 3/3 | start-up menu state machine, render, description scroll |
| `zig test out/editor_test.zig` | 3/3 | boot→load→3 notes→save→reload, final Screen, player hooks |

**Total: 74 tests green** (+ border_test 2, frame_test 3, startup_test now 4). `zig fmt` clean on every `out/*.zig`.

## Done this session (Part 5 + Part-4 completion)
- [x] `out/editor.zig` (new): `Editor` owning Song + View + menu/filer,
      `init`/`load`/`save`/`key`/`render`/`overlay`, `songForPlayer`
      (`swm.toC64` at $1D00), `playerState` ($10 + 7·channel bunches),
      `syncPlayback` (playadapter row counter), `filerListing`/`filerResult`.
- [x] `out/editor_test.zig` (new): scripted session checks saved bytes,
      reload, the final screen's note glyphs and the player-variable reads.
- [x] `out/filer.zig` (new, Part 4 gap): pure file-dialog state machine
      (windows, typing, selector, extension append, regauth, statuses).
- [x] `out/startup.zig` (new, Part 4 gap): start-up menu state machine and
      text screen (player/tuning/machine/config/description scroll).
- [x] `out/filer_test.zig` (new): the four prompt_4 cases plus typing,
      shift-reverse, author write-back, auto-dir, F1 listing, error status.
- [x] `out/startup_test.zig` (new): render, key cycle/wrap, scroll.
- [x] `keys.zig`: filer routing + `FileRef` effects, menu rows open the
      filer, `filerListing`/`filerResult`; STOP closes the dialog.
- [x] `display.zig`: `View.filer`, `filerRender` text screen.
- [x] NOTES.md §16–§17 appended: filer/start-up details, player-variable
      address table, self-review fixes, ranked **Known gaps**.

## Known gaps (ranked; details in NOTES.md §17)
1. Start-up player selection is informational (fixed 6502 player; no
   `altplayers.inc` code copy / feature-tick grid).
2. File-dialog painting is simplified (KERNAL reader, disk header, block
   counts, overwrite prompt are host-side).
3. `syncPlayback` needs a per-frame host call with the real `playmod`.
4. Instrument/config file contents (`packinst`/`.CFG`) are host-side.
5. Editor palette switching per theme is deferred (menu only).
6. MIDI / multi-SID / emulator-only / exporter builds are out of scope.
7. Start-up menu raster/skew/logo graphics are not in `Screen`.
8. `filer.Name` is PETSCII/ASCII uppercase; host maps it to its filesystem.

## Part-by-part record
### Part 1 — `out/swm.zig` (8/8)
Song model, `.SWM` load/save, C64 workfile image; 11 tunes round-trip
byte-identically on both the file and image paths; deviations D1–D5.

### Part 2 — `out/display.zig` (16/16)
`Screen`/`View`/`render`/`overlayRender`, exact screen codes and colour RAM
for template, patterns, step numbers, mutes, instrument panel, misc row,
orderlist sprites/row26 and the upper-border readouts.

### Part 3 — `out/keys.zig` (11/11)
Full key map (NOTES §12), cursor/edit state machine, note/instrument/FX
entry, insert/delete/copy/paste, octave, funktempo, undo, name mode.

### Part 4 — `out/menu.zig`, `out/filer.zig`, `out/startup.zig`
Main menu (17), file dialog (10), start-up menu (3). Menu rows now drive the
filer end-to-end; the host only supplies listings and bytes.

### Part 5 — `out/editor.zig`
Single-object glue plus the play hooks; scripted session test (3).

## Files
- Library: `out/swm.zig`, `out/display.zig`, `out/keys.zig`, `out/menu.zig`,
  `out/filer.zig`, `out/startup.zig`, `out/editor.zig`.
- Tests: `out/{swm,display,keys,menu,filer,startup,editor}_test.zig`.
- Docs: `out/NOTES.md` (§1–§17), `out/STATUS.md` (this file).
- Dev tools: `out/shot.zig` + `/tmp/swz_shot.py` (PNG screenshots).
- Run from `prototypes/swz_gemini`; `out/tunes -> ../tunes` symlink is
  needed for `@embedFile`.

## Host / ZigMachine integration next
1. Load the 6502 player at $1000, call `Editor.songForPlayer` into emulated
   memory, run initer/playsub, and call `Editor.syncPlayback(mem, playing)`
   once per frame.
2. Map `Effect` to the board: play/stop/fastfwd via the player emulator,
   `need_listing`/`load_file`/`save_file` via the host filesystem,
   `quit`/`menu`/`redraw` as UI events.
3. Paint `Screen` (+ `Overlay` sprites) on the Kestrel, and feed the host's
   key matrix through `Editor.key`.
4. Optional: theme palettes, start-up menu graphics, instrument/config file
   formats, and the MIDI/multi-SID paths listed in NOTES §17.

### Part 6 — screens match the real editor (NOTES §18)
- [x] `editor_charset.bin` dumped from VICE (provenance in §18.1)
- [x] A-Z -> 1..26 conversion removed (menu/display/startup); tests fixed
- [x] `border.zig` (upbordisp/ordldis sprites), `frame.zig` (400x280 picture)
- [x] chTmDisp wired into `render()`; panel colours fixed vs VICE cram
- [x] `shot.zig` + `shot_png.py`: ui_*.png, diffs: editor 643 px (live areas
      only), startup 14620 px, filer 7313 px (simplified Part-4 layouts)
- Left: start-up menu / file dialog full layouts, live scope/play bar/cursor
  sprite, oscilloscope trace, `rastime`/PW/CTF meters need the host's player
  state, menu/help/prompt have no reference screenshot.
