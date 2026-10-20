# SysInfo as a GEM program (branch feat/sysinfo-gem-app, 2026-10-19)

## What changed

SysInfo (cart 91, `sysinfo`) is now launched from the GEM desktop exactly the way ST Replay is:
its disk `docs/demo-sysinfo.zmd` is a **data disk** (boot sector sums to `$0000`), so inserting it
(the menu's SYSINFO entry, `?disk=demo-sysinfo.zmd`, or the board shelf) boots GEM; FLOPPY DISK
opens the floppy window, which lists `BOOT.WSM`; a double-click runs it (request 3); **Q** quits
back to the desktop (request 4) with the disk still in. On the board it could not quit before
because its disk was bootable: request 4 had no GEM to go back to.

- `tools/mkdisks.sh`: `sysinfo) ... --no-boot` beside `st_replay`.
- `tools/mkdisk.py`: a data disk now ALWAYS lists its executable in the FAT. ST Replay never hit
  this (its extra `SAMPLE.RAW` forced a FAT); SysInfo carries no other file, and its first repack
  came out with an empty FAT, so GEM's window was empty. No other disk changed (all 101 others
  repacked byte-identical).
- `tools/channels.py`: sysinfo excluded from +/- like st_replay ("a data disk that boots GEM + an
  app"); it stays in the menu. `docs/channels.json` regenerated.
- `apps/sysinfo_check.mjs`: page 4's BOOT SECTOR is now expected from the disk's own sum
  (`DATA DISK`), not hardcoded `BOOTABLE ($1234)`.
- NEW `apps/sysinfo_gem_check.mjs` + two `gate sysinfo_gem` lines in build.sh (+ `--break
  bootable`): disk is a data disk; its one program BOOT.WSM depacks (romDepack, as the loader)
  to `demo-sysinfo.wasm` byte for byte; GEM over the real disk (real FAT, real blocks) launches it
  from the floppy window 3 times (> MAX_GUI) with Q between; Space still opens the menu after
  the 3rd launch (ROM handles reclaimed); page 4 reads DATA DISK + BOOT.WSM; the last Q leaves
  GEM's desktop hash identical to before the first launch.
- `fpga/tests/test_board_cartreq.py`: the shelf stages `demo-sysinfo.zmd` with GEM's image
  ("a data disk: GEM boots") and `progs/demo-sysinfo/BOOT.WSM.zmd` from sysinfo's image.
- Docs: FLOPPY_DISK.md, FPGA_GLASS.md, glass_shelf.py comment, sysinfo.zig header (still 200 lines);
  ZIGMACHINE_GUIDE.html regenerated.

No change to the loader, the ROM, the desktop, the glass or the firmware: `glass_shelf.py`
already detects a data disk from its boot sector and prebuilds its programs under `progs/`.

## Decision: cart 91 stays

The cart IS the program (BOOT.WSM is `demo-sysinfo.wasm`), exactly like st_replay's cart 8, so
it stays in build.zig / cart.zig / catalog.zig / glass_shelf SHELF. ST Replay never had a
bootable disk, so there is no removal precedent. What changes for the user: the menu's SYSINFO
entry now brings up GEM (double-click the floppy, then BOOT.WSM) instead of SysInfo directly, and
it is no longer a +/- channel. `?demo=demo-sysinfo.wasm` still runs the cart directly.

## Gate

`./build.sh --changed origin/main` (escalated to the full gate: tools/mkdisk.py is shared).
Every harness passed, sysinfo + sysinfo_gem (both lines each) included, EXCEPT `raytrace`, a
`gate_timed` wall-clock harness: "a frame took 18.58 ms, over the 60 fps budget" with the box at
load average 13-15 (9 builds queued on build.lock). The raytrace cart is untouched by this
branch; see "Re-run" below for the isolated rerun.

## Board files

See `stage/INSTALL.txt`.

Isolated rerun of `node apps/raytrace_headless.mjs` under build.lock afterwards: `raytrace: OK`.
So the only gate failure was load, not this branch. The fpga shelf tests
(`uv run pytest tests/test_board_cartreq.py tests/test_board_gemdisk_shelf.py tests/test_shelf_titles.py`)
pass 30/30.

Lean carts: `make -C fpga -o build/soc_hp/hp_sim.json split-cart CART=sysinfo|gem ZM_AUDIO=snd ZM_FPU=1`
(table 1.2, the same as the card's system.rv32). Staged: `stage/zigmachine/demo-sysinfo.zmd` (GEM's
image) and `stage/zigmachine/progs/demo-sysinfo/BOOT.WSM.zmd` (SysInfo's image), md5s + steps in
`stage/INSTALL.txt`. Not touched: the board, the sim slots.

## How to test on the board

OSD -> SYSINFO -> GEM -> double-click FLOPPY DISK -> double-click BOOT.WSM -> SysInfo; Q -> GEM.
The request-3/4 swap on real silicon was "built, host-tested" for ST Replay; this is its second user.
