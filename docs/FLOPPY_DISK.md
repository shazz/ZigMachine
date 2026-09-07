# ZigMachine Disk — design

**Status:** MVP working — `tools/mkdisk.py` packs a cart into a `.zmd`, and
`sealed.html?disk=X.zmd` verifies the `$1234` boot sector and boots the cart (phases
B–D of the plan). Still to do: FAT/multi-file, disk-browser menu, block streaming.
Replaces the interim "one big `demo.wasm` links every scene" approach, which
overflows the 2 MiB demo window.

A simplified, ST-*flavored* disk: an **executable boot block** (the part worth
keeping from the ST floppy) on top of a **flat, linear-block** layout — no
tracks/sides, no FAT cluster chains. Real floppy fidelity isn't the goal; the boot
block + block streaming are.

## Why

A scene `@embedFile`s its assets, so linking many scenes into one `demo.wasm` blows
the demo window (~5.7 MB needed vs 2 MiB). Give the machine a **disk drive**: a scene
and its assets live on a disk image, and the machine **streams blocks into RAM on
demand** instead of baking assets into the binary. This unlocks:

- **All scenes, no link bloat** — each demo is a file/disk; the menu is a disk browser.
- **Block streaming** — pull a 32 KB screen a block at a time when the effect needs it.
- **Multi-file disks, save/load, "insert disk" UX**.
- **Executable boot block** — read block 0, verify it's a valid bootable ZigMachine
  disk, run its boot file.

## Format (fixed header, linear 512-byte blocks, contiguous files)

Three regions. Everything is addressed by **linear 512-byte block** (block N = byte
`N*512`); no track/sector/side. Files are stored **contiguously**, so a file byte is
just `file.start + offset` — the FAT is a flat table, not cluster chains.

```
[$0000 .. $0200)   Boot sector      512 B   magic + $1234 checksum + boot pointer
[$0200 .. $0600)   Descriptor + FAT  1 KB   disk metadata + the file table
[$0600 .. )        Data                     contiguous file contents
```

### Boot sector — `$0000`, 512 B (executable)

| Off | Sz | Field | Notes |
|-----|----|----|----|
| `$000` | 6 | magic `"ZMDISK"` | identifies a ZigMachine disk |
| `$006` | 2 | format version | 1 |
| `$008` | 2 | block size | 512 (fixed, v1) |
| `$00A` | 4 | total blocks | image size / 512 |
| `$00E` | 4 | **boot block** | block where the boot cart's data starts |
| `$012` | 4 | **boot length** | boot cart size in bytes |
| `$016` | … | reserved | zero |
| `$1FE` | 2 | checksum word (big-endian) | tunes the 256 BE 16-bit words → `$1234` |

The boot sector **points directly at the boot cart** (`boot block` + `boot length`),
so the simplest disk needs no FAT at all — see below. A multi-file disk still boots
from this pointer and uses the FAT for its other (asset) files.

**Executable-boot rule (kept from the ST):** the sum of all 256 big-endian 16-bit
words of the boot sector determines the disk kind — `$1234` = **bootable** (run this
disk's cart), `$0000` = a **data disk** (not bootable: the machine boots the OS —
GEM — instead, with the disk mounted so GEM can open its app + read its files). The
last word is the adjustment; `mkdisk` writes it (`--no-boot` for a data disk), and
the machine verifies it before booting — homage + a real integrity/kind check. This
is how the **ST Replay** disk works: a non-bootable data disk whose FAT carries the
app + a `SAMPLE.RAW`; inserting it brings up GEM, which runs ST Replay reading the
sample off the disk.

**Simplest disk (our demo carts):** boot sector → 1 KB descriptor (FAT empty, file
count 0) → the cart wasm as one contiguous data run. The machine reads block 0, checks
`$1234`, and loads `boot length` bytes from `boot block`. No FAT walk, no directory.

### Descriptor + FAT — `$0200`, 1 KB

First a fixed **descriptor** (metadata shown in the disk browser), then the **FAT**
(flat file table) filling the rest of the 1 KB:

| Off | Sz | Field |
|-----|----|----|
| `$200` | 64 | title |
| `$240` | 32 | author |
| `$260` | 128 | description |
| `$2E0` | 4 | date (YYYYMMDD) |
| `$2E4` | 2 | file count |
| `$2E6` | 26 | reserved |
| `$300` | 768 | **FAT**: up to 24 × 32-byte file entries |

**File entry (32 B):** `name[16]` (e.g. `"UNION.WSM"`, NUL-padded) · `start` u32
(absolute byte offset in the image) · `length` u32 · `type` u8 (0 wasm cart · 1 raw
asset · 2 text) · `reserved[7]`. Contiguous → no chains; the packer writes each file
once, so there's no fragmentation.

(24 files fit the fixed 1 KB; if a disk ever needs more, bump the header region — but
one cart + its assets is well under 24.)

## Drive ABI (block reads)

A sealed **disk register block** (like the blitter), serviced by the host:

- `DISK_BLOCK` (u32) — linear block to read.
- `DISK_DMA` (u32) — RAM address to land the 512 bytes.
- `DISK_CMD` = READ · `DISK_STATUS` = BUSY/DONE/ERR.
- Host copies one 512-byte block from the mounted image into shared RAM — the machine
  never fetches; it asks the drive, exactly like VRAM/PFB.

ZigOS `fs/` wraps it: `mount(image)`, `find("NAME.WSM") -> {block,len}`,
`readBlock(n)` — effects request bytes; the lib streams blocks underneath.

## Boot flow

1. Loader mounts `disk.zmd` (fetch bytes once).
2. Host reads block 0, verifies `magic` + `$1234`, parses the descriptor.
3. Loads the **boot file** (a cart wasm, contiguous blocks) and instantiates it over the
   shared memory (the cartridge swap); runs it.
4. The scene streams its own assets from the same disk by name, block by block.
5. ESC / eject → back to the disk browser (menu).

## Staged plan

- **A. Spec** — this doc.
- **B. `mkdisk`** (`tools/mkdisk.py`) — pack `boot.wasm` + assets + descriptor into a
  `.zmd` image (boot block, directory, contiguous data, `$1234` checksum).
- **C. Host drive** — loader mounts an image and services block reads into shared RAM.
- **D. Boot-from-disk** — `?disk=union_intro.zmd` boots that disk's cart (proves the
  path); the menu becomes a disk browser reading each disk's boot descriptor.
- **E. Streaming assets** — port one asset-heavy scene (e.g. `tex`) to stream its screens
  off the disk instead of `@embedFile`, shrinking its wasm — the payoff demonstrated.

## Notes

- The `$1234` checksum uses big-endian 16-bit words (the one ST-endian quirk we keep);
  everything else is little-endian.
- Keep block size 512 in v1 (bootsector homage + simple math); revisit if useful.
- A `.zmd` is trivially inspectable — a hex dump shows the descriptor in clear.

---

# Format v2 — the boot sector *is* executable (a wasm chainloader)

**Status: designing (2026-09-07).** v1's boot sector is *metadata that points at the
cart* — the host loads the cart. v2 makes the boot sector **the boot**, ST-style: it is
a real, tiny **wasm module** that the machine runs first, and it **chainloads** the cart
itself. The `$1234` checksum keeps its exact old meaning — it just now marks *executable
code* rather than a bootable descriptor. This moves boot logic **out of the host JS**
(the loader shrinks to: read block 0, checksum, instantiate, run) and into the disk.

## Layout (512-byte streaming blocks; 1 KB = 2-block header regions)

```
region            bytes        blocks   contents
BOOT SECTOR       [0K .. 1K)   0..1     executable wasm module ($1234 ⇒ run it)
DESCRIPTOR        [1K .. 2K)   2..3     zigcart BPB (metadata + cart pointer)
FAT               [2K .. 3K)   4..5     flat file table (24 × 32 B, as v1)
DATA              [3K .. )     6..      cart wasm + files, contiguous
```

Streaming granularity stays **512 B** (drive ABI unchanged); only the header is 1 KB per
region. Cart data starts at **block 6** (byte `$0C00`).

### Boot sector — `[0K..1K)`, an executable wasm module

The 1 KB **is a wasm binary** (`\0asm\01\00\00\00…`), not a struct. It is a minimal
"boot program" cart: the host instantiates it against the sealed machine and drives it
through the **normal render loop**, so it only needs the loop's mandatory demo contract
plus a chainload signal:

| Export | Sig | Role |
|--------|-----|------|
| `boot()` | `() -> ()` | one-shot setup: draw its screen, arm audio |
| `frame(dt)` | `(f32) -> ()` | per-frame (animate, count down the hold) |
| `isPlaneEnabled(i)` | `(i32) -> i32` | which planes the compositor shows |
| `pollCartRequest()` | `() -> i32` | returns **2 = chainload this disk's cart** (0 = keep running) |

Imports it may use: `memory`, `hwVideoBase` (find the video region → draw + set palette),
and the audio ABI for a tone. It draws by writing the shared video region directly (same
ABI a normal cart uses via ZigOS) — no ZigOS needed; a boot program is deliberately bare.

**`$1234` over a wasm module.** A wasm binary's bytes are fixed by the compiler, so the
checksum can't be tuned by editing code. Instead the boot program carries a **wasm custom
section** named `zmck` holding a 2-byte adjustment word; `mkdisk` tunes *that* word so the
1 KB's 512 big-endian words sum to `$1234`. Custom sections are ignored at execution, so
the wasm still runs. `$0000` (or any non-`$1234`) ⇒ **not executable** ⇒ POST → GEM (data
disk), exactly as v1.

### Descriptor — `[1K..2K)`

Same fields as v1's descriptor **plus** the cart pointer that used to live in the boot
sector (since the boot sector is now code):

| Off | Sz | Field |
|-----|----|----|
| `$400` | 6 | magic `"ZMDISK"` |
| `$406` | 2 | format version (**2**) |
| `$408` | 4 | **cart block** (first block of the cart wasm in DATA; ≥ 6) |
| `$40C` | 4 | **cart length** (bytes) |
| `$410` | 64 | title |
| `$450` | 32 | author |
| `$470` | 128 | description |
| `$4F0` | 4 | date (YYYYMMDD) |
| `$4F4` | 2 | file count |
| `$4F6` | … | reserved |

FAT (`[2K..3K)`) is v1's table verbatim (24 × 32 B entries), addressing files in DATA.

## Boot flow (v2)

1. **Host** mounts the `.zmd`, reads the 1 KB boot sector, sums its 512 BE words.
2. `== $1234` **and** `\0asm` magic → **executable**: instantiate the boot sector as the
   `demo` module (wired to the machine + a `chainload` import), `hwInit()`, `boot()`, and
   run it in the normal render loop.
3. The boot program shows its intro; when done it returns **2** from `pollCartRequest()`.
4. Host **chainloads**: reads the descriptor's `cart block`/`cart length`, instantiates
   those bytes as the new `demo`, `hwInit()`, `boot()`, and the loop continues on the cart.
5. `!= $1234` → **data disk**: POST → GEM (disk mounted for GEM to open), as v1.

The host thus keeps exactly two boot primitives — *instantiate block 0* and *chainload the
descriptor's cart* — and the disk owns everything else. `chainload` reuses the existing
`swapCart` machinery (a new `req = 2` = "this disk's cart" alongside `req = 1` = named
floppy).

## Staged build (v2)

- **1. Spec** — this section.
- **2. Host** — `mountDiskV2()` (parse the 4 regions), instantiate an executable boot
  sector, `pollCartRequest()==2 → chainloadCart()`. Loader stays thin.
- **3. `mkdisk.py` v2** — assemble boot-wasm + descriptor + FAT + data; inject the `zmck`
  adjustment word so the boot sector sums to `$1234`.
- **4. Boot-program build target** — a tiny `boot()`/`frame()`/`isPlaneEnabled()`/
  `pollCartRequest()` wasm (hand-written WAT or a bare Zig cart), ≤ 1 KB, with a `zmck`
  custom section for the checksum.
- **5. Flagship demo** — the **"No virus in ZigMachine"** boot intro (inverse-video
  message + a low YM2149 tone, hold ~2 s, then chainload) — the ST-antivirus-bootsector
  homage, proving the whole path in-browser.

## Writing a boot-sector program

A boot-sector program is a **bare wasm module** — *no ZigOS, no ROM* — that pokes the
sealed video ABI directly and stays under **1015 bytes** (the 1 KB sector minus the 9-byte
`zmck` checksum section). It participates in the machine's normal render loop, so it only
implements this contract:

| Export | Sig | Role |
|--------|-----|------|
| `boot()` | `() -> ()` | one-shot: draw the screen, arm audio |
| `frame(dt)` | `(f32) -> ()` | per-frame (animate / count the hold) |
| `isPlaneEnabled(i)` | `(i32) -> i32` | which planes the compositor shows |
| `pollCartRequest()` | `() -> i32` | return **2** to chainload the disk's cart (0 = keep running) |

It imports only `memory` + `hwVideoBase()` (the machine hands it the region base — the same
import ZigOS uses) and writes the video registers / a plane framebuffer itself.

**Build:** add the program's name to the `boot_progs` list in `build.zig` and drop the
source at `apps/zig/boot/<name>.zig` — it builds to `docs/boot-<name>.wasm` (bare: imports
only `hardware`). **Pack:** `python3 tools/mkdisk.py <cart>.wasm --boot-wasm
docs/boot-<name>.wasm -o docs/<disk>.zmd` — `mkdisk` appends the `zmck` custom section and
tunes it so the sector sums to `$1234`. **Run:** `sealed.html?disk=<disk>.zmd`.

**Example** — `apps/zig/boot/novirus.zig`, the "No virus in ZigMachine" intro (full white
= inverse video, hold ~2 s, chainload). Abridged (full 8×8 font in the source):

```zig
const hw = @import("hardware"); // ABI offsets only — no code
extern fn hwVideoBase() i32;    // the machine tells us where its region lives

const W: usize = hw.WIDTH; // 320
var frame_count: u32 = 0;

inline fn regBase() usize { return @intCast(hwVideoBase()); }
inline fn w32(off: usize, v: u32) void { @as(*volatile u32, @ptrFromInt(regBase() + off)).* = v; }
inline fn r32(off: usize) u32 { return @as(*volatile u32, @ptrFromInt(regBase() + off)).*; }
inline fn fbPtr() [*]u8 { return @ptrFromInt(regBase() + @as(usize, r32(hw.REG_FB_BASE))); } // plane 0

// One-shot: white ground everywhere (borders via REG_BACKGROUND + plane paper),
// black message on plane 0 → inverse video.
export fn boot() void {
    frame_count = 0;
    w32(hw.REG_BACKGROUND, 0xFFFFFFFF);        // borders + visible = white
    w32(hw.OFF_PAL + 0 * 4, 0xFFFFFFFF);       // plane idx 0 = white paper (compositor writes every pixel)
    w32(hw.OFF_PAL + 1 * 4, 0xFF000000);       // plane idx 1 = black ink
    const fb = fbPtr();
    var i: usize = 0;
    while (i < W * hw.HEIGHT) : (i += 1) fb[i] = 0;
    drawText(fb, "NO VIRUS IN ZIGMACHINE");     // 8×8 glyph blit — see source
}

export fn frame(dt: f32) void { _ = dt; frame_count +%= 1; }
export fn isPlaneEnabled(plane: i32) i32 { return if (plane == 0) 1 else 0; }
export fn pollCartRequest() i32 { return if (frame_count >= 120) 2 else 0; } // ~2 s → chainload
```

Gotchas worth knowing:
- **The compositor writes every plane pixel** (no alpha skip), so to show the background
  through a plane you paint the plane's index-0 the same colour, rather than relying on a
  transparent index.
- After `hwInit()` plane 0 is already a normal 320×200 plane with its default framebuffer
  base — read `REG_FB_BASE` (as above) rather than hard-coding the address.
- Keep it small: check `ls -l docs/boot-<name>.wasm` ≤ 1015 B; `mkdisk` prints the headroom.
