// --------------------------------------------------------------------------
// The ST this intro runs on: two 32000-byte low-res screens in the ST's own
// planar layout (16-pixel groups of four interleaved plane words), the video
// base register, the sixteen colour registers, and the shared per-line list at
// $6BDE4 every effect writes its rows into.
//
// Every effect writes the exact bytes the 68000 wrote — one plane of the
// wobble, plane 0 of the curtain, planes 1-2 of the typer — so the trail, the
// band and the text colours come out of the planes as they did on the ST.
// present() is the Shifter: it turns the screen the base register points at
// into the plane's palette indices, once a frame.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const A = @import("assets.zig");

pub const BYTES: usize = 32000;
pub const LINE: usize = 160; // bytes a line: 20 groups x 4 planes x 2 bytes
pub const LINES: usize = 200;
/// The right strip, px 128..319: every effect but PO·RNO lives here.
pub const STRIP: usize = 0x40;
pub const STRIP_BYTES: usize = LINE - STRIP; // 96: 12 groups

/// scrA/scrB ($078A/$078E, live $22B00/$2AB00). Module scope: 64 KB is the
/// cart's, and does not belong in the Demo struct.
pub var screens: [2][BYTES]u8 = undefined;

pub const Machine = struct {
    f: u16, // $2542, the frame word
    c: u32, // $2546, the part counter; the VBL bumps both
    scr_a: u1, // which of screens[] the long at $078A points at
    base: u1, // the video base register $FF8201/03
    palette: A.Palette, // what movem.l last put into $FF8240
    /// $6BDE4 as the wobble, curtain and distorter use it: 200 words. It is
    /// SHARED, which is why the first curtain frame after a wobble or a
    /// distorter reads a stale list (curtain.zig).
    list: [LINES]u16,
    typed: u16, // $254A, the typer's character counter

    pub fn init(self: *Machine) void {
        self.f = 0;
        self.c = 0;
        self.scr_a = 0;
        self.base = 0;
        self.palette = .porno;
        @memset(&self.list, 0);
        self.typed = 0;
    }

    pub fn scrA(self: *const Machine) *[BYTES]u8 {
        return &screens[self.scr_a];
    }

    /// $036E: base := scrA, then swap scrA and scrB. The caller draws into the
    /// new scrB — which is the buffer just made the base, latched at the next
    /// VBL, so it is never on screen while it is drawn.
    pub fn flip(self: *Machine) *[BYTES]u8 {
        self.base = self.scr_a;
        self.scr_a ^= 1;
        return &screens[self.base];
    }
};

/// Main's fill ($002A and $0316): both screens to $FF, colour 15 everywhere.
pub fn fillBoth() void {
    for (&screens) |*s| @memset(s, 0xFF);
}

/// Part 2's copy ($007A): the converted eye picture, whole, into both screens.
pub fn copyPic1() void {
    for (&screens) |*s| @memcpy(s, A.pic1);
}

/// $0452: the strip on scrA to colour 7 — planes 0, 1, 2 set, plane 3 clear.
pub fn stripFill(scr: *[BYTES]u8) void {
    const group = [8]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0 };
    for (0..LINES) |y| {
        const row = scr[y * LINE + STRIP ..][0..STRIP_BYTES];
        for (0..STRIP_BYTES / 8) |g| row[g * 8 ..][0..8].* = group;
    }
}

// --------------------------------------------------------------------------
// The Shifter.
// --------------------------------------------------------------------------

/// One plane byte -> eight pixels, one byte lane each, MSB = leftmost pixel.
/// Shifting the result left by p puts the bit at plane p's weight.
const SPREAD: [256]u64 = blk: {
    @setEvalBranchQuota(4000);
    var t: [256]u64 = undefined;
    for (0..256) |b| {
        var v: u64 = 0;
        for (0..8) |k| v |= @as(u64, (b >> (7 - k)) & 1) << (8 * k);
        t[b] = v;
    }
    break :blk t;
};

/// The screen at the base register, as the plane's 320x200 palette indices.
pub fn present(m: *const Machine, fb: *zg.LogicalFB) void {
    for (0..16) |i| fb.palette[i] = stColor(A.paletteWord(m.palette, i));
    const scr = &screens[m.base];
    const pixels = fb.fb[0 .. @as(usize, fb.stride) * LINES];
    for (0..LINES) |y| {
        const src = scr[y * LINE ..][0..LINE];
        const dst = pixels[y * fb.stride ..][0..zg.WIDTH];
        // Two passes of 8 pixels per group: the high bytes, then the low.
        for (0..LINE / 4) |h| {
            const g = (h >> 1) * 8 + (h & 1);
            const v = SPREAD[src[g]] | SPREAD[src[g + 2]] << 1 |
                SPREAD[src[g + 4]] << 2 | SPREAD[src[g + 6]] << 3;
            std.mem.writeInt(u64, dst[h * 8 ..][0..8], v, .little);
        }
    }
}

/// An ST colour register ($0RGB, three bits a gun) as the machine's RGBA.
pub fn stColor(word: u16) u32 {
    const r: u32 = gun(word >> 8);
    const g: u32 = gun(word >> 4);
    const b: u32 = gun(word);
    return (0xFF << 24) | (b << 16) | (g << 8) | r;
}

fn gun(nibble: u16) u32 {
    return @as(u32, nibble & 7) * 255 / 7;
}
