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

// The one host import the sealed machine needs: route an HBL point to the demo.
extern fn hblDispatch(id: u32, plane: u32, line: u32, x: u32) void;

const PWu: usize = memmap.PHYSICAL_WIDTH; // 400
const PHu: usize = memmap.PHYSICAL_HEIGHT; // 280
const HB: usize = memmap.HORIZONTAL_BORDERS_WIDTH; // 40
const VB: usize = memmap.VERTICAL_BORDERS_HEIGHT; // 40

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
inline fn lfb(plane: usize) [*]u8 {
    return @ptrFromInt(memmap.HW_VIDEO_BASE + memmap.OFF_LFB + plane * memmap.LFB_BYTES);
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

// --------------------------------------------------------------------------
// Entry points (wrapped as wasm exports in machine_video.zig)
// --------------------------------------------------------------------------
pub fn basePtr() usize {
    return memmap.HW_VIDEO_BASE;
}
pub fn pfbBytePtr() usize {
    return memmap.HW_VIDEO_BASE + memmap.OFF_PFB;
}

// Reset the register block; leave palettes/LFBs to the demo's boot.
pub fn reset() void {
    var i: usize = 0;
    while (i < 256) : (i += 1) w8(memmap.OFF_REG + i, 0);
    w8(memmap.REG_NB_PLANES, memmap.NB_PLANES);
    w8(memmap.REG_RESOLUTION, memmap.RES_PLANES);
    // Every plane starts NORMAL (320-wide, visible only). A plane opts into
    // fullscreen by writing STRIDE_FULLSCREEN to its FB_STRIDE.
    var p: usize = 0;
    while (p < memmap.NB_PLANES) : (p += 1) w16(memmap.REG_FB_STRIDE + p * 2, memmap.STRIDE_NORMAL);
}

// Fill the physical framebuffer with BACKGROUND, running the global HBL handler
// once per scanline (as the old clearPhysicalFrameBuffer did).
pub fn clear() void {
    const gid = r16(memmap.REG_GLOBAL_HBL_ID);
    const bg = r32(memmap.REG_BACKGROUND);
    const out = pfb();
    var y: usize = 0;
    while (y < PHu) : (y += 1) {
        if (gid != 0) hblDispatch(gid, 0, @intCast(y), 0);
        var x: usize = 0;
        const row = y * PWu;
        while (x < PWu) : (x += 1) out[row + x] = bg;
    }
    w32(memmap.REG_FRAME, r32(memmap.REG_FRAME) +% 1);
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
    const buf = lfb(fb_id); // 400×280, stride == PW
    const palette = pal(fb_id);
    const out = pfb();
    const hid = fbHblId(fb_id);
    const hpos = fbHblPos(fb_id);
    var y: usize = 0;
    while (y < PHu) : (y += 1) {
        // Fire the per-plane HBL once per scanline (raster palette effects).
        if (hid != 0) hblDispatch(hid, @intCast(fb_id), @intCast(y), @intCast(hpos));
        const row = y * PWu;
        var x: usize = 0;
        while (x < PWu) : (x += 1) out[row + x] = palette[buf[row + x]];
    }
}

pub fn renderPlane(fb_id: usize) void {
    if (fbStride(fb_id) == memmap.STRIDE_FULLSCREEN) {
        renderPlaneFullscreen(fb_id);
        return;
    }
    if (r8(memmap.REG_RESOLUTION) != memmap.RES_PLANES) return;

    const palfb = lfb(fb_id);
    const palette = pal(fb_id);
    const out = pfb();
    const hid = fbHblId(fb_id);
    const hpos = fbHblPos(fb_id);

    var fb_index: u32 = 0;
    var vertical_border_opened: bool = false;
    var horizontal_border_opened: bool = false;

    var y: usize = 0;
    while (y < PHu) : (y += 1) {
        const row = y * PWu;
        switch (y) {
            0...(VB - 1) => {
                var x: usize = 0;
                while (x < PWu) : (x += 1) {
                    if (hid != 0 and x == hpos) hblDispatch(hid, @intCast(fb_id), @intCast(y), @intCast(x));

                    if (y == 0 and x >= HB and isTruecolor() and !vertical_border_opened) {
                        vertical_border_opened = true;
                        setPlanes();
                    }
                    if ((x == 0 or x == (memmap.WIDTH + HB)) and isTruecolor()) {
                        if (vertical_border_opened) horizontal_border_opened = true;
                        setPlanes();
                    }

                    if (vertical_border_opened) {
                        switch (x) {
                            0...(HB - 1) => {
                                if (horizontal_border_opened) {
                                    out[row + x] = palette[palfb[fb_index]];
                                    fb_index += 1;
                                    if (x == HB - 1) fb_index -= @intCast(HB);
                                }
                            },
                            HB...(PWu - HB - 1) => {
                                if (x == HB) {
                                    setPlanes();
                                    horizontal_border_opened = false;
                                }
                                out[row + x] = palette[palfb[fb_index]];
                                fb_index += 1;
                            },
                            (PWu - HB)...(PWu - 1) => {
                                if (horizontal_border_opened) {
                                    if (x == PWu - HB) fb_index -= @intCast(HB);
                                    out[row + x] = palette[palfb[fb_index]];
                                    fb_index += 1;
                                    if (x == PWu - 1) horizontal_border_opened = false;
                                }
                            },
                            else => {},
                        }
                    }
                }
            },
            VB...(PHu - VB - 1) => {
                if (y == VB) {
                    vertical_border_opened = false;
                    fb_index = 0;
                }
                var x: usize = 0;
                while (x < PWu) : (x += 1) {
                    if (hid != 0 and x == hpos) hblDispatch(hid, @intCast(fb_id), @intCast(y), @intCast(x));

                    if ((x == 0 or x == (memmap.WIDTH + HB)) and isTruecolor()) {
                        horizontal_border_opened = true;
                        setPlanes();
                    }

                    switch (x) {
                        0...(HB - 1) => {
                            if (horizontal_border_opened) {
                                out[row + x] = palette[palfb[fb_index]];
                                fb_index += 1;
                                if (x == HB - 1) {
                                    fb_index -= @intCast(HB);
                                    setPlanes();
                                    horizontal_border_opened = false;
                                }
                            }
                        },
                        HB...(PWu - HB - 1) => {
                            out[row + x] = palette[palfb[fb_index]];
                            fb_index += 1;
                        },
                        (PWu - HB)...(PWu - 1) => {
                            if (horizontal_border_opened) {
                                if (x == PWu - HB) fb_index -= @intCast(HB);
                                out[row + x] = palette[palfb[fb_index]];
                                fb_index += 1;
                                if (x == PWu - 1) {
                                    horizontal_border_opened = false;
                                    setPlanes();
                                }
                            }
                        },
                        else => {},
                    }
                }
            },
            (PHu - VB)...(PHu - 1) => {
                var x: usize = 0;
                while (x < PWu) : (x += 1) {
                    if (hid != 0 and x == hpos) hblDispatch(hid, @intCast(fb_id), @intCast(y), @intCast(x));

                    if (y == (PHu - VB) and x >= HB and isTruecolor() and !vertical_border_opened) {
                        fb_index -= @intCast(VB * memmap.WIDTH);
                        vertical_border_opened = true;
                        setPlanes();
                    }

                    if (vertical_border_opened) {
                        if ((x == 0 or x == (memmap.WIDTH + HB)) and isTruecolor()) {
                            horizontal_border_opened = true;
                            setPlanes();
                        }
                        switch (x) {
                            0...(HB - 1) => {
                                if (horizontal_border_opened) {
                                    out[row + x] = palette[palfb[fb_index]];
                                    fb_index += 1;
                                    if (x == HB - 1) {
                                        fb_index -= @intCast(HB);
                                        setPlanes();
                                        horizontal_border_opened = false;
                                    }
                                }
                            },
                            HB...(PWu - HB - 1) => {
                                out[row + x] = palette[palfb[fb_index]];
                                fb_index += 1;
                            },
                            (PWu - HB)...(PWu - 1) => {
                                if (horizontal_border_opened) {
                                    if (x == PWu - HB) fb_index -= @intCast(HB);
                                    out[row + x] = palette[palfb[fb_index]];
                                    fb_index += 1;
                                    if (x == PWu - 1) {
                                        horizontal_border_opened = false;
                                        setPlanes();
                                    }
                                }
                            },
                            else => {},
                        }
                    }

                    if (y == PHu - 1) {
                        setPlanes();
                        vertical_border_opened = false;
                        horizontal_border_opened = false;
                    }
                }
            },
            else => {},
        }
    }
}
