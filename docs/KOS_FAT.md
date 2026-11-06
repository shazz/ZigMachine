# KOS FAT: real floppies in drive A, the SD card as C:

Status: **F1-F4 built, 31 Oct 2026; F3b (a floppy program's own board image) and F5 (C:, the SD card, read-only) 4 Nov; F5's first board run 4 Nov: the redraw and drive-A fixes in §4b** (the reader; the desktop over a FAT floppy in every host; the real floppy and its programs on the board; drive A shown only with a disk in, labelled FLOPPY or SD IMAGE); As built, the reader runs in the desktop shell cart, not behind a new ROM import (§2, "As built") (Matt: "go for B", then FAT before the cartridge slot). KOS is the
KESTREL Operating System (docs/ZIGTOS_BOOT.md).

Today GEM's drive A only knows ZigMachine's own `.zmd` disks: the host parses the disk's flat
FAT and hands the desktop up to 12 records (name, type, size, date; `docs/sealed-loader.js`,
`host/zmd_dir.h`). A real Atari floppy, a PC-formatted 1.44 MB disk or an `.ST` image means
nothing to it. And there is no hard disk. This design gives the ROM a GEMDOS-style FAT reader so
the desktop browses **any FAT12 floppy** in drive A (a real one through the USB floppy drive, an
`.ST` image in the browser), and adds **C:**, the SD card as a hard disk.

## 1. What changes, in one picture

```
 drive A                                      C:
 ───────                                      ──
 .zmd (SD shelf, today)   raw FAT12 image      the SD card's FAT32 partition, read-only
   │ the host's flat         │ (USB floppy: glass reads it raw,  │ sector by sector, on request
   │ listing, as today       │  browser: a dropped .ST/.IMG)     │ (glass serves, ZIGGY waits)
   ▼                         ▼                                    ▼
 desktop's disk_dir     rom/kos/fat.zig ── BPB, FAT, dirs, 8.3 names, file reads ──┘
                             │ over the drive ABI's 512-byte sectors (unit 0: A, unit 2: C)
                             ▼
                        the desktop's DirModel: windows, folders, ITEM/DISK INFO
```

## 2. The ROM's FAT reader (`rom/kos/fat.zig`, read-only)

One reader for FAT12, FAT16 and FAT32, written once in Zig, in `rom.wasm`, so the browser, the
native host and the board run the same code (as the POST, `rom/kos/kos.zig`).

- **Sectors through the drive ABI.** It reads 512-byte sectors with `diskReadBlock` (drive A, as
  carts do today) and a new `kosDriveRead(unit, sector, count, dst)` for C:. Both are new ROM
  imports: rom.wasm imports only `memory`, `hwVideoBase` and `hwBlit` today. Every host already
  defines `diskReadBlock` (one `w2c_env_*` serves every module), so A: costs nothing; C: is new
  (§4). A table bump: minor (the ROM's exports appended, the imports are the system's own).
- **The BPB** (boot sector offsets 11..35): bytes/sector (512 only), sectors/cluster (1..64, a
  power of 2), reserved sectors, FAT count (1..2), root entries, total sectors (16- or 32-bit),
  sectors/FAT, and FAT32's root cluster. The FAT type comes from the cluster count, as Microsoft's
  rule says (< 4085 FAT12, < 65525 FAT16, else FAT32), never from the label text. **Atari
  floppies**: TOS writes a BPB but no `55 AA` signature and often a random serial at offset 8;
  both are accepted. A BPB that does not add up (zero fields, a FAT past the disk) is `corrupt`:
  the window says so instead of listing garbage.
- **Directories**: the fixed root (FAT12/16) or a cluster chain (FAT32 and every subfolder).
  32-byte entries: `00` ends the directory, `E5` (deleted) skipped, attribute `0F` (a long-name
  piece) skipped, the volume label kept as the disk's name for DISK INFO, `.` and `..` hidden.
  Names are shown 8.3 upper case, as GEMDOS shows them.
- **Files**: size from the entry; contents by walking the chain, with a cycle guard (a chain
  longer than the disk's cluster count is corrupt). Fragmented files read right by construction.
- **Limits**: a folder lists up to 64 entries in v1 (the desktop's window model holds 12 today:
  §3); a path up to 8 levels.

**As built (F2).** The reader is `rom/kos/fat.zig`, but the code that walks drive A runs in the
desktop's shell cart (`apps/zig/scenes/gem_fat.zig`), through the `diskReadBlock` every cart
already imports, not in rom.wasm behind a new import: a ROM import would have to be served by
every host and by the ~100 harnesses that instantiate rom.wasm with a fixed env, for no gain the
shell does not give (it is the desktop on every host, wasm2c'd on the board). The shell fills the
ROM's desktop model through two appended exports (`deskFatReset`, `deskFatFolder`, sys_abi 1.7)
and the existing record buffer, which gained a folder byte (records of 26 bytes, the hosts ask
`deskDirEntryBytes`). `insertDisk(2)` means a FAT disk; a host mounts a raw image that is no
`.zmd` as one (`ZMKos.fatImage`, `disk_app_fat_image`). The model holds 32 files and 16 folders
over the whole disk, read breadth first. When glass needs the reader (a floppy's `.WSM`, C:), it
imports the same file.

## 3. The desktop

- The window model (`rom/gem/desktop/dirmodel.zig`) gets a second source: for a FAT disk the ROM
  fills it itself from `fat.zig` (no host packing), folders are the disk's own (today folders are
  RAM-only, a `.zmd` FAT being flat). `MAX_FILES` goes from 12 to 64 and the window scrolls
  (dirview has the slider; it never had more than a screenful). The `.zmd` path stays as it is.
- Opening a file: a ZigMachine program (`.WSM` on a `.zmd`) launches as today (request 3); a
  file on a FAT disk is read-only data in v1 (ITEM INFO shows its size, date, attributes).
- **Drive A's icon only when a disk is in** (Matt): `insertDisk(1/0)` already tells the desktop;
  the icon is drawn and selectable only while a disk is in, and appears / disappears on a media
  change. DESKTOP.INF's `#M` line keeps the icon's saved cell whether it is shown or not.
- **The source, as a Gotek / HxC shows it** (Matt): the icon's label says where the disk is:
  `FLOPPY` for the real USB floppy, `SD IMAGE` for a `.zmd` (or `.ST`) from the SD shelf or the
  page. Proposal: the label only (8 characters fit under the icon, TOS-like), and ITEM INFO's
  first line says the rest (`Source: USB floppy drive` / `Source: SD card, demo-stniccc.zmd`).
  The host passes the kind with the existing `insertDisk` call's argument: 0 none, 1 an SD image,
  2 the floppy (1 is what every host passes today). A PNG of both looks comes with phase F4,
  rendered from the real ROM through `scene_hash.mjs`.
  **As built (F4):** `insertDisk`'s bits 7:0 stay the disk's kind (0 none, 1 a `.zmd`, 2 a FAT
  image, F2) and **bit 8** says the real floppy (`desk_icons.setDrive`, `DRIVE_FLOPPY`). Only the
  board has one: glass writes the floppy's descriptor with `DISK_MAGIC_FLOPPY` ("ZMDF", at boot and
  at a media change), `cycles/bdisk.c` reads it as a disk booted for (`bdisk_floppy`) and
  `bdiskapp.c` sets bit 8. The browser and the native host always pass an SD image. The source is
  one line, `Source: FLOPPY` / `Source: SD IMAGE`, the last row of DISK INFORMATION (Show Info on
  the drive; the box grew one row); a file name there is left for later. DESKTOP.INF saves the
  drive's label as `FLOPPY DISK` whatever the source.
- **C:** is always shown (a hard-disk icon, `C`, label `SD CARD`), under drive A, opening the SD
  card's folders.
  **As built (F5):** shown once the shell MOUNTED C: (the board, the page with `?c=kos-c.img`, the
  native host and scene_hash.mjs with `--c-image`), not always: a host with no C: shows no icon, as
  an empty drive A shows none, so no desktop pin moved. C: has its own directory model
  (`rom/gem/desktop/deskdrive.zig`: `drives[0]` A:, `drives[1]` C:); each window remembers its
  drive and the model in focus follows the top window. The shell (`apps/zig/scenes/gem_fat.zig`)
  walks C: once at start, breadth first, through `env.kosDriveRead`, into C:'s model with the ROM's
  appended unit calls (`deskDriveReset/Folder/DirPtr/SetFileCount`, `deskSetDriveC`; sys_abi 1.9).
  Limits are A:'s: 32 files and 16 folders over the whole card, so on the real card C: shows its
  root and the first folders' files, the rest left out (a per-folder read on open is the next
  step); C:'s files are data (nothing on C: launches yet); edits (rename, delete, new folder) stay
  in RAM as A:'s do.
- **Pins that will move:** every GEM reference taken with an empty drive (the floppy icon goes):
  `apps/gem_headless.mjs`'s empty-drive shots, `fpga/tests/test_board_gemdisk.py`'s empty-drive
  hash (`22934ae1...`), `test_kos_boot.py`'s empty-drive desktop, the board-SoC sim's desktop hash
  (`71dbd6ea...`, the KOS power-on in docs/FPGA_GLASS.md). And every desktop shot once C: shows.
  Each is re-taken in the same commit as the change, browser = native.

## 4. Where the bytes come from

**Drive A, a `.zmd`**: unchanged (the disk in DDR, `diskReadBlock`).

**Drive A, the real floppy (board).** glass reads the whole floppy **raw** (`/dev/sdX`, 1,440 or
2,880 sectors of 512 bytes, one sequential pass: a few seconds, instead of the ~9 KB/s that
loading through the vfat mount gave, cluster by cluster) into the cart window where "The disk in
DDR" puts a disk. **As built (F3)** there is no new descriptor magic: every host tells a FAT image
from a `.zmd` by its content (no `.zmd` header, a size that is whole 512-byte sectors and at least
4 KiB, a BPB saying 512 bytes a sector: `plan.fatImage` in glass, `disk_app_fat_image` in the native
host, `ZMKos.fatImage` in the page, the same test in `cycles/bdiskapp.c`), so the firmware serves it
as a data disk with no listing (`insertDisk(2)`) and the desktop walks it itself. On the OSD shelf
`D` puts the floppy into drive A raw (`app_floppy_a.zig`, a media change if the desktop runs) and
`R` then boots the desktop over it. The
floppy source (`fpga/glass/src/app_source.zig`, feat/floppy-source) mounts vfat for `.zmd`
carts today; that path stays for carts, and a disk with no `.zmd` on it (or `R` on its line) is
taken raw for GEM. An Atari 720 KB (9 sectors, 80 tracks, 2 sides) disk reads the same way if the
USB drive reads 720 KB media (most do; to check on the board).

**Drive A in the browser.** Dropping or picking a raw `.ST` / `.IMG` (a multiple of 512 bytes,
a BPB at 0) inserts it in drive A as a sector image: the page's drive serves it through the same
`diskReadBlock`. `.MSA` (compressed) later. `?disk=X.st` too.

**C:, the SD card (board).** The SD card's first partition is FAT32, mounted read-only by Linux.
ZIGGY cannot see the SD card; only glass can. C: is served **sector by sector on request**:

1. the ROM calls `kosDriveRead(2, sector, count, dst)`; the firmware writes a request block in
   the cart window's top 4 KiB (beside the cart-request block: unit, sector, count, a sequence
   number and a check), and spins;
2. glass, which polls that word from a thread at ~2 kHz (no CSR, no RTL; a doorbell register
   would cut the latency, an RTL change for later), reads the sectors from the partition's block
   device (`/dev/mmcblk0p1`, opened read-only), writes them into a fixed 32 KB buffer in the
   window and bumps the answer word;
3. the firmware sees the answer (its D$ line dropped first), copies to `dst`, returns.

One request carries up to 64 sectors (32 KB), so a directory costs one round trip and a file
read streams at a few MB/s. Read-only, so a mounted read-only partition is safe to read raw; a
write path (later) would need glass to own the writes (a file API, not sectors). Timeout: 500 ms,
then the ROM sees an I/O error and the window says `C: not responding`.

**As built (F5, the plumbing, 4 Nov).** `env.kosDriveRead(unit, sector, count, dst) -> u32` is a
**cart** import (the desktop shell's first; since 6 Nov any cart's, through KOS GEMDOS, docs/KOS_GEMDOS.md),
a host entry of the system table
(`sys_abi` 1.8, `tools/host_bridges.py` KOS_DRIVE), not a ROM import: the ROM's own imports stay
`memory`, `hwVideoBase` and `hwBlit`. One rule set in every host: the answer is the sectors read,
0 for any refusal (no C:, a unit other than 2, count 0 or over 64, a run past the end, a `dst` off
a word or past the memory), all or nothing, never a trap. The page: `kosDriveRead` over the image
`kosMountC(buf)` mounted (`docs/sealed-loader.js`); the native host: `--c-image X` into
`host_cdisk` (`host/disk.h host_kos_drive_read`, the default the generated env carries); the board:
`cycles/bkosdrive.c` (force-included as `bkosdrive.h` into the board images' env only; the sim's
answer 0) writes the request block at window end - `KOS_DRIVE_FROM_TOP` (0x360, 9 words, between
the media word and the cart-request block: `map_cart.zig` KOS_DRIVE_*, `cycles/bkosreq.h`) and
waits up to 500 ms; glass's `src/kos_drive.zig` serves it from a thread polling every 500 us,
reading `/dev/mmcblk0p1` with `pread`, writing the sectors straight into the window at the
cart's own `dst` (no bounce buffer: the window is glass's to write), then `KD_DONE` and `KD_ACK`
last; the firmware drops the block's and `dst`'s D-cache lines. No glass thread (an older glass,
no partition): every read times out to 0. Proof: `fpga/tests/test_kos_drive.py` (the firmware's
words = glass's rule, the answer, the block's place, the native rules) and glass's
`kos_drive.zig` tests (served once, at its offset; every refusal answered 0; a half-written block
never served). The board is the one host not yet run.

**C: in the browser and the native host**: a FAT16 image built at build time (`mkfs.fat` over a
folder, `docs/kos-c.img`) served by the page as unit 2; the native host takes `--c-image`.
**As built:** `docs/kos-c.img` is a 200 KB FAT12 image (`tools/kos_c_image.py`, synthetic bytes
shaped like the card, `--check` in build.sh), mounted by the page with `?c=kos-c.img` (none by
default, a one-line change in `kosPowerOn`); FAT16 and FAT32 are F1's reader tests against mtools.
Proof: `apps/kos_boot_check.mjs` (the page's C: icon, then its window = scene_hash.mjs
`--c-image`, which the bare desktop differs from; `--break c`: a page whose kosDriveRead answers
nothing is caught), `fpga/tests/test_kos_fat_desktop.py` (the native host's `--c-image` =
scene_hash.mjs's, icon and window). The
proof that the board serves C: right is the board itself (the request path has no sim of the
ARM), plus a firmware-side unit test of the request block (as `test_board_cartreq.py`).

## 4b. The board's first run (4 Nov 2026)

Matt ran F1-F5 on the board (combo16, system table 1.9): D (the USB floppy into drive A), R (the
desktop over it). Two bugs, fixed on `fix/kos-desktop-board`:

- **25 fps once a drive window opened.** Nothing was reading the card per frame (C: is walked once,
  at the shell's start; `frame_cost.mjs --c-image` counts 0 reads a frame): the ROM's desktop
  repainted the whole screen, every icon and every open window with its listing, every frame.
  `frame_cost.mjs`: the desktop's ROM 0.30 Mc idle, 1.10 Mc with C:\ open (2.06 Mc estimated in all;
  the board's idle desktop is already 1.65 Mc, so a window pushed it far past the 60 fps band). Now
  it repaints only when something changed (`rom/gem/desktop/deskdirty.zig`): every input and every
  host write is a touch (the pointer moving or a button changing, a double-click, a key, drive A's
  word or C: changing, a drive model written, the screen re-bound; `insertDisk`, which the hosts call
  every frame, only when its word changes); after one it draws SETTLE (2) frames, and it draws while
  anything moves (a button held, the zoom-box, an open or a launch pending) and SETTLE frames after.
  The plane's logical buffer keeps its pixels (hwClear clears the physical picture), so a skipped
  frame shows exactly what a repaint would have drawn. With C:\ open: 0.70 Mc (FRESCO's alone).
  C:'s walk now reads 8 sectors a round trip (`gem_fat.zig` readC), not one.
- **"Drive A shows the SD card".** Not reproduced off the board: with a floppy in A: and a card in
  C:, the page, scene_hash.mjs and the native host agree and A:\ lists the floppy. Opening A: never
  spins the drive, by design: glass reads the whole floppy raw once, at D (and again at R), and drive A
  is that image in DDR. With no disk in drive A there is no A: icon (F4), and C:'s icon (SD CARD) is
  the only drive on the desktop: Matt's disk was a CART floppy (a PC vfat disk of `.zmd` and
  `shelf.txt`, meant for F), and what he opened was C:. The lead then wrote a program floppy
  (`kos_rv.py`: `.WSM` + `.RV`) to it, and with D then R the A: icon showed it and its programs ran:
  the reader is fine. D now says so on a cart floppy: `A: N .zmd carts, F lists them`
  (`glass/src/app_floppy_a.zig` carts(), KOS's reader over the root). Fixed
  on the way: a FAT disk swapped for another FAT disk under the running desktop was never re-read
  (the shell latched "a FAT disk is loaded"); it now re-reads drive A when KOS's media-change count
  (`sysvars.drive_a` bits 31:8) moves.

Proof: `apps/kos_desk_check.mjs` (gated): a 180-frame session (A:\ opens, a hover, a click, its
GAMES folder, a window dragged, the File menu, Close Window's zoom-box) hashed every frame equals
the pin taken from the every-frame repaint (main ef337055); A:\'s listing with C: mounted equals the
one without, and differs from C:\'s; C:\ open costs < 1.7 Mc (the old repaint: 2.5, failed) with no
C: read a frame. `fpga/tests/test_kos_fat_desktop.py`: A: and C: together, native = page.

## 4c. C: is /HD (6 Nov 2026)

The card has a layout now (docs/FPGA_GLASS.md, "The SD card's layout"): boot files at the root,
`KESTREL/` (the system), `CARTS/` (the OSD's shelf) and `HD/`, the future GEMDOS hard disk. **C:\
is `/HD`**, and nothing above it shows in GEM. Nothing in the hosts moved: glass still serves the
whole partition's sectors (`kos_drive.zig`), the page and the native host a whole image; the
desktop shell (`apps/zig/scenes/gem_fat.zig`) mounts the volume, looks up the folder `HD` in its
root (`C_ROOT`; up to 128 root entries) and walks from that folder's cluster instead of the root,
so the boot files, `KESTREL/` (whose `progs/by-hash` alone would eat the 32-file limit) and `CARTS/`
are never read into C:'s model. **A card with no `/HD` has no C:** (no icon, as a host with no C:
image), not an empty one: an icon that opens on nothing would say the card is empty when it is not
laid out. `fpga/tools/sd_migrate_layout.sh` makes `/HD`, empty; `glass_sd.py` stages one.

`docs/kos-c.img` (`tools/kos_c_image.py`) is shaped like such a card: `BOOT.BIN`,
`KESTREL/SYSTEM.RV3`, `CARTS/SHELF.TXT`, and `HD/` with `README.TXT` and the folders `DEMOS`,
`TOOLS`, `TUTORIAL`, so C:\ on the page lists `HD/`'s four entries. Proof:
`fpga/tests/test_kos_fat_desktop.py::test_c_is_the_cards_hd_folder_and_nothing_above_it`: FAT32
cards made by `mkfs.fat` + mtools (the board's file system); C:\ on a card with the boot files,
`KESTREL/`, `CARTS/` and `HD/` is, frame for frame in both hosts, C:\ on a card holding only that
`HD/`; it differs from another `HD/`'s; a card with no `HD/` shows the bare desktop.
`apps/kos_desk_check.mjs` and `kos_boot_check.mjs` (over the new `kos-c.img`) still pass.

## 4d. Programs read C: (KOS GEMDOS, 6 Nov 2026)

The desktop's walk of C: is the desktop's own. **Any cart** can now open files on C: (and on a FAT disk
in drive A) with GEMDOS's calls, Fopen / Fread / Fseek / Fsfirst / Dsetpath..., in the cart over the same
reader and the same `kosDriveRead`, so no host changed and the system table did not move: docs/KOS_GEMDOS.md.
The C ports get it as POSIX (`fopen("/C/PICTURES/X.PI1")`): GrafX2's file selector lists `/C` and loads
pictures from its folders. The page takes `?c=gemdos-c.img` for a C: with pictures in folders.

## 5. Phases

| Phase | What | Proof |
|---|---|---|
| F1 | `rom/kos/fat.zig`: BPB, FAT12/16/32, dirs, names, file reads, over a read-sector callback | native Zig tests over images made by `mkfs.fat` + `mcopy`: FAT12 1.44 MB, Atari 720 KB (`mkfs.fat -S 512 -s 2 -f 2 -r 112 -h 0`, no `55 AA`), FAT16, FAT32, subfolders, a fragmented file, deleted and long-name entries, a corrupt BPB, a looping chain |
| F2 | the ROM import `diskReadBlock`; the desktop lists a FAT disk in drive A, opens folders, INFO shows sizes; the browser takes a raw `.ST` | `scene_hash.mjs --kos X.st` = the native host, clicks scripted; kos_boot_check with `?disk=X.st` |
| F3 | glass: the raw floppy read (`D`), FAT images found by content; firmware accepts them; programs by hash | glass zig tests (a fake block device); one ≤6-frame board-SoC sim of the desktop over a FAT12 image; then the board with a real floppy |
| F3b | a floppy program's own `NAME.RV` (hash + ABI checked), the card's `progs/by-hash` the fallback; `kos_rv.py` writes `.RV`s and program floppies | glass zig tests (its own `.RV` with no card, over the card's, a stale one refused); `fpga/tests/test_kos_rv.py`; the board with a real floppy |
| F4 | drive A's icon only with a disk in, the source label, ITEM INFO's source line; the moved pins | PNGs, the pins re-taken, browser = native |
| F5 | C: `kosDriveRead`, the firmware's request block, glass's sector server thread, FAT32; C: in the browser and the native host from an image | ROM tests (FAT32); the request block's words natively; the board. As built: `test_kos_drive.py`, glass's `kos_drive.zig` tests, `kos_boot_check.mjs` (+ `--break c`), `test_kos_fat_desktop.py`; the board not yet |

## 6. Decided (Matt)

1. **C: is the whole SD partition**, read-only, raw (the simple v1). **Superseded 6 Nov 2026**
   (decisions.md, "The SD card's layout"): C: is the card's `/HD` folder (§ 4c).
2. **`.WSM` programs on a real floppy launch** from GEM, as a data disk's do. The board needs the
   program's native board image: glass reads the file's bytes from the floppy image it already
   holds (with this same reader, `rom/kos/fat.zig`: pure Zig, glass imports it), depacks them if
   they are ZX0-packed, hashes the wasm (SHA-256), and loads `KESTREL/progs/by-hash/<hash>.rv32`
   (`glass/src/app_floppy_prog.zig`; `tools/glass_shelf.py` writes one per cart it has a board image of, the board image of the cart whose
   `docs/demo-<cart>.wasm` has that hash, as it finds a data disk's program today). No image:
   `<NAME>: no board image for this program`, the desktop keeps running. The browser runs the
   file's wasm directly (request 3, as for a `.zmd`: `ZMKos.fatFile` reads it off the image).
3. **The floppy carries its own board image** (F3b; Matt, 31 Oct: the floppy must not need the SD
   card). `NAME.RV` beside `NAME.WSM`, in the same folder, is the program's board image in a
   40-byte container (`glass/src/app_floppy_rv.zig`): `ZMRV`, a u32 version (1), the SHA-256 of the
   program's wasm (unpacked), then the lean cart ZX0-packed, as `progs/by-hash` holds it. glass
   takes it first: a `.RV` built from another wasm (a stale one beside a rebuilt program) is
   refused (`RvForAnotherProgram`), never passed over to the card; its ABI is checked as every
   board image's is (the cart header's table version against the running system, `plan.planOver`).
   No `.RV`: the card's `progs/by-hash`, as in F3. `fpga/tools/kos_rv.py` writes one (`rv CART
   OUT.RV`) or a whole program floppy (`floppy OUT.st CART...`: each cart's `.WSM` and `.RV` on an
   Atari 720 KB image, to `dd` onto a disk), refusing a cart the system would refuse:

       cd fpga && uv run python tools/kos_rv.py --system build/hcycles/split/board_snd/sys.bin \
           --fw-dir build/hcycles/split/carts floppy progs.st tutorial sysinfo
