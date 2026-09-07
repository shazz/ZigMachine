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
