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

## Step 8, going further: borders and the blitter

Your screen is a normal plane: 320x200, border closed. Two directions from here,
both with working examples.

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

**Use the blitter.** The machine has a 2D coprocessor for fills, lines,
triangles and masked blits, driven through registers and `hwBlit()`. In Zig,
`zg.Blitter` wraps it. See `apps/zig/scenes/blitter_demo.zig`.

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
