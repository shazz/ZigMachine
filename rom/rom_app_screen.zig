// --------------------------------------------------------------------------
// GEM 5's program API, Setscreen (system table 1.25; the app half is rom.aes.setscreen):
// a program switches its screen through the ROM instead of reprogramming its plane
// itself (GEMTEST's "not in the API yet: Setscreen for a program"). As XBIOS
// Setscreen(log, phys, rez) took the screen's address, the desk mode takes the
// program's 640 x 480 buffer (`desk_off`, the plane's VRAM offset, from its own
// allocation): the ROM has no allocator of the program's VRAM. The context is
// re-bound to the new mode (as guiResize does) and its save-unders dropped.
// --------------------------------------------------------------------------
const hw = @import("hardware");
const main = @import("rom_main.zig");
const app = @import("rom_app.zig");
const BREAK_NOSWITCH: u32 = 1 << 31; // deskSetEngine's mutant (gemtest_screen_check --break switch)

// Low or medium on plane `id`, as LogicalFB.setResLow / setResMedium, through the machine's
// registers (the ROM's own ZigOS has no video base of its own to write through).
fn planes(id: u8, medium: bool) void {
    const regs: [*]volatile u8 = @ptrFromInt(@as(usize, @intCast(hw.hwVideoBase())));
    const stride: u16 = if (medium) 640 else 320;
    regs[hw.REG_FB_STRIDE + @as(usize, id) * 2] = @truncate(stride);
    regs[hw.REG_FB_STRIDE + @as(usize, id) * 2 + 1] = @truncate(stride >> 8);
    regs[hw.REG_FB_MODE + @as(usize, id)] = if (medium) hw.FB_MODE_MEDIUM else hw.FB_MODE_NORMAL;
    regs[hw.REG_RESOLUTION] = if (medium) hw.RES_MEDIUM else hw.RES_PLANES;
}

/// Setscreen: `rez` 0 low (320 x 200), 1 medium (640 x 200), 2 the desk (640 x 480 on the buffer
/// at `desk_off`). The mode set, or 0xFF (nothing changed): a bad handle, an unknown mode, the
/// desk with no buffer, on another plane than 0, or on a machine without the desk mode.
export fn guiSetscreen(h: u32, rez: u32, desk_off: u32) u32 {
    const g = main.guiAt(h) orelse return 0xFF;
    const fb = &main.raw_fbs[h - 1];
    if (@import("rom").gui.proglook.breaks & BREAK_NOSWITCH != 0) return rez; // the mutant: says yes, does nothing
    switch (rez) {
        0, 1 => planes(fb.id, rez == 1), // from the desk too: the plane stays on its buffer (leaveDesk)
        2 => {
            // The desk on the program's buffer, as LogicalFB.setDeskPlane on a buffer it already has
            // (the ROM imports no hwDeskAvailable: a program has a desk buffer only where the
            // machine has the mode, notepad/screen.zig allocPlane).
            if (desk_off == 0 or fb.id != 0) return 0xFF;
            fb.desk_off = desk_off;
            const vbase: usize = @intCast(hw.hwVideoBase());
            @as(*volatile u32, @ptrFromInt(vbase + hw.REG_FB_BASE)).* = desk_off; // bindFb below reads it back
            fb.stride = hw.DESK_WIDTH;
            fb.fb_w = hw.DESK_WIDTH;
            fb.fb_h = hw.DESK_HEIGHT;
            const pal: [*]volatile u32 = @ptrCast(fb.palette);
            for (0..256) |i| pal[i] = pal[i]; // the board shows the palette from a mirror CPU stores fill
            const res: *volatile u8 = @ptrFromInt(vbase + hw.REG_RESOLUTION);
            res.* = hw.RES_DESK;
        },
        else => return 0xFF,
    }
    const w: i32 = if (rez == 0) 320 else 640;
    const sh: i32 = if (rez == 2) 480 else 200;
    _ = main.bindFb(fb, fb.id, sh);
    g.screen = main.screenOf(fb, w, sh);
    app.screenChanged(h - 1);
    return rez;
}
