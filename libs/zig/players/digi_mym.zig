// --------------------------------------------------------------------------
// maxYMiser's digidrum interrupts, natively: crystallized.sndh (the D-Bug and
// music screens). A drum plays one byte a Timer B interrupt at 15,360 Hz (256
// a 60 Hz frame) onto one channel's volume; between drums the timer stops.
// Play switches the vector between two routines as each drum starts, and keeps
// a copy of each per channel, so the handler is not one address: every
// address an interrupt arrives at is matched against the two routines the
// first time (`Seen`), and Musashi keeps any it does not know.
//
//   4-bit (A), $00  move.b #R,$8800.w
//              $06  move.b P.l,$8802.w     P, the sample pointer, is the operand
//              $0E  bmi end / addq.l #1,P'   ... which addq.l bumps in the code
//              $18  end: move.b #E,$8802.w / clr.b T.w (the timer's control) / rte
//   8-bit (B), $04  move.b #R,$8800.w / move.b P.l,d0 / bmi end
//              $12  addi.b #I,d0 / move.b table(pc,d0.w),$8802.w / addq.l #1,P'
//              $26  end: as A; the table is at $34
// R, E, I, P and T are read from the code at every interrupt: play rewrites them.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");

const Form = enum { four, eight };
const A_LEN: u32 = 0x24;
const B_LEN: u32 = 0x34;
const A_HOLES = [_][2]u32{ .{ 0x03, 0x04 }, .{ 0x08, 0x0C }, .{ 0x12, 0x16 }, .{ 0x1B, 0x1C }, .{ 0x20, 0x22 } };
const B_HOLES = [_][2]u32{ .{ 0x07, 0x08 }, .{ 0x0C, 0x10 }, .{ 0x15, 0x16 }, .{ 0x1E, 0x22 }, .{ 0x29, 0x2A }, .{ 0x2E, 0x30 } };
const A_SIGNATURE: u64 = 0x0123A83110E38CDB; // digi.maskedHash of the 4-bit routine, its operands zeroed
const B_SIGNATURE: u64 = 0xC78A97CC13C5DB4B; // ... and of the 8-bit one
const PSG: u32 = 0xFF8800;
pub const STEP = [0]u32{}; // nothing is cached at arming: see `Seen`

/// What an interrupt address was found to be, once per INIT.
const Seen = struct { addr: u32 = 0, form: ?Form = null };

pub const Driver = struct {
    addr: u32, // the first routine found in the image (the status's)
    seen: [8]Seen = [_]Seen{.{}} ** 8,
    n: u32 = 0,
};

fn formAt(image: []const u8, off: usize) ?Form {
    if (off + A_LEN <= image.len and digi.be16(image, off) == 0x11FC and
        digi.maskedHash(image[off..][0..A_LEN], &A_HOLES) == A_SIGNATURE) return .four;
    if (off + B_LEN <= image.len and digi.be32(image, off) == 0x2F007000 and
        digi.maskedHash(image[off..][0..B_LEN], &B_HOLES) == B_SIGNATURE) return .eight;
    return null;
}

pub fn match(image: []const u8, base: u32) ?Driver {
    var off: usize = 0;
    while (off + A_LEN <= image.len) : (off += 2) {
        if (formAt(image, off) != null) return .{ .addr = base + @as(u32, @intCast(off)) };
    }
    return null;
}

/// INIT ran (digi_irq.zig): every address is matched again.
pub fn arm(comptime Bus: type, d: *Driver) bool {
    _ = Bus;
    d.n = 0;
    return true;
}

fn lookup(comptime Bus: type, d: *Driver, h: u32) ?Form {
    for (d.seen[0..d.n]) |s| if (s.addr == h) return s.form;
    var code: [B_LEN]u8 = undefined;
    for (&code, 0..) |*b, i| b.* = digi.Access(Bus).rd8(h + @as(u32, @intCast(i)));
    const f = formAt(&code, 0);
    if (d.n < d.seen.len) {
        d.seen[d.n] = .{ .addr = h, .form = f };
        d.n += 1;
    }
    return f;
}

/// One interrupt to `h`: natively if it is one of the two routines. False: Musashi's.
pub fn irq(comptime Bus: type, d: *Driver, h: u32) bool {
    const form = lookup(Bus, d, h) orelse return false;
    const m = digi.Access(Bus);
    const at: u32 = if (form == .four) 0 else 4; // the eight-bit form starts with two more words
    m.wr8(PSG, m.rd8(h + at + 3));
    const p = m.rd32(h + at + 8);
    const s = m.rd8(p);
    if (form == .four) m.wr8(PSG + 2, s); // written before the test, the end byte too
    if (s & 0x80 != 0) { // the drum's end: the end value, and the timer stopped
        const end = if (form == .four) h + 0x18 else h + 0x26;
        m.wr8(PSG + 2, m.rd8(end + 3));
        const t: u32 = @bitCast(@as(i32, @as(i16, @bitCast(m.rd16(end + 8))))); // clr.b T.w
        m.wr8(t & 0xFFFFFF, 0);
        return true;
    }
    if (form == .eight) {
        const i = s +% if (digi.irq.no_offset) 0 else m.rd8(h + 0x15);
        m.wr8(PSG + 2, m.rd8(h + 0x34 + @as(u32, i)));
    }
    const bump = m.rd32(h + if (form == .four) @as(u32, 0x12) else 0x1E);
    m.wr32(bump, m.rd32(bump) +% 1);
    return true;
}
