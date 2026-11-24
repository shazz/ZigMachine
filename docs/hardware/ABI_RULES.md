# The cart ABI is the contract (two boards, one cart)

KESTREL (Zynq 7010) and PEREGRINE (Zynq 7020) run the SAME carts. A cart (`.wasm`, `.zmd`) is board-agnostic:
one file on the site, one file on either SD card. What differs between boards is which OPTIONAL units exist,
and a cart learns that by asking (the capability word), never by guessing from the host.

## 1. The two numbers

| Number | Where | Says |
|---|---|---|
| System table version | `fpga/cycles/sys_abi.txt` (`version 1.28`), checked by `fpga/tools/sys_abi.py` | which `env.*` imports a lean cart can bind to; a system older than a cart's table refuses it |
| HW API version | `machine/sdk/memmap.zig` `ZM_HW_VERSION` (`hwVersion()`), `docs/hardware/HW_API.md` | the machine's registers and entry points |

Both are shared by every board: a board is not a version. They are the single source of truth.

## 2. Rules

1. **Additive only within a major.** Within major 1 you may append (a table entry, a register in a free slot, a
   capability bit, an optional cart export). You may not move, resize, renumber, repurpose or remove anything.
   A change that does is a MAJOR bump, and every cart is rebuilt (see "register-offset overlaps are silent").
2. **Optional things are optional on both sides.** The model is R83's `input2` / `inputRelease2`: optional cart
   exports looked up by name. A cart without them works; a system without a use for them ignores them. No bump.
3. **Optional hardware is asked for.** A cart that uses a unit not every board has reads the capability word
   (`zg.caps.has(.astro)`) and takes a fallback when the bit is clear. It never branches on "browser" or "board".
4. **A bit means one thing, forever.** Bits are never moved, reused or redefined. The next bit is the next
   free number. A bit a machine does not know reads 0 (and `hwSetCaps` drops it), so "unknown" is "absent".
5. **A fallback must be correct, not just present.** The gate runs the carts that ask in a "capabilities off"
   run (`apps/harness/caps_check.mjs`), so a fallback that rots fails the build.
6. **Deprecation.** A bit or entry is never deleted inside a major. Mark it deprecated in this table and in
   HW_API.md, keep answering it (a unit that went away: the bit reads 0, the fallback runs), and drop it only at
   the next major, with a rebuild of every cart.

## 3. The capability word

`env.hwCaps() -> u32` (system table 1.28, HW 1.19.0, a machine export). Zig: `zg.caps.word()` and
`zg.caps.has(.astro)` (`libs/zig/caps.zig`; the bit table is `machine/sdk/caps.zig`). C and Rust carts import
`env.hwCaps` (`unsigned hwCaps(void)`) as `apps/ports/syncterm/kestrel_desk.c` imports `hwDeskAvailable`; the C/Rust
mirrors (`apps/c`, `apps/rust`) carry only memory helpers, so no header changes.

| Bit | Name | Set when | Fallback when clear |
|---|---|---|---|
| 0 | `astro` | ASTROLABE (f64) is served by hardware: the board's ARM. The browser and native host set it (the machine stands in at no round trip) | `hwAstro` still answers from ZIGGY's soft f64, slowly: do the f64 in the cart (`copro/soft64.zig`) |
| 1 | `desk` | the 640x480 desk mode exists (= `hwDeskAvailable()`; one truth, the machine keeps them equal) | stay in low / medium |
| 2 | `chisel_v2` | CHISEL v2 ops: QUEUE, AFFINE, MAP, mirror, collision, area fill (HW 1.11) | draw with the CPU or v1 blits |
| 3 | `bard_jobs` | a coprocessor serves `hostBardJob` (BARD on the board) | `zg.bard.job` serves the job in the cart |
| 4 | `ziggy_fpu` | ZIGGY has an f32 FPU | integer / fixed point (the rule for per-frame code anyway) |
| 5 | `joy2` | a second pad reaches `input2` / `inputRelease2` | player 2 is merged into player 1 |

Bits 6..31 are free.

### Who sets it

- **Browser** (`site/js/sealed-loader.js`): the machine's default is every defined bit (all units are emulated
  in software). `?caps=<hex>` calls `hwSetCaps`; `?caps=0` is "capabilities off".
- **Native host** (`fpga/host`): same default; `--caps <hex>` (`host_caps`, applied in `host_boot_machine`).
- **Harnesses**: `machine.hwSetCaps(0)` after instantiating the machine (`copro_boot.mjs`, `caps_check.mjs`).
- **Board**: firmware declares what its bitstream has, once, before the cart boots, exactly as it does for
  `hwSetDeskAvailable` (`fpga/cycles/bdesk.c`). NOT DONE YET (needs a firmware rebuild, no RTL), see section 5.

`hwSetCaps` is a host call, not part of the cart's table: a cart can read the word, never write it.

## 4. How to add a bit

1. Append the next number to `Cap` in `machine/sdk/caps.zig` and widen `ALL`.
2. Add a row to the table above (name, meaning, fallback). `apps/harness/caps_check.mjs` fails if they disagree.
3. Make every host that has the unit set it: the machine's default covers the browser and native host; a board
   needs the firmware line in section 5.
4. Give the carts that use the unit a fallback and a "capabilities off" check. A bit nobody asks about needs no
   bump; a new `env.*` entry bumps the table minor (`python3 fpga/tools/sys_abi.py --update`).

## 5. What the board still needs (no RTL)

- A firmware call in `fpga/cycles/bsys.c` `host_boot_machine` (next to `hwSetRomHigh`), a new `fpga/cycles/bcaps.c`
  next to `bdesk.c`: `w2c_machine_hwSetCaps(&e->machine, word)`, with `word` built from what the board has:
  `astro` = the ARM worker is live (`bastro.c`), `desk` is already `hwSetDeskAvailable` from `ZMV_BIT(DESK)`,
  `chisel_v2` = the bitstream's CHISEL status bit, `bard_jobs` = BARD running, `ziggy_fpu` = the FPU status
  bit, `joy2` = glass's second pad (`fpga/glass/src/pads.zig`). Until then the board reports the machine's
  default (every bit), which over-reports on a bitstream without a unit: do this before PEREGRINE's first cart run.
- No PL register is required: the word lives in the machine, set by firmware from status bits that exist.
  A bitstream whose STATUS register lacks a bit for a unit (FPU, CHISEL v2) needs one, an RTL change for the
  board owner, listed in `docs/project/ROADMAP.md` R41.
