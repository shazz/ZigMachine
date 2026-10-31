# KOS FAT: real floppies in drive A, the SD card as C:

Status: **design, 31 Oct 2026** (Matt: "go for B", then FAT before the cartridge slot). KOS is the
KESTREL Operating System (docs/ZIGTOS_BOOT.md). Nothing here is built yet.

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
- **C:** is always shown (a hard-disk icon, `C`, label `SD CARD`), under drive A, opening the SD
  card's folders.
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
DDR" puts a disk, with a new descriptor magic `DISK_MAGIC_RAW` ("ZMDR") so the firmware knows it is
a sector image, not a `.zmd` (the drive ABI serves both the same way: 512-byte blocks). The
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

**C: in the browser and the native host**: a FAT16 image built at build time (`mkfs.fat` over a
folder, `docs/kos-c.img`) served by the page as unit 2; the native host takes `--c-image`. The
proof that the board serves C: right is the board itself (the request path has no sim of the
ARM), plus a firmware-side unit test of the request block (as `test_board_cartreq.py`).

## 5. Phases

| Phase | What | Proof |
|---|---|---|
| F1 | `rom/kos/fat.zig`: BPB, FAT12/16/32, dirs, names, file reads, over a read-sector callback | native Zig tests over images made by `mkfs.fat` + `mcopy`: FAT12 1.44 MB, Atari 720 KB (`mkfs.fat -S 512 -s 2 -f 2 -r 112 -h 0`, no `55 AA`), FAT16, FAT32, subfolders, a fragmented file, deleted and long-name entries, a corrupt BPB, a looping chain |
| F2 | the ROM import `diskReadBlock`; the desktop lists a FAT disk in drive A, opens folders, INFO shows sizes; the browser takes a raw `.ST` | `scene_hash.mjs --kos X.st` = the native host, clicks scripted; kos_boot_check with `?disk=X.st` |
| F3 | glass: the raw floppy read, `DISK_MAGIC_RAW`; firmware accepts it | glass zig tests (a fake block device); one ≤6-frame board-SoC sim of the desktop over a FAT12 image; then the board with a real floppy |
| F4 | drive A's icon only with a disk in, the source label, ITEM INFO's source line; the moved pins | PNGs, the pins re-taken, browser = native |
| F5 | C: `kosDriveRead`, the firmware's request block, glass's sector server thread, FAT32; C: in the browser and the native host from an image | ROM tests (FAT32); the request block's words natively; the board |

## 6. Open questions

1. C: shows the whole SD card, or only a folder of it (`zigmachine/c/`) so the system's own files
   stay out of reach of a future write path? (Proposal: a folder, `zigmachine/c/`, served as a FAT
   *view*; but a view needs glass to build FAT structures on the fly. The whole partition raw is
   the simple, honest v1.)
2. Programs on a FAT disk: should a `.WSM` file on a real floppy launch (the browser can; the
   board needs its prebuilt image, as `progs/` today)?
