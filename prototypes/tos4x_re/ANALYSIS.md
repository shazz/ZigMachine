# tos4x: what is in it, and where each GEM 2.x-5.0 mechanism lives

Study notes behind [docs/GEM5_PLAN.md](../../docs/GEM5_PLAN.md). Source: https://github.com/mikrosk/tos4x,
cloned `--depth 1` on 2026-11-07 (master 4bad523b) into `prototypes/tos4x_re/src/`. That folder is listed in
the repo's `info/exclude` and is never committed: re-clone it to follow the paths below.

## Licence: reference only

There is no licence file and no grant of any kind. Every source file carries
"Copyright (C) 1985 Digital Research Inc." and/or "Copyright 1989-1993 Atari Corp. All Rights Reserved"
(~50 DRI headers, ~80 Atari headers in `aes/` + `multitos/`; `docs/multitos/readme.doc` even says
"CONFIDENTIAL - For your eyes only"). The README says the tree was assembled from the archives on
docs.dev-docs.org; the TOS 2.07 parts credit Thorsten Otto's tos3x reconstruction (same status).
This is proprietary source that leaked. It is NOT GPL (Caldera's 1999 GPL release covered PC GEM, not
Atari's TOS code).

Rule for us: nothing is copied. No code, no RSC trees, no icon bitmaps, no `.inf` or string text. We read it
to learn the mechanism and the user-visible behaviour, and write ours in our own words and our own code.

## What the tree holds

| Dir | What |
|---|---|
| `aes/` | Single-TOS AES 3.x/4.x + the NEWDESK desktop (TOS 2.06 lineage to 4.04/4.05), resources in 6 languages (`desk*.rsc`, `gem*.rsc`) |
| `multitos/` | MultiTOS AES 4.1 (GEM.SYS 1.00-1.09) + the MultiTOS desktop (DESK.PRG), resources |
| `gemdos/` | GEMDOS (fs*.c, mem/pool, Pexec in fsproc.c) |
| `bios/` | Falcon/Sparrow BIOS, XBIOS, DSP and sound |
| `pixvdi/sources/` | The VDI (blit/no-blit, text, fonts 6x6, 8x8, 8x16, 16x32, true colour) |
| `docs/` | Atari's dev notes: `docs/multitos/iconify.doc`, `changes`, `bugs.lst`; `docs/aes/release.doc`, `fix.doc` |
| `build/` | Hatari-driven byte-exact build harness (TOS 2.07, 4.00-4.05, 4.92, GEM.SYS) |

`aes/*.c` + `multitos/*.c` = 93,700 lines of C.

What is NOT in it:
- **No MiNT kernel.** `multitos/` is the AES and desktop only; processes, background Pexec, signals,
  pipes and the filesystems are MiNT's, in https://github.com/freemint/freemint (not cloned). The AES
  talks to it through `multitos/mintbind.h` / `aesmint.h`.
- **No XaAES** (also freemint, `xaaes/`), no MagiC, no N.AES.
- **No TOS 1.0x or 3.06 tree.** The TOS 1 to 2.x+ split below is "what the NEWDESK desktop has that TOS 1.00
  (our reference) does not"; dates come from file header comments (e.g. `cjg 07/07/92`), not from a diff.
- `multitos/gemtcpip.c` is AES inter-process message plumbing, not TCP/IP.

## File map by feature

### Desktop (NEWDESK; `aes/desk*.c`, the MultiTOS copy in `multitos/desk*.c`)

| Feature | Where | Mechanism (our words) |
|---|---|---|
| Menu tree | `aes/deskusa.dfn` (object names), `aes/deskmenu.c` (1341 l.) | File: Open, Show Info, Search, Delete, New Folder, Close, Close Window, Bottom to Top (cycle windows), Select All, Set File Mask, Format. View: icons/text, sort name/date/size/type/none, size-to-fit, which text columns show. Options: Install Icon, Install Application, Install Devices, Remove Desktop Icon, Desktop Configuration, Set Preferences, Set Video, Read .INF, Save Desktop, Print Screen |
| Keyboard menu shortcuts | `aes/deskinf.c:389` (`#K`); `MAXMENU 29` `aes/defines.h:150` (31 in `multitos/deskdefi.h:80`); editor dialog `MNMENU`/`MKKEYS` | Every menu item can be bound to one key; the table is saved in NEWDESK.INF as a list of key codes |
| Files/folders on the desktop | `aes/deskinf.c:160-205` `inf_xdesk` (`#X` file, `#V` folder, `#O` printer, `#C` cartridge, `#M` drive, `#T` trash); `aes/deskins.c:405 ins_icons` | Any file, folder or program dragged onto the desktop becomes an icon there, saved with its path and position |
| Install Application | `aes/deskins.c:136 ins_app`, dialog `MNINSAPP` | Per program: a document extension (double-clicking `*.EXT` launches it with the document as the command tail), boot status (auto-run, `#Z`), TOS/TTP/GEM type, default dir (app's or top window's), parameter = full path or name only, a function key F1-F20 |
| File types | `aes/deskinf.c:271-290`: `#G` GEM app, `#Y` GEM app taking params, `#F` TOS, `#P` TTP, `#D` folder, `#N` text, `#I` icon | Pattern to type + icon index (+ document extension for apps) |
| Window icons per pattern | `aes/deskins.c:642 ins_wicon` | Bind an icon (from DESKICON.RSC) to a file pattern |
| Search / Find | `aes/desksear.c` (420 l.) `sea_file:98`, `rec_sea:190` | Wildcard search down a drive's folder tree; each hit opens its folder's window with the file selected; "Next" continues |
| Copy/move/delete with progress | `aes/deskact.c:150-230` (`CPBOX`), `dofiles` in `aes/deskdir.c` | Two passes: a counting pass (`OP_COUNT`: folders, files, bytes) fills the box, then the operation counts them down live; name conflict box `SAMENAME` (rename/skip/quit); Control-drag = move; copy/delete/overwrite confirm flags saved in `#E` |
| Show Info | rsc `ADFILEIN`/`ADDISKIN`/`FOLDINFO`, code in `aes/deskinf.c` | File: name editable, size, date, time, read-only/read-write toggle, Skip to the next of a multi-selection. Folder: counts. Disk: label, folders, files, used, free |
| Show/print text | `aes/deskshow.c` (375 l.) | Built-in pager for `#N` files |
| Preferences | `aes/deskpref.c` (233 l.), `#E`, `#Q` | Confirms; double-click speed; desk + window pattern and colour per resolution (`#Q`, 16 colours x 8 patterns) |
| Set Video | rsc `MNSETVID`, `SVSTLOW..SVTTOK` | Resolution / colour-depth choice, saved in `#E` |
| NEWDESK.INF | `aes/deskinf.c:380-540` read, `:630-920` write; default `aes/deskusa.inf` | Text records: `#a #b #c #d` (RS232, printer, palette), `#E` env bits (view, sort, confirms, res, font), `#W` per window (8 of them) x y w h + path, `#Q` colours, `#K` keys, `#Z` autoboot, the icon and type records above, strings ending `@` |
| Windows | `aes/deskwin.c`, `multitos/deskwin.c` (2098 l.) | 8 desktop windows (`MAXWIN 8`, `aes/window.h:9`); MultiTOS adds a per-window font (`multitos/deskpref.c`) |
| Colour icons | `aes/gemoblib.c:1436-1900` `match_planes`, `find_eq_or_less`, `gr_cicon`, `fixup_cicon`, `trans_cicon`; `G_CICON 33` `aes/mobdefs.h:59` | An icon holds its mono bitmap plus a list of colour images by plane count; the AES picks the best one at or under the screen's planes, has a separate "selected" image, falls back to mono. MultiTOS's readme: the desktop built its colour icon objects by hand because the tools could not make colour RSCs |

### AES 4.x (`aes/gem*.c`, `aes/mn_*.c`; MultiTOS superset in `multitos/`)

| Feature | Where | Mechanism |
|---|---|---|
| 3D objects | `aes/obdefs.h:145-181`: `IS3DOBJ 0x200`, `IS3DACT 0x400`, `ADJ3DPIX 2`; `draw_hi` in `aes/gemoblib.c:311`; `ob_sysvar` `:138` (`OBJC_SYSVAR 48`) | Two flag bits: indicator (radio/check, changes colour when selected) vs activator (button, looks pushed in). A 3D object grows 2 px each side; light/dark edges; a system face colour apps can query/set |
| 3D window gadgets | `aes/gemwmlib.c:800-970` | Sliders and arrows drawn 3D, the elevator inset by `ADJ3DPIX` |
| Popup menus | `aes/mn_popup.c:122 mn_popup` (`MN_POPUP 36`) | Any menu tree shown at x,y, scrolls if long, returns the item |
| Submenus | `aes/mn_submn.c` (885 l.): `mn_attach:282`, `mn_istart:144`, `mn_settings:825`; flag `SUBMENU 0x800` | An item with a right arrow opens a child menu after a delay; settings: open delay, drag delay, scroll height |
| Scrolling drop-downs | `multitos/changes` (6/14/93) | Long menus scroll |
| Messages | `aes/crysbind.h:171-185`, `multitos/message.h:12-50` | TOS 1's WM_REDRAW..WM_ARROWED, plus WM_BOTTOMED 33, WM_ICONIFY/UNICONIFY/ICONIFYALL 34-36, AP_TERM 50, AP_DRAGNDROP 63, SHUT_COMPLETED 60, RESCH_COMPLETED 61, CH_EXIT 90 |
| Bottom a window | `multitos/gemctrl.c:334, 469` | Click on the top window's mover (or shift-click) sends WM_BOTTOMED: the window goes behind the others |
| Iconify | `docs/multitos/iconify.doc`; `multitos/gemwmlib.c:547` (SMALLER gadget), `:1214` (WF_ICONIFY/UNICONIFY); `multitos/deskwin.h:165-171` | A "smaller" gadget; the window shrinks to a 72x72 box with only a title bar (small font), the app draws an icon in it; double-click restores |
| Toolbar | `multitos/deskwin.h:169` WF_TOOLBAR 30, WF_FTOOLBAR/NTOOLBAR | An object tree under the title bar, drawn and clicked by the AES |
| Move/resize | `aes/gemctrl.c:257` gr_dragbox, `multitos/gemctrl.c:343` graf_dragbox | **Outline** drag in both. Real-time move is MagiC/XaAES, not Atari; MultiTOS's sizer shows two size lines (6/15/93) |
| Accessories | `aes/struct88.h:49-52`: `NUM_ACCS 1` in ROM, `MAX_ACCS 6` from disk; AC_OPEN 40 / AC_CLOSE 41 `aes/crysbind.h:184` | Cooperative: an ACC is a GEM process the AES switches to inside the AES's own event wait; the Desk menu lists them |
| appl_search / getinfo | `multitos/gemaplib.c:75 ap_search`, `:160 ap_getinfo` | List the running apps; ask what the AES supports |
| shel_write | `multitos/gemshlib.c:1140 sh_write` | Launch an app (in parallel under MiNT), change resolution (`sh_reschg`), shutdown, environment |
| Shared menu bar, app switching | `multitos/gemmnlib.c:150 mn_bar`, `:350 mn_register` | The bar belongs to the owner of the top window; the Desk menu lists every registered app; choosing one tops it; in single-tasking mode it swaps the current process (`swap_next`) |
| Drag and drop | `multitos/deskmenu.c:1045, 1236` AP_DRAGNDROP | Desktop to app over a MiNT pipe |
| Long filenames | (absent) | No Dpathconf/Dopendir/Dreaddir anywhere in `aes/` or `multitos/`: even the MultiTOS desktop is 8.3 |

### VDI / fonts (`pixvdi/sources/`)

`font6x6.c`, `font8x8.c`, `font8x16.c`, `fnt16x32.c` (system fonts), `text.c`/`textblt.s` (text blit with
effects: bold, light, italic, outline, underline; `styles.h`), `trucolor.c`, `ttcolor.c`. GDOS (loadable
fonts, SpeedoGDOS/NVDI) is not here; the MultiTOS desktop's window font uses `vst_font` over whatever GDOS
loaded (`multitos/deskpref.c`, `deskvdi.c`).

## How this maps onto ZigGEM

- ZigGEM is a hand-coded, immediate-mode TOS 1.00 desktop on an 8 px cell grid (`rom/gem/gui/core.zig`,
  `grid.zig`); no OBJECT tree, no RSC, no trap API. Zig carts get it as a linked library; C ports draw
  through the SDL2 layer.
- Its file ops (`rom/gem/desktop/deskops.zig`) edit an in-memory FAT only ("the disk is read-only") and the
  folder COPY box is cosmetic (`desksel.zig:150`), although KOS GEMDOS now writes to C:
  (`rom/kos/gemdos_write.zig`, `gemdos_wops.zig`, table 1.10). Wiring the desktop to those is the biggest gap.
- Only A: launches (`desktop.zig:171`) and there is no command tail. Install Application / document types
  need a "launch cart X with argument Y" request to the host.
- `bevel()` exists unused (`core.zig:52`): the 3D look is cheap.
- DESKTOP.INF (`deskinf.zig`) reads/writes `#E #W #M #T` only; the NEWDESK records above are the model for
  what to add, in our own text.
