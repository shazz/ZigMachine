# GEM 5.0 plan: taking ZigGEM from TOS 1.00 toward TOS 4 / MultiTOS

Study of 7 Nov 2026 (branch `study/gem5-tos4x`), for Matt's ask: "run an analysis of TOS and MultiTOS
sources (https://github.com/mikrosk/tos4x) to see how we can improve our GEM 5.0, and propose a plan to
make our GEM more 5.0 than 1.0". The file map and deeper notes are in
[prototypes/tos4x_re/ANALYSIS.md](../prototypes/tos4x_re/ANALYSIS.md).

## Summary

- **Licence.** tos4x has no licence: DRI 1985 + Atari 1989-93 "All Rights Reserved" source from the
  dev-docs.org archives. It is reference only. We describe mechanisms in our own words and write our own
  code, art and text; nothing from it (code, RSC, icon bitmaps, .INF text) enters the tree. The clone lives
  in `prototypes/tos4x_re/src/`, excluded from the repo.
- **What it holds.** The TOS 2.07-4.05 AES and NEWDESK desktop (`aes/`), the MultiTOS AES 4.1 and desktop
  (`multitos/`), GEMDOS, BIOS and the VDI. MiNT (the process kernel) and XaAES are not there: they are in
  freemint. Even the MultiTOS desktop is 8.3 (no long-filename calls anywhere), and every Atari AES drags
  windows as an outline, as ours does.
- **Where we are.** ZigGEM is a faithful TOS 1.00 desktop: Desk/File/View/Options, 7 windows with outline
  move/size, live sliders and the info line, icon/text views, 4 sorts, Show Info, New Folder, rename, trash, a DESKTOP.INF
  with `#E #W #M #T`. Underneath it is flatter than TOS 1 in one way: every file operation edits an
  in-memory directory only ("the disk is read-only", `rom/gem/desktop/deskops.zig`), the folder COPY box is
  cosmetic (`desksel.zig:150`), and only A: launches (`desktop.zig:171`). KOS GEMDOS has written real files
  to C: since 6 Nov (`rom/kos/gemdos_write.zig`, `gemdos_wops.zig`, system table 1.10), so the biggest gap
  is now cheap to close.
- **The plan.** Phase 1 makes the desktop *work* like TOS 2.06 (real copy/move/delete on C: with the
  progress box, desktop file and program icons, keyboard shortcuts, Search, documents that open their
  program). Phase 2 gives it the TOS 4 *look* (3D objects, colour icons, iconify, bottoming, popups and
  submenus, an 8x16 font). Phase 3 is multitasking-lite in TOS 1's own cooperative style: desk accessories
  beside the desktop, the first being a control panel and a music jukebox on BARD. Real MultiTOS (MiNT
  processes, several carts at once) is skipped on purpose.

Top five, by value to Matt per day of work:
1. **Real file operations on C:** with the TOS copy box (count, then count down live). (P1.1)
2. **Documents open their program** (Install Application): `.MP3` to MP3 PLAYER, `.PI1/.NEO/.PC1` to
   GrafX2 or a viewer, `.KT` to klystrack, `.SND/.SNDH` to a jukebox. (P1.6)
3. **TOS 4 3D look** as a Desktop Configuration choice, flat TOS 1 kept byte-identical. (P2.1)
4. **Colour icons** (our own art, 16 colours) for drives, trash, programs, documents. (P2.2)
5. **Desk accessories**, starting with the control panel and a background SNDH/MP3 jukebox. (P3.1-3.2)

## Constraints that set the costs

- **ROM / RAM.** `system.rv32` on the staged cards is ~465 KB (prototypes/gem_fix_card/KESTREL/, 6 Nov).
  A Zig cart that links the GUI library carries GEM in its 2 MiB cart RAM window (GEM was ~525 KB of
  statics in Sept; `hwRamFree()` measures what is left). Every phase-2 asset (icons, font) is paid twice:
  in the ROM and in a cart that links it. Budget: colour icons <= 24 KB, a font <= 4 KB.
- **No FPU, 100 MHz rv32.** Nothing here needs float; the desktop already redraws only what changed
  (`deskdirty.zig`). A 3D look adds two lines per box: noise.
- **Single-tasking carts.** A cart replaces the desktop in the same memory (gem_desktop.zig request 3,
  back with request 4). There is no command tail: a launch names the program only.
- **Writes.** C: only, a whole file per host request (32 KB buffer, temp name then rename); A: is EWRPRO.
- **No trap API.** The GUI is a linked Zig library (gui/*.zig), not `trap #2`; C ports draw through
  kestrel_sdl2. AES messages, `evnt_multi` and `form_do` are worth something only if Zig carts adopt them.
- **Effort unit:** agent-days (d), including the proof harness. A new harness gets its
  `gate <tag> node apps/<name>.mjs` line in build.sh in the same commit (CLAUDE.md).

## Gap table

TOS 2.06/3.06 columns are "NEWDESK as in tos4x's TOS 2.07-4.0x lineage": the tree has no 1.0x/3.06 copy to
diff against (ANALYSIS.md). Fit: value to Matt / cost on our architecture.

| Feature | TOS 1.00 = ZigGEM today | TOS 2.06 / 3.06 | TOS 4.04 | MultiTOS | tos4x evidence | Fit |
|---|---|---|---|---|---|---|
| Copy/move/delete files | Delete + rename edit memory only; COPY box cosmetic | Real, two-pass progress box, name-conflict box, Control-drag = move, confirms | same | same, + drag to apps | `aes/deskact.c:150-230`, `deskdir.c` dofiles | **High / low** (writes exist) |
| Files and programs on the desktop | Drives + trash only | Any file/folder as a desktop icon (`#X #V`), printer icon | same | same | `aes/deskinf.c:160-205`, `deskins.c:405` | High / low |
| Install Application, document types | No; only A: launches | Per app: doc extension, auto-boot, F-key, params, default dir | same | + shel_write parallel launch | `aes/deskins.c:136`, `deskinf.c:271-290` | **High / medium** (host ABI: command tail) |
| Keyboard shortcuts | None (keys feed rename only) | Fixed + user-set menu keys (`#K`), function keys to apps | same | 31 items | `aes/deskinf.c:389`, `defines.h:150` | High / low |
| Search / Find | No | Wildcard, recursive, opens + selects, Next | same | same | `aes/desksear.c` | Medium / low |
| Show Info | Name, kind, size; disk counts | + date, time, read-only toggle, Skip through a multi-selection, folder counts | same | same | rsc `ADFILEIN`, `FOLDINFO` | Medium / low |
| Select All, Bottom to Top | No | Yes | Yes | Yes | `deskmenu.c`, `deskusa.dfn` | Medium / tiny |
| View options | Icons/text, 4 sorts | + no sort, size-to-fit, text columns, file mask | same | + per-window font | `deskusa.dfn` NOSORT, SIZEFIT, SCOLTYPE | Low-medium / low |
| Preferences | Background RGB only | Confirms, double-click speed, desk/window pattern + colour (`#Q`), Set Video | same | same | `aes/deskpref.c`, `deskinf.c:487-540` | Medium / low |
| NEWDESK.INF | `#E #W #M #T`, in memory on A: | + `#Q #K #Z #X #V #C #G #F #P #N #D #I #a-#d` | same | same | `aes/deskinf.c:380-920` | High / low (needed by the rows above) |
| Windows | 7, outline move/size, live sliders, info line ("N bytes used in M items", `deskwin.zig:154`) | as TOS 1 (window count not in tos4x's 2.07 tree) | 8 (`MAXWIN 8`) | + iconify, bottom, toolbar, two-line sizer | `aes/window.h:9`, `multitos/gemwmlib.c:547,1214`, `gemctrl.c:334` | Medium / medium |
| Real-time move/resize | Outline (as Atari) | Outline | Outline | Outline | `aes/gemctrl.c:257`, `multitos/gemctrl.c:343` | Skip: not Atari, costs blits on the board |
| 3D objects | Flat; `bevel()` exists unused (`core.zig:52`) | No | IS3DOBJ/IS3DACT, 3D gadgets, objc_sysvar | same | `aes/obdefs.h:145-181`, `gemwmlib.c:800-970` | **High / low** |
| Colour icons | 1 bpp mono | No | CICON, best plane match, selected image | same | `aes/gemoblib.c:1436-1900` | **High / medium** (our art, palette slots) |
| Popups, submenus | No | No | menu_popup, menu_attach, delays | + scrolling menus | `aes/mn_popup.c`, `mn_submn.c` | Medium / medium (carts gain most) |
| Fonts / VDI | 8x8 + 6x6 | + 8x16 in high res | + 16x32, styles | GDOS fonts per window | `pixvdi/sources/font*.c`, `text.c` | Low-medium / low (8x16 only) |
| AES messages / event API | None (immediate mode) | TOS 1 set | + WM_NEWTOP etc. | + WM_ICONIFY, AP_TERM, AP_DRAGNDROP | `multitos/message.h` | Low / high (no GEM-style carts) |
| Desk accessories | No (KOS v3 idea) | Up to 6 from disk, cooperative | same | Parallel processes | `aes/struct88.h:49-52` | **High / medium** (RAM reservation) |
| Several apps at once, app switching | No | No | No | Shared menu bar, Desk menu lists apps | `multitos/gemmnlib.c:150,350` | Skip (needs MiNT-class RAM split) |
| MiNT processes, pipes, signals | No | No | No | Yes (freemint) | not in tos4x | Skip |
| Long filenames | 8.3 | 8.3 | 8.3 | 8.3 in the desktop | no Dpathconf/Dreaddir in tos4x | Skip (Atari's desktop never had it) |
| Format, printer, RS232 | Format greyed | Yes | Yes | Yes | `deskusa.dfn` FORMITEM, PRINTFIL | Skip (A: read-only, no printer) |

## Phase 1: TOS 2.06 behaviour (quick wins with visible effect), ~14 d

| # | Item | What | Effort | The test that proves it |
|---|---|---|---|---|
| P1.1 | Real file operations on C: | **Built 9 Nov (`feat/gem-fileops`, docs/GEM_FILEOPS.md, system table 1.18: `deskFileOp`): all of what follows, in the old path (low, medium, desk) and the engine; a move on C: is one Frename per item (the source never at risk), a move from drive A copies, checks the copy, deletes the source and keeps it when that fails. Proof `gem_fileops_check` (+3 mutants).** Delete (trash), rename, New Folder, copy (drag to a folder or window), move (Control-drag) through KOS GEMDOS (Fcreate/Fwrite/Fdelete/Frename/Dcreate/Ddelete). TOS's two-pass box: count folders/files/bytes, then count down per file; a name-conflict box (rename / skip / stop); copies onto A: refused with TOS's write-protect alert. A: keeps today's in-memory behaviour | 3 d | New `apps/gem_fileops_check.mjs` over a C: image: drag-copy a folder, Control-drag move, rename, delete; the image re-read through KFS has the exact bytes and fsck is clean (as `test_kos_cfs.py`). Breaks: a full disk mid-copy shows the alert and leaves no partial file; a move whose delete fails keeps the source. Gate line added |
| P1.2 | DESKTOP.INF on C: | **First half done 9 Nov (`fix/gem5-desk-bugs`, gem_desk_bugs_check `inf`): the existing records written to and read from `C:\DESKTOP.INF`, at boot and on the return from a program, C:\ reopened.** Save Desktop writes `C:\DESKTOP.INF` (falls back to A:'s memory copy when there is no C:), read at boot; new records for the rows below (`#K #X #V #Q #G/#F/#P` + doc type), unknown records kept verbatim so a later version doesn't lose them | 1 d | `deskinf` native test: parse/write round trip of every record, unknown-record pass-through; `kos_desk_check.mjs`: save, reboot the page, same windows/icons |
| P1.3 | Keyboard shortcuts | Default TOS-like table (Control-letter shown right-aligned in the menus), user-editable table saved as `#K`; Select All; Bottom to Top (cycle windows); Escape refreshes the top window; arrows/Return move and open the selection | 1.5 d | `kos_desk_check.mjs` drives keys only: open C:, select all, cycle windows, close; a remapped key survives a save/reload |
| P1.4 | Files and programs on the desktop | Drag a file, folder or program out of a window onto the desktop: it becomes an icon (`#X`/`#V`), opens or launches on double-click, Remove Desktop Icon; drag a file onto a program icon = open it with that program (needs P1.6) | 2 d | Harness: drag out, save, reload, the icon is at the same cell and opens the same folder; scene_hash pin of the desktop with two such icons |
| P1.5 | Show Info + Search | Show Info: date/time, read-only toggle (Fattrib set), Skip through a multi-selection, folder counts. File > Search: wildcard, recursive on a drive, opens the hit's folder with the file selected, Next | 2 d | Harness: Show Info toggles read-only and the image's attribute byte changes; Search `*.PI1` on C: finds the 3 planted files in order; break: no match shows the "not found" alert |
| P1.6 | Launch from C: + Install Application | Host request "launch cart X with tail Y" (a new system-table call, so a table bump); a cart reads its tail (GEMDOS `Pexec`-style basepage command line through the KOS layer). Options > Install Application: program, document extension, auto-boot (`#Z`), F-key. Defaults shipped: `.MP3` MP3 PLAYER, `.KT` klystrack, `.PI1/.NEO/.PC1` GrafX2, `.SND` a jukebox | 3.5 d | Harness: double-click `C:\MUSIC\X.MP3` launches MP3 PLAYER which reports it is playing X.MP3 (existing `mp3_player_check` path); the old table still boots every shelf cart (`card_abi_check`); break: an unknown extension shows TOS's "no application installed" alert |
| P1.7 | Preferences | Confirm copies / deletes / overwrites, double-click speed, desk and window fill pattern + colour (`#Q`), Set Video (low/medium) in the dialog | 1 d | Native test of the `#E`/`#Q` bits; harness: confirms off means a delete has no box |

## Phase 2: the TOS 4 look and windows, ~13 d (+3 d optional P2.6)

| # | Item | What | Effort | Test |
|---|---|---|---|---|
| P2.1 | 3D objects | A look switch in Desktop Configuration: TOS 1 flat (today, default until Matt decides) or TOS 4 3D. 3D: buttons are activators (pushed in when pressed), check/radio are indicators (colour change), a 2 px grow on 3D boxes, 3D window gadgets and slider elevators, one system face colour. In the GUI library, so carts get it too | 3 d | scene_hash: the flat look is byte-identical to main on every desktop scenario (pin); new 3D fingerprints for desktop, a dialog, a window; break: forcing a 0 px grow changes the 3D hash |
| P2.2 | Colour icons | 16-colour 32x32 icons with a selected image and a mono fallback in low res, best match by depth (TOS 4's rule); our own art (pixel-drawn here, nothing ripped); reserved palette slots next to the GEM 8 | 3 d (half of it art) | Size check: the icon set <= 24 KB in system.rv32; scene_hash fingerprints; break: a missing colour image falls back to mono, not garbage |
| P2.3 | Window features | 8 windows, bottoming (click the top window's title bar), iconify (the "smaller" gadget, a 72x72 box with the drive or folder icon, double-click restores; iconified windows saved in DESKTOP.INF) | 3 d | Harness: iconify, save, reload, restore = the same rectangle; bottom a window and the next is topped; `window.zig` native tests for the order list |
| P2.4 | Popups and submenus | `gui/menu.zig` gains a popup at (x,y), a submenu arrow with an open delay, scrolling for long lists. Desktop uses: sort popup in text view, a New submenu (folder / text file). Carts use them through the library | 2.5 d | Native tests for the hit/keyboard logic; harness opens a submenu, chooses an item; scene_hash pin |
| P2.5 | Text and fonts | 8x16 system font in medium res (our own glyphs or a free font, not TOS's), algorithmic bold/light; text view column choice, no-sort, size-to-fit | 1.5 d | Font size check (<= 4 KB); scene_hash of the text view at 640 |
| P2.6 | Event/message API for Zig carts (optional) | A thin layer: a message queue (WM_TOPPED/CLOSED/FULLED/ARROWED/SIZED/MOVED, MN_SELECTED) over the immediate-mode GUI, `form_do`-style dialog runner, `form_alert`. Only if a Zig cart wants windows of its own | 3 d | One sample cart driven by the harness through 5 messages; skipped if no cart wants it |

## Phase 3: multitasking-lite and accessories, ~12 d

TOS 1's accessories were cooperative: the AES ran them inside its own event wait. That is the honest model
for a single CPU with one cart window, and it needs no MiNT.

| # | Item | What | Effort | Test |
|---|---|---|---|---|
| P3.1 | Desk accessories | Up to 6 small modules loaded at boot from `C:\` or the boot disk (`*.ACC`), into a reserved region of the desktop's RAM; each has init / open / event / draw entry points the desktop calls each frame; listed under Desk; draws in a window of the desktop's window manager. ACCs live only while the desktop runs (carts are not GEM apps here). Dependency: the RAM reservation and the module ABI (its own design doc, KOS v3 row) | 5 d | Harness: an ACC opens from Desk, its window is moved and closed, the desktop's hash is unchanged after close; break: an ACC that overruns its region is refused at load, not run |
| P3.2 | Control panel + jukebox ACCs | CONTROL.ACC: palette, double-click speed, key click, the 3D switch. JUKEBOX.ACC: plays SNDH (68000 player) or MP3 on BARD while the user browses; the music survives opening windows (BARD is its own CPU) | 3 d | `sysinfo_check`-style audio proof: the jukebox's PCM stays bit-exact while the harness drags windows |
| P3.3 | Ask a cart to quit (AP_TERM-lite) | The OSD / desktop can ask the running cart to quit cleanly (a flag the cart polls; carts that ignore it are killed as today) | 1 d | A sample cart quits on the flag and the desktop returns with its windows restored |
| P3.4 | Resume the desktop as it was | When a cart quits, the desktop comes back with its windows, scroll positions and selection (state saved before launch, as MultiTOS's single-task swap) | 2 d | Harness: open C:\MUSIC, launch, quit: same hash as before the launch |
| P3.5 | Drag a document onto a program | Drop a file on a program icon (window or desktop) = launch with it (P1.6 tail); TOS 4's AP_DRAGNDROP without the pipe | 1 d | Harness: drop X.KT on klystrack's icon, klystrack opens X.KT |

## What we skip, and why

- **MiNT processes, preemptive multitasking, memory protection, several carts at once, the shared menu
  bar.** Needs the cart RAM window split per process and a scheduler on ZIGGY; a cart already owns the
  machine and the board's frame budget. P3.4 gives the visible part (come back to where you were).
- **Long filenames.** Atari's own desktops never had them (no LFN calls in tos4x); FAT LFN would also touch
  KOS, KFS and glass. Revisit only if C: from SD folders makes 8.3 names painful.
- **Real-time window move/resize.** Atari dragged outlines; a live move costs full-window blits per frame on
  the board for no ST authenticity.
- **AES trap compatibility for 68000 GEM programs, RSC loading, GDOS/Speedo fonts.** No GEM program runs on
  ZIGGY; an RSC loader only matters with P2.6.
- **Format, printer, RS232, Print Screen, Install Devices.** A: is read-only and there is no printer.
- **TT/Falcon video modes in Set Video.** Our modes are low and medium; 640x400 is its own study.

## Order and dependencies

P1.2 (INF) first, since P1.3-P1.7 save into it; P1.1 next (the headline). P1.6 needs a system-table bump:
batch it with the next table change. P2.1 and P2.2 are independent of phase 1 and can run in parallel.
P3.1 needs its design doc (KOS v3 desk accessories row) and a RAM measure with `hwRamFree()` first.
Board check per phase: the desktop's frame cost (`apps/frame_cost.mjs`) must stay under today's GEM GUI
figure plus 0.1 Mc, and `system.rv32` growth is reported in each commit.
