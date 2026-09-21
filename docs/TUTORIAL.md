# Tutorial: your first screen, in Zig, C and Rust

This tutorial builds one small oldskool screen from scratch, one piece at a
time. It ends with:

- a sky gradient with a **copper bar** bouncing through it,
- a **bouncing block**,
- a **checkerboard floor**,
- a **text scroller**,
- **music**: Mad Max's "So Watt" (`sos.sndh`), played by the machine's
  emulated 68000 on its YM2149.

The screen is written three times, and every snippet below comes from a file
that builds and runs:

| Language | Finished file | Cart | Talks to the machine through |
|---|---|---|---|
| Zig | `apps/zig/scenes/tutorial.zig` | `demo-tutorial.wasm` | **ZigOS**, the open library (`docs/ZIGOS_API.md`) |
| C | `apps/c/scenes/tutorial.c` | `demo-c-tutorial.wasm` | the raw sealed ABI (`docs/HW_API.md`) |
| Rust | `apps/rust/scenes/tutorial.rs` | `demo-rust-tutorial.wasm` | the raw sealed ABI (`docs/HW_API.md`) |

The C and Rust versions use no library. They write palette indices into
shared memory and poke a few registers. The Zig version calls ZigOS helpers
for the same jobs. Where the two differ, the step says why.

Each step shows **only what that step adds or changes**. The finished files
are the last step. They are short enough to read in one sitting.

## Before you start

**The machine in one paragraph.** ZigMachine is a sealed console. Its hardware
is `machine-video.wasm` and `machine-audio.wasm`, and you never rebuild them.
Your program is a **cart**: a wasm module that shares one `WebAssembly.Memory`
with the machine. The screen is **4 planes**. Each plane is a 320x200 buffer of
**palette indices** with its own 256-colour RGBA palette. Around the 320x200
screen sits a 40-pixel **border**, 400x280 in all. Every frame the host does
this:

```
hwClear()  ->  your frame()  ->  hwRenderPlane(p) for each plane your isPlaneEnabled(p) says is on
```

**Toolchains.**

- Zig 0.16: `export PATH="$HOME/.local/zig/0.16.0:$PATH"`
- C: nothing extra. `apps/c/build.sh` uses `zig cc`, which bundles a linker.
- Rust: `rustup target add wasm32-unknown-unknown`. `rustc` bundles `rust-lld`.

**Build.**

```bash
sh ./build.sh                          # the Zig carts, plus every check
bash apps/c/build.sh tutorial          # -> docs/demo-c-tutorial.wasm
bash apps/rust/build.sh tutorial       # -> docs/demo-rust-tutorial.wasm
```

`./build.sh` also rebuilds the C and Rust carts, so a plain `./build.sh`
covers all three. The single-language scripts are faster while you iterate.

**Run.** Serve `docs/` and open a cart with `?demo=`:

```bash
cd docs && python3 -m http.server 3333
# http://localhost:3333/index.html?demo=demo-tutorial.wasm
# http://localhost:3333/index.html?demo=demo-c-tutorial.wasm
# http://localhost:3333/index.html?demo=demo-rust-tutorial.wasm
```

`sealed.html?demo=...` also works: it redirects to `index.html` and keeps the
query. The Zig screen is on the machine's menu too, as **TUTORIAL**. Hard-reload
(Ctrl+Shift+R) after every rebuild, or the browser keeps the old wasm.

**Where your file lives.** In Zig, add the scene to three lists that must stay
in step (already done for the tutorial):

- the `switch` in `apps/zig/cart.zig`,
- `cart_names` in `build.zig`,
- `apps/zig/scenes/catalog.zig`, if the menu should list it.

A C or Rust scene is just a new file in `apps/c/scenes/` or `apps/rust/scenes/`.
The build scripts pick up every file there.

---

## Step 1: an empty cart that boots

**Goal.** A cart the machine loads and runs, drawing nothing.

**Concept.** The host calls your cart through a handful of exports. `boot()`
runs once. `frame(dt)` runs every frame. `isPlaneEnabled(p)` tells the host
which planes to show. The rest (`hblDispatch`, `skipBoot`, `setShadeMode`,
`pointer`, `input`) must exist even as stubs: the build scripts export all
eight names, and linking fails if one is missing. `inputRelease(dir)` is
OPTIONAL and not one of the eight: the host calls it on key-up, only for a cart
that exports it, so a held direction stops exactly on release.

A Zig scene does not write these exports. `apps/zig/demo_main.zig` does, and it
calls your `Demo`'s `init` once, then `update` and `render` every frame.

### Zig

```zig
const zg = @import("zigos");
const ZigOS = zg.ZigOS;

pub const Demo = struct {
    pub fn init(self: *Demo, zigos: *ZigOS) void {
        _ = self;
        _ = zigos;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt;
    }
};
```

### C

```c
typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;

__attribute__((export_name("boot")))
void boot(void) {}

__attribute__((export_name("frame")))
void frame(float dt) { (void)dt; }

__attribute__((export_name("isPlaneEnabled")))
int isPlaneEnabled(int id) { (void)id; return 0; }

// The host calls these too. Stubs, so no call ever hits a missing export.
__attribute__((export_name("hblDispatch")))
void hblDispatch(u32 id, u32 plane, u32 line, u32 x) { (void)id; (void)plane; (void)line; (void)x; }
__attribute__((export_name("skipBoot")))     void skipBoot(void) {}
__attribute__((export_name("setShadeMode"))) void setShadeMode(u32 m) { (void)m; }
__attribute__((export_name("pointer")))      void pointer(int x, int y, u32 b) { (void)x; (void)y; (void)b; }
__attribute__((export_name("input")))        void input(u8 dir) { (void)dir; }
```

### Rust

```rust
#![no_std]
#![no_main]

use core::panic::PanicInfo;

#[panic_handler]
fn panic(_: &PanicInfo) -> ! {
    loop {}
}

#[no_mangle]
pub extern "C" fn boot() {}

#[no_mangle]
pub extern "C" fn frame(_elapsed_ms: f32) {}

#[no_mangle]
pub extern "C" fn isPlaneEnabled(_id: i32) -> i32 {
    0
}

// The host calls these too. Stubs, so no call ever hits a missing export.
#[no_mangle]
pub extern "C" fn hblDispatch(_id: u32, _plane: u32, _line: u32, _x: u32) {}
#[no_mangle]
pub extern "C" fn skipBoot() {}
#[no_mangle]
pub extern "C" fn setShadeMode(_m: u32) {}
#[no_mangle]
pub extern "C" fn pointer(_x: i32, _y: i32, _b: u32) {}
#[no_mangle]
pub extern "C" fn input(_dir: u8) {}
```

`no_std` because there is no operating system. `no_main` because the host calls
your exports, so there is no `main`. The panic handler is required without `std`.

**What you should see.** Nothing but the background. In Zig it is dark grey:
ZigOS resets the background to (20,20,20) before a scene starts. In C and Rust
the machine's reset leaves the background at 0, which has **alpha 0**, so the
page behind the canvas shows through (black on the default page).

**Common mistakes.**

- *Link error `symbol not defined` in C or Rust.* One of the eight exports is
  missing. Keep the stubs.
- *The Zig cart is not built.* The scene is missing from `cart.zig` or
  `build.zig`, or its index differs between them.

---

## Step 2: enable a plane and set a palette

**Goal.** Plane 0 on, five colours in its palette, the whole plane filled with
the sky colour, and a black border.

**Concept.** Like the ST, the screen stores **indices**, not colours. A colour
is an RGBA `u32`, stored little-endian as bytes R, G, B, A, so the value is
`a<<24 | b<<16 | g<<8 | r`. **Alpha 255 is opaque.** Alpha 0 is transparent,
which is how an upper plane lets a lower one show through. Changing a palette
entry recolours every pixel that uses it, at no cost. Step 5 builds on that.

The sealed memory map (from `machine/sdk/memmap.zig`), as offsets from
`hwVideoBase()`:

| Offset | What |
|---|---|
| `0x04` | `REG_BACKGROUND`: border/background colour, `u32` |
| `0x0100` | plane 0 palette: 256 x `u32` |
| `0x1100` | plane 0 framebuffer: 320 x 200 bytes, row by row |

**Zig vs C/Rust.** ZigOS wraps all of this: `zigos.lfbs[0]` is plane 0,
`is_enabled` feeds the `isPlaneEnabled` export, and `setPaletteEntry` writes the
palette. C and Rust ask the machine for the base address once, then write the
bytes themselves.

### Zig

```zig
const Color = zg.Color;

// palette indices
const SKY: u8 = 0;
const FLOOR_DARK: u8 = 1;
const FLOOR_LIGHT: u8 = 2;
const BLOCK: u8 = 3;
const TEXT_INK: u8 = 4;

fn rgb(r: u8, g: u8, b: u8) Color {
    return .{ .r = r, .g = g, .b = b, .a = 255 };
}
```

```zig
    pub fn init(self: *Demo, zigos: *ZigOS) void {
        _ = self;
        zigos.setBackgroundColor(rgb(0, 0, 0));

        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPaletteEntry(SKY, rgb(0, 0, 40));
        fb.setPaletteEntry(FLOOR_DARK, rgb(60, 20, 90));
        fb.setPaletteEntry(FLOOR_LIGHT, rgb(140, 60, 180));
        fb.setPaletteEntry(BLOCK, rgb(255, 210, 0));
        fb.setPaletteEntry(TEXT_INK, rgb(255, 255, 255));
        fb.clearFrameBuffer(SKY);
    }
```

### C

```c
// --- the sealed ABI: one import, and offsets from machine/sdk/memmap.zig ---
__attribute__((import_module("env"), import_name("hwVideoBase")))
extern int hwVideoBase(void);

#define OFF_PAL        0x0100 // plane 0 palette: 256 x RGBA u32
#define OFF_VRAM       0x1100 // plane 0 framebuffer: 320 x 200 palette indices
#define REG_BACKGROUND 0x04   // u32: the border/background colour
#define W 320
#define H 200

// palette indices
#define SKY         0
#define FLOOR_DARK  1
#define FLOOR_LIGHT 2
#define BLOCK       3
#define TEXT_INK    4

static int video_base;

static inline u8 *vram(void) { return (u8 *)(video_base + OFF_VRAM); }
static inline u32 *palette(void) { return (u32 *)(video_base + OFF_PAL); }
static inline u32 rgba(u32 r, u32 g, u32 b) { return 0xFF000000u | b << 16 | g << 8 | r; }

static void fill_rect(int x, int y, int w, int h, u8 index) {
    for (int j = y; j < y + h; j++)
        for (int i = x; i < x + w; i++) vram()[j * W + i] = index;
}

__attribute__((export_name("boot")))
void boot(void) {
    video_base = hwVideoBase();
    *(u32 *)(video_base + REG_BACKGROUND) = rgba(0, 0, 0);

    u32 *pal = palette();
    pal[SKY] = rgba(0, 0, 40);
    pal[FLOOR_DARK] = rgba(60, 20, 90);
    pal[FLOOR_LIGHT] = rgba(140, 60, 180);
    pal[BLOCK] = rgba(255, 210, 0);
    pal[TEXT_INK] = rgba(255, 255, 255);

    fill_rect(0, 0, W, H, SKY);
}
```

```c
__attribute__((export_name("isPlaneEnabled")))
int isPlaneEnabled(int id) { return id == 0; }
```

### Rust

Rust keeps the screen's state in one `Screen` struct in a `static mut`, reached
through `screen()`. A wasm cart is single-threaded and the host never calls back
into it while it runs, so that is sound. Each `unsafe` block says why it is safe.

```rust
use core::ptr::addr_of_mut;

// --- the sealed ABI: one import, and offsets from machine/sdk/memmap.zig ---
#[link(wasm_import_module = "env")]
extern "C" {
    fn hwVideoBase() -> i32;
}

const OFF_PAL: usize = 0x0100; // plane 0 palette: 256 x RGBA u32
const OFF_VRAM: usize = 0x1100; // plane 0 framebuffer: 320 x 200 palette indices
const REG_BACKGROUND: usize = 0x04; // u32: the border/background colour
const W: usize = 320;
const H: usize = 200;

// palette indices
const SKY: u8 = 0;
const FLOOR_DARK: u8 = 1;
const FLOOR_LIGHT: u8 = 2;
const BLOCK: u8 = 3;
const TEXT_INK: u8 = 4;

struct Screen {
    base: usize,
}

static mut SCREEN: Screen = Screen { base: 0 };

fn screen() -> &'static mut Screen {
    // SAFETY: a wasm32 cart is single-threaded, and the host never re-enters it.
    unsafe { &mut *addr_of_mut!(SCREEN) }
}

const fn rgba(r: u32, g: u32, b: u32) -> u32 {
    0xFF00_0000 | b << 16 | g << 8 | r
}

impl Screen {
    fn vram(&self) -> &'static mut [u8] {
        // SAFETY: plane 0's framebuffer, inside the machine's video region.
        unsafe { core::slice::from_raw_parts_mut((self.base + OFF_VRAM) as *mut u8, W * H) }
    }

    fn palette(&self) -> &'static mut [u32] {
        // SAFETY: plane 0's 256-entry palette, inside the machine's video region.
        unsafe { core::slice::from_raw_parts_mut((self.base + OFF_PAL) as *mut u32, 256) }
    }

    fn fill_rect(&self, x: usize, y: usize, w: usize, h: usize, index: u8) {
        let vram = self.vram();
        for row in y..y + h {
            vram[row * W + x..row * W + x + w].fill(index);
        }
    }
}
```

```rust
#[no_mangle]
pub extern "C" fn boot() {
    let s = screen();
    // SAFETY: a plain import from the machine; it returns the video region's base.
    s.base = unsafe { hwVideoBase() } as usize;
    // SAFETY: REG_BACKGROUND is a u32 register inside the video region.
    unsafe { ((s.base + REG_BACKGROUND) as *mut u32).write(rgba(0, 0, 0)) };

    let pal = s.palette();
    pal[SKY as usize] = rgba(0, 0, 40);
    pal[FLOOR_DARK as usize] = rgba(60, 20, 90);
    pal[FLOOR_LIGHT as usize] = rgba(140, 60, 180);
    pal[BLOCK as usize] = rgba(255, 210, 0);
    pal[TEXT_INK as usize] = rgba(255, 255, 255);

    s.fill_rect(0, 0, W, H, SKY);
}
```

```rust
#[no_mangle]
pub extern "C" fn isPlaneEnabled(id: i32) -> i32 {
    (id == 0) as i32
}
```

**What you should see.** A dark blue 320x200 rectangle in a black border.

**Common mistakes.**

- *Nothing shows.* Either alpha is 0 (a colour written as `0x000028` instead of
  `0xFF280000`), or the plane is not enabled (`is_enabled` in Zig,
  `isPlaneEnabled` in C and Rust).
- *Red and blue swapped.* The byte order is R, G, B, A from the low byte up.
- *A scene that enables a plane and later disables it leaves stale pixels on
  that plane's canvas.* Only enabled planes are repainted.

---

## Step 3: draw something static

**Goal.** A checkerboard floor under the sky.

**Concept.** Drawing is writing indices: row `y`, column `x` is byte
`y * 320 + x`. Something that never changes is drawn once, in `init`/`boot`,
not every frame.

**Zig vs C/Rust.** Zig uses `setPixelValue`, which clips to the plane.

### Zig

```zig
const LogicalFB = zg.LogicalFB;
```

```zig
const W: u16 = zg.WIDTH; // 320
const H: u16 = zg.HEIGHT; // 200
```

```zig
const FLOOR_Y: u16 = 160;
```

```zig
fn drawFloor(fb: *LogicalFB) void {
    for (FLOOR_Y..H) |y| {
        for (0..W) |x| {
            const light = ((x / 20 + y / 10) & 1) == 1;
            fb.setPixelValue(@intCast(x), @intCast(y), if (light) FLOOR_LIGHT else FLOOR_DARK);
        }
    }
}
```

At the end of `init`:

```zig
        fb.clearFrameBuffer(SKY);
        drawFloor(fb);
```

### C

```c
#define FLOOR_Y 160
```

```c
static void draw_floor(void) {
    for (int y = FLOOR_Y; y < H; y++)
        for (int x = 0; x < W; x++)
            vram()[y * W + x] = ((x / 20 + y / 10) & 1) ? FLOOR_LIGHT : FLOOR_DARK;
}
```

At the end of `boot`:

```c
    fill_rect(0, 0, W, H, SKY);
    draw_floor();
```

### Rust

```rust
const FLOOR_Y: usize = 160;
```

In `impl Screen`:

```rust
    fn draw_floor(&self) {
        let vram = self.vram();
        for y in FLOOR_Y..H {
            for x in 0..W {
                vram[y * W + x] = if (x / 20 + y / 10) & 1 == 1 { FLOOR_LIGHT } else { FLOOR_DARK };
            }
        }
    }
```

At the end of `boot`:

```rust
    s.fill_rect(0, 0, W, H, SKY);
    s.draw_floor();
```

**What you should see.** The blue sky over a two-tone purple checkerboard
filling the bottom 40 lines.

**Common mistakes.**

- *Zig's `drawScanline(x1, x2, y, index)` for a full row draws nothing.* It
  fills `[x1, x2)` but rejects `x2 == 320`, so it can never reach the last
  column. Use `setPixelValue` or write `fb.fb` directly.
- *C: writing past row 199.* Nothing traps. You overwrite the next plane's
  framebuffer, or worse. Rust's slices panic instead, and the cart stops.

---

## Step 4: animate it every frame

**Goal.** A yellow block bouncing around the sky.

**Concept.** A demo screen redraws what moves, every frame. Here that means:
wipe the sky, move the block, draw it. The floor is not touched. Movement is
whole pixels per frame, like on the ST. The `dt` the host passes is in
milliseconds and not reliable enough to pace an effect, so count frames instead.

**Zig vs C/Rust.** A Zig scene splits the frame into `update` (move) and
`render` (draw). C and Rust do both in `frame`.

### Zig

State lives in the `Demo` struct. **Set every field in `init`.** A cart's `Demo`
starts as zeroed memory and its field defaults (`block_x: i32 = 40`) are never
applied.

```zig
const BLOCK_SIZE: i32 = 24;
```

```zig
fn fillRect(fb: *LogicalFB, x: i32, y: i32, w: i32, h: i32, index: u8) void {
    var j = y;
    while (j < y + h) : (j += 1) {
        var i = x;
        while (i < x + w) : (i += 1) fb.setPixelValue(@intCast(i), @intCast(j), index);
    }
}
```

```zig
pub const Demo = struct {
    block_x: i32,
    block_y: i32,
    block_dx: i32,
    block_dy: i32,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // A cart's Demo is never built from field defaults: set every field here.
        self.block_x = 40;
        self.block_y = 40;
        self.block_dx = 2;
        self.block_dy = 1;
```

```zig
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.block_x += self.block_dx;
        self.block_y += self.block_dy;
        if (self.block_x <= 0 or self.block_x >= W - BLOCK_SIZE) self.block_dx = -self.block_dx;
        if (self.block_y <= 28 or self.block_y >= FLOOR_Y - BLOCK_SIZE) self.block_dy = -self.block_dy;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[0];
        @memset(fb.fb[0 .. @as(usize, FLOOR_Y) * W], SKY); // wipe last frame's sky
        fillRect(fb, self.block_x, self.block_y, BLOCK_SIZE, BLOCK_SIZE, BLOCK);
    }
```

### C

```c
#define BLOCK_SIZE 24
```

```c
static int block_x, block_y, block_dx, block_dy;
```

```c
static void move_block(void) {
    block_x += block_dx;
    block_y += block_dy;
    if (block_x <= 0 || block_x >= W - BLOCK_SIZE) block_dx = -block_dx;
    if (block_y <= 28 || block_y >= FLOOR_Y - BLOCK_SIZE) block_dy = -block_dy;
}
```

At the end of `boot`, and the new `frame`:

```c
    block_x = 40; block_y = 40; block_dx = 2; block_dy = 1;
```

```c
__attribute__((export_name("frame")))
void frame(float dt) {
    (void)dt;
    fill_rect(0, 0, W, FLOOR_Y, SKY); // wipe last frame's sky
    move_block();
    fill_rect(block_x, block_y, BLOCK_SIZE, BLOCK_SIZE, BLOCK);
}
```

### Rust

```rust
const BLOCK_SIZE: i32 = 24;

struct Screen {
    base: usize,
    block_x: i32,
    block_y: i32,
    block_dx: i32,
    block_dy: i32,
}

static mut SCREEN: Screen = Screen {
    base: 0,
    block_x: 40,
    block_y: 40,
    block_dx: 2,
    block_dy: 1,
};
```

In `impl Screen`, and the new `frame`:

```rust
    fn move_block(&mut self) {
        self.block_x += self.block_dx;
        self.block_y += self.block_dy;
        if self.block_x <= 0 || self.block_x >= W as i32 - BLOCK_SIZE {
            self.block_dx = -self.block_dx;
        }
        if self.block_y <= 28 || self.block_y >= FLOOR_Y as i32 - BLOCK_SIZE {
            self.block_dy = -self.block_dy;
        }
    }
```

```rust
#[no_mangle]
pub extern "C" fn frame(_elapsed_ms: f32) {
    let s = screen();
    s.fill_rect(0, 0, W, FLOOR_Y, SKY); // wipe last frame's sky
    s.move_block();
    let size = BLOCK_SIZE as usize;
    s.fill_rect(s.block_x as usize, s.block_y as usize, size, size, BLOCK);
}
```

In C and Rust, a `static`'s initial value is honoured, because the linker puts
it in the data segment. Only Zig scenes have the "defaults are ignored" trap.

**What you should see.** The block bounces off the screen edges and the floor,
and leaves no trail.

**Common mistakes.**

- *A Zig block frozen in the top-left, or flying off at a wild speed.* A field
  was left to its default and read as 0 or garbage. Set it in `init`.
- *A trail behind the block.* The old position was never wiped.
- *Zig: `self.* = .{ ... }` to reset a big struct.* It compiles, but the linker
  stores a second copy of the whole default value in the cart's data. On a
  struct holding a large buffer that cost one cart 517 KB of its 2 MB window.
  Set the fields one by one.

---

## Step 5: rasters, the copper bar

**Goal.** A sky that fades from dark to lighter blue, with a copper bar
sliding up and down through it, all drawn with **one** palette index.

**Concept.** The ST shows 16 colours. Demos got hundreds by changing a palette
entry **between scanlines**: an interrupt fires at each horizontal blank (HBL),
and the handler writes a new colour before the next line is drawn. On the Amiga
the copper chip did it, so a bar made this way is a *copper bar*.

ZigMachine has the same thing. Put a non-zero handler id in a plane's
`FB_HBL_ID` register, and the machine calls your `hblDispatch(id, plane, line, x)`
export before it composites each line of that plane. Every sky pixel is index
`SKY`, so writing `palette[SKY]` from the handler gives each line its own colour.
The framebuffer does not change. Only the palette does, 200 times a frame.

**The line numbers.** On a normal plane, a per-plane HBL gets **logical** lines
0..199, where 0 is the top of the 320x200 screen. The *global* HBL
(`GLOBAL_HBL_ID`, which recolours the border through `REG_BACKGROUND`) gets
**physical** lines 0..279, where the visible screen starts at 40. An overscan
plane's per-plane HBL also gets physical lines. Mixing these up shifts a raster
40 lines.

**Zig vs C/Rust.** ZigOS has `zg.copper`. You fill a table with one colour per
line, and its own HBL handler plays the table back. It works out which
numbering the plane uses, so the table is always indexed from the top of the
screen. C and Rust keep the table themselves and write the handler by hand.
Either way the colours are computed in `frame`/`render`, and the handler only
copies one value. The handler runs 200 times a frame, so keep it tiny.

### Zig

```zig
const BAR_H: i32 = 16;

// The copper's per-line colours for SKY. Module scope and owned by the scene:
// an HBL handler gets no pointer to your Demo.
var copper_table: [1]zg.copper.Table = undefined;
```

Two new fields, `bar_y: i32` and `bar_dy: i32`, set in `init` (`24` and `2`).
At the end of `init`, after the palette is set (the table starts as the entry's
current colour):

```zig
        // One HBL on plane 0 that rewrites SKY before every line.
        zg.copper.install(fb, &.{SKY}, &copper_table, .{});
```

At the end of `update`:

```zig
        self.bar_y += self.bar_dy;
        if (self.bar_y <= 24 or self.bar_y >= FLOOR_Y - BAR_H) self.bar_dy = -self.bar_dy;
```

At the end of `render`, and the new method:

```zig
        self.buildCopper(zg.copper.visible(fb, 0));
```

```zig
    // One colour per visible line: a sky gradient, with a copper bar over it.
    fn buildCopper(self: *const Demo, lines: *[H]u32) void {
        for (lines, 0..) |*colour, i| {
            const d = @as(i32, @intCast(i)) - self.bar_y;
            if (d >= 0 and d < BAR_H) {
                const k: u8 = @intCast(if (d < BAR_H / 2) d + 1 else BAR_H - d); // 1..8..1
                colour.* = rgb(k * 31, k * 24, k * 8).toRGBA();
            } else {
                colour.* = rgb(0, @intCast(i / 4), @intCast(40 + i / 2)).toRGBA();
            }
        }
    }
```

The table is at module scope because it belongs to this scene. Do the same in
a library you write: a module-scope array in a *library* costs its size in
every cart that imports the library, whether or not the cart uses it.

### C

```c
#define REG_FB_HBL_ID  0x20   // u16 per plane: 0 = no HBL
#define REG_FB_HBL_POS 0x28   // u16 per plane: the column the HBL fires at
```

```c
#define BAR_H      16
```

```c
static int bar_y, bar_dy;
static u32 copper[H]; // the SKY colour of each visible line
```

```c
// One colour per line: a sky gradient, with a copper bar over it.
static void build_copper(void) {
    for (int line = 0; line < H; line++) {
        u32 c = rgba(0, line / 4, 40 + line / 2);
        int d = line - bar_y;
        if (d >= 0 && d < BAR_H) {
            int k = d < BAR_H / 2 ? d + 1 : BAR_H - d; // 1..8..1: bright in the middle
            c = rgba(k * 31, k * 24, k * 8);
        }
        copper[line] = c;
    }
    bar_y += bar_dy;
    if (bar_y <= 24 || bar_y >= FLOOR_Y - BAR_H) bar_dy = -bar_dy;
}
```

At the end of `boot`:

```c
    bar_y = 24; bar_dy = 2;
    for (int i = 0; i < H; i++) copper[i] = pal[SKY];

    // Arm plane 0's HBL: any non-zero id, fired at column 0 of every line.
    *(u16 *)(video_base + REG_FB_HBL_ID + 0 * 2) = 1;
    *(u16 *)(video_base + REG_FB_HBL_POS + 0 * 2) = 0;
```

`build_copper();` goes at the end of `frame`, and the `hblDispatch` stub becomes
the handler:

```c
// The machine calls this before it draws each line of plane 0. `line` is the
// LOGICAL line, 0..199, on a normal plane.
__attribute__((export_name("hblDispatch")))
void hblDispatch(u32 id, u32 plane, u32 line, u32 x) {
    (void)id; (void)plane; (void)x;
    palette()[SKY] = copper[line];
}
```

### Rust

```rust
const REG_FB_HBL_ID: usize = 0x20; // u16 per plane: 0 = no HBL
const REG_FB_HBL_POS: usize = 0x28; // u16 per plane: the column the HBL fires at
```

```rust
const BAR_H: i32 = 16;
```

`Screen` gains `bar_y: i32`, `bar_dy: i32` and `copper: [u32; H]`, initialised
to `24`, `2` and `[0; H]`. In `impl Screen`:

```rust
    // One colour per line: a sky gradient, with a copper bar over it.
    fn build_copper(&mut self) {
        for line in 0..H as i32 {
            let d = line - self.bar_y;
            self.copper[line as usize] = if (0..BAR_H).contains(&d) {
                let k = (if d < BAR_H / 2 { d + 1 } else { BAR_H - d }) as u32; // 1..8..1
                rgba(k * 31, k * 24, k * 8)
            } else {
                rgba(0, line as u32 / 4, 40 + line as u32 / 2)
            };
        }
        self.bar_y += self.bar_dy;
        if self.bar_y <= 24 || self.bar_y >= FLOOR_Y as i32 - BAR_H {
            self.bar_dy = -self.bar_dy;
        }
    }
```

At the end of `boot`:

```rust
    s.copper = [pal[SKY as usize]; H];

    // Arm plane 0's HBL: any non-zero id, fired at column 0 of every line.
    // SAFETY: plane 0's u16 HBL registers, inside the video region.
    unsafe {
        ((s.base + REG_FB_HBL_ID) as *mut u16).write(1);
        ((s.base + REG_FB_HBL_POS) as *mut u16).write(0);
    }
```

`s.build_copper();` goes at the end of `frame`, and the stub becomes:

```rust
// The machine calls this before it draws each line of plane 0. `line` is the
// LOGICAL line, 0..199, on a normal plane.
#[no_mangle]
pub extern "C" fn hblDispatch(_id: u32, _plane: u32, line: u32, _x: u32) {
    let s = screen();
    s.palette()[SKY as usize] = s.copper[line as usize];
}
```

**What you should see.** A gradient sky and a gold bar, brightest in its
middle, sliding between the top of the screen and the floor. The block stays
yellow and the floor stays purple: they use other indices.

**Common mistakes.**

- *The bar sits 40 lines too low, and the top of the screen never changes.*
  The handler subtracted 40 from a logical line, or indexed a physical table.
- *The whole sky is one colour.* The HBL is not armed (id still 0), or the
  handler writes the wrong palette entry.
- *The bar jitters.* The handler computes the colour itself from state that
  `frame` is still changing. Build the table in `frame`, copy it in the handler.

---

## Step 6: a text scroller

**Goal.** A line of text scrolling right to left across the top of the screen,
looping forever.

**Concept.** A font is a set of small bitmaps. To scroll, draw the text starting
at `-scroll_x`, clip what falls off either edge, and add 2 to `scroll_x` every
frame. When `scroll_x` reaches the text's pixel width, wrap it to 0. That lands
the text exactly where it started, so the loop has no seam.

**Zig vs C/Rust.** ZigOS carries the ST's 8x8 system font, and
`zigos.printText(fb, text, x, y, ink, paper)` draws with it. `x` is signed and
clipped, so text can start off the left edge. The paper index is written behind
the glyphs, and `SKY` there lets the copper show through. C and Rust have no
font, so they embed one: a 5x7 bitmap for just the letters the text needs, one
byte per row, drawn 2x2. That is why the C and Rust text is bigger.

### Zig

```zig
const TEXT = "HELLO FROM ZIG * THIS IS YOUR FIRST ZIGMACHINE SCREEN * ";
const TEXT_W: i32 = TEXT.len * 8; // the 8x8 system font
```

A `scroll_x: i32` field, set to `0` in `init`. At the end of `update`:

```zig
        self.scroll_x = @mod(self.scroll_x + 2, TEXT_W);
```

At the end of `render`:

```zig
        // Two copies of the text, one text-width apart, so the loop has no gap.
        const x = -self.scroll_x;
        zigos.printText(fb, TEXT, @intCast(x), 8, TEXT_INK, SKY);
        zigos.printText(fb, TEXT, @intCast(x + TEXT_W), 8, TEXT_INK, SKY);
```

### C

```c
static int scroll_x;
```

```c
// A 5x7 font holding only the letters TEXT uses: one byte per row, bit 4 = left.
static const char GLYPHS[] = "ACEFGHILMNORSTUYZ*";
static const u8 FONT[][7] = {
    {0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11}, // A
    {0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E}, // C
    {0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F}, // E
    {0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10}, // F
    {0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F}, // G
    {0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11}, // H
    {0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E}, // I
    {0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F}, // L
    {0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11}, // M
    {0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11}, // N
    {0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E}, // O
    {0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11}, // R
    {0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E}, // S
    {0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04}, // T
    {0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E}, // U
    {0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04}, // Y
    {0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F}, // Z
    {0x00, 0x15, 0x0E, 0x1F, 0x0E, 0x15, 0x00}, // *
};
static const char TEXT[] = "HELLO FROM C * THIS IS YOUR FIRST ZIGMACHINE SCREEN * ";
#define TEXT_LEN (int)(sizeof(TEXT) - 1)
#define SCALE    2  // each font pixel is drawn 2x2
#define ADVANCE  12 // 5 columns x 2, plus a 2-pixel gap

static int glyph_of(char c) {
    for (int g = 0; GLYPHS[g]; g++)
        if (GLYPHS[g] == c) return g;
    return -1;
}

static void draw_char(char c, int x, int y) {
    int g = glyph_of(c);
    if (g < 0) return; // a space, or a letter the font lacks
    for (int row = 0; row < 7; row++)
        for (int col = 0; col < 5; col++) {
            if (!(FONT[g][row] & (0x10 >> col))) continue;
            for (int sy = 0; sy < SCALE; sy++)
                for (int sx = 0; sx < SCALE; sx++) {
                    int px = x + col * SCALE + sx;
                    if (px >= 0 && px < W) vram()[(y + row * SCALE + sy) * W + px] = TEXT_INK;
                }
        }
}

static void draw_scroller(void) {
    for (int i = 0;; i++) {
        int x = i * ADVANCE - scroll_x;
        if (x >= W) break;
        if (x > -ADVANCE) draw_char(TEXT[i % TEXT_LEN], x, 8);
    }
    scroll_x = (scroll_x + 2) % (TEXT_LEN * ADVANCE);
}
```

`scroll_x = 0;` goes in `boot` and `draw_scroller();` at the end of `frame`.
`TEXT[i % TEXT_LEN]` repeats the text, so one loop fills the whole width.

### Rust

```rust
// A 5x7 font holding only the letters TEXT uses: one byte per row, bit 4 = left.
const GLYPHS: &[u8] = b"ACEFGHILMNORSTUYZ*";
const FONT: [[u8; 7]; 18] = [
    [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11], // A
    [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E], // C
    [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F], // E
    [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10], // F
    [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F], // G
    [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11], // H
    [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E], // I
    [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F], // L
    [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11], // M
    [0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11], // N
    [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E], // O
    [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11], // R
    [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E], // S
    [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04], // T
    [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E], // U
    [0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04], // Y
    [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F], // Z
    [0x00, 0x15, 0x0E, 0x1F, 0x0E, 0x15, 0x00], // *
];
const TEXT: &[u8] = b"HELLO FROM RUST * THIS IS YOUR FIRST ZIGMACHINE SCREEN * ";
const SCALE: usize = 2; // each font pixel is drawn 2x2
const ADVANCE: usize = 12; // 5 columns x 2, plus a 2-pixel gap
```

`Screen` gains `scroll_x: usize`, initialised to `0`. In `impl Screen`:

```rust
    fn draw_char(&self, c: u8, x: i32, y: usize) {
        // a space, or a letter the font lacks, draws nothing
        let Some(g) = GLYPHS.iter().position(|&l| l == c) else { return };
        let vram = self.vram();
        for (row, bits) in FONT[g].iter().enumerate() {
            for col in 0..5 {
                if bits & (0x10 >> col) == 0 {
                    continue;
                }
                for sy in 0..SCALE {
                    for sx in 0..SCALE {
                        let px = x + (col * SCALE + sx) as i32;
                        if (0..W as i32).contains(&px) {
                            vram[(y + row * SCALE + sy) * W + px as usize] = TEXT_INK;
                        }
                    }
                }
            }
        }
    }

    fn draw_scroller(&mut self) {
        let mut i = 0;
        loop {
            let x = (i * ADVANCE) as i32 - self.scroll_x as i32;
            if x >= W as i32 {
                break;
            }
            if x > -(ADVANCE as i32) {
                self.draw_char(TEXT[i % TEXT.len()], x, 8);
            }
            i += 1;
        }
        self.scroll_x = (self.scroll_x + 2) % (TEXT.len() * ADVANCE);
    }
```

`s.draw_scroller();` goes at the end of `frame`.

**What you should see.** White text gliding right to left over the top of the
gradient, with no gap when it loops. Zig's is the small ST system font. C and
Rust show a chunkier 10x14 font.

**Common mistakes.**

- *A gap or a jump when the text loops.* The wrap width is not exactly the text
  width: length times the glyph advance.
- *Letters wrap onto the next line at the right edge.* A glyph was drawn without
  clipping `x`. Clip every pixel, as all three versions do.
- *Text with a black box around it over the raster.* The paper index is not
  `SKY`, so the copper cannot recolour it.

---

## Step 7: music

**Goal.** "So Watt" by Mad Max plays while the screen runs.

**Concept.** A cart never contains a music player. It asks the host for a tune
**by name**, a file under `docs/music/`. The host polls the cart every frame,
fetches the file, and plays it on the audio thread. An SNDH carries the tune's
own 68000 replay code, which the machine runs on an emulated 68000 driving its
YM2149, as the ST did. The full guide is `docs/MUSIC.md`.

Request once, at start-up. Each request replaces the tune playing.

**Zig vs C/Rust.** Zig calls `zg.requestSong`, and `demo_main.zig` already
exports what the host polls. C and Rust include a small bridge that defines
those exports: `apps/c/zigmachine_music.h` or `apps/rust/zigmachine_music.rs`.

### Zig

```zig
const MUSIC = "sos.sndh"; // a file under docs/music/
```

In `init`:

```zig
        zg.requestSong(MUSIC);
```

### C

At the top of the file:

```c
#include "../zigmachine_music.h" // from exactly ONE .c file: it defines exports
```

At the start of `boot`:

```c
    zm_request_song("sos.sndh"); // a file under docs/music/
```

### Rust

At the top of the file:

```rust
// The song bridge. Declaring the module defines the exports the host polls.
#[path = "../zigmachine_music.rs"]
mod zigmachine_music;
```

At the start of `boot`:

```rust
    zigmachine_music::request_song("sos.sndh"); // a file under docs/music/
```

**What you should hear.** The music starts **as soon as you click or press a
key** in the page. Browsers only allow sound after a user gesture. The request
waits until then.

**Common mistakes.**

- *Silence, and no error.* No gesture yet; click the screen. Otherwise, check
  the name matches a file in `docs/music/` exactly, 64 bytes at most.
- *C: `duplicate symbol pollSongRequest`.* The header was included from two
  `.c` files of the same cart. It defines the exports, so include it once.
- *An SNDH that loads but plays nothing.* Some need the STE's DMA sound chip
  (`FLAG ~a`), which this machine does not have. Listen before you ship one.
- *A multi-song SNDH plays the wrong tune.* Use
  `requestSongTune(name, n)` / `zm_request_song_tune` /
  `request_song_tune`. Subtunes count from 1, and 0 is the file's default.

---

## Step 8, going further: opening the borders

Your screen is a normal plane: 320x200, border closed. Two directions from here,
both with working examples: this step opens the borders, the next one puts the
blitter to work.

**Open the borders.** On an ST the border is opened by flickering the video
resolution at an exact moment on each scanline. ZigMachine makes you earn it the
same way. Put the plane in overscan mode (400x280), register the plane's HBL at
the magic column `OVERSCAN_MAGIC_X` (40), and flicker the resolution register
from the handler. Miss the column and that line's border shows garbage. In Zig
it is one call, `fb.openBorders(.all)`, or pass `.{ .flicker = true }` to
`zg.copper.install` to keep your rasters. In C, `apps/c/scenes/screen34.c` does
it by hand:

```c
// Open the border on THIS scanline, ST-style: flicker the resolution register
// medium->planes. The sealed machine cannot trap writes to shared memory, so the
// flicker latch is bumped too — that is what it samples once per line.
__attribute__((export_name("hblDispatch")))
void hblDispatch(u32 id, u32 plane, u32 line, u32 x) {
    (void)id; (void)plane; (void)line; (void)x;
    w8(REG_RESOLUTION, RES_MEDIUM);
    w8(REG_RESOLUTION, RES_PLANES);
    w16(REG_RES_FLICKER, (u16)(r16(REG_RES_FLICKER) + 1));
}
```

Remember the line numbers: once a plane is in overscan mode, its HBL gets
**physical** lines 0..279, so a raster table indexed by logical line moves 40
lines. `zg.copper` handles that for you.

## Step 9, going further: the blitter, and what a technique costs

**Goal.** A 3D torus shaded as a grid of dots, drawn by the 2D coprocessor —
and then drawn three more ways over the same data, with the cost of each on
screen, so the techniques can be judged against each other.

**Concept.** The machine has a blitter: fills, lines, triangles and masked
blits. You set up a block of registers at `0x80` in the video region — what to
draw, where, in what colour, combined how — and call `hwBlit()`. It runs
synchronously and reports what it cost in `BLIT_CYCLES`.
`docs/BLITTER_HW_SPEC.md` is the full register map;
`apps/zig/scenes/blitter_demo.zig` exercises the operations one at a time. The
worked example here is **POLKA DOTS** (`apps/zig/scenes/polkadots/`), which you
can run from the menu.

**The split it wants.** POLKA DOTS divides the frame in two:

- **the CPU decides** — `torus.zig` projects the torus, `shade.zig` reduces it
  to a 45x28 grid of one byte per cell: how bright that cell is, 0..10
- **the blitter draws** — and it draws that same grid FOUR different ways, on
  keys 1 to 4

Nothing above the renderer changes when you press a key. That is the point of
the screen: the intensity grid is the interface between the two halves, and
turning intensity into pixels is a separate decision with a separate cost.

**Technique 1: dot SIZE, one blit per cell.** The ten dot sizes live side by
side in one 70x7 sheet, so the brightness *is* the source-x. There is no
branching on brightness and no second image: the cell value picks which part of
the sheet to blit. This is how newsprint halftone works, and no fixed pattern
can do it.

**Technique 2: the HALFTONE register, one fill per run.** The blitter carries a
16x16 one-bit pattern in `HALFTONE[16]`. Load it, and every `FILL` paints
`COLOR` where a bit is set and `BG_COLOR` where it is clear — the *density* half
of halftone, and what an ST blitter could actually do. Two things follow, and
together they are the whole lesson.

The pattern is fixed for the duration of the operation, so the dot **cannot**
change size within one fill. Intensity has to come from how many bits are set:
POLKA DOTS builds ten ordered-dither (Bayer) patterns whose densities are the
ink counts of the ten dots in the sheet — `0, 1, 5, 9, 13, 17, 25, 37, 45, 49`
pixels out of 49, rescaled to bits out of 64 — so both techniques draw the same
ramp.

And because the pattern is anchored to *screen* coordinates rather than to the
operation, neighbouring cells of the same brightness dither continuously into
each other. So a whole **run** of equal cells can be covered by ONE fill instead
of one per cell. That is where the operations go.

### Zig

`zg.Blitter` wraps the register block. The stamp, from `polkadots/dots.zig`:

```zig
pub const CELL = 7;           // the dot cell, from the original's initTile(7, 7)
const SHEET_W: u16 = 70;      // ten 7x7 dots side by side
const PAT = @embedFile("../../assets/screens/polkadots/pat.raw");

pub fn stamp(fb: *zg.LogicalFB, bl: *zg.Blitter, grid: *const shade.Grid) Cost {
    var cost = Cost{};
    for (0..shade.CELLS_Y) |cy| {
        const dy = Y_OFF + @as(i16, @intCast(cy * CELL));
        for (0..shade.CELLS_X) |cx| {
            const cell = grid[cy * shade.CELLS_X + cx];
            if (cell == 0) continue;               // dark: draw nothing at all
            const sx: u16 = @as(u16, cell - 1) * CELL;  // brightness IS source-x
            const dx = X_OFF + @as(i16, @intCast(cx * CELL));
            bl.blitImage(fb, dx, dy, PAT, SHEET_W, sx, 0, CELL, CELL, null);
            cost.ops += 1;
            cost.px += bl.cycles();                // what the blitter reports
        }
    }
    return cost;
}
```

`blitImage` takes the destination plane and position, then the source: the sheet
in cart RAM, its width, the source x/y, and the size to copy. The trailing
`null` is the colour key — these tiles are fully opaque, so each one paints its
own field over whatever was there and no masking is needed.

The halftone pass, from `polkadots/modes.zig`, loads one pattern per intensity
that is actually present in the frame and then fills runs:

```zig
for (1..LEVELS) |lvl| {
    if (present & (@as(u16, 1) << @intCast(lvl + 1)) == 0) continue;
    bl.setHalftone(PATTERNS[lvl]);   // 16 register writes, not an operation
    fillLevel(fb, bl, grid, @intCast(lvl + 1), &cost);
}
```

and `fillLevel` walks each cell row, finds the maximal run of cells holding that
intensity, and issues ONE `bl.fill(fb, x, y, cells * CELL, CELL, ink)` for it.

### C

There is no wrapper: you write the registers yourself, the way
`apps/c/scenes/screen34.c` writes the resolution register in the previous step.
`w8`/`w16`/`w32` are the same one-line helpers, and `hwBlit` is imported like
`hwVideoBase`:

```c
#define OFF_BLIT      0x80
#define BLIT_COMMAND  (OFF_BLIT + 0x00)
#define BLIT_MINTERM  (OFF_BLIT + 0x01)
#define BLIT_CON      (OFF_BLIT + 0x02)
#define BLIT_COLOR    (OFF_BLIT + 0x04)
#define BLIT_BG_COLOR (OFF_BLIT + 0x05)
#define BLIT_CON2     (OFF_BLIT + 0x07)
#define BLIT_B_BASE   (OFF_BLIT + 0x10)
#define BLIT_B_STRIDE (OFF_BLIT + 0x14)
#define BLIT_D_BASE   (OFF_BLIT + 0x20)
#define BLIT_D_STRIDE (OFF_BLIT + 0x24)
#define BLIT_W        (OFF_BLIT + 0x28)
#define BLIT_H        (OFF_BLIT + 0x2A)
#define BLIT_X0       (OFF_BLIT + 0x2C)
#define BLIT_Y0       (OFF_BLIT + 0x2E)
#define BLIT_HALFTONE (OFF_BLIT + 0x40)
#define CMD_BLIT 1
#define CMD_FILL 2
#define CON_USEB 0x02      // channel B (the image) enabled
#define CON2_SRC_ABS 0x01  // B_BASE is an absolute address, not a region offset
#define MT_B 0xCC          // D = B: copy the source through untouched

__attribute__((import_module("env"), import_name("hwBlit")))
extern void hwBlit(void);

static const u8 PAT[70 * 7] = { /* the ten dots, side by side */ };

static void stamp(int dx, int dy, int level) {
    w32(BLIT_D_BASE, OFF_VRAM);             // destination: plane 0
    w16(BLIT_D_STRIDE, W);
    w32(BLIT_B_BASE, (u32)&PAT[level * 7]); // brightness IS source-x
    w16(BLIT_B_STRIDE, 70);
    w8(BLIT_CON2, CON2_SRC_ABS);            // the sheet is in the cart, not VRAM
    w8(BLIT_CON, CON_USEB);
    w8(BLIT_MINTERM, MT_B);
    w16(BLIT_X0, dx); w16(BLIT_Y0, dy);
    w16(BLIT_W, 7);   w16(BLIT_H, 7);
    w8(BLIT_COMMAND, CMD_BLIT);
    hwBlit();
}
```

The halftone half is a pattern load and a fill. `CON` is 0 because `FILL` uses
no source channel at all:

```c
static void load_halftone(const u16 pattern[16]) {
    for (int i = 0; i < 16; i++) w16(BLIT_HALFTONE + i * 2, pattern[i]);
}

static void fill_run(int dx, int dy, int cells, u8 ink) {
    w32(BLIT_D_BASE, OFF_VRAM);
    w16(BLIT_D_STRIDE, W);
    w8(BLIT_CON, 0);
    w8(BLIT_COLOR, ink);      // where a pattern bit is SET
    w8(BLIT_BG_COLOR, 0);     // where it is clear
    w16(BLIT_X0, dx); w16(BLIT_Y0, dy);
    w16(BLIT_W, cells * 7); w16(BLIT_H, 7);
    w8(BLIT_COMMAND, CMD_FILL);
    hwBlit();
}
```

### Rust

The same registers through raw pointers, in the idiom
`apps/rust/scenes/tutorial.rs` already uses for the HBL. The constants are the
offsets from the C block above:

```rust
#[link(wasm_import_module = "env")]
extern "C" { fn hwBlit(); }

static PAT: [u8; 70 * 7] = [/* the ten dots, side by side */];

// SAFETY: a wasm32 cart is single-threaded and these are the machine's own
// registers, inside the video region hwVideoBase() handed us.
unsafe fn stamp(base: usize, dx: i16, dy: i16, level: usize) {
    ((base + BLIT_D_BASE) as *mut u32).write(OFF_VRAM as u32);
    ((base + BLIT_D_STRIDE) as *mut u16).write(W as u16);
    ((base + BLIT_B_BASE) as *mut u32).write(PAT.as_ptr().add(level * 7) as u32);
    ((base + BLIT_B_STRIDE) as *mut u16).write(70);
    ((base + BLIT_CON2) as *mut u8).write(CON2_SRC_ABS);
    ((base + BLIT_CON) as *mut u8).write(CON_USEB);
    ((base + BLIT_MINTERM) as *mut u8).write(MT_B);
    ((base + BLIT_X0) as *mut i16).write(dx);
    ((base + BLIT_Y0) as *mut i16).write(dy);
    ((base + BLIT_W) as *mut u16).write(7);
    ((base + BLIT_H) as *mut u16).write(7);
    ((base + BLIT_COMMAND) as *mut u8).write(CMD_BLIT);
    hwBlit();
}

unsafe fn load_halftone(base: usize, pattern: &[u16; 16]) {
    for (i, row) in pattern.iter().enumerate() {
        ((base + BLIT_HALFTONE + i * 2) as *mut u16).write(*row);
    }
}

unsafe fn fill_run(base: usize, dx: i16, dy: i16, cells: i16, ink: u8) {
    ((base + BLIT_D_BASE) as *mut u32).write(OFF_VRAM as u32);
    ((base + BLIT_D_STRIDE) as *mut u16).write(W as u16);
    ((base + BLIT_CON) as *mut u8).write(0);
    ((base + BLIT_COLOR) as *mut u8).write(ink);
    ((base + BLIT_BG_COLOR) as *mut u8).write(0);
    ((base + BLIT_X0) as *mut i16).write(dx);
    ((base + BLIT_Y0) as *mut i16).write(dy);
    ((base + BLIT_W) as *mut u16).write((cells * 7) as u16);
    ((base + BLIT_H) as *mut u16).write(7);
    ((base + BLIT_COMMAND) as *mut u8).write(CMD_FILL);
    hwBlit();
}
```

**A FILL with no pattern loaded** is the screen's third mode, `SOLID`: the same
runs, one palette entry per intensity, no dither at all. It is the baseline the
other two are measured against — and the reminder that halftone buys you shades
you do not have colours for. On a four-colour ST screen it was the only way to
get ten. The fourth mode, `FILL DOTS`, goes back to one operation per cell but
draws a constant-filled square sized by the intensity, so it isolates what the
source channel costs.

**What you should see.** A torus of red dots turning, and the bottom line
reading the mode, the blitter operations it issued this frame, and the pixels
the blitter reported touching. Press 1 to 4: the shape does not change, only the
technique. Four consecutive frames of the same torus, from
`apps/polkadots_headless.mjs`:

| mode | technique | operations | pixels |
|---|---|---|---|
| 1 DOT SIZE | one BLIT per lit cell, from the sheet | 233 | 11K |
| 2 HALFTONE | one FILL per run, `HALFTONE` + `COLOR` | 108 | 9K |
| 3 SOLID | one FILL per run, palette ramp | 146 | 12K |
| 4 FILL DOTS | one FILL per lit cell, square sized by intensity | 214 | 3K |

Halftone covers the same torus in **less than half** the operations, because a
run of equal cells is one fill — and it looks worse, a grey newsprint dither
instead of round dots that grow. That is exactly the trade the ST offered, and
the harness asserts it rather than leaving it to this paragraph.

The wall-clock figures are worth reading carefully: averaged over 40 rounds
every one of the four modes takes about 0.3 ms a frame, and the differences
between them are inside the measurement noise. They barely differ because the
CPU half — projecting the torus and shading the grid — is the same in all four
and dominates. **Count operations, not just milliseconds:** the op count is what
scales when the effect grows, and it is the number that would have decided the
technique on real hardware.

**Common mistakes.**

- *Every fill comes out dithered, including the screen clear.* The halftone
  pattern is sticky: it stays loaded until you clear it, and the machine treats
  "any non-zero row" as "halftone on". Clear it before a plain fill —
  `bl.clearHalftone()`, or sixteen zero words.
- *The darkest level turns solid.* An all-zero pattern means halftone OFF, not
  "draw nothing", so a level with no bits set fills with `COLOR` at full
  strength. Skip that level instead of loading an empty pattern.
- *The blit draws nothing at all.* If the source is an asset in your cart rather
  than another plane, `CON2.SRC_ABS` must be set — otherwise `B_BASE` is read as
  an offset into the video region, and the machine refuses a source outside the
  windows it can read.
- *The dots are in the right places but the wrong sizes.* `B_BASE` points at the
  first pixel of the source rectangle, not at the start of the sheet: the
  source-x has to be added to the pointer (`PAT + level * CELL`), and
  `B_STRIDE` stays the width of the whole sheet.

## Step 10: PCM audio, streamed off the disk

**Goal.** A sampled loop — a real recording, not a chip tune — plays out of the
machine while its waveform draws on screen, from a file far too big to hold in
RAM.

**Concept.** Step 7's music is a *file name*: the cart asks, the host plays, and
the cart never sees a sample. PCM is the opposite. The machine gives you a
speaker and a drive, and you are the pump between them. Three host imports are
the whole speaker:

| import | what it does |
| --- | --- |
| `hostAudioStreamStart(rate: f32)` | open the stream at `rate` Hz |
| `hostAudioFeed(ptr: u32, len: u32)` | append `len` **signed 8-bit mono** samples |
| `hostAudioStreamStop()` | silence it |

and one is the whole drive: `diskReadBlock(block: u32, dst: u32)` copies one
512-byte block into your RAM and returns how many bytes it moved. They are plain
`env` imports, so a Zig, C or Rust cart reaches them the same way — no bridge
header, unlike the song request.

**The ring is a pump, not a buffer.** Behind `hostAudioFeed` is a 32 KiB ring in
the audio worklet, and the worklet drains it at the sample rate whether or not
your cart is running. Feed too slowly and it replays the lap it has already
played — the stutter. Feed too fast and you overwrite samples it has not reached
yet. At 12517 Hz a 32 KiB ring is 2.6 seconds, so you have two and a half
seconds of slack and no more. Pre-fill about half of it in `init`, before the
first frame; if you do not, playback starts on an empty ring and the first thing
the reader hears is noise.

**Pace by real dt, never by frame count.** This is the trap, and it is the only
part of this step the gate has a harness for. The obvious loop is "feed
`rate / 60` bytes a frame", or the defensive-looking "clamp `dt` to 50 ms so one
bad frame cannot spike the audio". Both are wrong, because the audio clock does
not care how often the page draws. A phone at 18 fps, a 144 Hz monitor, or a tab
hidden for three seconds each leave the song position drifting away from where
the speaker actually is, and once it is a ring away it never comes back. The
correct quantity is bytes the *speaker* consumed since the previous frame:
`rate * dt / 1000`, with the frame's true `dt`. `apps/stream_pacing_check.mjs`
drives the real carts through 30 seconds at 60 Hz, at 144 Hz, at a jittery
18 fps and across a 3 s stall, and fails if the position ever strays more than
one ring from `rate * wall_time`. Given a cart from before this rule it fails,
which is how the harness proves it can see the bug.

**A backlog bigger than the ring is a skip, not a catch-up.** If a stall leaves
you owing 100 KiB, feeding 100 KiB laps the 32 KiB ring three times and the
listener hears only the last lap. Drop whole rings from the budget and move the
*clip* position forward by the same amount — the song jumps, which is what
actually happened, instead of playing three laps of stale audio in fast-forward.

**Finding the file.** The disk is a flat FAT (`docs/FLOPPY_DISK.md`): a `ZMDISK`
descriptor, a file count, then 32-byte entries of `name[16]`, `start: u32`,
`len: u32`, `type: u8`. `start` is a **byte offset into the image**, not a block
number — divide by 512 yourself. There are two layouts, v1 (descriptor `$000`,
count `$2E4`, FAT `$300`) and v2, which puts an executable boot sector first and
moves them to `$400` / `$4F4` / `$800`. Probe v2 first: a v1 image has nothing
at `$400`, but a v2 image has a boot sector at `$000`, so testing v1 first
mis-identifies every v2 disk.

### Zig

ZigOS already owns the FAT walk, so the Zig cart only does the pumping.
`libs/zig/disk.zig` is the reader; `zg.disk.mount()` returns the layout or
`null`, and `zg.disk.find()` a `{ start, len, kind }` entry.

```zig
const RATE: f32 = 12517.0;  // Hz, and the .raw carries no header saying so
const RING: f32 = 32768.0;  // the worklet's stream ring, in bytes
const RING_BLOCKS: u32 = 64; // 32768 / 512

first_block: u32 = 0,
total_blocks: u32 = 0,
file_len: u32 = 0,
cur: u32 = 0,      // blocks fed so far; wraps, which loops the clip
budget: f32 = 0,   // bytes the speaker has consumed and we still owe it
wave: [512]u8 = [_]u8{128} ** 512, // the block we fed last, for the display
```

```zig
    // Pull one block off the disk, feed it to the speaker, keep it to draw.
    fn feedBlock(self: *Demo) void {
        var buf: [512]u8 = undefined;
        _ = zg.readBlock(self.first_block + self.cur, &buf);
        const done = self.cur * 512;
        const n: usize = @min(@as(u32, 512), self.file_len - done); // last block is short
        zg.audioFeed(buf[0..n]);
        @memcpy(self.wave[0..], buf[0..]);
        self.cur += 1;
        if (self.cur >= self.total_blocks) self.cur = 0; // loop
    }
```

In `init`, after the palette:

```zig
        const lay = zg.disk.mount() orelse return;           // no disk in the drive
        const e = zg.disk.find(lay, "MICROMIX.RAW") orelse return;
        self.first_block = e.start / 512;
        self.file_len = e.len;
        self.total_blocks = (e.len + 511) / 512;

        zg.audioStreamStart(RATE);
        for (0..32) |_| self.feedBlock(); // pre-fill ~half the ring
```

And `update` is the pacing rule, in full:

```zig
    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = zigos;
        if (self.total_blocks == 0) return;
        // Bytes the speaker consumed since the previous frame. The REAL dt: a
        // clamped or assumed one leaves the clip behind the speaker for good.
        self.budget += RATE * @max(elapsed_time, 0) / 1000.0;
        // Whole rings of backlog would only lap the ring onto itself. Skip them
        // in the clip instead, then feed at most one ring's worth.
        const rings = @floor(self.budget / RING);
        if (rings > 0) {
            const skip = @as(u64, @intFromFloat(rings)) * RING_BLOCKS;
            self.cur = @intCast((@as(u64, self.cur) + skip) % self.total_blocks);
            self.budget -= rings * RING;
        }
        var guard: u32 = 0;
        while (self.budget >= 512 and guard < RING_BLOCKS) : (guard += 1) {
            self.feedBlock();
            self.budget -= 512;
        }
    }
```

The `guard` is not decoration. `budget` is a float you add to every frame; one
absurd `dt` from a browser that was asleep must cost a bounded number of disk
reads, not a loop that runs until the frame is over.

### C

No ZigOS, so the FAT walk is yours — about twenty lines, and it is the same
twenty lines in any language.

```c
__attribute__((import_module("env"), import_name("diskReadBlock")))
extern int diskReadBlock(unsigned block, void *dst);
__attribute__((import_module("env"), import_name("hostAudioStreamStart")))
extern void hostAudioStreamStart(float rate);
__attribute__((import_module("env"), import_name("hostAudioFeed")))
extern void hostAudioFeed(const void *ptr, unsigned len);

#define RATE        12517.0f
#define RING        32768.0f
#define RING_BLOCKS 64

static unsigned first_block, total_blocks, file_len, cur;
static float budget;
static unsigned char wave[512];
```

```c
static unsigned char blk[512];

// Read the 512-byte block holding `off` and return the offset within it.
static unsigned at(unsigned off) {
    diskReadBlock(off / 512, blk);
    return off % 512;
}
static unsigned rd32(unsigned off) {
    unsigned i = at(off);
    return blk[i] | (blk[i+1] << 8) | (blk[i+2] << 16) | ((unsigned)blk[i+3] << 24);
}
static int magic_at(unsigned off) {
    unsigned i = at(off);
    const char *m = "ZMDISK";
    for (int k = 0; k < 6; k++) if (blk[i + k] != (unsigned char)m[k]) return 0;
    return 1;
}

// Find `name` in the flat FAT. Probes v2 FIRST: a v2 image has a boot sector at
// $000, so testing v1 first would mis-identify it.
static int find_file(const char *name) {
    unsigned count_off, fat;
    if (magic_at(0x400))      { count_off = 0x4f4; fat = 0x800; }
    else if (magic_at(0x000)) { count_off = 0x2e4; fat = 0x300; }
    else return 0;                                   // no ZigMachine disk mounted
    unsigned ci = at(count_off);
    unsigned count = blk[ci] | (blk[ci + 1] << 8);
    for (unsigned i = 0; i < count; i++) {
        unsigned e = at(fat + i * 32), k = 0;
        while (k < 16 && name[k] && blk[e + k] == (unsigned char)name[k]) k++;
        if (name[k] || (k < 16 && blk[e + k])) continue; // both must end here
        first_block = rd32(fat + i * 32 + 0x10) / 512;   // `start` is a BYTE offset
        file_len    = rd32(fat + i * 32 + 0x14);
        total_blocks = (file_len + 511) / 512;
        return 1;
    }
    return 0;
}

static void feed_block(void) {
    unsigned char buf[512];
    diskReadBlock(first_block + cur, buf);
    unsigned done = cur * 512;
    unsigned n = file_len - done < 512 ? file_len - done : 512;
    hostAudioFeed(buf, n);
    for (int i = 0; i < 512; i++) wave[i] = buf[i];
    if (++cur >= total_blocks) cur = 0;
}
```

At the end of `boot`:

```c
    if (find_file("MICROMIX.RAW")) {
        hostAudioStreamStart(RATE);
        for (int i = 0; i < 32; i++) feed_block(); // pre-fill ~half the ring
    }
```

And in `frame(float dt)`:

```c
    if (total_blocks) {
        budget += RATE * (dt > 0 ? dt : 0) / 1000.0f;   // the REAL dt, never rate/60
        while (budget >= RING) {                        // a whole ring behind: skip it
            cur = (cur + RING_BLOCKS) % total_blocks;
            budget -= RING;
        }
        for (int g = 0; budget >= 512.0f && g < RING_BLOCKS; g++) {
            feed_block();
            budget -= 512.0f;
        }
    }
```

Note `find_file` reuses one static `blk` buffer for every probe, so `rd32` must
re-read before each field: `at()` is what makes that safe, and reading two fields
from one stale `blk` is the bug waiting in any shortened version of this.

### Rust

```rust
#[link(wasm_import_module = "env")]
extern "C" {
    fn diskReadBlock(block: u32, dst: *mut u8) -> i32;
    fn hostAudioStreamStart(rate: f32);
    fn hostAudioFeed(ptr: *const u8, len: u32);
}

const RATE: f32 = 12517.0;
const RING: f32 = 32768.0;
const RING_BLOCKS: u32 = 64;

pub struct Stream {
    first_block: u32,
    total_blocks: u32,
    file_len: u32,
    cur: u32,
    budget: f32,
    pub wave: [u8; 512],
    blk: [u8; 512],
}
```

```rust
impl Stream {
    /// Read the block holding `off`; returns the offset within `self.blk`.
    fn at(&mut self, off: u32) -> usize {
        // SAFETY: the drive copies exactly 512 bytes into a 512-byte buffer.
        unsafe { diskReadBlock(off / 512, self.blk.as_mut_ptr()) };
        (off % 512) as usize
    }
    fn rd32(&mut self, off: u32) -> u32 {
        let i = self.at(off);
        u32::from_le_bytes(self.blk[i..i + 4].try_into().unwrap())
    }
    fn magic_at(&mut self, off: u32) -> bool {
        let i = self.at(off);
        &self.blk[i..i + 6] == b"ZMDISK"
    }

    /// Probes v2 FIRST: a v2 image has a boot sector at $000, so testing v1
    /// first would mis-identify it.
    pub fn open(&mut self, name: &str) -> bool {
        let (count_off, fat) = if self.magic_at(0x400) {
            (0x4f4, 0x800)
        } else if self.magic_at(0x000) {
            (0x2e4, 0x300)
        } else {
            return false; // no ZigMachine disk mounted
        };
        let i = self.at(count_off);
        let count = u16::from_le_bytes([self.blk[i], self.blk[i + 1]]) as u32;
        for n in 0..count {
            let e = self.at(fat + n * 32);
            let raw = &self.blk[e..e + 16];
            let end = raw.iter().position(|&b| b == 0).unwrap_or(16);
            if &raw[..end] != name.as_bytes() {
                continue;
            }
            self.first_block = self.rd32(fat + n * 32 + 0x10) / 512; // a BYTE offset
            self.file_len = self.rd32(fat + n * 32 + 0x14);
            self.total_blocks = (self.file_len + 511) / 512;
            return true;
        }
        false
    }

    fn feed_block(&mut self) {
        let mut buf = [0u8; 512];
        // SAFETY: 512 bytes into a 512-byte buffer, then `n` of them to the ring.
        unsafe {
            diskReadBlock(self.first_block + self.cur, buf.as_mut_ptr());
            let n = (self.file_len - self.cur * 512).min(512);
            hostAudioFeed(buf.as_ptr(), n);
        }
        self.wave = buf;
        self.cur += 1;
        if self.cur >= self.total_blocks {
            self.cur = 0; // loop
        }
    }

    pub fn start(&mut self) {
        // SAFETY: opening the speaker; the host validates the rate.
        unsafe { hostAudioStreamStart(RATE) };
        for _ in 0..32 {
            self.feed_block(); // pre-fill ~half the ring
        }
    }

    /// Call once a frame with the frame's REAL dt in ms — never `1000.0 / 60.0`.
    pub fn pump(&mut self, dt: f32) {
        if self.total_blocks == 0 {
            return;
        }
        self.budget += RATE * dt.max(0.0) / 1000.0;
        while self.budget >= RING {
            // A whole ring behind: skip the clip forward, do not replay the lap.
            self.cur = (self.cur + RING_BLOCKS) % self.total_blocks;
            self.budget -= RING;
        }
        let mut guard = 0;
        while self.budget >= 512.0 && guard < RING_BLOCKS {
            self.feed_block();
            self.budget -= 512.0;
            guard += 1;
        }
    }
}
```

In `boot`, `if s.stream.open("MICROMIX.RAW") { s.stream.start(); }`; in
`frame(dt)`, `s.stream.pump(dt);`.

**What you should hear.** The clip, at pitch, looping seamlessly, and staying
in step with the picture no matter what the frame rate does. Drawing
`wave[x * 512 / 320]` as a signed byte gives you the oscilloscope the STREAM
scene shows. As in step 7, nothing sounds until the reader clicks: a stream
started before the gesture is held and pre-filled, then released.

**Common mistakes.**

- *It plays, then slowly goes out of sync with the screen and never recovers.*
  Paced by frame count, or with `dt` clamped. Use the frame's real `dt`.
- *A short buzzing lap repeats after the tab was hidden.* The backlog was fed
  instead of skipped: whole rings must move the clip, not the ring.
- *Noise for the first half-second.* No pre-fill — the ring started empty.
- *The sample plays at the wrong speed, or as a chainsaw.* A `.raw` has no
  header: the rate is something you must know, and the samples must be signed
  8-bit mono. Unsigned bytes fed as signed become a square wave.
- *Nothing at all, on a disk you know has the file.* The FAT was probed v1
  first and matched a v2 image's boot sector, or `start` was used as a block
  number instead of a byte offset.
- *The last few samples click on every loop.* The final block is short; feed
  `len - cur * 512` bytes, not 512.

---

## Step 11: loading and drawing a 3D object

**Goal.** A Wavefront `.obj` model — an icosahedron, a gem, a logo — spinning
on screen, flat-shaded by the blitter, drawn from the same file a modelling
package exports.

**Why this step is Zig only.** Everything a scene needs here is *in ZigOS*: the
OBJ parser (`zg.obj`, `libs/zig/utils/obj_loader.zig`), the wireframe camera
pipeline (`zg.wireframe`) and the three.js-exact projector (`zg.zig3d`). ZigOS
is a Zig library that compiles **into** the cart, so a C or Rust cart cannot
link against it. What those carts see is the sealed ABI — registers, `hwBlit`,
the ROM's exports — and there is no 3D in the ABI, because 3D on this machine
is the CPU's job, the same way it was on a 68000. A C or Rust cart can
absolutely spin a model; it brings its own parser and its own matrices, roughly
the sixty lines below rewritten. That is a different tutorial, not a
translation of this one. The *drawing* half — `triangle`, `line` and the glenz
minterm in step 12 — is hardware and is reachable from all three languages.

**Concept.** The whole pipeline is four steps and no hardware knows about any
of them until the last:

1. parse the `.obj` into vertices and triangles, once;
2. every frame, rotate each vertex and project it to screen x/y;
3. sort the faces far-to-near, and shade each one from its normal;
4. hand the blitter three screen points per face.

**Two loaders, and they are not interchangeable.** `zg.obj` has both, and
picking the wrong one is the first thing that goes wrong:

| | `Mesh.load(text)` | `obj.parseWire(text)` |
| --- | --- | --- |
| when | at run time, in `init` | at **comptime** |
| reads | `v` vertices, `f` faces (fan-triangulated) | `v` vertices, `l` line records |
| geometry | **recentred and scaled to a unit sphere** | kept exactly as written |
| costs | the fixed `Mesh` struct, always | only the arrays you name; the text stays at comptime |
| for | solid objects you will fill | line objects: logos, grids, ships |

The normalising is the trap. `Mesh.load` rescales *every* model to the same
size, which is what you want when the reader can cycle models and what you
absolutely do not want for a hand-placed logo — pass that one through
`parseWire`, whose contract is that your coordinates survive bit for bit.

**Fixed capacity, because there is no allocator.** `obj.Mesh` is
`MAX_VERTS = 2048` vertices and `MAX_FACES = 4096` faces as plain arrays, about
49 KB, and it costs that whether your model has twelve faces or four thousand.
Add the scene's own `pos` and `screen` arrays and a spinning-object scene is
80 KB of RAM before it draws anything. That is affordable once. It is also why
you should **not** write `self.* = .{}` to reset a struct this size: on a large
struct that emits a second, duplicate data segment in the cart, and this repo
has paid 517 KB for that mistake. Reset the fields you actually mean to reset.

**Sort the faces; there is no z-buffer.** The machine has one byte per pixel
and no depth buffer, so visibility is the painter's algorithm: order the faces
by average z and draw far ones first. An insertion sort over an index array is
the right call here — a few hundred faces, already nearly sorted from the
previous frame, so it runs in close to linear time and never allocates.

**Three cameras, pick on purpose.** The projection below is hand-rolled: three
Euler rotations and a divide by `z + DIST`, about fifteen lines, and it is what
most scenes should use. `zg.wireframe` is the matrix pipeline (zalgebra `Mat4`,
camera → projection → 1/w → screen) that the line-object scenes share. `zg.zig3d`
is something else entirely: a replay of three.js r49's projector, f32 matrix
storage and all, so that a CODEF port renders the *same* pixels as the original
remake. Reach for `zig3d` only when byte-fidelity with a CODEF screen is the
point; it is a fidelity tool, not a faster camera.

### Zig

The model is text, embedded at compile time and parsed at boot:

```zig
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Blitter = zg.Blitter;
const Vec2 = zg.BlitVec2;   // { x: i16, y: i16 } — what the blitter takes
const obj = zg.obj;

const W: i32 = zg.WIDTH;
const H: i32 = zg.HEIGHT;
const DIST: f32 = 3.2;      // camera distance; the mesh is a unit sphere
const FOV: f32 = 150.0;     // pixels per unit at z = 1
const LEVELS: u8 = 12;      // shade ramp, palette indices 1..12
const LIGHT = [3]f32{ 0.36, 0.48, -0.80 };

const MODEL = @embedFile("../assets/obj/icosahedron.obj");

pub const Demo = struct {
    blitter: Blitter = .{},
    mesh: obj.Mesh = .{},
    ax: f32 = 0,
    ay: f32 = 0,
    pos: [obj.MAX_VERTS][3]f32 = undefined,    // rotated, before projection
    screen: [obj.MAX_VERTS]Vec2 = undefined,   // projected, ready to blit

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.blitter.init();
        const fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 0, .a = 0 });
        for (0..LEVELS) |l| {
            const f: f32 = @as(f32, @floatFromInt(l)) / @as(f32, LEVELS - 1);
            fb.setPaletteEntry(1 + @as(u8, @intCast(l)), .{
                .r = chan(0.15 + 0.85 * f),
                .g = chan(0.45 + 0.55 * f),
                .b = chan(0.55 + 0.45 * f),
                .a = 255,
            });
        }
        self.mesh.load(MODEL); // runtime parse into the fixed-capacity mesh
    }
```

`update` turns the object and projects it. Rotation and projection belong here,
not in `render`: `render` may be called for more than one plane.

```zig
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.ax += 0.019;
        self.ay += 0.027;
        const sx = @sin(self.ax);
        const cx = @cos(self.ax);
        const sy = @sin(self.ay);
        const cy = @cos(self.ay);
        for (self.mesh.verts[0..self.mesh.nverts], 0..) |p, i| {
            const y1 = p.y * cx - p.z * sx;      // rotate about X
            const z1 = p.y * sx + p.z * cx;
            const x2 = p.x * cy + z1 * sy;       // then about Y
            const z2 = -p.x * sy + z1 * cy;
            self.pos[i] = .{ x2, y1, z2 };
            const zc = z2 + DIST;                // push it in front of the camera
            self.screen[i] = .{
                .x = @intFromFloat(@as(f32, @floatFromInt(@divTrunc(W, 2))) + x2 * FOV / zc),
                .y = @intFromFloat(@as(f32, @floatFromInt(@divTrunc(H, 2))) + y1 * FOV / zc),
            };
        }
    }
```

`render` sorts, shades and blits — three screen points per face:

```zig
    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb: *LogicalFB = &zigos.lfbs[0];
        const b = &self.blitter;
        b.clear(fb, 0);
        var order: [obj.MAX_FACES]u16 = undefined;
        self.sortFaces(&order);
        for (order[0..self.mesh.nfaces]) |f| {
            const t = self.mesh.faces[f];
            const shade: u8 = 1 + self.brightness(f);
            b.triangle(fb, self.screen[t.a], self.screen[t.b], self.screen[t.c], shade);
        }
    }

    // Lambert on the face normal: |n . light| / |n|, quantised to the ramp.
    // The ABSOLUTE value is deliberate — with no back-face culling a face turned
    // away would otherwise go black and punch a hole in the solid.
    fn brightness(self: *Demo, face: u16) u8 {
        const t = self.mesh.faces[face];
        const a = self.pos[t.a];
        const n = cross(sub(self.pos[t.b], a), sub(self.pos[t.c], a));
        const d = @abs(dot(n, LIGHT)) / (len(n) + 0.0001);
        return @intFromFloat(@min(d, 0.999) * @as(f32, LEVELS - 1));
    }

    // Painter's algorithm: far faces first. Insertion sort over an index array,
    // which is near-linear on a list that was already sorted last frame.
    fn sortFaces(self: *Demo, order: *[obj.MAX_FACES]u16) void {
        const n = self.mesh.nfaces;
        for (0..n) |i| order[i] = @intCast(i);
        var i: usize = 1;
        while (i < n) : (i += 1) {
            const cur = order[i];
            const key = self.avgZ(cur);
            var j: usize = i;
            while (j > 0 and self.avgZ(order[j - 1]) < key) : (j -= 1) order[j] = order[j - 1];
            order[j] = cur;
        }
    }

    fn avgZ(self: *Demo, face: u16) f32 {
        const t = self.mesh.faces[face];
        return self.pos[t.a][2] + self.pos[t.b][2] + self.pos[t.c][2];
    }
};

fn chan(v: f32) u8 {
    return @intFromFloat(@max(@as(f32, 0), @min(v, 1.0)) * 255.0);
}
fn sub(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
fn cross(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}
fn dot(a: [3]f32, b: [3]f32) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
fn len(a: [3]f32) f32 {
    return @sqrt(dot(a, a));
}
```

Swap `b.triangle` for three `b.line(fb, va.x, va.y, vb.x, vb.y, 201, .copy)`
calls and the same mesh is a wireframe; swap it for `b.triangleEx(...,
.glenz)` and it is see-through, which is step 12.

For a line object — a logo, a grid — use the comptime loader instead, and note
that only the arrays you name reach the cart:

```zig
const logo = obj.parseWire(@embedFile("../assets/obj/empire_logo.obj"));
var verts = zg.wireframe.vec4s(logo.verts.len, logo.verts);
```

`apps/zig/scenes/obj_demo.zig` is this step finished, with four renderers
(hardware flat, glenz, hardware wireframe and a CPU scanline fill of the same
mesh) on keys 1-4 so you can watch the same geometry go through hardware and
software side by side.

**What you should see.** A solid icosahedron turning on two axes, its faces
shading from teal to white as they face the light, with no seams or popping
where faces meet. Swap in `gem.obj` and nothing about the code changes — the
loader normalises it to the same size.

**Common mistakes.**

- *The object turns inside out, or near faces vanish behind far ones.* The face
  sort is backwards, or sorting by one vertex's z instead of the face's average.
- *Black wedges flicker across the solid as it turns.* The shade came out 0.
  Take `@abs` of the dot product, or cull back faces properly — not neither.
- *A logo loads at the wrong size or in the wrong place.* `Mesh.load` recentred
  and rescaled it. Use `obj.parseWire` when the coordinates are the point.
- *The model is a mess of long triangles across the screen.* An `f` record used
  negative (relative) indices, which this loader does not support, or the model
  has more than `MAX_VERTS` vertices and the extra ones silently became index 0.
- *The cart grew by hundreds of KB after a refactor.* Something did
  `self.* = .{}` on the struct holding the mesh. Assign the fields instead.
- *It is smooth at 200 faces and a slideshow at 2000.* Every vertex is
  transformed in f32 on the CPU each frame; the blitter only fills. Reduce the
  model, or cull back faces before you sort.

---

## Step 12: glenz vectors, the OR minterm

**Goal.** A solid object you can see through: every face translucent, and every
overlap a colour of its own. The Amiga trick, on the hardware that did it.

**Concept.** Step 9 drove the blitter two ways — one stamp per cell, and one
halftone fill per run — and both left `MINTERM` at `MT_B`, `D = B`: copy the
source through untouched. That byte at `OFF_BLIT + 0x01` is the register that
makes the blitter a *coprocessor* rather than a fast memcpy. It is the
truth table of the three sources A, B and C, applied bit by bit to the 8-bit
palette index, so the blitter computes `D = LF(A, B, C)` per pixel in one pass.
Three of the 256 functions have names in ZigOS:

| `Minterm` | byte | `D =` | what it is |
| --- | --- | --- | --- |
| `.copy` | `0xCC` | `B` | a flat fill |
| `.xor` | `0x66` | `B ^ C` | reversible: draw it twice and it is gone |
| `.glenz` | `0xEE` | `B \| C` | **OR into the destination — glenz** |

**OR is not alpha.** There is no blending here and nothing is multiplied by
anything. The blitter takes the ink you set in `COLOR`, ORs it into the index
already in the framebuffer, and writes the result back. Ink 1 over a background
of 0 gives 1. Ink 2 over that same pixel gives 3. Nothing about 3 is "half of
1 and half of 2" — 3 is simply a different palette entry, and *you decide what
colour it is*. The transparency is entirely in the palette you write. This is
why the technique is cheap enough for a 68000: no per-pixel arithmetic, just an
OR gate and a lookup.

**Choose inks that are single bits.** That is the whole design rule. Give each
face an ink of `1 << k`, and then every possible overlap of those faces lands on
an index nothing else can produce: faces 1 and 2 overlap at 3, faces 1, 2 and 4
at 7, and so on. With six bits you have 63 reachable indices and a palette entry
for each. Program them by *adding the hues of the bits that are set*, and you
get a solid that looks additively lit for free:

```zig
// Index i means "these faces overlap here": bit k set = face-group k is in.
var i: u8 = 1;
while (i < 64) : (i += 1) {
    var acc = [3]f32{ 0, 0, 0 };
    for (0..6) |k| if (i & (@as(u8, 1) << @intCast(k)) != 0) {
        for (0..3) |c| acc[c] += HUE[k][c];
    };
    fb.setPaletteEntry(i, rgb(acc, 0.72));
    if (i == 63) break;
}
```

Use a plain index — 5, say — for one of these faces and the scheme collapses:
5 is 1|4, so that face is indistinguishable from an overlap of the first and
third, and the object develops patches of the wrong colour that move with the
geometry.

**The background must be index 0.** `x | 0 == x`, so drawing over 0 leaves your
ink intact, and — the other direction — an ink of 0 leaves the destination
untouched. That second property is what lets the glenz object share a plane
with something else, and it is how `apps/zig/scenes/tsl_hybridglenz/` puts two
objects through each other: each one is drawn through a `HALFTONE` of alternating
full rows with `BG_COLOR` 0, so object A owns the even scanlines, object B the
odd ones, and neither clears the other's rows. Two interpenetrating glenz objects
with no off-screen buffer and no compositing pass.

**OR is symmetric, and that is a real limitation — state it honestly.** `a | b`
is `b | a`, so the hardware genuinely cannot tell which face is in front. A red
face over a white one and a white face over a red one both land on the same
index and therefore the same colour. Sorting your faces before you draw them
changes nothing at all, which is disorienting the first time: with `.copy` the
sort is everything, with `.glenz` it is wasted work. Live with it — this is what
glenz vectors looked like in 1990 and the reason they look *right* — or, if one
particular pair reads badly, renumber so those two faces do not share a
combination (the `GLENZ_RW` entry in that scene's `assets.zig` is exactly one
such hand-fixed pair). What you cannot do is recover depth from an OR.

**You still need the geometry.** Nothing in this step projects anything: the
three screen points come from step 11's pipeline, or from `zg.zig3d` when the
scene is a CODEF port. Glenz is a *drawing* mode, and the only thing that
changes from a flat-shaded object is the minterm and the ink.

### Zig

`triangleEx` is `triangle` with the minterm and a background index exposed:

```zig
fn drawGlenz(self: *Demo, fb: *LogicalFB) void {
    const b = &self.blitter;
    for (self.mesh.faces[0..self.mesh.nfaces], 0..) |t, i| {
        const bit: u8 = @as(u8, 1) << @intCast(i % 6); // ink = ONE bit
        b.triangleEx(fb, self.screen[t.a], self.screen[t.b], self.screen[t.c], bit, 0, .glenz);
    }
}
```

No face sort, because it would do nothing. To interlace two objects, load a
halftone of whole rows around the draw:

```zig
// Rows of the 16x16 halftone this object owns; `odd` picks rows 1,3,5...
fn stripes(comptime odd: bool) [16]u16 {
    var p: [16]u16 = undefined;
    for (&p, 0..) |*row, i| row.* = if ((i & 1 == 1) == odd) 0xFFFF else 0;
    return p;
}

bl.setHalftone(stripes(true));
// ... triangleEx calls, all with bg 0 ...
bl.clearHalftone();
```

`clearHalftone` is not optional. The pattern is a register, not an argument: it
stays loaded, and the next scene primitive that expects a solid fill will come
out striped.

### C

Step 9's register block and its `w8`/`w16`/`w32` helpers, with three more names.
As there, `D_BASE` is a **region offset**, not a pointer — the blitter writes
only video memory — so plane 0's destination is `OFF_VRAM`.

```c
#define BLIT_X1           (OFF_BLIT + 0x30) // i16 x2: triangle v1
#define BLIT_X2           (OFF_BLIT + 0x34) // i16 x2: triangle v2
#define CMD_TRIANGLE      4
#define MT_OR_BC          0xEE // D = B | C — additive glenz transparency
```

```c
// One see-through triangle. `ink` must be a SINGLE BIT for the overlap
// palette to mean anything: 1, 2, 4, 8, 16, 32.
static void glenz_triangle(int x0, int y0, int x1, int y1, int x2, int y2, u8 ink) {
    w32(BLIT_D_BASE, OFF_VRAM);      // destination: plane 0
    w16(BLIT_D_STRIDE, W);
    w8(BLIT_CON, 0);                 // no source channel: TRIANGLE uses COLOR
    w8(BLIT_MINTERM, MT_OR_BC);
    w8(BLIT_COLOR, ink);
    w8(BLIT_BG_COLOR, 0);            // 0 OR dest leaves dest alone
    w16(BLIT_X0, x0); w16(BLIT_Y0, y0);
    w16(BLIT_X1, x1); w16(BLIT_X1 + 2, y1);
    w16(BLIT_X2, x2); w16(BLIT_X2 + 2, y2);
    w8(BLIT_COMMAND, CMD_TRIANGLE);
    hwBlit(); // registers are inert memory until this runs the op
}

// The 63 overlap colours, built by adding the hues of the bits that are set.
static void program_glenz_palette(void) {
    static const float HUE[6][3] = {
        {0.95f, 0.30f, 0.40f}, {0.30f, 0.90f, 0.50f}, {0.98f, 0.80f, 0.20f},
        {0.30f, 0.60f, 0.98f}, {0.85f, 0.40f, 0.95f}, {0.30f, 0.90f, 0.90f},
    };
    for (int i = 1; i < 64; i++) {
        float acc[3] = {0, 0, 0};
        for (int k = 0; k < 6; k++)
            if (i & (1 << k)) for (int c = 0; c < 3; c++) acc[c] += HUE[k][c];
        palette()[i] = rgba(chan(acc[0] * 0.72f), chan(acc[1] * 0.72f), chan(acc[2] * 0.72f));
    }
}

static u32 chan(float v) {
    if (v < 0) v = 0;
    if (v > 1) v = 1;
    return (u32)(v * 255.0f);
}
```

Drawing a face is then `glenz_triangle(x0, y0, x1, y1, x2, y2, 1 << (i % 6));`.

### Rust

Step 9's constants, plus the triangle command and the OR minterm:

```rust
const BLIT_X0: usize = OFF_BLIT + 0x2C; // X0 Y0 X1 Y1 X2 Y2, six contiguous i16
const CMD_TRIANGLE: u8 = 4;
const MT_OR_BC: u8 = 0xEE; // D = B | C — additive glenz transparency

/// One see-through triangle. `ink` must be a SINGLE BIT (1, 2, 4, 8, 16, 32)
/// or the overlap palette stops meaning anything.
fn glenz_triangle(base: usize, v: [(i16, i16); 3], ink: u8) {
    // SAFETY: the blitter register block, inside the video region. Nothing runs
    // until hwBlit(); these writes are inert memory.
    unsafe {
        ((base + BLIT_D_BASE) as *mut u32).write(OFF_VRAM as u32);
        ((base + BLIT_D_STRIDE) as *mut u16).write(W as u16);
        ((base + BLIT_CON) as *mut u8).write(0);
        ((base + BLIT_MINTERM) as *mut u8).write(MT_OR_BC);
        ((base + BLIT_COLOR) as *mut u8).write(ink);
        ((base + BLIT_BG_COLOR) as *mut u8).write(0); // 0 OR dest leaves dest
        let p = (base + BLIT_X0) as *mut i16;
        for (i, (x, y)) in v.iter().enumerate() {
            p.add(i * 2).write(*x);
            p.add(i * 2 + 1).write(*y);
        }
        ((base + BLIT_COMMAND) as *mut u8).write(CMD_TRIANGLE);
        hwBlit();
    }
}

/// The 63 overlap colours: add the hues of the bits that are set.
fn program_glenz_palette(pal: &mut [u32]) {
    const HUE: [[f32; 3]; 6] = [
        [0.95, 0.30, 0.40], [0.30, 0.90, 0.50], [0.98, 0.80, 0.20],
        [0.30, 0.60, 0.98], [0.85, 0.40, 0.95], [0.30, 0.90, 0.90],
    ];
    for i in 1..64usize {
        let mut acc = [0.0f32; 3];
        for (k, hue) in HUE.iter().enumerate() {
            if i & (1 << k) != 0 {
                for c in 0..3 {
                    acc[c] += hue[c];
                }
            }
        }
        pal[i] = rgba(chan(acc[0] * 0.72), chan(acc[1] * 0.72), chan(acc[2] * 0.72));
    }
}

fn chan(v: f32) -> u32 {
    (v.clamp(0.0, 1.0) * 255.0) as u32
}
```

**What you should see.** A solid object whose every face you can see through,
with the overlaps picking up their own colours as it turns — six hues where a
single face is in the way, brighter mixes where two or three are. The silhouette
stays crisp: each face is still a hardware-filled triangle, so there are no soft
edges anywhere. Key 2 of `apps/zig/scenes/obj_demo.zig` is this, on the same
mesh as step 11's flat shading, so you can flip between them.

**Common mistakes.**

- *The object is one flat colour with no overlaps visible.* The inks are not
  single bits — `1, 2, 3, 4, 5, 6` looks reasonable and is wrong. Use
  `1 << (i % 6)`.
- *It draws over the background instead of through it.* The minterm is still
  `.copy`. `0xCC` is `D = B`; you want `0xEE`.
- *The object smears and never clears.* OR can only set bits, never clear them,
  so a glenz object **must** be drawn onto a cleared plane every frame. There is
  no "undraw" — that is `.xor`'s trick, not this one.
- *Overlaps show as black holes.* Those indices have no palette entry. All 63
  combinations you can reach need a colour, not just the six singles.
- *Everything after the object comes out striped.* A halftone was left loaded.
  `clearHalftone()` after the draw, or zero the sixteen `BLIT_HALFTONE` words.
- *Faces do not look layered no matter how they are sorted.* They will not.
  OR is symmetric; the hardware cannot tell front from back, and the sort is
  wasted work. See the paragraph above.
- *Nothing is drawn at all.* `hwBlit()` was never called, or `D_BASE` was set to
  a pointer instead of the region offset of the plane's framebuffer.

---

## Step 13: seeing the sound — YM channels and a PCM spectrum

**Goal.** Three bars that rise and fall with the YM2149's three voices while an
SNDH plays, and — when the cart is streaming its own PCM — a real frequency
spectrum under them.

**Concept.** The audio does not happen where your cart does. The players live in
`demo-audio.wasm` on the **audio thread**, and a cart cannot call into them. What
it can do is hold out a buffer and let the host fill it. Four exports are that
buffer, and the host feature-detects each one by name: export it and it gets
written, leave it out and nothing happens.

| export | returns a pointer to | filled with |
| --- | --- | --- |
| `getYmRegsPointer` | 16 bytes | the YM2149's registers, R0..R13 |
| `getAudioModePointer` | 1 byte | which player is live |
| `getSongMsPointer` | 1 u32 | milliseconds into the tune |
| `getScopesPointer` | 4 x 128 f32 | per-channel sample captures |

A Zig cart gets all four for free — `apps/zig/demo_main.zig` exports them
pointing into ZigOS, so you just read `zigos.ym_regs`, `zigos.audio_mode`,
`zigos.song_ms` and `zigos.scopes`. A C or Rust cart exports the four functions
itself, pointing at its own statics, and gets exactly the same data. Nothing in
this step is Zig-only.

**The YM gives you registers, not sound.** This is the honest limit, and it is
the thing to understand before designing anything: **no audio samples come back
from the YM path.** When a SNDH or a YM dump is playing, `scopes` is not
refreshed — the scope array belongs to the sample engine's four Paula channels,
and the PSG does not go through them. So you cannot FFT a SNDH from inside a
cart. There is no buffer of its output to transform.

What you get instead is the chip, which is arguably better: fourteen registers,
read fresh several times a second, exactly what the 68000 replay routine last
wrote. Everything a visualiser needs is in them:

| registers | meaning |
| --- | --- |
| R0/R1, R2/R3, R4/R5 | channel A/B/C tone period, 12 bits: `(R1 & 0x0F) << 8 \| R0` |
| R6 | noise period, 5 bits |
| R7 | mixer. Bits 0-2 tone A/B/C, bits 3-5 noise A/B/C — **0 means ON** |
| R8, R9, R10 | channel A/B/C volume, 0..15; **bit 4 set = follow the envelope** |
| R11/R12, R13 | envelope period and shape |

Two of those lines are where visualisers go wrong. The mixer is
**active-low** — a set bit *disables* that voice, because the chip's designers
wired it that way — so a naive `if (r7 & bit)` lights up exactly the channels
that are silent. And a volume register with bit 4 set does not mean volume 16;
it means "this channel is under envelope control", and its real loudness is
sweeping between 0 and 15 at the envelope rate. Draw it as a fixed high-ish
value or read R11-R13 and follow the shape, but do not draw `vreg & 0x1F`.

The pitch is `125000 / period` Hz on a 2 MHz ST PSG, so the period is an
*inverse*: a small period is a high note, and period 0 means the channel was
never programmed. Clamp before you divide.

**Everything you draw from registers is a reconstruction, not a capture.** The
music scene, `apps/zig/scenes/music_debug.zig`, draws a convincing three-channel
oscilloscope for SNDH, and every pixel of it is synthesised: a square wave whose
wavelength comes from the period, whose height comes from the volume, plus a
hash-noise term when the mixer says noise is on. It looks like a scope because
the chip really is making square waves. It is not one, and it will not show you
a digidrum. Say so in your own comments and nobody downstream will be misled.

**For real samples, switch on the mode.** `audio_mode` says which world you are
in, and the scope array only means something in two of them:

| mode | player | `scopes` |
| --- | --- | --- |
| 0 | nothing | stale |
| 1 | MOD | **4 channels, live** |
| 2 | YM dump | stale — use `ym_regs` |
| 3 | raw sample / **your Step 10 PCM stream** | **channel 0, live** |
| 4 | SNDH | stale — use `ym_regs` |

Mode 3 is the interesting one: a stream you started with
`hostAudioStreamStart` plays on Paula channel 0, so `scopes[0]` is a live
capture of *your own* PCM, after resampling. It is 128 f32 taken one in four at
the engine's 44100 Hz, so it is a window of about 11.6 ms sampled at
**11025 Hz** — Nyquist 5.5 kHz. Bass and mids are all there; a cymbal is not.

**A spectrum needs a transform, and the machine has none.** There is no FFT in
the ABI, in ZigOS or in the ROM. For a bar display you do not want one either:
you want a handful of bands, and **Goertzel** gives you one band in one pass
with three floats of state and no tables. Eight to sixteen bands over 128
samples is a few thousand multiplies a frame — nothing, on a machine that
projects 3D meshes in f32.

### Zig

ZigOS already has the fields; read them in `render`.

```zig
const SCOPE_LEN: usize = zg.SCOPE_LEN;   // 128
const SCOPE_RATE: f32 = 44100.0 / 4.0;   // captured one sample in four

// Three YM channels as bars: height = volume, colour = tone/noise/both.
fn drawYmBars(zigos: *ZigOS, fb: *LogicalFB) void {
    const regs = &zigos.ym_regs;
    for (0..3) |ch| {
        const period: u16 = (@as(u16, regs[ch * 2 + 1] & 0x0F) << 8) | regs[ch * 2];
        const vreg = regs[8 + ch];
        // Bit 4 = "the envelope drives this channel", NOT volume 16. Show it as
        // a loud-ish constant rather than pretending we know where the sweep is.
        const vol: f32 = if (vreg & 0x10 != 0) 13.0 else @floatFromInt(vreg & 0x0F);
        // The mixer is ACTIVE LOW: a SET bit silences that voice.
        const tone_on = (regs[7] >> @intCast(ch)) & 1 == 0;
        const noise_on = (regs[7] >> @intCast(ch + 3)) & 1 == 0;
        if (!tone_on and !noise_on) continue;             // genuinely silent
        const ink: u8 = if (noise_on and !tone_on) 3 else if (noise_on) 2 else 1;

        const h: i32 = @intFromFloat(vol / 15.0 * 60.0);
        const x0: i16 = @intCast(40 + ch * 80);
        var y: i32 = 120 - h;
        while (y < 120) : (y += 1) {
            for (0..48) |dx| fb.setPixelValue(@intCast(x0 + @as(i16, @intCast(dx))), @intCast(y), ink);
        }
        // Pitch, for a tick mark: 125000 / period Hz. Period 0 = never programmed.
        const hz: f32 = if (period == 0) 0 else 125000.0 / @as(f32, @floatFromInt(period));
        const tick: i32 = 130 + @min(@as(i32, @intFromFloat(hz / 40.0)), 60);
        for (0..48) |dx| fb.setPixelValue(@intCast(x0 + @as(i16, @intCast(dx))), @intCast(tick), ink);
    }
}
```

The spectrum, for mode 3 — one Goertzel pass per band over `scopes[0]`:

```zig
// Power of `samples` at `hz`, by Goertzel: one band, one pass, no tables.
fn goertzel(samples: []const f32, hz: f32, rate: f32) f32 {
    const w = 2.0 * std.math.pi * hz / rate;
    const coeff = 2.0 * @cos(w);
    var s1: f32 = 0;
    var s2: f32 = 0;
    for (samples) |x| {
        const s = x + coeff * s1 - s2;
        s2 = s1;
        s1 = s;
    }
    return @max(0.0, s1 * s1 + s2 * s2 - coeff * s1 * s2);
}

// Sixteen bands, logarithmically spaced from 60 Hz to just under Nyquist.
const BANDS: usize = 16;

fn drawSpectrum(zigos: *ZigOS, fb: *LogicalFB) void {
    if (zigos.audio_mode != 3 and zigos.audio_mode != 1) return; // registers only
    const samples = &zigos.scopes[0];
    for (0..BANDS) |b| {
        const t = @as(f32, @floatFromInt(b)) / @as(f32, BANDS - 1);
        const hz = 60.0 * std.math.pow(f32, 5000.0 / 60.0, t); // 60 Hz .. 5 kHz
        const p = goertzel(samples, hz, SCOPE_RATE);
        // Power spans orders of magnitude: a log scale, or every bar is 0 or full.
        const db = 10.0 * @log10(p + 1e-9);
        const h: i32 = @intFromFloat(std.math.clamp((db + 50.0) * 1.2, 0.0, 60.0));
        const x0: i32 = @intCast(16 + b * 18);
        var y: i32 = 190 - h;
        while (y < 190) : (y += 1) {
            for (0..14) |dx| fb.setPixelValue(@intCast(x0 + @as(i32, @intCast(dx))), @intCast(y), 4);
        }
    }
}
```

`1e-9` inside the log is not superstition: a silent band gives exactly 0, and
`@log10(0)` is `-inf`, which becomes an illegal `@intFromFloat` and traps the
cart.

### C

The exports are yours to define. The host checks each name and skips the ones
that are missing, so you can export only what you read.

```c
// The host writes these between frames; export the pointers and it finds them.
static unsigned char ym_regs[16];
static unsigned char audio_mode;
static unsigned song_ms;
static float scopes[4][128];

__attribute__((export_name("getYmRegsPointer")))
unsigned char *getYmRegsPointer(void) { return ym_regs; }
__attribute__((export_name("getAudioModePointer")))
unsigned char *getAudioModePointer(void) { return &audio_mode; }
__attribute__((export_name("getSongMsPointer")))
unsigned *getSongMsPointer(void) { return &song_ms; }
__attribute__((export_name("getScopesPointer")))
float *getScopesPointer(void) { return &scopes[0][0]; }
```

```c
// Three YM channels as bars. The two traps, spelled out:
//   - the MIXER (R7) is ACTIVE LOW: a set bit SILENCES that voice;
//   - volume bit 4 means "envelope drives this channel", not volume 16.
static void draw_ym_bars(void) {
    for (int ch = 0; ch < 3; ch++) {
        unsigned period = ((ym_regs[ch * 2 + 1] & 0x0F) << 8) | ym_regs[ch * 2];
        unsigned vreg = ym_regs[8 + ch];
        float vol = (vreg & 0x10) ? 13.0f : (float)(vreg & 0x0F);
        int tone_on  = ((ym_regs[7] >> ch) & 1) == 0;
        int noise_on = ((ym_regs[7] >> (ch + 3)) & 1) == 0;
        if (!tone_on && !noise_on) continue;
        u8 ink = (noise_on && !tone_on) ? 3 : (noise_on ? 2 : 1);

        int h = (int)(vol / 15.0f * 60.0f);
        fill_rect(40 + ch * 80, 120 - h, 48, h, ink);

        float hz = period ? 125000.0f / (float)period : 0.0f; // period 0 = unset
        int tick = 130 + (int)(hz / 40.0f > 60.0f ? 60.0f : hz / 40.0f);
        fill_rect(40 + ch * 80, tick, 48, 1, ink);
    }
}

// One frequency band of `n` samples, by Goertzel: three floats of state.
static float goertzel(const float *s, int n, float hz, float rate) {
    float coeff = 2.0f * __builtin_cosf(6.28318530718f * hz / rate);
    float s1 = 0, s2 = 0;
    for (int i = 0; i < n; i++) {
        float v = s[i] + coeff * s1 - s2;
        s2 = s1;
        s1 = v;
    }
    float p = s1 * s1 + s2 * s2 - coeff * s1 * s2;
    return p > 0 ? p : 0;
}
```

The band loop is the Zig one transliterated: `scopes[0]` is live only when
`audio_mode` is 1 or 3, and the log needs its `+ 1e-9f`.

### Rust

```rust
// The host writes these between frames; export the pointers and it finds them.
static mut YM_REGS: [u8; 16] = [0; 16];
static mut AUDIO_MODE: u8 = 0;
static mut SONG_MS: u32 = 0;
static mut SCOPES: [[f32; 128]; 4] = [[0.0; 128]; 4];

#[no_mangle]
pub extern "C" fn getYmRegsPointer() -> *mut u8 {
    core::ptr::addr_of_mut!(YM_REGS) as *mut u8
}
#[no_mangle]
pub extern "C" fn getAudioModePointer() -> *mut u8 {
    core::ptr::addr_of_mut!(AUDIO_MODE)
}
#[no_mangle]
pub extern "C" fn getSongMsPointer() -> *mut u32 {
    core::ptr::addr_of_mut!(SONG_MS)
}
#[no_mangle]
pub extern "C" fn getScopesPointer() -> *mut f32 {
    core::ptr::addr_of_mut!(SCOPES) as *mut f32
}
```

```rust
/// One YM channel, decoded from the register file.
struct Voice {
    period: u16,
    vol: f32,
    tone: bool,
    noise: bool,
}

fn voice(regs: &[u8; 16], ch: usize) -> Voice {
    Voice {
        period: ((regs[ch * 2 + 1] & 0x0F) as u16) << 8 | regs[ch * 2] as u16,
        // Bit 4 = envelope-driven, NOT volume 16.
        vol: if regs[8 + ch] & 0x10 != 0 { 13.0 } else { (regs[8 + ch] & 0x0F) as f32 },
        // The mixer is ACTIVE LOW: a SET bit silences that voice.
        tone: regs[7] >> ch & 1 == 0,
        noise: regs[7] >> (ch + 3) & 1 == 0,
    }
}

impl Voice {
    /// Hz on a 2 MHz ST PSG. Period 0 means the channel was never programmed.
    fn hz(&self) -> f32 {
        if self.period == 0 { 0.0 } else { 125_000.0 / self.period as f32 }
    }
}

/// Power at `hz`, by Goertzel: one band, one pass, three floats of state.
fn goertzel(samples: &[f32], hz: f32, rate: f32) -> f32 {
    let coeff = 2.0 * (core::f32::consts::TAU * hz / rate).cos();
    let (mut s1, mut s2) = (0.0f32, 0.0f32);
    for &x in samples {
        let s = x + coeff * s1 - s2;
        s2 = s1;
        s1 = s;
    }
    (s1 * s1 + s2 * s2 - coeff * s1 * s2).max(0.0)
}
```

Read the statics through `addr_of!` in `frame`, and gate the spectrum on
`AUDIO_MODE` being 1 or 3 exactly as in Zig.

**What you should see.** With a SNDH playing: three bars stepping in time with
the tune, dropping to nothing on rests, and changing colour when a channel
switches to noise — which is what a drum is, on this chip. With a Step 10 PCM
stream: the bars stay flat (no PSG is running) and the spectrum lights up
instead, bass on the left, the top bands mostly dark because the capture stops
at 5.5 kHz. `apps/zig/scenes/music_debug.zig` is the full version, with a
synthesised three-channel oscilloscope that switches on `audio_mode`.

**Common mistakes.**

- *Every channel reads as loud all the time, including the silent ones.* The
  mixer test is inverted. R7 is active low: `(r7 >> ch) & 1 == 0` means ON.
- *One channel pegs at maximum and never moves.* Its volume register has bit 4
  set — it is envelope-driven, and `vreg & 0x1F` is not its loudness.
- *A bass note draws taller than a lead.* The period is an inverse. Pitch is
  `125000 / period`, so divide — and guard period 0 first.
- *The spectrum is empty while a SNDH plays.* It always will be. The YM path
  fills no scope buffer; there is nothing in the machine to transform. Draw
  registers for modes 2 and 4, samples for 1 and 3.
- *The cart traps the moment the music stops.* `@log10(0)` is `-inf` and
  `@intFromFloat(-inf)` is illegal, not merely wrong. Add the epsilon.
- *Every bar is either flat or full height.* The Goertzel output is power, which
  spans orders of magnitude. Plot dB.
- *The C or Rust cart shows nothing but the Zig one works.* One of the four
  exports is missing or misnamed. The host feature-detects them by exact name
  and silently skips what it cannot find — there is no error for this.
- *The visualiser freezes for a moment when the screen changes.* The host stops
  writing during a cart swap, because those addresses belong to the cart being
  unpacked. Expected; the next `audioState` message resumes it.

---

## Where next

- [`docs/ZIGOS_API.md`](ZIGOS_API.md): the Zig library, including the copper,
  `blit`, `scrollring` and wireframe helpers.
- [`docs/HW_API.md`](HW_API.md): the sealed ABI C and Rust carts use, the full
  register map, overscan and the RAM window.
- [`docs/MUSIC.md`](MUSIC.md): formats, subtunes and the headless checks.
- [`docs/BLITTER_HW_SPEC.md`](BLITTER_HW_SPEC.md): the blitter's registers and
  operations.
- The CODEF port skill (`.claude/skills/codef-port/`, or `/convert_codef <id>`
  in Claude Code): how the real cracktro ports in `apps/zig/scenes/` were made,
  and a good source of screens to read next.
- Real screens by language: `apps/zig/scenes/replicants_garfield.zig` (copper,
  blit, scrollring), `apps/c/scenes/screen34.c` (bottom border opened in C),
  `apps/rust/scenes/v8_populous.rs` (a full cracktro in Rust).
