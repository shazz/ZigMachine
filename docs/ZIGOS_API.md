# ZigMachine — ZigOS API (ZIGOS_API)

**ZigOS** is the OPEN OS/library layer you write effects and scenes against. It is
plain Zig source you compile into your own `demo.wasm`; it sits on top of the
sealed hardware (see **HW_API.md**) and hides the raw memory map behind a small,
stable object API. You may read and extend ZigOS freely — it is the part of the
console that is *yours*.

Source: `src/zigos.zig` (the library) and `src/audio/mod.zig` /
`src/audio/ym_player.zig` (the players). Reference scene: `src/scenes/music_debug.zig`.

---

## 1. Constants

```zig
PHYSICAL_WIDTH  = 400   PHYSICAL_HEIGHT = 280   // the full framebuffer (with borders)
WIDTH           = 320   HEIGHT          = 200   // the visible screen
NB_PLANES       = 4
HORIZONTAL_BORDERS_WIDTH = 40   VERTICAL_BORDERS_HEIGHT = 40
SCOPE_LEN       = 128                            // per-channel audio scope length
```

## 2. Colours

```zig
pub const Color = struct { r: u8, g: u8, b: u8, a: u8,
    pub fn toRGBA(self) u32
    pub fn fromRGBA(v: u32) Color
};
```

Alpha matters: planes are composited by the front-end as stacked transparent
canvases, so a palette entry with `a = 0` is transparent (lets lower planes show
through) and `a = 255` is opaque.

## 3. Scene contract

A scene is a `Demo` struct exposing three methods; the host calls them each frame.

```zig
pub const Demo = struct {
    pub fn init(self: *Demo, zigos: *ZigOS) void      // set up planes, palettes, HBL handlers
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void  // advance state (no drawing)
    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void  // draw into the logical framebuffers
};
```

Select the active scene at compile time in `floppy.zig`.

## 4. `ZigOS`

The machine handle passed to every scene method.

```zig
lfbs: [NB_PLANES]LogicalFB                 // the 4 logical framebuffers (planes)
system_font: []const u8                    // 8x8 1-bit system font (used by printText)

// audio state, mirrored in from the worklet each frame (for visualisers):
ym_regs: [16]u8                            // live YM2149 registers
audio_mode: u8                             // 0 none, 1 MOD, 2 YM, 3 sample
scopes: [4][SCOPE_LEN]f32                  // per-channel oscilloscope captures

physical_framebuffer: *[PHYSICAL_HEIGHT][PHYSICAL_WIDTH]u32  // see §7 (overscan escape hatch)

pub fn setResolution(self, res: Resolution) void      // .planes | .truecolor (opens borders)
pub fn setBackgroundColor(self, color: Color) void    // border/background colour
pub fn getBackgroundColor(self) Color
pub fn setHBLHandler(self, handler) void              // global per-scanline handler (see §6)
pub fn removeHBLHandler(self) void
pub fn printText(self, lfb: *LogicalFB, text, x, y, fg_index, bg_index) void
```

## 5. `LogicalFB` (a plane)

Each plane is 320×200 palette indices + a 256-entry palette. Obtain one with
`&zigos.lfbs[i]`.

```zig
is_enabled: bool                           // set true to composite this plane
id: u8

pub fn setPixelValue(self, x: u16, y: u16, pal_entry: u8) void
pub fn drawScanline(self, x1: u16, x2: u16, y: u16, pal_entry: u8) void
pub fn clearFrameBuffer(self, pal_entry: u8) void

pub fn setPalette(self, entries: [256]Color) void
pub fn setPaletteEntry(self, entry: u8, value: Color) void
pub fn getPaletteEntry(self, entry: u8) Color
pub fn setFramebufferBackgroundColor(self, pal_entry: u8) void

pub fn getRenderTarget(self) RenderTarget  // pass to effects that draw into a target
pub fn setFrameBufferHBLHandler(self, position: u16, handler) void   // per-plane HBL (see §6)
```

`RenderTarget` is a small union (`.fb` | `.render_buffer`) with `setPixelValue`
and `clearFrameBuffer`, so an effect can render into either a plane or a scratch
buffer.

### Typical scene setup

```zig
var p0 = &zigos.lfbs[0];
p0.is_enabled = true;
p0.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 }); // transparent bg
// ... draw with p0.setPixelValue(x, y, index) in render()
```

## 6. HBL handlers (rasters)

Per-scanline callbacks are how you do copper-style raster effects. Register a Zig
function; the sealed machine invokes it (via `hblDispatch`) as it renders.

```zig
// Per-plane: fires on plane `p2` at x == position, every scanline.
fn scrollRaster(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    fb.setPaletteEntry(SCROLL, COPPER[(line + offset) % 256]); // recolour per scanline
}
p2.setFrameBufferHBLHandler(0, scrollRaster);

// Global: fires once per scanline during the clear (good for a per-line background).
fn bgRaster(zigos: *ZigOS, line: u16) void { zigos.setBackgroundColor(...); }
zigos.setHBLHandler(bgRaster);
```

Handlers write palettes/registers in the shared region; the machine reads the
updated values for the pixels it draws after the HBL point — that's the raster.
Your `*const fn` never leaves ZigOS; only an integer id crosses to the machine.

## 7. Overscan / the physical framebuffer

`zigos.physical_framebuffer` is a direct view of the machine's output buffer. The
sanctioned way to reach the borders ("fullscreen") is `setResolution(.truecolor)`
+ a border HBL, which opens the overscan legitimately. Writing
`physical_framebuffer` directly (as `music_debug`'s scroller does for its border
spill) is an **out-of-ABI escape hatch** — it works only because memory is not
sealed, and it is not guaranteed by the ABI. Prefer the resolution/HBL mechanism.

## 8. Audio players

Players are open ZigOS code that drive the sealed chips. Three ship today:

- **MOD** (`ModPlayer`) — ProTracker 4-channel `.MOD`, drives the Paula channels.
- **YM** (`YmPlayer`) — YM5!/YM6! register dump, writes the YM2149 registers.
- **raw sample** — streams 8-bit PCM on one Paula channel.

They run on the audio thread and are swappable — add your own by driving the same
chip ABI (see HW_API.md §5). The active player's mode + per-channel scopes are
mirrored back into `zigos.audio_mode` / `zigos.scopes` / `zigos.ym_regs` so scenes
can visualise the sound (as `music_debug`'s oscilloscope does).

## 9. Build & run

```
export PATH="$HOME/.local/zig/0.16.0:$PATH"
zig build -Drelease=true -Dwasm     # -> docs/{machine-video,demo,machine-audio,demo-audio}.wasm
cd docs && python3 -m http.server 3333   # open /sealed.html  (hard-reload after rebuilds)
```

You only ever rebuild `demo.wasm` / `demo-audio.wasm` (your code). The
`machine-*.wasm` binaries are the sealed hardware — you receive them, you don't
compile them.
