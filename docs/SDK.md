# The KESTREL SDK: write carts for the ZigMachine and the board

The SDK is for a coder who wants to make demos for the ZigMachine and run them on a KESTREL board
(a Z7-Lite with the KESTREL bitstream), without the SoC sources, Verilator or Vivado. You download
one tarball. Your cart lives in your own directory, and three commands take it everywhere:

| Command | What you get |
|---|---|
| `make` | your cart running in the browser emulator, on a local web server |
| `make floppy` | your cart on a disk image, `zig-out/demo-<name>.zmd` |
| `make board` | your cart's board image and an SD-card folder to copy onto the card |

## What is in the release

`kestrel-sdk-<version>.tar.gz` unpacks to:

```
kestrel-sdk-v1.2/
  README.txt     where to start
  RELEASE.txt    the KESTREL release it targets: version, HW version, commit, system table
  zigmachine/    the ZigMachine repository at that commit: ZigOS, the SDK headers, the emulator
  template/      a cart to copy: build.zig, Makefile, src/hello.zig, VS Code settings
  card/          the whole SD card of that release: a blank Z7-Lite 7010 boots it
  card.md5       the card's checksums
  INSTALL.md     from a blank board to the first cart: the card, the cables, what you see
  THIRD_PARTY.md the boot files that are not ours (zeST's BOOT.BIN, Linux, Buildroot), licences/
```

The machine itself (`machine-video.wasm`, `rom.wasm`, `machine-audio.wasm`) ships prebuilt in
`zigmachine/docs/`, and you never rebuild it. The board's `system.rv32` on the card was built from
those very bytes. That is why a cart from this SDK runs on that card.

The release targets **KESTREL v1.2** (combo16, HW 1.16.0, system table 1.9: KOS and its GEM
desktop). A cart is refused by a card whose system serves another table, and `make board` says so
before you copy anything.

### The card (since v1.2: complete)

v1.1's card only updated a card that already booted. v1.2's is the whole card, in the layout of
6 Nov 2026 (docs/FPGA_GLASS.md, "The SD card's layout"); `card/MANIFEST.txt` says where each file
came from:

| On the card | What | From |
|---|---|---|
| `BOOT.BIN` | FSBL + U-Boot: DDR3, clocks, MIO | zeST 20260518's prebuilt `boards/z7lite_7010/boot.bin`, unmodified (GPL-3, `THIRD_PARTY.md`) |
| `boot.scr` | `fpga/glass/boot/boot.cmd`, compiled: bitstream, AFI widths, Linux | plan A's (`fpga/glass/boot/build_planA.sh`) |
| `zigmachine.bit` | the KESTREL SoC, combo16 | Vivado, the lead's board build |
| `zImage`, `zigmachine.dtb` | Linux 6.19.14 and its device tree | Buildroot 2026.02.3 (`build_planA.sh`) |
| `rootfs.cpio.uboot` | the initramfs: busybox, dropbear, `S99glass`, `/usr/bin/glass` (reads this layout) | the same Buildroot, glass of 6 Nov |
| `KESTREL/system.rv32` | firmware, machine, ROM, BARD: table 1.9 | `make -C fpga board-split` at the release's commit |
| `KESTREL/kos/desktop.rv32` | KOS's GEM desktop (the `gem` cart) | `split-cart`, the release's commit |
| `KESTREL/progs/`, `KESTREL/glass.cfg` | data disks' programs; the console's settings (defaults) | `glass_sd.py`; written by hand |
| `CARTS/<category>/demo-<tag>.zmd`, `CARTS/shelf.txt` | the shelf: every committed cart, wasm + board image | `split-cart` per cart, `glass_sd.py` |
| `HD/` | GEM's C: (a `README.TXT`) | |

Our own `BOOT.BIN` (U-Boot SPL, `BOOT.BIN.ours` + `u-boot.img`) is **not** in v1.2: it has not run
on a board yet, and a bad SPL can only be fixed by taking the card out. zeST's is the one every
KESTREL board has booted. Plan B (zeST's `uImage` and `rootfs.ub`) is not on the card either: with
a `zImage` on the card, `boot.scr` never uses it.

## 1. Install the toolchains

Run the doctor first. It lists every tool with its version and tells you how to install what is
missing:

```sh
kestrel-sdk-v1.2/zigmachine/tools/sdk_doctor.sh            # add --board to make the board tools required
```

| Tool | For | Ubuntu / Debian | Arch | macOS |
|---|---|---|---|---|
| zig **0.16.0** | everything | [ziglang.org](https://ziglang.org/download/#release-0.16.0) | same | same |
| python3 3.11+, make | everything | `apt install python3 make` | `pacman -S python make` | `brew install python make coreutils` |
| wabt 1.0.42 (wasm2c) | `make board` | `sdk_doctor.sh --fetch-wabt` | `pacman -S wabt` | `brew install wabt` |
| clang | `make board` | `apt install clang` | `pacman -S clang` | Xcode tools |
| uv | `make board` | [astral.sh/uv](https://docs.astral.sh/uv/) | `pacman -S uv` | `brew install uv` |
| riscv gcc | `make board` | `apt install gcc-riscv64-unknown-elf picolibc-riscv64-unknown-elf` | `pacman -S riscv64-elf-gcc riscv64-elf-newlib` | xPack `riscv-none-elf-gcc` |
| node 24 | only the SDK's own test | | | |

For the editor: VS Code with the Zig extension (`ziglang.vscode-zig`) and a ZLS build for Zig 0.16.
The template's `.vscode/` turns ZLS on and adds the four make commands as tasks.

### The riscv toolchain

The board's cart CPU (ZIGGY) is rv32imf: no compressed (C) and no atomic (A) instructions. The
board image of a cart links **no C library**: it is `-nostdlib`, and the system image gives it
`memcpy`, `floor` and the rest. All a cart needs from the toolchain is the compiler and libgcc's
helpers (soft double, 64-bit division). So any of these works:

- **Ubuntu's** `riscv64-unknown-elf-gcc` + picolibc: what the repository's own board builds use. It
  has an rv32imf/ilp32f libgcc, and the cart links it.
- **Arch's** `riscv64-elf-gcc` + newlib, or **xPack's** `riscv-none-elf-gcc`: no picolibc and no
  rv32imf/ilp32f multilib. The cart compiles against the gcc's own newlib headers, and links Zig's
  compiler_rt in place of libgcc. `zig build` makes it (`zig-out/rt/zrt.o`, rv32imf, ilp32f, no C),
  and `sdk/zrt_cart.sh` keeps libgcc's helpers only and checks there is no `.data` and no
  compressed instruction.

The Makefile picks whichever gcc is on `PATH` (`riscv64-unknown-elf-`, `riscv64-elf-`,
`riscv-none-elf-`) and says which headers and runtime it used. Proof that the choice does not
change the cart (4 Nov 2026, the template cart, gcc 16.2): the same gcc with newlib headers and
with picolibc's gives the same 223 functions, every one the same instructions. Only the order of
two forwarders in `zm_cart_rt.o` moves.

## 2. Your first build

```sh
tar xzf kestrel-sdk-v1.2.tar.gz && cd kestrel-sdk-v1.2
cp -R template mydemo && cd mydemo      # a sibling of zigmachine/: build.zig.zon finds it at ../zigmachine
make NAME=mydemo
```

`make` builds `zig-out/demo-mydemo.wasm`, packs it on a disk, puts both in the SDK's `docs/` and
serves the emulator. Open the address it prints:

- `http://localhost:3333/sealed.html?disk=demo-mydemo.zmd` boots like the machine: the POST, then
  your disk;
- `http://localhost:3333/sealed.html?demo=demo-mydemo.wasm` runs the cart straight away.

Click the page once for sound (browsers start audio on a gesture). Ctrl-C stops the server. Edit
`src/hello.zig`, `make` again, then reload the page with Ctrl+Shift+R.

Set `NAME` once at the top of the Makefile instead of typing it. A name is lower case, digits and
`_`, and it may not be one of the SDK's own carts (`make` refuses `stniccc`, say).

To keep your cart elsewhere, change the one path in `build.zig.zon`:

```zig
.kestrel = .{ .path = "../zigmachine" },   // relative to your directory
```

## 3. What a cart is

`src/hello.zig` is a scene: a struct `Demo` with `init`, `update` and `render`. The template shows
the four things a screen usually needs:

- **a plane**: `zigos.lfbs[0]`, made an overscan plane (400x280, the whole raster);
- **real rasters**: `zg.copper` rewrites palette entry 0 before every scanline. No pixel is drawn
  for a bar, and the copper's `.flicker` opens every border, so the bars run the full width as
  they do on an ST;
- **a scroller**: the 8x8 system font, one glyph at a time on a sine (`zg.fixtrig`);
- **music**: `zg.requestSong("sos.sndh")`, a file under `zigmachine/docs/music/`. Put your own SNDH
  there and request it by name. The board build packs every song the cart asks for.

A cart can also read files from the hard disk, C: (the card's `HD/` folder, see "The card"), and
from a FAT floppy in drive A, with TOS's GEMDOS calls: `const dos = @import("kos_gemdos").dos();`
then `dos.Fopen("C:\\PICTURES\\X.PI1", 0)`, `Fread`, `Fsfirst` / `Fsnext`, and on C: writes too:
`Fcreate` / `Fwrite` / `Fclose` (the file is saved whole at `Fclose`), `Fdelete`, `Frename`, `Dcreate`,
`Ddelete`, `Fattrib(path, 1, attr)` (`zigmachine/docs/KOS_GEMDOS.md`, `KOS_GEMDOS_WRITES.md`; such a cart
needs system table 1.10). On the page, `?c=gemdos-c.img` gives it a C: (writes stay in the page's memory).

A cart can play an **MP3** it reads: `zg.mp3Ctl(.start, 0)`, then `zg.mp3Feed(bytes)` 32 KiB at a time while
`fed - zg.mp3Status(.used)` stays under `zg.MP3_RING`, then `zg.mp3Ctl(.end, 0)`; the sound side (BARD) decodes it
onto the four Paula channels (`zigmachine/docs/ZIGOS_API.md` 8c; the MP3 PLAYER tools cart is the example). Such a
cart needs system table 1.11. On the page, `?c=mp3-c.img` gives it a C:\\MUSIC with test files.

Keep per-frame maths in integers or fixed point. The board's CPU has no FPU on every image, and
there float is soft-float, hundreds of cycles a divide.

The API: `zigmachine/docs/ZIGOS_API.md` (ZigOS), `zigmachine/docs/HW_API.md` (the registers),
`zigmachine/docs/TUTORIAL.md` (a first screen, step by step), and every screen in
`zigmachine/apps/zig/scenes/`. To add a module (an asset table, a second file), use the `scene`
module that `addCart` returns in `build.zig`.

## 4. Put it on a floppy

```sh
make floppy NAME=mydemo TITLE="MY DEMO" FILES="LOGO.RAW=art/logo.raw"
```

`zig-out/demo-mydemo.zmd` is a bootable disk with your cart ZX0-packed on it, plus any `FILES`
(read them with `zg.disk`). Drop it on the emulator page to boot it, or put it on the card.

## 5. Put it on the board

```sh
make board NAME=mydemo TITLE="MY DEMO" GROUP="MY GROUP" CATEGORY=demos
```

This runs the repository's own board pipeline on your cart, `make -C zigmachine/fpga split-cart`
with the flags of the v1.2 card (`ZM_AUDIO=snd ZM_FPU=1 ZM_ZMX=1`):

1. wasm2c translates the cart to C;
2. the cart runs natively once (clang) to find the songs it requests, and they are packed;
3. riscv gcc compiles it for ZIGGY: `zig-out/board/mydemo/cart.bin`, a lean cart for the card's
   `system.rv32`;
4. `sdk/card.py` writes `zig-out/sd/`: a copy of the release's card, plus your fat disk at
   `CARTS/<category>/demo-mydemo.zmd` (your `.zmd` with `cart.bin` in it) and its line in
   `CARTS/shelf.txt` (what the OSD shows). It checks the cart against the card's system
   table first. The card's layout (since 6 Nov 2026, docs/FPGA_GLASS.md "The SD card's layout"):
   the boot files at the root, the system in `KESTREL/` (`system.rv32`, KOS's desktop,
   `glass.cfg`), the shelf in `CARTS/`, and `HD/`, which is what GEM shows as C:. A card from
   before that (everything in `zigmachine/`) still boots; move it with
   `fpga/tools/sd_migrate_layout.sh` on the board before copying `zig-out/sd/` over it.

Copy the contents of `zig-out/sd/` onto the card's first (FAT32) partition. It is the whole
release card plus your cart, so a freshly formatted card works (the release's `INSTALL.md`). On a
card that already holds the release, the two files printed with their md5 are all that changed.
Then boot the board and pick your cart in the OSD menu (F12). Categories are the OSD's folders:
`demos`, `games`, `tools`, `tutorials`, `tests`.

No Verilator, no Vivado and no SoC file is involved: the board image of a cart needs only the
toolchains above.

## 6. The release (for the maintainer)

```sh
sdk/release.sh --version v1.2 --hw 1.16.0 --rev <sha> --out <dir> --card <a staged card>
```

`sdk/release.sh` takes the repository at a commit (`git archive`, so nothing untracked and no
`prototypes/`), the template pointed at `../zigmachine`, and a card staged by
`fpga/tools/glass_sd.py --system ...`. It refuses a card whose `system.rv32` serves another system
table than the commit's carts (`fpga/cycles/sys_abi.txt`), a card missing a boot file, `KESTREL/`'s
system or desktop, `CARTS/shelf.txt` or `HD/`, and a card holding a file that must never leave the
maintainer's machine (the TC TEST pictures, `local.xm`, `rollback/`, a `KESTREL/glass` override).
It writes `RELEASE.txt`, `card.md5`, `INSTALL.md`, `THIRD_PARTY.md` with zeST's licence, and the
tarball. A new bitstream or system image means a new release.

How v1.2's card was staged (6 Nov 2026): the system and **every committed cart** rebuilt from the
release's commit in a clean worktree (`make board-split`'s system, `split-cart ZM_ZMX=1` per cart,
`native-cart` for the three native carts), with the combo16 bitstream's `csr.json`. A clean
worktree has no `docs/music/local.xm` and no TC TEST pictures, so no cart can carry them. Then
`glass_sd.py --system ... --fw-dir ... --bit ...` without `--buildroot`, and plan A's `zImage`,
`zigmachine.dtb` and `boot.scr`, the layout's `rootfs.cpio.uboot` (its glass reads this layout),
`KESTREL/glass.cfg` (the defaults) and `HD/README.TXT` laid over it; the MANIFEST names each.

In this repository, `make` in `sdk/template` works too (its `build.zig.zon` points at `../..`). It
copies `demo-hello.*` into `docs/` like any SDK cart: gitignored, but `tools/mkdisks.sh` and
`apps/disk_check.mjs` then see one more disk. `make clean` takes the copies out again.

## How it works

A cart outside the repository has its own `build.zig`, which depends on the repository as a Zig
package (a path dependency in `build.zig.zon`) and calls `addCart` (`sdk/build_cart.zig`, exported
by the repository's `build.zig`). `addCart` builds the cart the way the cart matrix does
(`apps/zig/demo_main.zig` around the scene, the same named modules, the same memory layout), but
only that cart. Your directory has a real `build.zig`, so ZLS resolves `@import("zigos")`, and
nothing in the repository is edited to add a cart (`decisions.md`, 2026-11-04).

The gate builds the template exactly this way, from a temporary directory outside the repository
(`apps/sdk_check.mjs`). It checks that the cart runs, moves, has real rasters and requests a song
that exists, so a change to the repository that breaks outside carts fails the gate.

Not tested yet: macOS (the fpga Makefiles use GNU `truncate` and `stat`: install coreutils and GNU
make, and put their gnubin directories first on `PATH`), the release card on a board that never had
one (every file on it has booted the lead's board, but never this exact set from a blank card), and
a cart linked with Zig's compiler_rt running on the board itself.
