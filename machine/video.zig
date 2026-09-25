// --------------------------------------------------------------------------
// ZigMachine — SEALED video hardware.
//
// The physical framebuffer + the border/raster/plane compositing pipeline.
// Coders never see this source; they get machine-video.wasm + sdk/hardware.zig.
//
// All state lives in the memory-mapped video region at memmap.HW_VIDEO_BASE
// (registers, 4 palettes, 4 logical framebuffers, physical framebuffer). The
// demo module writes framebuffers/registers into that shared region; this code
// reads them and composites into the physical framebuffer the host blits.
//
// HBL handlers live in the OPEN ZigOS layer. When the pipeline reaches an HBL
// point it calls the host import `hblDispatch(id, plane, line, x)`, which routes
// back into the demo module — only integer ids cross the sealed boundary, never
// a Zig function pointer.
// --------------------------------------------------------------------------
const std = @import("std");
const memmap = @import("sdk/memmap.zig");
const beam = @import("beam.zig");

// The one host import the sealed machine needs: route an HBL point to the demo.
extern fn hblDispatch(id: u32, plane: u32, line: u32, x: u32) void;

// The physical RASTER the PFB holds (see memmap): 800x280. Low-res is composited
// pixel-DOUBLED horizontally into it, medium 1:1, so both share one dot grid.
const RW: usize = memmap.RASTER_WIDTH; // 800
const RH: usize = memmap.RASTER_HEIGHT; // 280
const BX: usize = memmap.RASTER_BORDER_X; // 80 (physical border; = 2 * logical 40)
const BY: usize = memmap.RASTER_BORDER_Y; // 40

// --------------------------------------------------------------------------
// Region accessors (typed views into the reserved hardware address space)
// --------------------------------------------------------------------------
inline fn region() [*]u8 {
    return @ptrFromInt(memmap.HW_VIDEO_BASE);
}
inline fn r8(off: usize) u8 {
    return region()[off];
}
inline fn w8(off: usize, v: u8) void {
    region()[off] = v;
}
inline fn r16(off: usize) u16 {
    return std.mem.readInt(u16, region()[off .. off + 2][0..2], .little);
}
inline fn w16(off: usize, v: u16) void {
    std.mem.writeInt(u16, region()[off .. off + 2][0..2], v, .little);
}
inline fn r32(off: usize) u32 {
    return std.mem.readInt(u32, region()[off .. off + 4][0..4], .little);
}
inline fn w32(off: usize, v: u32) void {
    std.mem.writeInt(u32, region()[off .. off + 4][0..4], v, .little);
}
inline fn pal(plane: usize) [*]u32 {
    return @ptrFromInt(memmap.HW_VIDEO_BASE + memmap.OFF_PAL + plane * memmap.PAL_BYTES);
}
inline fn fbBase(plane: usize) u32 {
    return r32(memmap.REG_FB_BASE + plane * 4);
}
inline fn hscroll(plane: usize) u16 {
    return r16(memmap.REG_HSCROLL + plane * 2);
}
inline fn lfb(plane: usize) [*]u8 {
    // Screen base is the FB_BASE register (ST(E) "screen base"): a byte offset
    // into the region, so a plane's framebuffer can live anywhere in the VRAM pool.
    return @ptrFromInt(memmap.HW_VIDEO_BASE + @as(usize, fbBase(plane)));
}
inline fn pfb() [*]u32 {
    return @ptrFromInt(memmap.HW_VIDEO_BASE + memmap.OFF_PFB);
}

// --- register shortcuts ---
inline fn isTruecolor() bool {
    return r8(memmap.REG_RESOLUTION) == memmap.RES_TRUECOLOR;
}
inline fn setPlanes() void {
    w8(memmap.REG_RESOLUTION, memmap.RES_PLANES);
}
inline fn fbHblId(plane: usize) u16 {
    return r16(memmap.REG_FB_HBL_ID + plane * 2);
}
inline fn fbHblPos(plane: usize) u16 {
    return r16(memmap.REG_FB_HBL_POS + plane * 2);
}
inline fn fbStride(plane: usize) u16 {
    return r16(memmap.REG_FB_STRIDE + plane * 2);
}
inline fn fbMode(plane: usize) u8 {
    return r8(memmap.REG_FB_MODE + plane);
}

// --------------------------------------------------------------------------
// Entry points (wrapped as wasm exports in machine_video.zig)
// --------------------------------------------------------------------------
pub fn basePtr() usize {
    return memmap.HW_VIDEO_BASE;
}
pub fn pfbBytePtr() usize {
    return memmap.HW_VIDEO_BASE + memmap.OFF_PFB;
}

// --------------------------------------------------------------------------
// RAM instructions. The machine owns the memory map, so it answers "how much is
// left?" — but only the LOADER knows where a given cart's static data + stack
// end, because that is baked into the cart wasm. The host measures it once at
// load time and declares it here; everything below is arithmetic on the map.
// --------------------------------------------------------------------------
pub fn setCartHigh(high: u32) void {
    w32(memmap.REG_CART_HIGH, high);
}
pub fn cartHigh() u32 {
    return r32(memmap.REG_CART_HIGH);
}
pub fn setRomHigh(high: u32) void {
    w32(memmap.REG_ROM_HIGH, high);
}
pub fn romHigh() u32 {
    return r32(memmap.REG_ROM_HIGH);
}
// Bytes still available in a window. 0 means either "full" or "never declared" —
// a caller that wants to tell those apart reads the high-water itself. Never
// guesses: an undeclared or out-of-range high-water reports 0 rather than a
// number someone would size a buffer from.
inline fn freeIn(high: u32, base: usize, top: usize) u32 {
    if (high < base or high >= top) return 0;
    return @intCast(top - high);
}
inline fn usedIn(high: u32, base: usize, top: usize) u32 {
    if (high < base or high >= top) return 0;
    return @intCast(high - base);
}
pub fn ramFree() u32 {
    return freeIn(cartHigh(), memmap.CART_RAM_BASE, memmap.CART_RAM_TOP);
}
pub fn ramUsed() u32 {
    return usedIn(cartHigh(), memmap.CART_RAM_BASE, memmap.CART_RAM_TOP);
}
pub fn romRamFree() u32 {
    return freeIn(romHigh(), memmap.ROM_RAM_BASE, memmap.ROM_RAM_TOP);
}
pub fn romRamUsed() u32 {
    return usedIn(romHigh(), memmap.ROM_RAM_BASE, memmap.ROM_RAM_TOP);
}

// Reset the register block; leave palettes/LFBs to the demo's boot.
pub fn reset() void {
    // The high-water registers describe the loaded MODULES, not the video state,
    // and the host may declare them either side of hwInit() — so they survive.
    const cart_high = cartHigh();
    const rom_high = romHigh();
    var i: usize = 0;
    while (i < 256) : (i += 1) w8(memmap.OFF_REG + i, 0);
    w32(memmap.REG_CART_HIGH, cart_high);
    w32(memmap.REG_ROM_HIGH, rom_high);
    w8(memmap.REG_NB_PLANES, memmap.NB_PLANES);
    w8(memmap.REG_RESOLUTION, memmap.RES_PLANES);
    // Every plane starts NORMAL: stride 320, no fine scroll, and its screen base
    // at the legacy contiguous layout — so a binary that never touches these
    // registers behaves exactly as before. ZigOS re-points FB_BASE via its VRAM
    // allocator; a plane opts into fullscreen with FB_STRIDE = STRIDE_FULLSCREEN.
    var p: usize = 0;
    while (p < memmap.NB_PLANES) : (p += 1) {
        w16(memmap.REG_FB_STRIDE + p * 2, memmap.STRIDE_NORMAL);
        w16(memmap.REG_HSCROLL + p * 2, 0);
        w32(memmap.REG_FB_BASE + p * 4, memmap.defaultFbBase(p));
    }
}

// Fill the RASTER with BACKGROUND, running the global HBL handler once per
// scanline (so a per-line handler paints the border/background rasters). A line
// the HBL queued BEAM writes on is painted in spans instead (beam.zig).
pub fn clear() void {
    const gid = r16(memmap.REG_GLOBAL_HBL_ID);
    const out64: [*]u64 = @ptrCast(@alignCast(pfb()));
    var y: usize = 0;
    while (y < RH) : (y += 1) {
        if (gid != 0) hblDispatch(gid, 0, @intCast(y), 0);
        if (r16(memmap.REG_BEAM_COUNT) != 0) {
            beamLine(out64[(y * RW) >> 1 ..][0..beam.W]);
            continue;
        }
        const bg = r32(memmap.REG_BACKGROUND); // re-read after the HBL (per-line colour)
        const pair = @as(u64, bg) | (@as(u64, bg) << 32);
        const row64 = (y * RW) >> 1;
        var i: usize = 0;
        while (i < RW / 2) : (i += 1) out64[row64 + i] = pair; // fill 2 pixels/write
    }
    w32(memmap.REG_FRAME, r32(memmap.REG_FRAME) +% 1);
}

// One BEAM line: paint it, carry its last colour into BACKGROUND (colour 0 keeps
// its value into the next line on an ST), count the drops, consume the list.
fn beamLine(row: []u64) void {
    const table: [*]const u32 = @ptrFromInt(memmap.HW_VIDEO_BASE + memmap.OFF_BEAM_TABLE);
    const line = beam.paintLine(row, r32(memmap.REG_BACKGROUND), table[0..memmap.BEAM_MAX], r16(memmap.REG_BEAM_COUNT));
    w32(memmap.REG_BACKGROUND, line.bg);
    w32(memmap.REG_BEAM_DROPPED, r32(memmap.REG_BEAM_DROPPED) +% line.dropped);
    w16(memmap.REG_BEAM_COUNT, 0);
}

// Write one logical pixel DOUBLED at physical (px..px+1, py) as a single 64-bit
// store (px is always even in the doubled paths, and the raster is 8-aligned), so
// low-res compositing costs one write per logical pixel, not two.
inline fn put2(out: [*]u32, py: usize, px: usize, c: u32) void {
    const out64: [*]u64 = @ptrCast(@alignCast(out));
    out64[(py * RW + px) >> 1] = @as(u64, c) | (@as(u64, c) << 32);
}

// Composite one logical framebuffer into the physical framebuffer, honouring
// the border-opening (overscan) trick driven by the RESOLUTION register + HBL
// handlers. Ported 1:1 from the original bootloader render loop; the per-pixel
// fb_index accounting for opened borders is delicate, so it is kept as a single
// faithful pass rather than refactored.
// Option B: a fullscreen plane (stride 400) is backed by a 400×280 buffer and
// composited across the WHOLE physical frame — borders included — so independent
// content (e.g. a fullscreen scroller) lands in the borders from a real backing
// store, no physical-framebuffer poke. The border pixels it writes persist in the
// PFB through the later (border-untouching) plane renders, so they reach the top
// canvas. Transparent index (palette alpha 0) lets lower planes/background show.
fn renderPlaneFullscreen(fb_id: usize) void {
    const buf = lfb(fb_id); // 400x280 logical, stride 400
    const stride: usize = fbStride(fb_id);
    const palette = pal(fb_id);
    const out = pfb();
    const hid = fbHblId(fb_id);
    const hpos = fbHblPos(fb_id);
    const hs: usize = @intCast(hscroll(fb_id)); // fine horizontal scroll (wraps within the row)
    var y: usize = 0;
    while (y < RH) : (y += 1) {
        if (hid != 0) hblDispatch(hid, @intCast(fb_id), @intCast(y), @intCast(hpos));
        const srow = y * stride;
        var lx: usize = 0;
        while (lx < memmap.PHYSICAL_WIDTH) : (lx += 1) // 400 logical -> 800 physical (doubled)
            put2(out, y, lx * 2, palette[buf[srow + (lx + hs) % stride]]);
    }
}

// --- overscan (border-opening trick) helpers -------------------------------
// True when the flicker landed within tolerance of the magic column (hpos is the
// per-plane HBL fire position, in logical coords 0..PHYSICAL_WIDTH).
inline fn overscanHit(hpos: u16) bool {
    const d: i32 = @as(i32, hpos) - @as(i32, memmap.OVERSCAN_MAGIC_X);
    return (if (d < 0) -d else d) <= @as(i32, memmap.OVERSCAN_X_TOL);
}
// Composite logical columns [x0, x1) of one buffer row, pixel-doubled into the raster.
fn compRow(out: [*]u32, buf: [*]u8, palette: [*]u32, y: usize, srow: usize, x0: usize, x1: usize) void {
    var lx = x0;
    while (lx < x1) : (lx += 1) put2(out, y, lx * 2, palette[buf[srow + lx]]);
}
// Botched-timing corruption: frame-animated colour noise in a border region.
fn noiseRow(out: [*]u32, palette: [*]u32, y: usize, x0: usize, x1: usize, seed: usize) void {
    var lx = x0;
    while (lx < x1) : (lx += 1) {
        const idx: u8 = @truncate(lx *% 37 +% y *% 101 +% seed *% 7);
        put2(out, y, lx * 2, palette[idx]);
    }
}
// A full-width border-band row: buffer content if the band is open, noise on a
// mistimed flicker, otherwise untouched (background from clear()).
fn bandRow(out: [*]u32, buf: [*]u8, palette: [*]u32, y: usize, srow: usize, open: bool, flick: bool, seed: usize) void {
    if (open) compRow(out, buf, palette, y, srow, 0, memmap.PHYSICAL_WIDTH) else if (flick) noiseRow(out, palette, y, 0, memmap.PHYSICAL_WIDTH, seed);
}
// A visible row: the 320 window is always drawn; the two side borders open (from
// the buffer) on a well-timed flicker, or show noise on a mistimed one.
fn visibleRow(out: [*]u32, buf: [*]u8, palette: [*]u32, y: usize, srow: usize, sides: bool, flick: bool, seed: usize) void {
    const l: usize = memmap.HORIZONTAL_BORDERS_WIDTH; // 40
    const r: usize = l + memmap.WIDTH; // 360
    compRow(out, buf, palette, y, srow, l, r);
    if (sides) {
        compRow(out, buf, palette, y, srow, 0, l);
        compRow(out, buf, palette, y, srow, r, memmap.PHYSICAL_WIDTH);
    } else if (flick) {
        noiseRow(out, palette, y, 0, l, seed);
        noiseRow(out, palette, y, r, memmap.PHYSICAL_WIDTH, seed);
    }
}

// OVERSCAN plane: a 400×280 buffer whose borders stay CLOSED until the scene
// "opens" them with the resolution-flicker trick (see memmap OVERSCAN_*). The
// per-plane HBL fires on EVERY scanline (border bands included) so the handler
// can flicker there; the machine observes the (untrappable) flicker via the
// REG_RES_FLICKER latch bumped by the SDK. Opening is causal top-to-bottom.
fn renderPlaneOverscan(fb_id: usize) void {
    const buf = lfb(fb_id);
    const stride: usize = fbStride(fb_id);
    const palette = pal(fb_id);
    const out = pfb();
    const hid = fbHblId(fb_id);
    const hpos = fbHblPos(fb_id);
    const seed: usize = @intCast(r32(memmap.REG_FRAME));
    var top_open = false;
    var bottom_open = false;
    var y: usize = 0;
    while (y < RH) : (y += 1) {
        const before = r16(memmap.REG_RES_FLICKER);
        if (hid != 0) hblDispatch(hid, @intCast(fb_id), @intCast(y), @intCast(hpos));
        const flick = r16(memmap.REG_RES_FLICKER) != before;
        const hit = flick and overscanHit(hpos);
        const srow = y * stride;
        if (y < BY) {
            if (hit) top_open = true;
            bandRow(out, buf, palette, y, srow, top_open, flick, seed);
        } else if (y < BY + memmap.HEIGHT) {
            visibleRow(out, buf, palette, y, srow, hit, flick, seed);
        } else {
            if (hit) bottom_open = true;
            bandRow(out, buf, palette, y, srow, bottom_open, flick, seed);
        }
    }
}

// Low-res NORMAL plane: 320x200 logical, composited pixel-doubled into the visible
// 640x200 physical window. Borders are left to the background (clear).
fn renderPlaneNormal(fb_id: usize) void {
    const buf = lfb(fb_id);
    const stride: usize = fbStride(fb_id);
    const palette = pal(fb_id);
    const out = pfb();
    const hid = fbHblId(fb_id);
    const hpos = fbHblPos(fb_id);
    var ly: usize = 0;
    while (ly < memmap.HEIGHT) : (ly += 1) {
        const py = BY + ly;
        if (hid != 0) hblDispatch(hid, @intCast(fb_id), @intCast(ly), @intCast(hpos));
        const srow = ly * stride;
        var lx: usize = 0;
        while (lx < memmap.WIDTH) : (lx += 1) put2(out, py, BX + lx * 2, palette[buf[srow + lx]]);
    }
}

// MEDIUM plane: a 640-wide buffer composited into the visible window. The global
// RESOLUTION register is RE-READ per scanline (after the per-plane HBL), so a
// handler can switch resolution mid-screen (the ST shifter trick): a MEDIUM line
// draws 640 pixels 1:1; a low (RES_PLANES) line draws the first 320 columns
// pixel-doubled — both land on the same raster.
// A MEDIUM plane whose stride is the full raster width (800) is an OVERSCAN plane:
// it covers the whole frame including the borders (the medium twin of Option B).
fn renderPlaneMedium(fb_id: usize) void {
    const buf = lfb(fb_id);
    const stride: usize = fbStride(fb_id);
    const palette = pal(fb_id);
    const out = pfb();
    const hid = fbHblId(fb_id);
    const hpos = fbHblPos(fb_id);
    const overscan = stride >= RW;
    const rows: usize = if (overscan) RH else memmap.MEDIUM_HEIGHT;
    const oy: usize = if (overscan) 0 else BY;
    const ox: usize = if (overscan) 0 else BX;
    const medcols: usize = if (overscan) RW else memmap.MEDIUM_WIDTH; // 800 or 640
    const lowcols: usize = if (overscan) memmap.PHYSICAL_WIDTH else memmap.WIDTH; // 400 or 320
    var ly: usize = 0;
    while (ly < rows) : (ly += 1) {
        const py = oy + ly;
        if (hid != 0) hblDispatch(hid, @intCast(fb_id), @intCast(ly), @intCast(hpos));
        const srow = ly * stride;
        if (r8(memmap.REG_RESOLUTION) == memmap.RES_MEDIUM) {
            const orow = py * RW + ox;
            var lx: usize = 0;
            while (lx < medcols) : (lx += 1) out[orow + lx] = palette[buf[srow + lx]];
        } else {
            var lx: usize = 0;
            while (lx < lowcols) : (lx += 1) put2(out, py, ox + lx * 2, palette[buf[srow + lx]]);
        }
    }
}

// Composite the visible 320x200 window from a bigger-than-screen buffer (SCROLL
// mode). FB_BASE points at the window's top-left in the buffer (coarse pan, incl.
// vertical); HSCROLL adds a horizontal offset that is RE-READ per scanline, so a
// per-plane HBL handler can rewrite it each line for a sine/line-shear distort
// (the ST/Amiga "screen-offset" wobble). Borders are left untouched.
fn renderPlaneScroll(fb_id: usize) void {
    const buf = lfb(fb_id);
    const stride: usize = fbStride(fb_id);
    const palette = pal(fb_id);
    const out = pfb();
    const hid = fbHblId(fb_id);
    const hpos = fbHblPos(fb_id);
    var vy: usize = 0;
    while (vy < memmap.HEIGHT) : (vy += 1) {
        const py = BY + vy;
        if (hid != 0) hblDispatch(hid, @intCast(fb_id), @intCast(vy), @intCast(hpos));
        const hs: usize = @intCast(hscroll(fb_id)); // read AFTER the HBL so a per-line handler distorts
        const srow = vy * stride + hs;
        var vx: usize = 0;
        while (vx < memmap.WIDTH) : (vx += 1) put2(out, py, BX + vx * 2, palette[buf[srow + vx]]);
    }
}

pub fn renderPlane(fb_id: usize) void {
    switch (fbMode(fb_id)) {
        memmap.FB_MODE_SCROLL => return renderPlaneScroll(fb_id),
        memmap.FB_MODE_FULLSCREEN => return renderPlaneFullscreen(fb_id),
        memmap.FB_MODE_OVERSCAN => return renderPlaneOverscan(fb_id),
        memmap.FB_MODE_MEDIUM => return renderPlaneMedium(fb_id),
        else => {},
    }
    // Back-compat: fullscreen was once detected purely by stride == 400.
    if (fbStride(fb_id) == memmap.STRIDE_FULLSCREEN) return renderPlaneFullscreen(fb_id);
    renderPlaneNormal(fb_id);
}
