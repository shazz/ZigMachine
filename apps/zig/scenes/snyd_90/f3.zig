// --------------------------------------------------------------------------
// F3 -- "the funny curve editor" (part 3: track 60 side 0, ByteKiller-packed,
// to $18000): 32 red balls on a curve of six byte sines over a starfield and
// a water picture they are reflected in, and a panel of the curve's twelve
// parameters to edit live. The music is David Whittaker's Platoon (the
// replay at $1CA66, init d0 = 4, played from the last Timer B of a frame),
// wrapped as snyd90_f3.sndh.
//
// Its set-up ($18000..$180FA: screens, the water picture at line 140, the
// star tables at $30000, sine tables at $40000/$50000/$6F000, the ball's 16
// preshifts and masks, the panel's labels) ran once on the original code
// (the Musashi oracle); the memory it leaves is this part's asset. From there
// every VBL is ported, on that memory ($14000..$80000):
//   VBL    $1888E: palette $1CA44, flip $60000 / $70000 (shown next VBL),
//          erase that screen's balls (f3_draw.zig); a lightning flash of
//          colours 8 and 12 for 6 frames in every 1000 ($1CA64).
//   body   stars, the balls (f3_draw.zig), then f3_panel.zig: every 5th frame
//          the keys, the other frames one parameter's value redrawn.
//   rasters (rasters()): the Timer B chain -- colours 8/12 from line 39, the
//          horizon (colour 0 = 1, 2, 3) from line 139, the water's colours
//          from line 188, and at line 199 ($18776) the bottom border opened:
//          the screen runs on below the window (shifter.zig: a real flicker).
// Best effort, not byte for byte: the Timer B races (where exactly in a line
// a register changes) are rounded to whole lines.
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const draw = @import("f3_draw.zig");
const panel = @import("f3_panel.zig");

pub const BASE: u32 = 0x14000;
pub const TOP: u32 = 0x80000;
pub const PALETTE: u32 = 0x1CA44;
/// ST lines it shows: the bottom border is open down to the frame's end.
pub const LINES: usize = 240;
/// $18776, at the end of line 198: the 60 Hz switch -- no bottom border.
pub const OPEN_FROM: usize = 199;

const FLIP: u32 = 0x1AA9A;
const FLASH: u32 = 0x1CA64;
const STAR_SAVED: u32 = 0x19162;
const SAVED: u32 = 0x1AAAA;

/// A fresh start: no key waiting. (The ST reads the keyboard's last byte:
/// the F3 that started the part, released during the load, reads $BD, which
/// the panel ignores. Hold F3 through the load -- as a Hatari key script
/// does -- and $3D stays: preset 3 is reloaded every 5th frame, a 5-frame
/// loop.)
pub fn enter() void {
    panel.reset();
}

/// A host key as the ST scancode the panel reads ($FFFC02); 0 if none.
pub fn key(cp: u32) void {
    const scan: u8 = switch (cp) {
        0xE001...0xE00A => @intCast(cp - 0xE001 + 0x3B), // F1..F10
        '1'...'9' => @intCast(cp - '1' + 2),
        '0' => 0x0B,
        0xF000 => 0x48, // up
        0xF001 => 0x50, // down
        0xF002 => 0x4B, // left
        0xF003 => 0x4D, // right
        0xE00B => 0x52, // Insert: -1
        0xE00C => 0x47, // Delete stands for Home (no Home key on the host): +1
        0xE011 => 0x62, // Help: -8
        0xE010 => 0x61, // Undo: +8
        else => letter(cp),
    };
    if (scan != 0) panel.press(scan);
}

/// The preset keys of the letter rows (w, a, s, d are the host's arrows).
fn letter(cp: u32) u8 {
    const rows = [_]struct { keys: []const u8, first: u8 }{
        .{ .keys = "q\x00ertyuiop[]", .first = 0x10 },
        .{ .keys = "\x00\x00\x00fghjkl;'", .first = 0x1E },
    };
    for (rows) |row| for (row.keys, 0..) |c, i| {
        if (c != 0 and c == cp) return row.first + @as(u8, @intCast(i));
    };
    return 0;
}

/// One VBL: the handler, then (unless it was the panel's redraw-all VBL) the
/// main loop's pass. Returns the screen drawn: the one shown next.
pub fn vbl(r: *const st.Ram) u32 {
    if (panel.redrawAll(r)) {
        _ = flip(r);
        draw.stars(r);
        return r.l(draw.DRAW);
    }
    r.sw(FLASH, r.w(FLASH) -% 1);
    if (r.w(FLASH) == 0) r.sw(FLASH, 1000);
    draw.erase(r, flip(r));
    draw.stars(r);
    draw.balls(r);
    panel.tick(r);
    return r.l(draw.DRAW);
}

/// $188EA: the other screen becomes the one drawn; its lists with it.
fn flip(r: *const st.Ram) u32 {
    const v = ~r.w(FLIP);
    r.sw(FLIP, v);
    const b = v != 0;
    r.sl(draw.DRAW, if (b) 0x70000 else 0x60000);
    r.sl(STAR_SAVED, if (b) 0x14000 else 0x15000);
    const list: u32 = if (b) 0x1B2CA else 0x1B1B2;
    r.sl(SAVED, list);
    return list;
}

/// The colour registers on each ST line 0..LINES-1, as the VBL and the
/// Timer B chain ($18626 / $18654, $18682.., $186FA) leave them.
pub fn rasters(r: *const st.Ram, out: *[LINES][16]u16) void {
    var pal: [16]u16 = undefined;
    for (&pal, 0..) |*c, i| c.* = r.w(PALETTE + 2 * @as(u32, @intCast(i)));
    const flash = r.w(FLASH) <= 6;
    for (out, 0..) |*line, y| {
        switch (y) {
            39 => {
                pal[8] = if (flash) 0x777 else 0;
                pal[12] = if (flash) 0x777 else 0x333;
            },
            139 => pal[0] = 1,
            140 => pal[0] = 2,
            141 => {
                pal[0] = 3;
                pal[4] = 2;
                pal[8] = 5;
                pal[12] = 0x27;
            },
            188 => pal[1..16].* = .{ 3, 1, 1, 2, 2, 1, 1, 4, 5, 1, 1, 6, 0x27, 1, 1 },
            else => {},
        }
        line.* = pal;
    }
}
