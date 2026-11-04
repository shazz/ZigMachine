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
// A true-colour plane (FB_MODE_TRUECOLOR / _FULL) is two bytes a pixel: its FB_STRIDE is in BYTES.
pub const TRUECOLOR_STRIDE: u16 = 2 * WIDTH; // 640
pub const TRUECOLOR_FULL_STRIDE: u16 = 2 * PHYSICAL_WIDTH; // 800
pub const TRUECOLOR_FB_BYTES: usize = 2 * NORMAL_FB_BYTES; // 128000
pub const TRUECOLOR_FULL_FB_BYTES: usize = 2 * FULLSCREEN_FB_BYTES; // 224000

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
// --- TRUE-COLOUR FADE (1.16.0, docs/HW_API.md "True-colour fade"; machine/video_tc_fade.zig) ---
// Applied to a true-colour plane's 888 pixel after the 565 expansion, every line (a copper REG
// may rewrite them per line): a coefficient toward black or white, then a signed offset per
// channel, clamped to 0..255. All zero (the reset) is the identity; other modes ignore them.
pub const REG_TC_FADE: usize = 0x0C; // u8 x4 (0x0C..0x0F) bits 0..4 coef 0..31 (31 = full), bit 5 1 = toward white, bits 6..7 ignored
pub const REG_TC_OFS_R: usize = 0x14; // i8 x4 (0x14..0x17) red offset of plane p, -128..127
pub const REG_TC_OFS_G: usize = 0x18; // i8 x4 (0x18..0x1B)
pub const REG_TC_OFS_B: usize = 0x1C; // i8 x4 (0x1C..0x1F)
pub const TC_FADE_WHITE: u8 = 0x20;
pub const REG_GLOBAL_HBL_ID: usize = 0x10; // u16  border/background HBL handler id (0 = none)
pub const REG_FB_HBL_ID: usize = 0x20; // u16 x4 per-plane HBL handler id (0 = none)
pub const REG_FB_HBL_POS: usize = 0x28; // u16 x4 x position at which the per-plane HBL fires
pub const REG_FRAME: usize = 0x30; // u32  (ro) frame counter
pub const REG_FB_STRIDE: usize = 0x34; // u16 x4 per-plane row stride in pixels (320 normal, 400 fullscreen, or any SCROLL buffer width)
pub const REG_HSCROLL: usize = 0x3C; // u16 x4 per-plane horizontal scroll (re-read PER SCANLINE in SCROLL and, since 1.10.0, OVERSCAN mode → line distort)
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
pub const REG_ROM_HIGH: usize = 0x60; // u32  (0x60..0x63)

// --- BEAM (1.6.0): mid-line colour-0 writes ---------------------------------
// The ST's zero-bitplane trick: rewrite colour 0 ($FF8240) with cycle-counted
// move.w's while the beam crosses a line, so the background itself is the
// picture. The GLOBAL HBL for physical line y queues up to BEAM_MAX writes;
// clear() paints the line in spans from them, then consumes the list. The
// machine enforces the 68000's limits and COUNTS every write that breaks them
// (docs/HARDWARE_SPEC.md, "BEAM"). BEAM_COUNT = 0 is the pre-1.6.0 path exactly.
pub const REG_BEAM_COUNT: usize = 0x64; // u16  entries queued for the CURRENT line (0x64..0x65; 0x66..0x67 free)
pub const REG_BEAM_DROPPED: usize = 0x68; // u32  running count of rejected writes (0x68..0x6B)

// --- RAM ARENA (1.7.0): hwRamAlloc / hwRamMark / hwRamRelease ----------------
// A bump allocator over the cart window ABOVE the cart's high-water (CART_HIGH)
// and below the video region, so a big working buffer costs nothing in the cart
// binary (machine/arena.zig). Both registers are the machine's own state: they
// survive hwInit() like CART_HIGH, and hwSetCartHigh() -- the host declaring a
// NEW cart, at every boot or swap -- empties the arena and zeroes the counter.
pub const REG_RAM_ARENA_TOP: usize = 0x6C; // u32  first byte above the arena; 0 = empty (0x6C..0x6F)
pub const REG_RAM_ALLOC_FAILS: usize = 0x70; // u32  (ro) refused hwRamAlloc/hwRamRelease calls (0x70..0x73)
// --- PURE HBL (1.8.0) -----------------------------------------------------------
// A plane's HBL handler that writes ONLY its own plane's palette and/or flickers the
// border (flickerBorder: RESOLUTION and RES_FLICKER), reading tables and what frame()
// wrote, may be run between the passes of OTHER planes on the same line: the board's
// compositor then moves each line once for a run of such planes (fpga/cycles/vseq_group.c).
// The cart (ZigOS: openBorders, copper, linepal, setFrameBufferHBLHandlerPure) sets the
// byte; the browser machine ignores it: its plane-major order is the reference.
pub const REG_FB_HBL_PURE: usize = 0x74; // u8 x4  1 = plane p's HBL handler is pure (0x74..0x77)
// --- COPPER LIST (1.9.0) -------------------------------------------------------
// Plane p's per-line register writes (machine/copper.zig, fpga/review/COPPER_LIST.md): the list
// is at region offset OFF_VRAM + 16 * v; v = 0: none. Read when the plane's frame starts.
pub const REG_FB_COPPER: usize = 0x78; // u16 x4 (0x78..0x7F, the register block's last bytes)
// The table is 256 bytes, too big for the register block, so it sits directly
// ABOVE the physical framebuffer: outside REGION_BYTES, which is the window the
// blitter reads and writes — a blit can never scribble a line's writes.
// Entry = x:u16 (high half, PHYSICAL px 0..399, left border included) | colour
// (low half: an ST/STE colour word exactly as written to $FF8240).
pub const OFF_BEAM_TABLE: usize = OFF_PFB + PFB_BYTES; // = REGION_BYTES
pub const BEAM_MAX: usize = 64; // entries a line
pub const BEAM_TABLE_BYTES: usize = BEAM_MAX * 4; // 256
// The blitter's QUEUE ring (1.11.0, see BLIT_CMD_QUEUE): 512 u32 words above the BEAM
// table, 2 KiB-aligned (KESTREL's CHISEL keeps a copy of it, fed by the CPU's stores,
// indexed by the offset's low bits). Outside REGION_BYTES: no blit can write it.
pub const BLIT_QUEUE_WORDS: usize = 512;
pub const BLIT_QUEUE_BYTES: usize = BLIT_QUEUE_WORDS * 4;
pub const OFF_BLIT_QUEUE: usize = (OFF_BEAM_TABLE + BEAM_TABLE_BYTES + BLIT_QUEUE_BYTES - 1) / BLIT_QUEUE_BYTES * BLIT_QUEUE_BYTES;
pub const BEAM_GRID: u16 = 4; // x snaps DOWN to it: the 68000's 4-cycle bus slot (1 low-res px a cycle)
pub const BEAM_MIN_GAP: u16 = 8; // px between accepted writes: move.w Dn,(An) = 8 cycles, the fastest write

pub const FB_MODE_NORMAL: u8 = 0; // 320x200 low-res plane (pixel-doubled into the raster)
pub const FB_MODE_FULLSCREEN: u8 = 1; // 400x280 low-res overscan plane (Option B, doubled)
pub const FB_MODE_SCROLL: u8 = 2; // window into a bigger-than-screen buffer; pan via FB_BASE + HSCROLL
pub const FB_MODE_MEDIUM: u8 = 3; // 640x200 medium-res plane (1:1 into the raster)
pub const FB_MODE_OVERSCAN: u8 = 4; // 400x280 buffer, borders CLOSED until opened by the resolution-flicker trick (see OVERSCAN_* below)
pub const FB_MODE_TRUECOLOR: u8 = 5; // 320x200 RGB565 plane (u16 LE pixels, no palette, doubled from x 80), HSCROLL per line; bit 0 of a line's address is ignored (HW 1.15.0)
pub const FB_MODE_TRUECOLOR_FULL: u8 = 6; // 400x280 RGB565 plane over the whole raster, borders open (nothing to earn), HSCROLL per line (HW 1.15.0)

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
// ASYNC (KESTREL only, no machine behaviour): non-zero lets the board's hwBlit() return
// while CHISEL still runs. The cart promises not to touch an op's source or destination
// pixels until it syncs (a NOP hwBlit); the next hwBlit, any ROM call, a disk read, the RAM
// arena's alloc/mark/release and the frame's end wait too, the getters (hwVideoBase...) do
// not (fpga/cycles/bchisel.h, fpga/tools/host_gen.py GETTERS). The machine's blitter is synchronous, so
// it never reads this byte: the browser's pixels cannot change. Outside the 24 words
// CHISEL's tap copies (0x80..0xDF) and every video snoop window: plain memory.
pub const BLIT_ASYNC: usize = OFF_BLIT + 0x64; // u8  (board) 1 = hwBlit may return before the op ends
// QUEUE (1.11.0): COMMAND 5 runs a list of op descriptors that the program stored in
// the QUEUE ring (OFF_BLIT_QUEUE, u32 words), so many small ops cost one hwBlit().
// A descriptor is a header word -- bits 0..23 a mask of the block's words 0..23
// (offset / 4) it sets, bits 24..31 the op's COMMAND -- then the words of the
// mask, lowest first. Each op runs on a WORKING COPY of the block taken at the
// hwBlit(): a descriptor's words land in that copy (word 0: MINTERM and CON only,
// COMMAND is the header's; strides: low 16 bits) and stay for the descriptors
// after it. COMMAND 0 only sets words. The block itself is left as it was: CYCLES
// becomes the SUM of the ops' costs. Refused (CYCLES 0, nothing drawn) unless
// 1 <= Q_COUNT and Q_START + Q_COUNT <= BLIT_QUEUE_WORDS; a descriptor cut short by
// Q_COUNT ends the list unrun. COMMAND 5 inside a descriptor is an unknown op, and
// an op whose D_BASE is below OFF_VRAM is refused (cost 0): a list draws into planes.
pub const BLIT_Q_START: usize = OFF_BLIT + 0x68; // u16 first ring word of the list
pub const BLIT_Q_COUNT: usize = OFF_BLIT + 0x6A; // u16 words in the list

// COMMAND values
pub const BLIT_CMD_NOP: u8 = 0;
pub const BLIT_CMD_BLIT: u8 = 1;
pub const BLIT_CMD_FILL: u8 = 2;
pub const BLIT_CMD_LINE: u8 = 3;
pub const BLIT_CMD_TRIANGLE: u8 = 4;
pub const BLIT_CMD_QUEUE: u8 = 5; // 1.11.0: run the descriptors at BLIT_Q_START/COUNT (see above)
pub const BLIT_CMD_AFFINE: u8 = 6; // 1.11.0: textured spans from a list (see BLIT_SPAN_*)
pub const BLIT_CMD_MAP: u8 = 7; // 1.11.0: W x H box, each pixel's texel from a (u, v) map (see below)

// --- CHISEL v2 (1.11.0): AFFINE and MAP --------------------------------------------
// Both read a TEXTURE through channel A: texel (U, V) at A_BASE + V * A_STRIDE + U
// (A_BASE relative or, with CON2.SRC_ABS, absolute, as a BLIT source), U and V cut by
// U_MASK / V_MASK: wrapped (U & U_MASK), or with CON2.TEX_CLIP a texel past a mask is
// not drawn. The texel is B of the minterm: D = LF(0, texel, D) (MT_B: a plain write),
// KEY_EN skips texel == COLOR_KEY, the clip and D are as for any op, CYCLES counts the
// pixels written. The texture rectangle (U_MASK+1) x (V_MASK+1) must lie in ONE readable
// window, or the op draws nothing.
// AFFINE: SPAN_COUNT spans of BLIT_SPAN_BYTES at SPAN_BASE, an ABSOLUTE 4-aligned address
// whose whole list lies in cart RAM or the ROM window (never video memory: CHISEL never
// writes what it is walking). A span is x0:i16, x1:i16 (exclusive), y:i16, 0:u16, then
// u0, v0, du, dv: u32 (16.16, two's complement). Pixel x of the span reads texel
// (u >> 16, v >> 16) with u = u0 + (x - x0) * du, v = v0 + (x - x0) * dv (mod 2^32).
// A Mode 7 floor is a span a row; a textured polygon a span per row it covers.
// MAP: the BLIT box (W x H at X0, Y0, clipped, ascending); pixel (i, j) reads the u16 at
// B_BASE + j * B_STRIDE + 2 * i, an ABSOLUTE address in cart RAM or the ROM window (as
// SPAN_BASE; B_BASE and B_STRIDE even): u = its low byte, v = its high byte, then U = (u + U_OFF) mod 2^16,
// V = (v + V_OFF) mod 2^16 before the masks. A tunnel is a map plus a moving offset.
// The registers reuse words no other op reads (C_BASE/C_STRIDE: channel C is always the
// destination; the strides' high halves; X1/Y1 for MAP), so the QUEUE's 24-word
// descriptors can set them.
pub const BLIT_U_MASK: usize = OFF_BLIT + 0x0E; // u16 texture U mask (A_STRIDE's high half)
pub const BLIT_V_MASK: usize = OFF_BLIT + 0x16; // u16 texture V mask (B_STRIDE's high half)
pub const BLIT_SPAN_BASE: usize = OFF_BLIT + 0x18; // u32 AFFINE span list, absolute (was C_BASE)
pub const BLIT_SPAN_COUNT: usize = OFF_BLIT + 0x1C; // u16 AFFINE spans in the list (was C_STRIDE)
pub const BLIT_U_OFF: usize = BLIT_X1; // u16 MAP: added to every map u
pub const BLIT_V_OFF: usize = BLIT_Y1; // u16 MAP: added to every map v
pub const BLIT_SPAN_BYTES: usize = 24;
// COLL (1.11.0): bit 0 set by an op run with CON2.COLL_EN that wrote a pixel over a
// non-zero destination byte; sticky until the program writes the byte (0) itself.
pub const BLIT_COLL: usize = OFF_BLIT + 0x66; // u8 (outside the QUEUE's words: a status, not a parameter)

// CON control bits
pub const CON_USEA: u8 = 1 << 0; // channel A enabled
pub const CON_USEB: u8 = 1 << 1; // channel B enabled
pub const CON_USEC: u8 = 1 << 2; // channel C enabled
pub const CON_KEY_EN: u8 = 1 << 3; // colour-key cookie-cut (skip B == COLOR_KEY)
pub const CON_IFE: u8 = 1 << 4; // inclusive area fill (1.11.0: BLIT, FILL; see CON2_FILL_CARRY)
pub const CON_EFE: u8 = 1 << 5; // exclusive area fill (1.11.0: BLIT, FILL)
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
// FILL_MT (1.5.0): FILL combines its source (channel B: COLOR, or the halftone
// pick) with the destination (channel C) through MINTERM, exactly as TRIANGLE
// does. Opt-in, because FILL ignored MINTERM until 1.5.0 and every caller left
// the register holding whatever the previous op wrote: with the bit clear FILL
// writes the colour straight, as it always did.
pub const CON2_FILL_MT: u8 = 1 << 1;
// HALFTONE_EN (1.5.0): the HALFTONE pattern is active because the program says
// so, not because the machine found a non-zero row in it. An all-zero pattern
// then means "every pixel is BG_COLOR" (density 0) instead of "no halftone".
// With the bit clear the machine sniffs the pattern, as it did before 1.5.0.
pub const CON2_HALFTONE_EN: u8 = 1 << 2;
// 1.11.0 (CHISEL v2):
// MIRROR_X / MIRROR_Y: a BLIT reads its sources flipped, column W-1-i / row H-1-j for
// the destination's pixel (i, j) (sprite flips, kaleidoscopes).
pub const CON2_MIRROR_X: u8 = 1 << 3;
pub const CON2_MIRROR_Y: u8 = 1 << 4;
// COLL_EN: the op sets BLIT_COLL bit 0 when it writes a pixel over a non-zero byte.
pub const CON2_COLL_EN: u8 = 1 << 5;
// TEX_CLIP: AFFINE/MAP draw nothing for a texel past U_MASK / V_MASK (else they wrap).
pub const CON2_TEX_CLIP: u8 = 1 << 6;
// FILL_CARRY: area fill (CON.IFE/EFE) starts each row inside (the Amiga's FCI).
pub const CON2_FILL_CARRY: u8 = 1 << 7;

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
// Layout of the shared memory (v1.3 — cart window 3 MiB, HW 1.13.0):
//   [0x000000 .. 0x100000)  machine module data + stack  (global-base 0x400)
//   [0x100000 .. 0x400000)  demo module data + stack     (global-base 0x100000) — 3 MiB
//   [0x400000 .. ~0x5DC000) video hardware region        (this base)
//   [0x600000 .. 0x800000)  ROM chip data + stack        (global-base 0x600000) — 2 MiB
// The demo window grew from 1 MiB to 2 MiB (v1.1: a full cart was overflowing 1 MiB
// into the video region, silently corrupting the top of its stack), then to 4 MiB
// (HW 1.12.0, 2026-11-01): the C port of pt2-clone could not load a ProTracker
// module in 2 MiB. The video region and the ROM window moved up 2 MiB with it.
// HW 1.13.0 (2026-11-02) settled on 3 MiB: the whole memory then ends at exactly
// 8 MiB, the most CHISEL's 23-bit linear addresses and the seal's 8 MiB linear
// window reach, so the board needs a new bitstream (the video base is compiled into
// CHISEL) but no RTL change. 4 MiB would have needed a 24-bit CHISEL.
// --------------------------------------------------------------------------
pub const HW_VIDEO_BASE: usize = 0x400000; // 4 MiB (demo cart gets [0x100000..0x400000))
// The cart's RAM window, as reported by the hwRam* instructions. The ceiling is
// HW_VIDEO_BASE: one byte past it is the video region, and a cart that runs into
// it corrupts VRAM silently rather than trapping.
pub const CART_RAM_BASE: usize = 0x100000; // = build.zig demo_global_base
pub const CART_RAM_TOP: usize = HW_VIDEO_BASE;
pub const CART_RAM_BYTES: usize = CART_RAM_TOP - CART_RAM_BASE; // 3 MiB

// The ROM chip's own RAM window (Phase 2 — see docs/PHASE2_ROM_CHIP.md). Placed
// ABOVE the video region, never carved out of the cart's: the whole point is that
// an app's window stays the app's. The video region ends at HW_VIDEO_BASE + OFF_PFB
// + PFB_BYTES = 0x5DBFE0, so 0x600000 clears it with room to spare.
//
// It is one shared linear memory, so a pointer an app passes is directly readable
// by the ROM — strings and structs cross the module boundary with no copy, and
// GEM keeps drawing straight into the framebuffers in the video region.
pub const ROM_RAM_BASE: usize = 0x600000; // 6 MiB (= build.zig rom_global_base)
pub const ROM_RAM_TOP: usize = 0x800000; // 8 MiB
pub const ROM_RAM_BYTES: usize = ROM_RAM_TOP - ROM_RAM_BASE; // 2 MiB
// The shared memory ends at ROM_RAM_TOP: SHARED_PAGES * 64 KiB == ROM_RAM_TOP
// (checked below). initial == max. History: 79 pages (video only), 112 (7 MiB, the
// ROM window), 144 (9 MiB, the 4 MiB cart window, HW 1.12.0), 128 (8 MiB, the 3 MiB cart
// window, HW 1.13.0: the board's limit). Every change is a
// BREAKING change for any cart packed before it — a cart declares the imported
// memory's initial/max, and an old cart's max is smaller than the memory the host
// now creates, so it fails to instantiate. Repack with tools/mkdisks.sh and
// rebuild the C/Rust carts; node apps/disk_check.mjs is what catches it.
pub const SHARED_PAGES: u32 = 128;

pub const ZM_HW_VERSION: u32 = 0x0001_1000; // 1.16.0 — the true-colour fade: REG_TC_FADE + REG_TC_OFS_R/G/B per plane, also copper REG targets (decisions.md 2026-11-03 "True-colour fade"); 1.15.0 — the true-colour plane: FB_MODE_TRUECOLOR (5) / _FULL (6), RGB565 through FRESCO's painter (decisions.md 2026-11-02 "True-colour plane"); 1.14.0 — a cart may claim the four Paula channels (env.hostPaula*: chip RAM uploads, timed Amiga register writes; decisions.md 2026-11-02); 1.13.0 — the cart RAM window is 3 MiB [0x100000..0x400000), video at 0x400000, ROM RAM at 0x600000, 8 MiB in all (1.12.0: 4 MiB, never on the board; 1.11.0: CHISEL v2 QUEUE/AFFINE/MAP/mirror/collision/area fill; 1.10.0: copper LBASE + HSCROLL on overscan; 1.9.0: REG_FB_COPPER)

// Register-block overlaps are SILENT (two names, one byte), so the BEAM and RAM
// ARENA layouts prove at compile time that they clear their neighbours.
comptime {
    if (REG_PLANE_ENABLE + NB_PLANES > REG_TC_FADE or REG_TC_FADE + NB_PLANES > REG_GLOBAL_HBL_ID) @compileError("memmap: TC_FADE overlaps its neighbours");
    if (REG_GLOBAL_HBL_ID + 2 > REG_TC_OFS_R or REG_TC_OFS_R + NB_PLANES > REG_TC_OFS_G or REG_TC_OFS_G + NB_PLANES > REG_TC_OFS_B or REG_TC_OFS_B + NB_PLANES > REG_FB_HBL_ID) @compileError("memmap: TC_OFS overlaps its neighbours");
    if (REG_ROM_HIGH + 4 > REG_BEAM_COUNT) @compileError("memmap: ROM_HIGH overlaps BEAM_COUNT");
    if (REG_BEAM_COUNT + 2 > REG_BEAM_DROPPED) @compileError("memmap: BEAM_COUNT overlaps BEAM_DROPPED");
    if (REG_BEAM_DROPPED + 4 > REG_RAM_ARENA_TOP) @compileError("memmap: BEAM_DROPPED overlaps RAM_ARENA_TOP");
    if (REG_RAM_ARENA_TOP + 4 > REG_RAM_ALLOC_FAILS) @compileError("memmap: RAM_ARENA_TOP overlaps RAM_ALLOC_FAILS");
    if (REG_RAM_ALLOC_FAILS + 4 > REG_FB_HBL_PURE) @compileError("memmap: RAM_ALLOC_FAILS overlaps FB_HBL_PURE");
    if (REG_FB_HBL_PURE + NB_PLANES > REG_FB_COPPER) @compileError("memmap: FB_HBL_PURE overlaps FB_COPPER");
    if (REG_FB_COPPER + 2 * @as(usize, NB_PLANES) > OFF_BLIT) @compileError("memmap: FB_COPPER overlaps the blitter block");
    if (REG_RAM_ARENA_TOP % 4 != 0 or REG_RAM_ALLOC_FAILS % 4 != 0) @compileError("memmap: RAM arena registers must be u32-aligned");
    if (OFF_BEAM_TABLE % 4 != 0) @compileError("memmap: BEAM table must be u32-aligned");
    if (OFF_BEAM_TABLE < REGION_BYTES) @compileError("memmap: BEAM table inside the blitter's window");
    if (HW_VIDEO_BASE + OFF_BEAM_TABLE + BEAM_TABLE_BYTES > ROM_RAM_BASE) @compileError("memmap: BEAM table runs into the ROM window");
    if (BLIT_ASYNC + 1 > BLIT_Q_START or BLIT_Q_COUNT + 2 > OFF_PAL) @compileError("memmap: BLIT_Q_* overlap ASYNC or the palettes");
    if (OFF_BLIT_QUEUE < OFF_BEAM_TABLE + BEAM_TABLE_BYTES) @compileError("memmap: QUEUE ring overlaps the BEAM table");
    if (HW_VIDEO_BASE + OFF_BLIT_QUEUE + BLIT_QUEUE_BYTES > ROM_RAM_BASE) @compileError("memmap: QUEUE ring runs into the ROM window");
    if (CART_RAM_TOP > HW_VIDEO_BASE) @compileError("memmap: the cart window runs into the video region");
    if (HW_VIDEO_BASE + OFF_PFB + PFB_BYTES > ROM_RAM_BASE) @compileError("memmap: the video region runs into the ROM window");
    if (@as(usize, SHARED_PAGES) * 65536 != ROM_RAM_TOP) @compileError("memmap: SHARED_PAGES must end exactly at ROM_RAM_TOP");
}
