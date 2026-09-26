# Memory management

A cart gets **2 MiB of RAM**, the window `[0x100000, 0x300000)`, and nothing
traps when it runs out: one byte past the top is the video region, so an
overrun corrupts VRAM and the machine dies later, somewhere else. This chapter
is how to spend that window: what is already in it, what a big buffer really
costs, and the machine's allocator (HW 1.7.0).

## What lives in the cart window

Bottom to top, as the linker lays out a cart (`--global-base=0x100000`):

- **static data**: every `@embedFile` asset, every constant table, every
  module-scope variable. ZigOS's own state is here too: the `LogicalFB`s,
  fonts, palettes, the disk and song bridges.
- **the stack**, above the data. Zig and C link it there by default; Rust carts
  are linked `--no-stack-first` for the same layout (`apps/rust/build.sh`). Stack
  first, rustc's default, grew the stack down from `0x100000` into the machine's
  RAM and left the cart's zeroed statics out of the measured high-water.
- **free RAM**, up to the video region at `0x300000`.

The code is not in the window: wasm keeps functions outside linear memory. GEM
is not in it either: since Phase 2 the ROM chip has its own 2 MiB window above
the video region, `[0x500000, 0x700000)`.

The host measures where the data and stack end (the **high-water**) when it
loads the cart (`docs/wasm_hiwater.js`) and declares it to the machine
(`hwSetCartHigh`). Everything below is arithmetic on that number.

```zig
hwRamBase()  // 0x100000
hwRamTop()   // 0x300000, the video region
hwRamUsed()  // statics + stack + the RAM arena
hwRamFree()  // hwRamTop() - max(high-water, arena top); 0 = full OR undeclared
```

`hwRamFree()` returns 0 when the high-water was never declared: treat 0 as
"take nothing", never as "unknown, so assume plenty".

## Zero-filled statics are not free

A cart **imports** its memory, so the linker cannot assume that memory is zero.
It writes every zero byte of a module-scope buffer into the data segment:

```zig
var work: [900 * 1024]u8 = undefined; // 900 KB in the cart binary, 900 KB of the window
```

`demo-swedish_newyear.wasm` carried a 922,018-byte data segment that was 100%
zeros, plus about 320 KB more zeros in its other segment: 1866 KB of the window
used for about 600 KB of real content. The same zeros ride in every `.zmd` disk
and every download.

`apps/zero_segments.mjs` (in `build.sh`) now **fails the build** on any cart
whose data section holds a run of zeros of 64 KB or more, naming the cart, the
segment and the address. The carts that exceeded it when the gate landed are on
its allow-list, each one a migration still to do. The list may only shrink: a
cart that grows past its entry fails, and so does an entry for a cart that no
longer needs it.

## The RAM arena: hwRamAlloc (HW 1.7.0)

The machine hands out the free part of the window, above the high-water:

```zig
hwRamAlloc(bytes, alignment) u32  // ZEROED block, or 0
hwRamMark() u32                   // the arena's current top
hwRamRelease(mark)                // free everything allocated after mark
hwRamAllocFailures() u32          // refusals since this cart was loaded
```

- It is a bump allocator. Nothing is freed on its own: take a **mark**, then
  **release** back to it. A demo with several parts marks when a part starts
  and releases when it ends, so each part reuses the same region.
- Memory comes back **zeroed**, exactly as a static array did, even when the
  previous cart left garbage there.
- `alignment` is a power of two, 1 to 65536. A refused request (no room, zero
  bytes, a bad alignment, an undeclared high-water) returns **0** and bumps
  `hwRamAllocFailures()`. A release to a mark outside the arena is refused and
  counted too. Nothing fails silently.
- A new cart starts with an empty arena: the host's `hwSetCartHigh` at every
  boot, chainload and swap empties it. `hwInit()` leaves it alone.
- `hwRamUsed()` includes the arena, so `hwRamBase() + hwRamUsed()` is still the
  first byte nobody owns. Scenes that depack into free RAM there keep working,
  but that memory is borrowed: a later `hwRamAlloc` hands out the same bytes.

## zg.mem (Zig)

ZigOS wraps the arena as `zg.mem`:

```zig
const zg = @import("zigos");

var canvas: []u8 = &.{};

fn init() void {
    canvas = zg.mem.mustAlloc(u8, 408 * 64);          // zeroed; stops the cart if the window is full
    const maybe = zg.mem.alloc(u16, 320 * 200) orelse return; // or handle a null
    _ = maybe;
    var list: std.ArrayList(u32) = .empty;            // std containers run on it
    list.append(zg.mem.allocator, 7) catch return;

    const m = zg.mem.mark();  // a part starts...
    zg.mem.release(m);        // ...and ends: everything since m is free again
}
```

`zg.mem.allocator` is an `std.mem.Allocator`. Its `free` releases a block only
when it is the topmost one, and the topmost block grows in place, so an
`ArrayList` that grows does not leave a copy behind at every step.
`zg.mem.failures()` should read 0; anything else is a bug.

The arena belongs to the cart, not to a scene: `resetForScene` does not touch
it. A cart that starts scenes at run time (a menu, a multi-part demo) marks
before a scene starts and releases after it, or allocates each buffer once and
keeps it (`if (canvas.len == 0) canvas = ...`).

`apps/zig/scenes/dyno_paradis3.zig` is the worked example: its four offscreens
(68 KB) moved from module-scope arrays to `zg.mem`, and the cart's zero run went
with them.

## C and Rust

`apps/c/zigmachine_mem.h` and `apps/rust/zigmachine_mem.rs` import the four
instructions and wrap them:

```c
#include "../zigmachine_mem.h"
static u8 *tri;
tri = zm_alloc_array(u8, 256);      // zeroed, or NULL (counted by the machine)
zm_mark m = zm_mark_now();  /* ... */  zm_release(m);
```

```rust
mod zigmachine_mem;
let Some(tri) = zigmachine_mem::alloc::<u8>(256) else { return }; // &'static mut [u8], zeroed
let m = zigmachine_mem::mark(); /* ... */ unsafe { zigmachine_mem::release(m) };
```

Both "hello world" carts (`apps/c/scenes/hello.c`, `apps/rust/hello.rs`) take
their plasma table from the arena, and `apps/verify.mjs` runs them on the real
machine.

## VRAM is a different pool

Plane framebuffers do not come from the cart window. They live in the **1 MiB
VRAM pool** inside the video region, handed out by ZigOS's `vramAlloc` when a
plane is set up (`NORMAL_FB_BYTES` = 64000 for a 320x200 plane,
`OVERSCAN_FB_BYTES` = 112000 for 400x280). ZigOS empties the pool in `init`
and `resetForScene`.

`vramAlloc` has **no guard**: past the end of the pool it bumps straight into
the physical framebuffer, silently. A scene that allocates big backing buffers
should check its total against `zg.VRAM_BYTES` at comptime.

## What check_fits cannot see

`apps/check_fits.mjs` measures the static footprint: data + stack, the same
number the host declares. It cannot see what a cart takes **at run time**:

- a ZX0-packed asset (`docs/DEPACK.md`) is small in the data segment and large
  once it is depacked into free RAM at boot;
- arena allocations, however big.

A cart can pass `check_fits` and still run out at boot. So size a run-time
buffer against `hwRamFree()` (or let `zg.mem.alloc` return null), and check
`zg.mem.failures()` in the scene's harness.
