# GEM desktop: real file operations on C: (GEM5_PLAN P1.1)

Status: **built 9 Nov 2026** on `feat/gem-fileops` (not merged). Matt, 9 Nov: "let's implement the desktop
copy and move". Before this the desktop's delete, rename and New Folder edited its in-memory model only and
the COPY box was cosmetic: nothing reached the card.

## What the user does (TOS 1.00, plus TOS 1.04's Control-drag)

| gesture | what happens on C: |
|---|---|
| drag a file or folder (or the rubber-band selection it is part of) onto a folder, another open window, or the C: icon | **COPY FOLDERS / ITEMS**: the folders and items counted on the card, OK, then the same box counts down live while each file is copied |
| the same with **Control** held | **MOVE FOLDERS / ITEMS**: on C: each item is renamed into place (Frename: one request, the source is never at risk); from drive A it is copied, the copy checked, then the source deleted, and a source that cannot be deleted (A: is write-protected) is kept and an alert says so |
| drop onto the TRASH | **DELETE FILE(S)** counted, OK, files then emptied folders deleted, counting down |
| Show Info, a new name, OK | Frename |
| File > New Folder, a name, OK | Dcreate (empty: NEWDIRn, as drive A's) |
| a name that exists where an item goes | **NAME CONFLICT DURING COPY / MOVE**: OK with a new name copies under it, OK with the same name replaces (a folder: copies into the one there), Skip leaves the item out, Quit stops |
| a drop onto drive A | TOS's alert: "The disk in drive A: is write-protected." Nothing is written |

Drive A keeps its in-memory behaviour for delete / rename / New Folder (a .zmd is not a writable disk).
A failure stops the operation where it is and raises an alert (full card, write-protected, an item gone, an
unreadable source); what was done stays done. A file whose copy fails half way is dropped whole: KOS GEMDOS
writes to `~KOS<slot>.TMP` and renames it over the file at Fclose (KOS_GEMDOS_WRITES.md §2), so no partial
file is ever left.

## How (the ROM reaches no disk)

rom.wasm imports only `hwVideoBase` and `hwBlit`; GEMDOS and `env.kosFileOp` live in carts. So, as Save
Desktop does, the desktop decides and the shell cart acts:

```
 ROM  rom/gem/desktop/deskdrop.zig   where a drag lands -> fileop.copy / delete (Items: drive, folder, masks)
      rom/gem/desktop/fileop.zig     the request into the mailbox; at the end C:'s windows found again by path
      rom/gem/desktop/fileop_ui.zig  the confirm / count-down box (trash.zig), NAME CONFLICT (conflict.zig), alerts
        |  the mailbox: rom/sdk/deskop.zig Box, at deskFileOp() (system table 1.18), in the ROM's memory
        v
 shell apps/zig/scenes/gem_fileop.zig        tick() once a frame after the desktop: the phase it answers
      gem_fileop_count.zig  pass 1: Fsfirst/Fsnext over the sources (never C:'s model: capped at 32 files)
      gem_fileop_walk.zig   pass 2: depth first, one entry a frame, the place kept between frames
      gem_fileop_entry.zig  one entry: delete / Dcreate / start a copy / Frename / skip
      gem_fileop_copy.zig   one file: Fread + Fwrite of 32 KB a frame (= GEMDOS's write buffer: at most one
                            kosFileOp request a frame), committed at Fclose
```

Phases: idle -> count (ROM) -> counted (shell: totals) -> run (ROM: OK) -> conflict (shell) -> answer (ROM)
-> run -> done (shell: status, C: re-read through gem_fat.loadC) -> idle (ROM: windows re-pointed, alert).
New Folder and rename are posted at run. The shell bumps `seq` at every change and the ROM repaints on it
(deskdirty), so the board's idle desktop still paints nothing.

Control: the browser and glass send Control as its own key (0xE014 / 0xE016); its release reaches the ROM
through the shell's new `keyUp` export as `deskKey(code | KEY_RELEASE)`, so no export was added for it.

## Board

Each write on the board is a remount and a sync of the card (seconds; KOS_FILE_TIMEOUT_MS 10 s), one request
a frame at most, so a copy of N files of < 32 KB takes about N such writes, a 70 KB file three, and the box
counts down between them. Needs: `KESTREL/system.rv32` with **system table 1.18** (the ROM's `deskFileOp`),
the GEM shell cart (`demo-gem`, it exports `keyUp` now) and glass with kos_file (already on the card since
6 Nov).

Check: C:\ open; drag `ECHO.REQ` onto `NET`: COPY FOLDERS / ITEMS 0 / 1, OK, the box counts to 0; open NET:
ECHO.REQ there (and `/mnt/sd/HD/NET/ECHO.REQ` on the console). Control-drag a file of C:\ onto MUSIC:
MOVE FOLDERS / ITEMS, OK, it leaves C:\ for MUSIC (one rename, so one write). Drop a folder on the TRASH: it goes, contents too. Show Info renames, New Folder
creates. Drag something onto the SD IMAGE / FLOPPY icon: the write-protect alert.

## Proof

`apps/gem_fileops_check.mjs` (gate `gem`): see its header. Mutants (`--break copy|delete|rename`: the host
answers 0 to that request and writes nothing) are each caught by the byte compare / listing checks.
