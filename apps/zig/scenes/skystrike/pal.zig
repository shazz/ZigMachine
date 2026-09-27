// --------------------------------------------------------------------------
// The 16 colour registers and the two VBL palette effects of the STOS
// system VBL ($3D18E):
//
//   FADE speed [TO screen | ,c0,c1,...]   every `speed` VBLs each colour
//        still fading moves each of its R, G, B one step toward its target
//        (ST 3-bit guns), and drops out once equal. No target = black;
//        TO s = screen s's palette; a list sets the first colours only.
//   FLASH c,"(rgb,t)(rgb,t)..."   colour c cycles through the list, each
//        entry held t VBLs; FLASH OFF stops it.
// --------------------------------------------------------------------------
const scr = @import("scr.zig");

pub var hw: [16]u16 = [_]u16{0} ** 16;

var target: [16]u16 = [_]u16{0} ** 16;
var fading: u16 = 0;
var speed: u16 = 1;
var count: u16 = 0;

const MAXF = 8;
var flash_c: i32 = -1;
var flash_rgb: [MAXF]u16 = undefined;
var flash_t: [MAXF]u16 = undefined;
var flash_n: usize = 0;
var flash_i: usize = 0;
var flash_left: u16 = 0;

pub fn reset() void {
    hw = [_]u16{0} ** 16;
    fading = 0;
    flash_c = -1;
}

fn begin(s: i32) void {
    speed = @intCast(@max(1, s));
    count = speed;
    fading = 0xFFFF;
}

/// FADE s: to black.
pub fn fadeBlack(s: i32) void {
    target = [_]u16{0} ** 16;
    begin(s);
}

/// FADE s TO screen.
pub fn fadeTo(s: i32, id: scr.Id) void {
    target = scr.pal[@intFromEnum(id)];
    begin(s);
}

/// FADE s,c0,c1,...: the listed colours, the rest where they are.
pub fn fadeList(s: i32, cols: []const u16) void {
    target = hw;
    for (cols, 0..) |c, i| target[i] = c & 0x777;
    begin(s);
}

fn step(cur: u16, to: u16) u16 {
    var out: u16 = 0;
    inline for (.{ 8, 4, 0 }) |sh| {
        const a = cur >> sh & 7;
        const b = to >> sh & 7;
        const v = if (a < b) a + 1 else if (a > b) a - 1 else a;
        out |= v << sh;
    }
    return out;
}

pub fn flash(c: i32, rgb: []const u16, t: []const u16) void {
    flash_c = c;
    flash_n = @min(rgb.len, MAXF);
    for (0..flash_n) |i| {
        flash_rgb[i] = rgb[i];
        flash_t[i] = t[i];
    }
    flash_i = 0;
    flash_left = 1;
}

pub fn flashOff() void {
    flash_c = -1;
}

/// One VBL of both effects.
pub fn vbl() void {
    if (fading != 0) {
        count -= 1;
        if (count == 0) {
            count = speed;
            for (0..16) |i| {
                const bit = @as(u16, 1) << @intCast(i);
                if (fading & bit == 0) continue;
                if (hw[i] & 0x777 == target[i]) fading &= ~bit else hw[i] = step(hw[i] & 0x777, target[i]);
            }
        }
    }
    if (flash_c >= 0 and flash_n > 0) {
        flash_left -= 1;
        if (flash_left == 0) {
            hw[@intCast(flash_c)] = flash_rgb[flash_i];
            flash_left = @max(1, flash_t[flash_i]);
            flash_i = (flash_i + 1) % flash_n;
        }
    }
}
