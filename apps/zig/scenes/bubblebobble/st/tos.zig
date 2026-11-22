// --------------------------------------------------------------------------
// The TOS calls the game makes, answered here (high-level, as TOS 1.0 would):
//
//   GEMDOS (trap #1)  Super, Dsetdrv, Dsetpath, Fopen / Fread / Fclose of
//                     the GRAPHICS\ files (files[], the disk's own bytes),
//                     Crawio (the name entry's keys), Pterm
//   BIOS   (trap #13) Bconout to the IKBD (joystick event mode): accepted
//   XBIOS  (trap #14) Setscreen (the video base), Kbdvbase (the vector table
//                     the game hooks joyvec into: KBDVECS below)
// Arguments are on the stack (a7) as the 68000 code pushed them; the result
// goes in d0.
// --------------------------------------------------------------------------
const k = @import("cpu.zig");
const io = @import("io.zig");

pub const File = struct { name: []const u8, data: []const u8 };
/// The GRAPHICS folder (set by the host before reset).
pub var files: []const File = &.{};

/// Kbdvbase's table in low RAM: midivec, vkbderr, vmiderr, statvec, mousevec, clockvec, joyvec.
pub const KBDVECS: u32 = 0x0E00;
const MAX_OPEN = 4;
var open_file: [MAX_OPEN]?usize = .{null} ** MAX_OPEN;
var open_pos: [MAX_OPEN]usize = .{0} ** MAX_OPEN;

/// Keys typed for Crawio, ASCII.
var typed: [16]u8 = undefined;
var typed_n: usize = 0;
pub var terminated: bool = false;
pub var unknown: u32 = 0;

pub fn reset() void {
    open_file = .{null} ** MAX_OPEN;
    typed_n = 0;
    terminated = false;
    unknown = 0;
}

pub fn typeKey(ascii: u8) void {
    if (typed_n < typed.len) {
        typed[typed_n] = ascii;
        typed_n += 1;
    }
}

fn arg16(off: u32) u16 {
    return k.rw(k.a[7] +% off);
}
fn arg32(off: u32) u32 {
    return k.rl(k.a[7] +% off);
}
fn ret(v: i32) void {
    k.d[0] = @bitCast(v);
}

pub fn trap(n: u32, next: u32) u32 {
    switch (n) {
        1 => gemdos(),
        13 => ret(0),
        14 => xbios(),
        else => unknown += 1,
    }
    if (terminated) k.limit = k.cy;
    return next;
}

fn gemdos() void {
    switch (arg16(0)) {
        0x00, 0x4C => terminated = true,
        0x06 => ret(crawio()),
        0x0E => ret(0x0003),
        0x20, 0x3B => ret(0),
        0x3E => ret(fclose(arg16(2))),
        0x3D => ret(fopen(arg32(2))),
        0x3F => ret(fread(arg16(2), arg32(4), arg32(8))),
        else => {
            unknown += 1;
            ret(-32);
        },
    }
}

fn crawio() i32 {
    if (typed_n == 0) return 0;
    const c = typed[0];
    for (1..typed_n) |i| typed[i - 1] = typed[i];
    typed_n -= 1;
    return c;
}

fn fopen(name_at: u32) i32 {
    var name: [16]u8 = undefined;
    var len: usize = 0;
    while (len < name.len) : (len += 1) {
        const c = k.rb(name_at + @as(u32, @intCast(len)));
        if (c == 0 or c == ' ') break;
        name[len] = c;
    }
    for (files, 0..) |f, i| {
        if (!std_eql(f.name, name[0..len])) continue;
        for (&open_file, 0..) |*slot, h| if (slot.* == null) {
            slot.* = i;
            open_pos[h] = 0;
            return @intCast(6 + h);
        };
    }
    return -33; // file not found
}

fn fread(handle: u16, count: u32, buf: u32) i32 {
    if (handle < 6 or handle >= 6 + MAX_OPEN) return -37;
    const h = handle - 6;
    const i = open_file[h] orelse return -37;
    const data = files[i].data;
    const n = @min(count, data.len - open_pos[h]);
    for (0..n) |j| k.wb(buf + @as(u32, @intCast(j)), data[open_pos[h] + j]);
    open_pos[h] += n;
    return @intCast(n);
}

fn fclose(handle: u16) i32 {
    if (handle < 6 or handle >= 6 + MAX_OPEN) return -37;
    open_file[handle - 6] = null;
    return 0;
}

fn xbios() void {
    switch (arg16(0)) {
        5 => {
            const phys = arg32(6);
            if (phys != 0xFFFFFFFF) {
                io.vbase_hi = @truncate(phys >> 16);
                io.vbase_mid = @truncate(phys >> 8);
            }
            ret(0);
        },
        0x22 => k.d[0] = KBDVECS,
        else => {
            unknown += 1;
            ret(0);
        },
    }
}

fn std_eql(x: []const u8, y: []const u8) bool {
    if (x.len != y.len) return false;
    for (x, y) |p, q| if (p != q) return false;
    return true;
}
