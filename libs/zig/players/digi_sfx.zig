// --------------------------------------------------------------------------
// Two games' sampled sound effects, natively: North & South's (north_south_digi
// .sndh, 47 effects) and Rick Dangerous's (rick_dangerous.sndh, 87 subtunes).
// While an effect sounds, a Timer A interrupt plays one byte of it a tick, at
// 5-17 kHz: up to ~240 % of BARD on Musashi for the effect's length. Both stop
// at a 0 byte. Rick's init copies its handler elsewhere, so, as for maxYMiser
// (digi_mym.zig), each address an interrupt arrives at is matched once per INIT.
//
//   North & South, $08  movea.l #P,a0 / clr.w d0 / move.b (a0)+,d0 / beq end
//        $14  P stored back into the movea's operand; lsl.w #3; move.l and
//        move.w from table(pc,d0.w) ($5C, $60): movep.l + movep.w onto $8800;
//        bclr #5,$720F(a0) (ISRA). end ($40): TACR = 0, a flag byte (sf), ISRA
//   Rick, $04  lea S(pc): the pointer; move.b (a0)+,d0 / beq end; stored;
//        d0 x4 into S+4: three move.l (+0, +$400, +$800) onto $8800; ISRA.
//        end ($38): tst.b F.l / bne: the pointer back to the loop (move.l A.l,
//        S); else TACR = 0, G.l = 0; ISRA
// At the 0 byte the pointer is left where it was: the byte is never played.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");

const Form = enum { ns, rick };
const NS_LEN: u32 = 0x5C;
const RICK_LEN: u32 = 0x74;
const NS_HOLES = [_][2]u32{.{ 0x0A, 0x0E }};
const RICK_HOLES = [_][2]u32{ .{ 0x3A, 0x3E }, .{ 0x4A, 0x4E }, .{ 0x5E, 0x66 } };
const NS_SIGNATURE: u64 = 0x47901CA00858C415; // digi.maskedHash, P zeroed
const RICK_SIGNATURE: u64 = 0x662ED3540F00BB73; // ... F, G, A and S zeroed
const PSG: u32 = 0xFF8800;
const TACR: u32 = 0xFFFA19;
const ISRA: u32 = 0xFFFA0F;
pub const STEP = [0]u32{};

const Seen = struct { addr: u32 = 0, form: ?Form = null };

pub const Driver = struct {
    addr: u32, // the first routine found in the image (the status's)
    seen: [4]Seen = [_]Seen{.{}} ** 4,
    n: u32 = 0,
};

fn formAt(image: []const u8, off: usize) ?Form {
    if (off + NS_LEN <= image.len and digi.be32(image, off) == 0x3F002F01 and
        digi.maskedHash(image[off..][0..NS_LEN], &NS_HOLES) == NS_SIGNATURE) return .ns;
    if (off + RICK_LEN <= image.len and digi.be32(image, off) == 0x48E780C0 and
        digi.maskedHash(image[off..][0..RICK_LEN], &RICK_HOLES) == RICK_SIGNATURE) return .rick;
    return null;
}

pub fn match(image: []const u8, base: u32) ?Driver {
    var off: usize = 0;
    while (off + NS_LEN <= image.len) : (off += 2) {
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
    var code: [RICK_LEN]u8 = undefined;
    for (&code, 0..) |*b, i| b.* = digi.Access(Bus).rd8(h + @as(u32, @intCast(i)));
    const f = formAt(&code, 0);
    if (d.n < d.seen.len) {
        d.seen[d.n] = .{ .addr = h, .form = f };
        d.n += 1;
    }
    return f;
}

pub fn irq(comptime Bus: type, d: *Driver, h: u32) bool {
    const form = lookup(Bus, d, h) orelse return false;
    if (form == .ns) ns(Bus, h) else rick(Bus, h);
    return true;
}

fn ns(comptime Bus: type, h: u32) void {
    const m = digi.Access(Bus);
    const p = m.rd32(h + 0x0A);
    const s = m.rd8(p);
    if (s == 0) {
        if (digi.irq.sfx_end_stores) m.wr32(h + 0x0A, p +% 1);
        m.wr8(TACR, 0);
        m.wr8(digi.pcRel(h + 0x46, m.rd16(h + 0x48)), 0); // sf.b (a1)
        m.bclr(ISRA, 5);
        return;
    }
    m.wr32(h + 0x0A, p +% 1);
    const i = @as(u32, s) * 8;
    const hi = m.rd32(h + 0x5C + i);
    const lo = m.rd16(h + 0x60 + i);
    for (0..4) |k| m.wr8(PSG + 2 * @as(u32, @intCast(k)), @truncate(hi >> @intCast(24 - 8 * k)));
    m.wr8(PSG, @truncate(lo >> 8));
    m.wr8(PSG + 2, @truncate(lo));
    m.bclr(ISRA, 5);
}

fn rick(comptime Bus: type, h: u32) void {
    const m = digi.Access(Bus);
    const sp = digi.pcRel(h + 0x04, m.rd16(h + 0x06));
    const p = m.rd32(sp);
    const s = m.rd8(p);
    if (s == 0) {
        if (digi.irq.sfx_end_stores) m.wr32(sp, p +% 1);
        if (m.rd8(m.rd32(h + 0x3A)) != 0) {
            m.wr32(m.rd32(h + 0x62), m.rd32(m.rd32(h + 0x5E)));
        } else {
            m.wr8(TACR, 0);
            m.wr8(m.rd32(h + 0x4A), 0);
        }
        m.bclr(ISRA, 5);
        return;
    }
    m.wr32(sp, p +% 1);
    const e = sp + 4 + @as(u32, s) * 4;
    for ([_]u32{ 0, 0x400, 0x800 }) |k| m.wr32(PSG, m.rd32(e + k));
    m.bclr(ISRA, 5);
}
