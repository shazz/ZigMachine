# KOS GEMDOS phase 2: carts write to C:

Status: **built 6 Nov 2026** on `feat/gemdos-write` (after phase 1, docs/KOS_GEMDOS.md). GrafX2 saves a
picture to `C:\PICTURES\NEW.PI1`; it is there afterwards on the page (the `?c=` image), in the native
host (`--c-image`, `--c-image-rw` for the file) and, on the board, as a real file in `/mnt/sd/HD`. The
ADR is decisions.md, "KOS GEMDOS runs in the cart" (phase 2 paragraph).

## 1. Who writes

Linux mounts the card's partition read-only, and must: glass, the OSD and the kernel read it while a cart
runs, and two writers to one FAT corrupt it. So **a cart never writes sectors**. The host owns every write,
at the file level:

```
 cart: Fcreate / Fwrite / Fclose, Fdelete, Frename, Dcreate, Ddelete, Fattrib(path, 1, a)
   │  rom/kos/gemdos_write.zig, gemdos_wops.zig: checked as TOS checks, then ONE request
   ▼
 env.kosFileOp(req)              rom/kos/kfs_abi.zig: 12 words + path + path2 + data in the cart's memory
   ├── the page, node            docs/kos-cfile.js → KFS (docs/kos-cfs.wasm) over the ?c= image in memory
   ├── the native host           host/kos_cfile.c → the same wasm, wasm2c'd, over --c-image (-rw: the file too)
   └── the board                 cycles/bkosfile.c → the window's file block → glass/src/kos_file.zig:
                                 remount rw, the file ops under /mnt/sd/HD (kos_fs.zig), sync, remount ro
```

`kosFileOp` is a new host import: **system table 1.10** (appended, so a 1.9 cart still runs on a 1.10
system; a cart that uses GEMDOS needs 1.10 — GrafX2 is the only one). Every card update after this one
carries the new `KESTREL/system.rv32`.

## 2. The calls

| call | what | answers |
|---|---|---|
| `Fcreate(path, attr)` | a file to write (a new one, or one to replace), `attr` read-only/hidden/system/archive | a handle; EACCDN (a folder, a read-only file, a name FAT cannot hold, `attr` a label or folder), EPTHNF, EWRPRO (A:, or no host writes), ENHNDL |
| `Fwrite(h, n, buf)` | `n` bytes at the position | `n`; the first failed request's error, then on every call |
| `Fseek(off, h, mode)` | on a file being written: anywhere in 0 .. what was written | the position; ERANGE |
| `Fclose(h)` | a file written: **the save** (the last bytes and the commit) | 0, or the save's error (EWRITF: the card is full or failed) |
| `Fdelete(path)` | a file | 0; EFILNF (none, or a folder), EACCDN (read-only) |
| `Frename(0, old, new)` | a file or a folder: a new name, another folder, or both | 0; EFILNF, EACCDN (the name is taken, a folder into itself), ENSAME (another drive) |
| `Dcreate(path)` / `Ddelete(path)` | a folder (8 deep at most) / an empty folder, not the current one | 0; EACCDN (exists / not empty / current), EPTHNF |
| `Fattrib(path, 1, attr)` | read-only, hidden, system, archive (a folder keeps its bit) | the new attributes |

New codes: EWRITF -10, ENSAME -48. A: answers EWRPRO to every write. Not built: `Fopen` modes 1 and 2
(a file changed in place: EACCDN), `Fdatime`, `Dfree`.

**Buffering.** `Fwrite` fills one 32 KB buffer in the cart (owned by the handle that wrote last; another
handle's write sends it first). A request goes when it is full, at a seek outside it, and at `Fclose`, so
a save of up to 32 KB is ONE request: on the board one round trip plus the card's own write time.
`Fcreate` sends nothing (the file appears at the first request, whole at `Fclose`): unlike TOS, an
`Fsfirst` between `Fcreate` and `Fclose` does not see it.

**A save goes through a temporary name.** The first request creates `~KOS<slot>.TMP` (slot: the handle's
index) in the file's folder, the data goes there, the last renames it over the file: until then the old
file is whole. A save that failed half way is dropped at `Fclose` (`abort`). A cart that dies mid-save
leaves the temp file; the next save on that slot in that folder replaces it.

**Coherence.** After each of its own requests the library forgets its sector cache and remounts the drive
at its next use (the FAT and folders changed under it). Each request's answer carries the C: generation
(`gen`, the request's last word); the `gen` operation asks for it alone (the board's firmware answers it
from the window's generation word, no round trip). The desktop reads C: afresh at each start, which
follows every program, so it needs nothing more.

## 3. The path gate

Path traversal is the main risk: a cart is not trusted. Requests carry C:'s canonical form, `A\B\NAME.EXT`
relative to `C:\` (the library resolves `.`, `..`, drives and the current folder first). Every host checks
its own copy with **`rom/kos/kfs_path.zig`**: names joined by `\`, each a plain upper-case 8.3 FAT name
(letters, digits, DOS punctuation; no `.` or `..`, no `/`, no space, no control byte), at most 9 deep, at
most 127 bytes. Anything else is EPTHNF, refused whole. On the board glass also copies the request block,
the paths and the data OUT of the window before it checks them (the cart could rewrite them meanwhile),
bounds them below the window's top blocks, and walks the folders from an fd on `/mnt/sd/HD` one at a time
with `O_NOFOLLOW | O_DIRECTORY`: nothing is reachable above `/HD`, and a link (none on FAT) is refused,
never followed.

## 4. The hosts

- **KFS** (`rom/kos/kfs*.zig`, the page's and the native host's): FAT12/16/32 over sector reads and
  writes, mounted afresh per request, C:\ = the volume's `HD`. Order: new data into clusters the FAT
  still calls free, then the FAT (FAT 1 then FAT 2), then the entry; a delete takes the long-name slots
  in front of an entry first. FAT32's FSInfo counts are set "unknown" at the first write.
- **glass** (`kos_file.zig`, `kos_fs.zig`): the C: thread polls the file block beside the sector block,
  so a write and a raw read never overlap. Each write: remount `/mnt/sd` read-write, the operation
  (data `pwrite` + `fsync`, `renameat`, `unlinkat`, `mkdirat`; attributes by vfat's
  `FAT_IOCTL_SET_ATTRIBUTES`), `syncfs`, remount read-only (retried once; if it fails the card stays rw
  and glass logs it), then `POSIX_FADV_DONTNEED` on the raw partition fd so the next sector reads see
  what Linux wrote, then the generation word. The firmware waits `KOS_FILE_TIMEOUT_MS` (10 s): a remount
  and a sync on an SD card take far more than a sector read's 0.5 ms, and the cart's frame waits.
  glass writes `KF_TAKEN` = the sequence as soon as a request is whole and checked; the firmware gives up
  after `KOS_FILE_TAKE_MS` (250 ms) without it and answers EWRPRO (no glass, an older one, or one built
  for another block place) instead of waiting the 10 s. The first board run lost a save that way: the
  staged glass was built before the block moved from 0x3C8 to 0x3C0, so it polled 8 bytes off, the
  firmware timed out (EWRITF) and GrafX2, which ignores `fclose`'s answer, said done. glass writes the
  window only in answer to a request: a ready word written on every poll broke every cart load (the
  loader reads the whole window back after placing a cart: DdrMismatch).

## 5. Crashes

KFS: FAT has no journal, so no order of sector writes is clean at every cut. What holds, tested by cutting
a save after its sector writes (`tools/tests/test_kos_cfs.py`): every other file is intact, the file is
its old or its new bytes (or, cut between the old entry's deletion and the rename, the new bytes wait
under `~KOS0.TMP`), and what fsck.fat finds (lost clusters, FAT copies that differ) it repairs with
`fsck.fat -a` to a clean disk with nothing lost. A save that completes leaves `fsck.fat -n` clean.

The board: Linux's vfat does the sectors; the temp name and `fsync` before the rename keep the old file
until the new one is whole; a power cut while the card is remounted rw can still leave what any vfat
write leaves (the boot's fsck repairs it).

## 6. Proof

- `rom/kos/gemdos_wtest.zig` (native, gated): the library and KFS over a copy of `docs/gemdos-c.img`
  (FAT12): a picture saved through 1 KB writes is ONE request and reads back whole, the listing shows it
  once and no temp name; 70 KB in three requests; an overwrite, `Fseek` while writing; two files written
  at once; delete, rename, folders, attributes and every refusal; a host that fails mid-save.
- `tools/tests/test_kos_cfs.py` (gate's unittest run): KFS vs mtools and `fsck.fat -n` on FAT16 and FAT32
  cards: create, grow across clusters (150 KB, five requests), overwrite (the clusters come back),
  delete, rename in a folder / across folders / a folder moved (its `..` follows), mkdir/rmdir, a full
  disk (EWRITF, the old file kept), long-name folder neighbours untouched (and one deleted by its alias
  takes its long name), refused paths, and the crash cuts (§5).
- `fpga/glass/src/kos_file_test.zig` (`zig build test` in fpga/glass): every escape (`..`, `\`, drives,
  `/`, empty names, lower case, a planted symlink, as source and destination of a rename) refused and
  nothing outside HD changed; the operations; the block served once, from a copy, bounded.
- `fpga/tests/test_kos_file.py` (gate kos_fat): the firmware's block (cycles/bkosfreq.h) is the one
  glass reads; its answer; its place in the window.
- `apps/gemdos_grafx2_save.mjs` (gated): GrafX2 off its floppy, the floppy's ZIGPLASM.PI1 loaded, F2,
  Select drive, `/C`, PICTURES, `NEW` typed, Enter: one request, answered 0; the image then holds
  `HD/PICTURES/NEW.PI1` = the picture byte for byte (mtools), fsck clean; a new session lists it and
  re-opens it showing the floppy's picture. `--break write | torn | bytes` are caught.
- `fpga/tests/test_gemdos_native.py`: the native host = scene_hash.mjs through the same save, and the two
  C: images after it byte-identical.

## 7. Try it

On the page: `index.html?disk=demo-grafx2.zmd&c=gemdos-c.img`, double-click BOOT.WSM, OK, F3, load a
picture, F2, Select drive, `/C`, a folder, click the name field, type a name, Enter. (The page's C: lives
in memory: a reload loses it.)

On the board: the card needs the new glass (`KESTREL/glass`), `KESTREL/system.rv32` (table 1.10) and
GrafX2's lean cart. The same keys; then F3 on `/C`: the new file is listed and loads, and in the card's
`/HD` (on a PC, or `ls /mnt/sd/HD` on the console) it is a real file. Watch for: a frame frozen for the
write's time (a remount and a sync), `C: remount` lines in glass's log, a `~KOS?.TMP` left behind.
