// --------------------------------------------------------------------------
// ZigMachine — memory map (THE ABI)
//
// This file is the single source of truth for the sealed hardware's memory
// layout. Both the sealed machine (machine/video.zig) and the SDK header the
// coder receives (sdk/hardware.zig) derive their addresses from here, so the
// two can never disagree. Changing a value here is an ABI change.
//
// Layer: this is machine-side data, but it is pure constants (no code, no
// extern/export), so it is safe for both the sealed binary and the open SDK to
// import without entangling their symbol tables.
// --------------------------------------------------------------------------

// --- geometry (fixed; the console's identity) ---
pub const PHYSICAL_WIDTH: u16 = 400;
pub const PHYSICAL_HEIGHT: u16 = 280;
pub const WIDTH: u16 = 320;
pub const HEIGHT: u16 = 200;
pub const NB_PLANES: u8 = 4;
pub const HORIZONTAL_BORDERS_WIDTH: u16 = (PHYSICAL_WIDTH - WIDTH) / 2; // 40
pub const VERTICAL_BORDERS_HEIGHT: u16 = (PHYSICAL_HEIGHT - HEIGHT) / 2; // 40

// --- sizes ---
pub const PAL_ENTRIES: usize = 256;
pub const PAL_BYTES: usize = PAL_ENTRIES * 4; // 1024 (RGBA u32 per entry)
// Each logical-framebuffer slot is PHYSICAL-sized so a plane can go FULLSCREEN
// (Option B: a 400-wide plane whose border columns hold independent content).
// Plane framebuffers live in a VRAM POOL, allocated by ZigOS (pay-per-use): a
// NORMAL plane costs WIDTH×HEIGHT, a FULLSCREEN plane costs PHYSICAL_WIDTH×
// PHYSICAL_HEIGHT. Each plane's screen base is the FB_BASE register (the ST(E)
// "screen base" model) — a byte offset into the region, so a plane can point
// anywhere in the pool (scroll-by-base, double buffering, plane sharing).
pub const NORMAL_FB_BYTES: usize = @as(usize, WIDTH) * @as(usize, HEIGHT); // 64000
pub const FULLSCREEN_FB_BYTES: usize = @as(usize, PHYSICAL_WIDTH) * @as(usize, PHYSICAL_HEIGHT); // 112000
// Medium resolution (ST-medium-style): 640x200 chunky, 2 planes. It is drawn 1:1
// into the shared physical RASTER; low-res is drawn pixel-DOUBLED into that same
// raster (320 logical -> 640 physical), so both land on one dot grid and an HBL
// can switch resolution per scanline (the ST shifter model). Scenes keep drawing
// in LOGICAL coordinates (WIDTH/PHYSICAL_WIDTH); the doubling lives in the machine.
pub const MEDIUM_WIDTH: u16 = 640; // logical medium visible width
pub const MEDIUM_HEIGHT: u16 = 200;
pub const MEDIUM_PLANES: u8 = 2;
pub const MEDIUM_FB_BYTES: usize = @as(usize, MEDIUM_WIDTH) * @as(usize, MEDIUM_HEIGHT); // 128000
// A medium OVERSCAN plane covers the whole raster (borders included): 800x280 logical.
pub const MEDIUM_FULL_FB_BYTES: usize = @as(usize, RASTER_WIDTH) * @as(usize, RASTER_HEIGHT); // 224000

// --- the physical RASTER (actual PFB the host blits) ---
// Low-res doubles horizontally (not vertically — low & medium are both 200 lines).
pub const RASTER_WIDTH: u16 = PHYSICAL_WIDTH * 2; // 800
pub const RASTER_HEIGHT: u16 = PHYSICAL_HEIGHT; // 280
pub const RASTER_BORDER_X: u16 = HORIZONTAL_BORDERS_WIDTH * 2; // 80
pub const RASTER_BORDER_Y: u16 = VERTICAL_BORDERS_HEIGHT; // 40
pub const RASTER_VIS_WIDTH: u16 = WIDTH * 2; // 640 (physical visible)
pub const RASTER_VIS_HEIGHT: u16 = HEIGHT; // 200

pub const PFB_PIXELS: usize = @as(usize, RASTER_WIDTH) * @as(usize, RASTER_HEIGHT); // 224000
pub const PFB_BYTES: usize = PFB_PIXELS * 4; // 896000

// Per-plane row stride, in pixels: 320 (normal, visible-only) or 400 (fullscreen).
pub const STRIDE_NORMAL: u16 = WIDTH; // 320
pub const STRIDE_FULLSCREEN: u16 = PHYSICAL_WIDTH; // 400

// --- region layout (offsets from the video hardware base) ---
pub const OFF_REG: usize = 0x0000;
pub const OFF_PAL: usize = 0x0100; // 4 x PAL_BYTES
pub const OFF_VRAM: usize = 0x1100; // framebuffer pool base (ZigOS-allocated)
pub const VRAM_BYTES: usize = 1024 * 1024; // 1 MiB — holds 3 fullscreen planes + effect sheets
pub const OFF_PFB: usize = OFF_VRAM + VRAM_BYTES;
pub const REGION_BYTES: usize = OFF_PFB + PFB_BYTES;
// Default per-plane framebuffer offsets (reset values of FB_BASE): the legacy
// contiguous 320×200 layout, so a binary that never touches FB_BASE is unchanged.
pub inline fn defaultFbBase(plane: usize) u32 {
    return @intCast(OFF_VRAM + plane * NORMAL_FB_BYTES);
}

// --- registers (offsets from OFF_REG) ---
pub const REG_RESOLUTION: usize = 0x00; // u8   0 = planes, 1 = truecolor (border-open)
pub const REG_NB_PLANES: usize = 0x01; // u8   (ro) = 4
pub const REG_BACKGROUND: usize = 0x04; // u32  border/background RGBA
pub const REG_PLANE_ENABLE: usize = 0x08; // u8 x4 (informational in v1; host gates blits)
pub const REG_GLOBAL_HBL_ID: usize = 0x10; // u16  border/background HBL handler id (0 = none)
pub const REG_FB_HBL_ID: usize = 0x20; // u16 x4 per-plane HBL handler id (0 = none)
pub const REG_FB_HBL_POS: usize = 0x28; // u16 x4 x position at which the per-plane HBL fires
pub const REG_FRAME: usize = 0x30; // u32  (ro) frame counter
pub const REG_FB_STRIDE: usize = 0x34; // u16 x4 per-plane row stride in pixels (320 normal, 400 fullscreen, or any SCROLL buffer width)
pub const REG_HSCROLL: usize = 0x3C; // u16 x4 per-plane horizontal scroll (re-read PER SCANLINE in SCROLL mode → line distort)
pub const REG_FB_BASE: usize = 0x44; // u32 x4 per-plane framebuffer screen base (0x44..0x53) — pan point for SCROLL mode
pub const REG_FB_MODE: usize = 0x54; // u8 x4 per-plane render mode (0x54..0x57): 0 normal, 1 fullscreen, 2 scroll, 3 medium, 4 overscan
pub const REG_RES_FLICKER: usize = 0x58; // u16  overscan-trick latch: the SDK bumps it on a RES_MEDIUM->RES_PLANES flicker so the (untrappable) poke is observable per scanline (0x58..0x59; 0x5A..0x5B free)
// The first byte of the cart's RAM window the cart does NOT own: its static
// data + stack high-water, measured off the cart wasm by the host at load time
// and written here (see hwSetCartHigh). 0 = the host never told us, which the
// hwRam* instructions report as "unknown" rather than guessing. Survives
// hwInit() — it describes the loaded cart, not the video state.
pub const REG_CART_HIGH: usize = 0x5C; // u32  (0x5C..0x5F)
// Same, for the ROM module's window (Phase 2). 0 = no ROM chip fitted, which
// is the state until rom.wasm exists — hwRomRamFree() then reports 0.
pub const REG_ROM_HIGH: usize = 0x60; // u32  (0x60..0x63; 0x64..0x7F free below OFF_BLIT)

pub const FB_MODE_NORMAL: u8 = 0; // 320x200 low-res plane (pixel-doubled into the raster)
pub const FB_MODE_FULLSCREEN: u8 = 1; // 400x280 low-res overscan plane (Option B, doubled)
pub const FB_MODE_SCROLL: u8 = 2; // window into a bigger-than-screen buffer; pan via FB_BASE + HSCROLL
pub const FB_MODE_MEDIUM: u8 = 3; // 640x200 medium-res plane (1:1 into the raster)
pub const FB_MODE_OVERSCAN: u8 = 4; // 400x280 buffer, borders CLOSED until opened by the resolution-flicker trick (see OVERSCAN_* below)

pub const RES_PLANES: u8 = 0;
pub const RES_TRUECOLOR: u8 = 1;
pub const RES_MEDIUM: u8 = 2; // 640x200, 2 planes, no border (ST-medium style)

// --- overscan / border-opening trick (authentic ST timing exploit) ---
// A FB_MODE_OVERSCAN plane draws only its visible 320x200 window until the scene
// "opens" a border by FLICKERING the resolution register (RES_MEDIUM->RES_PLANES)
// from a per-plane HBL handler at the magic column, on the scanline of the border
// it wants. The flicker must land within OVERSCAN_X_TOL of OVERSCAN_MAGIC_X (the
// HBL fires at REG_FB_HBL_POS) or the border shows GARBAGE that line — like botching
// the timing on real hardware. Opening is causal top-to-bottom: a flicker at row k
// in a border band opens that band from row k down; a flicker on a visible line
// opens both side borders for that line (sides must be re-opened every line).
pub const OVERSCAN_MAGIC_X: u16 = HORIZONTAL_BORDERS_WIDTH; // 40 — the visible-window left edge (logical coords)
pub const OVERSCAN_X_TOL: u16 = 4; // +/- tolerance the flicker column must hit

// --------------------------------------------------------------------------
// Blitter register block (see docs/BLITTER_HW_SPEC.md).
//
// A fixed-function 2D coprocessor living inside machine-video.wasm. ZigOS sets
// these registers then calls the sealed `hwBlit()` export to execute COMMAND.
// The block sits above the video registers and below the palettes (OFF_PAL =
// 0x100), so it is covered by reset()'s 256-byte register clear (COMMAND -> NOP).
// Offsets are region-relative (OFF_REG == 0); the layout matches the spec's
// per-block offsets shifted by OFF_BLIT.
// --------------------------------------------------------------------------
pub const OFF_BLIT: usize = 0x80; // blitter block base

pub const BLIT_COMMAND: usize = OFF_BLIT + 0x00; // u8  0 NOP 1 BLIT 2 FILL 3 LINE 4 TRIANGLE
pub const BLIT_MINTERM: usize = OFF_BLIT + 0x01; // u8  LF truth table of A,B,C (index = A<<2|B<<1|C)
pub const BLIT_CON: usize = OFF_BLIT + 0x02; // u8  control bits (see CON_* below)
pub const BLIT_STATUS: usize = OFF_BLIT + 0x03; // u8  (ro) bit7 BUSY
pub const BLIT_COLOR: usize = OFF_BLIT + 0x04; // u8  foreground index
pub const BLIT_BG_COLOR: usize = OFF_BLIT + 0x05; // u8  halftone background index
pub const BLIT_COLOR_KEY: usize = OFF_BLIT + 0x06; // u8  transparent index (KEY_EN cookie-cut)
pub const BLIT_CON2: usize = OFF_BLIT + 0x07; // u8  control bits, second byte (see CON2_* below) — since 1.4.0
pub const BLIT_A_BASE: usize = OFF_BLIT + 0x08; // u32 channel A source base
pub const BLIT_A_STRIDE: usize = OFF_BLIT + 0x0C; // u16 channel A row stride
pub const BLIT_B_BASE: usize = OFF_BLIT + 0x10; // u32 channel B source base
pub const BLIT_B_STRIDE: usize = OFF_BLIT + 0x14; // u16 channel B row stride
pub const BLIT_C_BASE: usize = OFF_BLIT + 0x18; // u32 channel C source base
pub const BLIT_C_STRIDE: usize = OFF_BLIT + 0x1C; // u16 channel C row stride
pub const BLIT_D_BASE: usize = OFF_BLIT + 0x20; // u32 channel D destination base
pub const BLIT_D_STRIDE: usize = OFF_BLIT + 0x24; // u16 channel D row stride
pub const BLIT_W: usize = OFF_BLIT + 0x28; // u16 blit width  (BLIT/FILL)
pub const BLIT_H: usize = OFF_BLIT + 0x2A; // u16 blit height (BLIT/FILL)
pub const BLIT_X0: usize = OFF_BLIT + 0x2C; // i16 dst x0 / line start / tri v0
pub const BLIT_Y0: usize = OFF_BLIT + 0x2E; // i16
pub const BLIT_X1: usize = OFF_BLIT + 0x30; // i16 line end / tri v1
pub const BLIT_Y1: usize = OFF_BLIT + 0x32; // i16
pub const BLIT_X2: usize = OFF_BLIT + 0x34; // i16 tri v2
pub const BLIT_Y2: usize = OFF_BLIT + 0x36; // i16
pub const BLIT_CLIP_X: usize = OFF_BLIT + 0x38; // u16 clip rect origin x
pub const BLIT_CLIP_Y: usize = OFF_BLIT + 0x3A; // u16 clip rect origin y
pub const BLIT_CLIP_W: usize = OFF_BLIT + 0x3C; // u16 clip rect width
pub const BLIT_CLIP_H: usize = OFF_BLIT + 0x3E; // u16 clip rect height
pub const BLIT_HALFTONE: usize = OFF_BLIT + 0x40; // u16 x16 1-bit halftone pattern
pub const BLIT_CYCLES: usize = OFF_BLIT + 0x60; // u32 (ro) estimated cost of last op

// COMMAND values
pub const BLIT_CMD_NOP: u8 = 0;
pub const BLIT_CMD_BLIT: u8 = 1;
pub const BLIT_CMD_FILL: u8 = 2;
pub const BLIT_CMD_LINE: u8 = 3;
pub const BLIT_CMD_TRIANGLE: u8 = 4;

// CON control bits
pub const CON_USEA: u8 = 1 << 0; // channel A enabled
pub const CON_USEB: u8 = 1 << 1; // channel B enabled
pub const CON_USEC: u8 = 1 << 2; // channel C enabled
pub const CON_KEY_EN: u8 = 1 << 3; // colour-key cookie-cut (skip B == COLOR_KEY)
pub const CON_IFE: u8 = 1 << 4; // inclusive area fill (reserved, v2)
pub const CON_EFE: u8 = 1 << 5; // exclusive area fill (reserved, v2)
pub const CON_DESC: u8 = 1 << 6; // descending copy (overlapping moves)
pub const CON_CLIP_EN: u8 = 1 << 7; // clip to CLIP rect

// CON2 control bits (since 1.4.0). reset() clears the byte, so a cart that never
// writes it keeps 1.3.0 behaviour.
// SRC_ABS: A_BASE/B_BASE are ABSOLUTE linear addresses instead of offsets in the
// video region, so a blit can read the cart's own RAM (@embedFile assets, scratch
// buffers) or the ROM window. The machine accepts the source only when its whole
// W x H rectangle lies inside ONE readable window (cart RAM, video region, ROM
// RAM); otherwise the BLIT draws nothing. D stays a video-region offset: the
// blitter reads anywhere a program may, but writes only video memory.
pub const CON2_SRC_ABS: u8 = 1 << 0;

pub const BLIT_STATUS_BUSY: u8 = 1 << 7;

// Useful MINTERM (LF) values, index = (A<<2)|(B<<1)|C.
pub const MT_A: u8 = 0xF0; // D = A
pub const MT_B: u8 = 0xCC; // D = B (plain image copy)
pub const MT_C: u8 = 0xAA; // D = C (dest unchanged)
pub const MT_COOKIE: u8 = 0xCA; // (A & B) | (~A & C) — cookie-cut bob
pub const MT_XOR_BC: u8 = 0x66; // D = B ^ C (reversible draw)
pub const MT_OR_BC: u8 = 0xEE; // D = B | C (additive — glenz vector transparency)
pub const MT_CLEAR: u8 = 0x00;
pub const MT_SET: u8 = 0xFF;

// HBL dispatch ids. Per-plane handlers use id = plane + 1 (1..4); the global
// border/background handler uses a distinct id. Only integer ids cross the
// sealed boundary — the machine never sees a Zig function pointer.
pub const HBL_GLOBAL_ID: u16 = 5;

// --------------------------------------------------------------------------
// Reserved hardware address space.
//
// The video region is NOT a linker-allocated array in either module. It lives
// at a fixed linear-memory address ABOVE both modules' static data + stacks, so
// the two wasm modules can share ONE WebAssembly.Memory with no collision. The
// machine reads/writes it; the demo writes framebuffers/registers into it. This
// is the "you get the memory map, not the schematics" contract, and it gives
// the authentic fixed-address feel the spec's §10 asks about.
//
// Layout of the shared memory (v1.1 — demo window raised to 2 MiB):
//   [0x000000 .. 0x100000)  machine module data + stack  (global-base 0x400)
//   [0x100000 .. 0x300000)  demo module data + stack     (global-base 0x100000) — 2 MiB
//   [0x300000 .. ~0x4DC000) video hardware region        (this base)
// The demo window grew from 1 MiB to 2 MiB: a full cart (code + all @embedFile'd
// assets + 6-page stack) was overflowing 1 MiB into the video region (silent
// corruption of the top of the stack). VRAM also grew to 1 MiB so 3 fullscreen
// planes + effect sheets fit the pool.
// --------------------------------------------------------------------------
pub const HW_VIDEO_BASE: usize = 0x300000; // 3 MiB (demo cart gets [0x100000..0x300000))
// The cart's RAM window, as reported by the hwRam* instructions. The ceiling is
// HW_VIDEO_BASE: one byte past it is the video region, and a cart that runs into
// it corrupts VRAM silently rather than trapping.
pub const CART_RAM_BASE: usize = 0x100000; // = build.zig demo_global_base
pub const CART_RAM_TOP: usize = HW_VIDEO_BASE;
pub const CART_RAM_BYTES: usize = CART_RAM_TOP - CART_RAM_BASE; // 2 MiB

// The ROM chip's own RAM window (Phase 2 — see docs/PHASE2_ROM_CHIP.md). Placed
// ABOVE the video region, never carved out of the cart's: the whole point is that
// an app's 2 MiB stays the app's. The video region ends at OFF_PFB + PFB_BYTES =
// 0x4DBFE0, so 0x500000 clears it with room to spare.
//
// It is one shared linear memory, so a pointer an app passes is directly readable
// by the ROM — strings and structs cross the module boundary with no copy, and
// GEM keeps drawing straight into the framebuffers in the video region.
pub const ROM_RAM_BASE: usize = 0x500000; // 5 MiB
pub const ROM_RAM_TOP: usize = 0x700000; // 7 MiB
pub const ROM_RAM_BYTES: usize = ROM_RAM_TOP - ROM_RAM_BASE; // 2 MiB
// Region ends at OFF_PFB + PFB_BYTES = 1052768 + 896000 = 1948768 above the base;
// 3 MiB base + 1948768 needs ~78 pages, so 79 (~5.2 MiB) gives headroom. initial == max.
// 112 pages = 7 MiB = ROM_RAM_TOP. Raised from 79 for the ROM window; note that
// this is a BREAKING change for any cart packed before it — a cart declares the
// imported memory's initial/max, and an old cart's max (79 pages) is smaller
// than the memory the host now creates, so it fails to instantiate. Repack with
// tools/mkdisks.sh; node apps/disk_check.mjs is what catches it.
pub const SHARED_PAGES: u32 = 112;

pub const ZM_HW_VERSION: u32 = 0x0001_0400; // 1.4.0 — blitter CON2.SRC_ABS: sources in cart RAM / ROM window
