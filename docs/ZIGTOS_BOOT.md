# ZigTOS boot: KESTREL starts like an ST

Status: **design, 25 Oct 2026**, nothing built yet. Matt's brief: at reset the boot program
initialises KESTREL, looks for a cart, checks its boot sector and runs it, or else loads GEM.
"It doesn't have to be exactly like the TOS", but it is the foundation for making ZigGEM a
real small OS in ROM.

Reference: how TOS boots, step by step:
https://www.retrovirology.ca/pages/HowAtariBoots-en.html (the step numbers below are its).

## 1. What TOS does at reset

Condensed to what matters for us:

| # | TOS | Why it matters |
|---|---|---|
| 1-2 | reset vector at `$0`/`$4`, supervisor mode, `RESET` | the ROM owns the machine before anything else runs |
| 3 | a **diagnostic cartridge** is run first if present | a service hook that runs before the OS |
| 6 | **warm or cold**: `memvalid`/`memval2`/`memval3` all valid → warm; memory kept | the reset button differs from power-on |
| 7 | `resvalid` = `$31415926` → jump to `resvector` | a program survives a warm reset (resident tools, viruses) |
| 8-10 | memory sized and (cold only) cleared, palette, screen at PHYSTOP − 32 KB | the ROM sets the machine up |
| 11-15 | system variables, cookie jar, vectors, BIOS, MFP, IKBD | the OS's own state and drivers |
| 16/18/20 | **application cartridges**, types 2, 0, 1, at three points of the init | the ROM port boots before the floppy |
| 21 | Fuji logo + memory test (later TOS) | the POST screen |
| 22 | `hdv_boot`: the floppy's boot sector is loaded, and run if it sums to `$1234` | a disk can take over the machine |
| 23-24 | DMA / IDE hard disk boot sectors | later media |
| 25 | reset-resident programs on `$200` boundaries | the other survival hook |
| 26-27 | GEM, then every `\AUTO\*.PRG` of the boot disk | the disk configures the OS |
| 28 | `cmdload` → `\COMMAND.PRG` instead of the desktop | a shell instead of the GUI |
| 29 | if the AES quits, reset and start again | the OS is the loop that never ends |

DESKTOP.INF (the desktop's saved state on the boot disk) and desk accessories (.ACC) are
read by the desktop at step 26.

## 2. What KESTREL does today

**The board.** The Zynq's BootROM, FSBL and U-Boot load the bitstream, then Linux, which
starts `glass` (ZWINDOW, docs/FPGA_GLASS.md "Boot flow"). glass shows the OSD shelf over a
cart CPU (ZIGGY) **held in reset**: nothing runs until a disk is picked. Picking one loads
`system.rv32` (machine + ROM + firmware), the disk's lean cart and the disk into DDR, and
releases ZIGGY. Then the firmware does the ST-like part:

- an executable 1 KB wasm boot sector (sum `$1234`) runs sandboxed (`cycles/bbootsec.c`,
  sysinfo's "No virus in ZigMachine");
- a **bootable** disk runs its cart;
- a **data** disk runs GEM (the `gem` cart, `OS_CART`) with the disk in drive A. A program
  double-clicked in GEM is request 3, a quit is request 4 back to GEM ("Programs off a
  data disk").

R (cold) and W (warm) reset exist, warm with its own `ZMME` mark and `WARM_LOST`
("Cold and warm reset").

**The browser** (`docs/sealed-loader.js`): machine → `rom.wasm` (the ROM chip: GEM and the
desktop, `rom/gem/`) → the cart. The POST screen (`machine/boot.zig`) is linked into every
cart and shown before it unless `skipBoot()`. The page's menu is itself a cart.

**So all the pieces exist, but the ARM menu is in charge and GEM is one cart that data disks
carry.** On an ST the ROM is in charge and a disk is something it finds.

## 3. The ZigTOS boot sequence

ZigTOS = the system image (`system.rv32` on the board, machine + `rom.wasm` in the browser)
with a **boot program** in it. Power-on and every reset run this, in order:

| Stage | ZigTOS | TOS # |
|---|---|---|
| 0 | glass starts ZIGGY at once; the OSD stays closed | 1-2 |
| 1 | **cold or warm**: the `ZMME` mark decides (exists). Cold clears the cart RAM and the machine arena | 6, 8-10 |
| 2 | (v3) **resident hook**: a warm boot with a valid `resvalid`-style mark runs the resident routine first | 7, 25 |
| 3 | **hardware init**: video, FRESCO, CHISEL, BARD and the sound path, the drive, input; system variables (§5) | 11-15 |
| 4 | **POST screen**: logo, ZigTOS version, memory count (the `machine/boot.zig` look, moved into the ROM) | 21 |
| 5 | (v2) **diagnostic cartridge**: if one is fitted, run it | 3 |
| 6 | (v2) **application cartridge**: if one is fitted, run it | 16-20 |
| 7 | **drive A**: read the disk's boot sector. Executable (`$1234`) → run it sandboxed (exists) | 22 |
| 8 | **bootable disk** → run its cart. Done | 22 |
| 9 | data disk or empty drive → **GEM** | 26 |
| 10 | (v2) `\AUTO\*` programs of the data disk run, in FAT order | 27 |
| 11 | (v2) `COMMAND.WSM` on the disk → that shell instead of the desktop | 28 |
| 12 | the **desktop**, DESKTOP.INF read from drive A if present (`rom/gem/desktop/deskinf.zig` exists) | 26 |
| 13 | a program that quits returns to the desktop (request 4, exists); quitting the desktop re-runs stage 0 | 29 |

A bootable disk's cart never "returns": it ends with a reset, as on an ST. Carts that
already offer a way out (the demo menus, the Union doors) keep it through the existing
requests.

## 4. The pieces

### 4.1 The disk drive: "inserted", not "run"

Today picking a disk on the OSD means "run this cart". In ZigTOS the OSD shelf becomes the
**floppy drive**: Insert puts a disk in drive A, Eject removes it. Nothing runs by itself
then, exactly as on an ST: the running program sees a media change, and the next reset
boots from the disk.

- glass keeps `drive_a=<file>` in `glass.cfg` (exists: `config.zig`), so the disk is still
  in the drive after a power cycle.
- **Insert while GEM runs**: the disk goes into DDR where the drive ABI reads it
  ("The disk in DDR") and the cart's `insertDisk(1)` export is called (exists for GEM).
  GEM re-reads the listing: no reset, as the ST desktop's media change.
- **Insert while a cart runs**: the same `insertDisk(1)`; a cart that ignores it keeps
  running. Most demos ignore it, as on the ST.
- A one-key shortcut keeps today's speed: **Insert + reset** (Enter on the shelf), which is
  what a demoscener did with the reset button.

### 4.2 GEM moves into the ROM

The desktop code is already in `rom.wasm` (`rom/gem/desktop/`); only its host cart, `gem`
(`OS_CART`), rides along on each data disk's fat disk. In ZigTOS the boot program starts the
desktop itself: no `gem` cart on any disk, and a data disk becomes just files. The fat disk
then carries only programs (`progs/`), which also shrinks the card.

### 4.3 The boot program

One small module in the system image, the same source for the browser and the board (Zig,
`rom/boot/`), driving stages 1-13. It calls the existing pieces: the boot-sector sandbox
(`bbootsec`), the cart loader (requests 1-4), the desktop's entry point. It owns the POST
screen, so carts stop linking `machine/boot.zig` (the seal's open item in that file's
header).

### 4.4 Cartridges (v2)

KESTREL has no ROM port; a cartridge is a disk file glass places in a **cartridge slot**:
`cart=<file>` in `glass.cfg`, Insert/Eject on the OSD's own Cartridge line.

- A **diagnostic** cartridge (a flag in its descriptor) runs at stage 5, before any init the
  OS does beyond the hardware. First users: sysinfo's hardware tests and the bench cart, so
  the board can self-test at power-on without the shelf.
- An **application** cartridge runs at stage 6 and wins over drive A.

### 4.5 AUTO and COMMAND (v2)

A data disk's FAT gets an `AUTO` convention: a type-0 file named `AUTO.<n>.WSM` (the FAT is
flat: no folders yet), run in order before the desktop, each one returning with request 4.
`COMMAND.WSM` replaces the desktop. Both are plain programs over the existing request path.

### 4.6 Resident programs (v3)

The ST's survival hooks (`resvector`, programs on `$200` boundaries) are how resident tools
and boot viruses lived. ZigTOS can offer a **declared** version: a program registers a
resident routine through the ROM (not by writing a magic into low memory), the warm boot
runs it in the boot-sector sandbox. Faithful in spirit, impossible to abuse beyond the
sandbox. Last, and only if a cart wants it.

## 5. System variables

TOS keeps its state at fixed low addresses (`_bootdev`, `memvalid`, `hz_200`, `_sysbase`).
ZigTOS gets a small, versioned **system variables block** at a fixed place in the ROM's RAM
window, read through a ROM export:

| Variable | Meaning |
|---|---|
| `boot_kind` | cold / warm |
| `boot_dev` | what booted: cartridge, drive A, desktop |
| `zigtos_version` | the ROM's version (the sys table's) |
| `ram_total`, `ram_free` | what the POST counted (`hwRamFree` exists) |
| `frames` | a frame counter since reset (the ST's `_frclock`) |
| `drive_a`, `cart_slot` | present / empty, media-change count |

GEM's About box, sysinfo and the OSD read the same values.

## 6. The OSD's new role

The OSD stops being the launcher and becomes the console's **front panel**: power and reset
(R cold, W warm), the floppy drive and the cartridge slot (Insert / Eject), volume, the F11
fps line, the frame-budget page and the debug page. The shelf list stays: it is the box of
disks next to the drive.

## 7. The browser

`sealed.html` follows the same stages: power on → POST → drive A → cart or desktop. The
page's disk picker becomes the drive (insert / eject), `?disk=X.zmd` keeps meaning "insert X
and reset". Today's "boot the menu cart" becomes "the desktop with the menu disk inserted".

## 8. Phases

| Version | What | Visible result |
|---|---|---|
| **v1** | stages 0-1, 3-4, 7-9, 12-13; GEM in the ROM (§4.2); the drive as insert/eject (§4.1); `glass.cfg drive_a=`; the system variables block (§5); browser parity (§7) | power on → POST → the disk in drive A boots, or the desktop |
| **v2** | cartridge slot with diagnostic + application cartridges (§4.4); AUTO and COMMAND (§4.5) | the board self-tests at power-on; a disk configures the OS |
| **v3** | resident programs (§4.6); hard disk C: from SD folders (roadmap idea); desk accessories | the ROM is a small real OS |

## 9. What v1 changes, and what it doesn't

- **No RTL change.** Everything is firmware, glass and the ROM: ZIGGY already boots the
  system image first, and the cart loader, boot-sector sandbox and requests exist.
- **The sys table ABI** gets the boot program's and the variables' entries: a minor bump
  for appended exports (`tools/sys_abi.py`), so today's carts keep running.
- **Lean carts are unchanged.** A bootable disk boots exactly as now, one stage later.
- **Data disks lose their `gem` cart** (smaller fat disks); `glass_shelf.py` stops adding it.
- **The menu carts** (`demo.zmd`, the Union doors) stay carts. Whether the shelf's default
  disk should be the menu or nothing (the desktop) is a choice for Matt.

## 10. How it is proved

The same way the existing pieces are: the native host and `scene_hash.mjs` run the boot
sequence with a given drive A (bootable, data, executable boot sector, empty) and must agree
frame for frame; glass's state machine for insert/eject/reset is tested against the
simulated glass (`app_request_test.zig`'s style); one board-SoC sim of power-on → POST →
desktop (≤ 6 frames after boot); then the board.

## 11. Open questions for Matt

1. With no disk in drive A at power-on: the desktop (the ST answer) or the menu disk?
2. Should the POST screen be skippable (a key, or a `glass.cfg` flag) for fast demo work?
3. The cartridge slot in v2: wanted, or drive A only?
