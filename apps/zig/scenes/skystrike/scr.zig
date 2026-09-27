// --------------------------------------------------------------------------
// STOS's screens and banks, as the game uses them.
//
//   physic   the displayed screen ($F8000 on the ST)
//   back     the sprites' background screen ($F0000): the sprite engine
//            restores from it, `put sprite` stamps into it
//   b5, b6   banks 5 and 6, `reserve as screen`: SKYPIC1 / SKYPIC2, the
//            graphics sheets every screen is built from
// Each is 320x200 palette indices (the ST planes, decoded) and the 16-colour
// palette STOS keeps after the picture (+32000).
//
// The game keeps DATA past the pictures of banks 5 and 6 (`sno9 = start(5) +
// 32033`, `sc9 = start(6) + 32033`) and in the 307-byte work bank 7 (so9,
// ghx9 = so9 + 105, lc9 = ghx9 + 51 -- which OVERLAP: so9 + sx * 4 + a runs
// to so9 + 203; kept as one array, so the overlap is the original's). PEEK
// and POKE take the addresses the BASIC computes: START(n) is n << 16 here.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const assets = @import("assets.zig");

pub const W: usize = 320;
pub const H: usize = 200;
pub const PIX: usize = W * H;

pub const Id = enum(u2) { physic, back, b5, b6 };

pub var pix: [4][]u8 = .{ &.{}, &.{}, &.{}, &.{} };
pub var pal: [4][16]u16 = [_][16]u16{[_]u16{0} ** 16} ** 4;
/// Graphics and text draw here (`logic = back` / `logic = physic`).
pub var logic: Id = .physic;
/// `auto back`: what is drawn on the physical screen goes to back as well.
pub var auto_back: bool = true;

/// The bytes past the pictures of banks 5 and 6 (+32000 on), bank 7.
pub const EXTRA: usize = 1024;
pub var extra5: [EXTRA]u8 = [_]u8{0} ** EXTRA;
pub var extra6: [EXTRA]u8 = [_]u8{0} ** EXTRA;
pub const BANK7_LEN: i32 = 307;
pub var bank7: [512]u8 = [_]u8{0} ** 512;
/// PEEKs and POKEs that fell outside every modelled byte (checked 0).
pub var oob: u32 = 0;

pub fn alloc() void {
    if (pix[0].len != 0) return;
    for (&pix) |*p| p.* = zg.mem.mustAlloc(u8, PIX);
}

pub fn get(id: Id) []u8 {
    return pix[@intFromEnum(id)];
}

pub fn start(bank: i32) i32 {
    return bank << 16;
}

fn cell(addr: i32) ?*u8 {
    const bank = addr >> 16;
    const off = addr & 0xFFFF;
    switch (bank) {
        5, 6 => if (off >= 32000 and off < 32000 + EXTRA) {
            const e = if (bank == 5) &extra5 else &extra6;
            return &e[@intCast(off - 32000)];
        },
        7 => if (off < bank7.len) return &bank7[@intCast(off)],
        else => {},
    }
    return null;
}

pub fn peek(addr: i32) i32 {
    if (addr >> 16 == 8) {
        const off: usize = @intCast(addr & 0xFFFF);
        if (off < assets.SCREENS.len) return assets.SCREENS[off];
    }
    const c = cell(addr) orelse {
        oob += 1;
        return 0;
    };
    return c.*;
}

pub fn poke(addr: i32, v: i32) void {
    const c = cell(addr) orelse {
        oob += 1;
        return;
    };
    c.* = @truncate(@as(u32, @bitCast(v)));
}

/// `fill a to b, 0` (only ever zeros, long-aligned stretches).
pub fn fillZero(a: i32, b: i32) void {
    var p = a;
    while (p < b) : (p += 1) poke(p, 0);
}

pub fn reset() void {
    @memset(&extra5, 0);
    @memset(&extra6, 0);
    @memset(&bank7, 0);
    oob = 0;
    logic = .physic;
    auto_back = true;
}
