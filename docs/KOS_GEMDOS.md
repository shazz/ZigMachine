# KOS GEMDOS: carts read files on C: (and A:)

Status: **phase 1 (read-only) built, 6 Nov 2026** on `feat/gemdos`: the library, the C ports' POSIX layer,
GrafX2 browsing and loading pictures from `C:\`; on the page (`?c=`), in the native host (`--c-image`)
and in the board images (the board run is the lead's). Phase 2 (writes) is designed here, not built.
Matt, 6 Nov: *"start the gemdos like FS to support HD so for example grafx2 can read files from HD/
substructure"*; C: is the SD card's `/HD` folder, *"on the GEM should be mapped as drive C"*
(docs/KOS_FAT.md §4c). The ADR is decisions.md, "KOS GEMDOS runs in the cart".

## 1. What a cart gets

TOS's GEMDOS file calls, with TOS's names, arguments, handles and error codes, so an ST program's file
code ports unchanged, and a POSIX layer over them so a C port's `fopen` / `opendir` / `stat` reach C:
with no change to its sources.

```
 a Zig cart                     a C port (GrafX2, pt2, ...)
   @import("kos_gemdos")          fopen("/C/PICTURES/X.PI1")   or   Fopen("C:\\PICTURES\\X.PI1", 0)
        │                              │ wasi-libc: the preopen "/C" (fd 4)        │ kestrel_gemdos.h
        │                         kestrel_sdl2/src/opt/kestrel_wasi_c*.c ─────────┤
        ▼                                                                         ▼
 rom/kos/gemdos.zig: drives, paths, handles, DTA searches ── rom/kos/fat.zig (+ fat_dir.zig)
        │ gemdos_cart.zig: A: through env.diskReadBlock, C: through env.kosDriveRead (unit 2)
        ▼
 the host: the page (the ?c= image), the native host (--c-image), the board (glass reads /dev/mmcblk0p1)
```

## 2. The calls (phase 1)

| call | what | answers |
|---|---|---|
| `Dgetdrv()` | the current drive | 0 A:, 2 C: |
| `Dsetdrv(d)` | makes `d` current (any letter, as TOS) | the drives that mount, a bit each (bit 2: C:) |
| `Dgetpath(buf, drv)` | `drv`'s current folder (0 the current drive, 1 A:, 3 C:), `\A\B`, `""` at the root | 0, EDRIVE, ERANGE |
| `Dsetpath(path)` | the current folder of the path's drive, checked | 0, EPTHNF, EDRIVE |
| `Fopen(path, 0)` | opens a file for reading | a handle >= 6; EFILNF, EPTHNF, EDRIVE, ENHNDL (8 open); mode 1/2: EACCDN |
| `Fread(h, n, buf)` | up to `n` bytes | the count (0 at the end); EIHNDL, EREADF |
| `Fseek(off, h, mode)` | 0 from the start, 1 the position, 2 the end | the new position; ERANGE outside 0..size, EINVFN |
| `Fclose(h)` | | 0, EIHNDL |
| `Fattrib(path, 0, 0)` | a file's or folder's attributes (a root: FA_DIR) | the attributes; `wflag` 1: EWRPRO |
| `Fsetdta(dta)` / `Fgetdta()` | the disk transfer address (TOS's 44 bytes) | |
| `Fsfirst(spec, attr)` / `Fsnext()` | the entries `spec` (`C:\PICTURES\*.PI1`) matches, into the DTA | 0; EFILNF (none), ENMFIL (no more), EPTHNF |

Errors are TOS's negative codes (`rom/kos/gemdos_err.zig`): EREADF -11, EWRPRO -13, EINVFN -32,
EFILNF -33, EPTHNF -34, ENHNDL -35, EACCDN -36, EIHNDL -37, EDRIVE -46, ENMFIL -49, ERANGE -64. A
refusal is an answer, never a trap: a drive that stops answering is EREADF on what was open, EDRIVE after.
Fsfirst follows TOS: plain files always match; folders, hidden and system entries only when `attr`
asks; `*` fills the rest of its field with `?`. The DTA is TOS's layout (attributes at 21, time 22,
date 24, length 26, name 30) with its words in the cart's byte order (little-endian: carts are wasm);
its first 21 bytes hold the search (drive, folder, slot, attributes, pattern), so searches need no table.
Two non-TOS helpers: `Kgemdos_media_a()` (drive A has a new disk) and `Kgemdos_trips(d)` (round trips).

**Later (phase 2):** `Fcreate`, `Fwrite`, `Fdelete`, `Frename`, `Dcreate`, `Ddelete`, `Fattrib` set,
`Fdatime`, `Dfree` (§7). Not in v1: the volume label search (`attr` 8), `.`/`..` entries in a listing
(GEMDOS resolves them by name, §3).

## 3. Names, paths, drives

- **Paths** are TOS's: `C:\FOLDER\FILE.EXT`; `/` is taken as `\`; no drive letter: the current drive;
  no leading `\`: from that drive's current folder. `.` and `..` are resolved by name before the disk is
  read, never by following a folder's `..` entry, so `..` at a root stays there, as on TOS. Up to 8
  folders deep (KOS_FAT §2).
- **Names are 8.3**, shown upper case, matched in any case. A longer name is cut to 8.3 as TOS cuts it
  (`ZIGPLASMA.PI1` opens `ZIGPLASM.PI1`). **Long names** are not read: the long-name entries are skipped
  and the file shows as its 8.3 alias (`A long name.txt` is `ALONGN~1.TXT`, as GEMDOS on an ST shows a
  card written by a PC). Name the files on `/HD` in 8.3 and nothing surprises.
- **Drives:** `A:` is the disk in drive A when it is a FAT image (a real floppy read raw by glass, an
  `.ST` on the page). A `.zmd` has no BPB, so A: does not mount over one: carts read their `.zmd` the
  way they do today (`zg.disk`, the C ports' flat floppy at `/`). `C:` is the SD card's `/HD` folder:
  glass serves the whole partition's sectors and GEMDOS roots C:\ at `HD`, so the boot files, `KESTREL/`
  and `CARTS/` never show. A card with no `/HD` has no C: (EDRIVE). The current drive starts at A:.
- **For the C ports**, C:\ is the folder `/C`: `C:\PICTURES\X.PI1` is `/C/PICTURES/X.PI1`.

## 4. Where it runs, and what it costs

**In the cart**, a library over the sector imports every host already serves (decisions.md, "KOS
GEMDOS runs in the cart"). `env.kosDriveRead` (unit 2, up to 64 sectors a request, all or nothing) has
been a host entry of the system table since 1.8, so **no system table change and no new
`system.rv32`**: a cart that uses GEMDOS needs table >= 1.8 (combo16's is 1.9), which `host_split.py`
already stamps on any cart importing it. No host code: the page, the native host and the board serve
the same sectors by the same rules (KOS_FAT §4), and the same Zig answers on all three.

**Costs on the board.** A request is one round trip to glass: the firmware writes the request block and
spins while glass's thread (polling at 2 kHz) `pread`s the sectors into the cart's buffer: **~0.5 ms
whatever its length** up to 64 sectors (32 KB), and the cart waits that long (a frame of a C port
under Asyncify waits inside its own call). So the library counts requests, not bytes:

- **The cache:** 4 runs of 8 sectors (4 KB) per drive, oldest replaced. A directory's sectors and the
  FAT's arrive 8 at a time, so a folder of 64 entries, or the FAT entries of 1,000 FAT32 clusters, cost
  one request. 16 KB of the cart's RAM per drive.
- **Reads of 4 KB or more** of whole sectors into a word-aligned buffer go straight from the card to the
  caller, contiguous clusters merged into requests of up to 64 sectors; smaller reads (stdio's 1 KB)
  go through the cache, a request per 4 KB.
- **Measured** (`Drive.trips`; the harness counts the imports): reading a 32 KB picture whole is 1
  request of 62 sectors plus its 34-byte tail from the cache (`gemdos_test.zig`); on the small image a
  cold mount + three folders fit in the cache's first runs; GrafX2's whole session (mount, the drive list,
  three folders listed, the picture loaded through stdio's 1 KB reads and every loader's probe):
  **12 requests, ~6 ms on the board** (`apps/gemdos_grafx2_check.mjs`). On a real card each folder and
  the FAT region are further apart: count a request per folder level, then one per 4 KB of folder. `rom/kos/gemdos_dump.zig` over a FAT32 card: a
  folder of 150 files and a 300 KB file read whole in fewer requests than in 1 KB pieces (the test).
- **Never per frame.** A cart that streams (a module, a long sample) reads ahead in big reads, as it
  would from a floppy; the ~0.5 ms latency is glass's poll, which a doorbell register would cut (RTL,
  KOS_FAT §4).

## 5. The C binding

`apps/ports/kestrel_sdl2/include/kestrel_gemdos.h` declares the calls (`int32_t Fopen(const char *,
int32_t)`, ...); the Zig library is linked as one wasm object built from `rom/kos/gemdos_c.zig`
(`zig build-obj -target wasm32-wasi`, see `apps/ports/grafx2/Makefile`). On top of it, the POSIX layer,
opt-in so the other ports' carts stay byte-identical: built with `-DKESTREL_CDRIVE`,
`kestrel_wasi.c`'s functions become the floppy's half and `src/opt/kestrel_wasi_c.c` /
`kestrel_wasi_cdir.c` hold the WASI entry points:

- wasi-libc finds its folders by asking fd 3, 4, ... until one is refused: fd 3 is the floppy (`/`), **fd 4
  is C: as `/C`** when C: mounts. libc resolves a path against the longest preopen, so
  `/C/PICTURES/X.PI1` (or a relative path after `chdir("/C/PICTURES")`) arrives as fd 4 + `PICTURES/X.PI1`
  and becomes `Fopen("C:\PICTURES\X.PI1", 0)`. C:'s files and folders are fds 32..39.
- `path_open` / `fd_read` / `fd_seek` / `fd_filestat_get` / `path_filestat_get` are Fattrib, Fopen,
  Fread, Fseek; `fd_readdir` is Fsfirst / Fsnext on a DTA of the folder fd's own, a POSIX `..` first.
  A create, a truncate, a write right or a write: EROFS (phase 1).
- wasi-libc's `chdir("..")` appends `/..` and never folds it; `kestrel_getcwd` folds `.` and `..` in place
  (a port maps `getcwd` to it: `grafx2/kestrel_port.h`), so `..` from `/C` leads back to `/`.
- **GrafX2**: its file selector's drive list (mountlist's `getmntent`, `grafx2/kestrel_stubs.c`) shows
  `/C` with a hard disk's icon when C: mounts. Select drive, `/C`, then folders and files as on any disk.

## 6. Proof

- `rom/kos/gemdos_test.zig` (native, in the gate's list): the calls over `docs/gemdos-c.img`: a nested
  picture read whole in one request, names (either separator, any case, cut to 8.3, `..`, the current
  folder), Fsfirst / Fsnext as TOS lists, Fseek's three modes and ERANGE, every refusal's code, a drive
  that stops answering (EDRIVE, then EREADF), a card with no HD.
- `tools/tests/test_kos_gemdos.py` (the gate's unittest run; skipped without mtools): cards made by
  `mkfs.fat` + mtools, FAT16 and FAT32 (small and big clusters), the board's layout, a fragmented
  file, a long name, 150 files in a folder, a 300 KB file: every byte under HD/ = mtools', in one read
  and in 1 KB pieces; nothing above HD/; no HD/, no C:.
- `docs/gemdos-c.img` (`tools/gemdos_c_image.py`, `--check` in the gate): FAT12, shaped like the card,
  `HD/PICTURES/ZIGWAVES.PI1`, `HD/PICTURES/PLASMA/ZIGPLASM.PI1` + `.NEO` (our own art, the files the
  GrafX2 floppy carries), `HD/TEXTS/` (20 files, two directory sectors), `HD/EMPTY.DAT`.
- `apps/gemdos_grafx2_check.mjs` (gated): GrafX2 started from GEM over its floppy, C: = that image: F3,
  Select drive (`/C` offered), C:\, PICTURES, PLASMA, ZIGPLASM.PI1 loaded. The oracle: that frame
  equals, hash for hash, a second run that loads the floppy's own ZIGPLASM.PI1. The selector's views are
  pinned; C: costs <= 16 requests. `--break c` (C: answers nothing) and `--break bytes` (a byte of the
  picture on C: changed) must fail it.
- `fpga/tests/test_gemdos_native.py`: the native host (`--disk --c-image`, GrafX2 wasm2c'd) = scene_hash.mjs,
  frame for frame, through the same session.
- The board: the lead's run (§8).

## 7. Phase 2: writes (designed, not built)

Linux mounts the card's partition read-only, and must: glass, the OSD and the kernel read it while a cart
runs, and two writers to one FAT corrupt it. So a cart never writes sectors: **glass owns every write,
at the file level**, on a read-write mount of its own (remount `rw` for the write, `ro` after; or
`/HD` as its own partition later):

1. A second request block beside the sector one (`map_cart.zig`: a `KOS_FILE_*` block, a sequence and a
   check, as `bkosreq.h`), carrying an operation (`create`, `write`, `close`, `delete`, `rename`, `mkdir`,
   `rmdir`, `setattr`), a path under `/HD` (8.3, checked by glass: no `..` out of `/HD`, no device
   names), a handle, an offset, a length and a buffer offset in the window; glass answers a TOS code.
2. `Fcreate` / `Fwrite` / `Fclose` / `Fdelete` / `Frename` / `Dcreate` / `Ddelete` / `Fattrib(.., 1, ..)`
   in the library send those; a write is buffered in the cart (32 KB) and sent whole, so a picture is one
   request.
3. **Coherence:** after a write glass bumps a C: generation word; the library drops its sector caches
   and remounts when it moves (the FAT and folders changed under it). The desktop shell does the same.
4. The page writes into its image (and offers it for download); the native host into its image file
   (`--c-image-rw`); new imports (`kosFileOp`) bump the system table to 1.10, so every card update must
   then carry the new `system.rv32`.
5. Proof: glass zig tests over a fake block device and a tmpfs; FAT16/32 images written by glass and
   checked by `fsck.fat` + mtools; a GrafX2 save on the page read back by mtools; `--break` a torn write.

## 8. Try it

On the page: `sealed.html?disk=demo-grafx2.zmd&c=gemdos-c.img`, double-click BOOT.WSM, OK, F3,
Select drive, `/C`. In the native host: `--c-image docs/gemdos-c.img`.

On the board:

Build the GrafX2 board image (`fpga/tools/glass_shelf.py`, the card's `CARTS/` and `KESTREL/progs/by-hash`
like any rebuilt cart: no new system). Copy the test pictures to the card's `HD/`
(`HD/PICTURES/ZIGWAVES.PI1`, `HD/PICTURES/PLASMA/ZIGPLASM.PI1`, from `apps/ports/grafx2/ownpics/`, 8.3
names). In GrafX2: F3, Select drive, `/C`, PICTURES, PLASMA, ZIGPLASM.PI1. Watch for: the drive list
without `/C` (the card has no `/HD`, or glass's C: thread is not running: every request times out after
500 ms, so the dialog takes 0.5 s to open and shows no `/C`), and the OSD's fps while the dialog reads
(a request blocks the frame ~0.5 ms).
