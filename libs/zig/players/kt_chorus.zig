// --------------------------------------------------------------------------
// cyd's chorus (cydchr.c) with the klystrack cart's integer delay curve
// (apps/ports/klystrack/kestrel_chorus.c): the same entries as the cart's LUT,
// +-1/256 sample of upstream's double sin(), but computed when read instead of
// held. Upstream's LUT is 4 s of Sint32 per bus (353 KB at 22.05 kHz, two
// buses in DPINTRO): each read here steps that entry's phase, q = i * 2^32 / n
// (quotient and remainder, as kestrel_chorus_lut steps it), and evaluates the
// curve: a sine table read, a lerp and one 32x32->64 multiply.
// Quirks kept: the line is fed the RIGHT input only (in_l is used only when
// the rate is 0), and a rate of 0 reads a delay that is not scaled by 256.
// --------------------------------------------------------------------------
const gen = @import("kt_tables_gen.zig");

pub const ACCURACY = 256; // CHORUS_ACCURACY
pub const SIZE_MS = 50; // CYDCHR_SIZE

/// One read position into the curve: its index and its phase i * 2^32 / n.
const Pos = struct { i: u32 = 0, q: u32 = 0, r: u32 = 0 };

pub const Chorus = struct {
    line: []i32 = &.{}, // 2 x buf_size: each input written twice
    buf_size: u32 = 0,
    pos_buf: u32 = 0,
    n: u32 = 0, // lut_size
    pos_l: Pos = .{},
    pos_r: Pos = .{},
    q_step: u32 = 0,
    r_step: u32 = 0,
    k: u64 = 0, // 256 * rate / 10000, Q12 (kestrel_chorus_lut's K)
    span: i32 = 0,
    min_delay: i32 = 0,
    max_delay: i32 = 0,
    rate0_delay: i32 = 0, // the delay a rate of 0 reads
};

/// cydchr_set (and cydchr_init's buffer size): `line` holds 2 * rate * 50 ms.
pub fn set(ch: *Chorus, rate: u32, chr_rate: u8, min_delay: u8, max_delay: u8, sep: u8) void {
    ch.buf_size = rate * SIZE_MS / 1000;
    if (chr_rate == 0) {
        ch.n = 0;
        ch.pos_l = .{};
        ch.pos_r = .{};
        ch.rate0_delay = @intCast(rate * min_delay / 10000);
        return;
    }
    ch.n = rate * 4 * 10 / (10 + (@as(u32, chr_rate) - 1));
    ch.pos_l = .{};
    ch.pos_r = at(ch.n, (@as(u32, sep) * ch.n / 2 / 64) % ch.n);
    ch.min_delay = min_delay;
    ch.max_delay = max_delay;
    ch.span = @as(i32, max_delay) - @as(i32, min_delay);
    const turn: u64 = 1 << 32;
    ch.q_step = @intCast(turn / ch.n);
    ch.r_step = @intCast(turn % ch.n);
    ch.k = ((@as(u64, 256) * rate) << 32) / (@as(u64, 10000) << 20);
}

/// The phase of entry `i` of an `n`-entry curve, as kestrel_chorus_lut reaches it.
fn at(n: u32, i: u32) Pos {
    const t: u64 = @as(u64, i) << 32;
    return .{ .i = i, .q = @truncate(t / n), .r = @intCast(t % n) };
}

fn step(ch: *const Chorus, p: *Pos) void {
    p.i += 1;
    if (p.i >= ch.n) {
        p.* = .{};
        return;
    }
    p.q +%= ch.q_step;
    p.r += ch.r_step;
    if (p.r >= ch.n) {
        p.r -= ch.n;
        p.q +%= 1;
    }
}

/// kestrel_chorus_lut's entry at phase q.
fn curve(ch: *const Chorus, q: u32) i32 {
    const idx = q >> 22;
    const frac: i32 = @intCast((q >> 6) & 0xFFFF);
    const a = gen.sine_q30[idx];
    const b = gen.sine_q30[idx + 1];
    const s = a +% (((b -% a) >> 8) *% frac >> 8);
    const half: i32 = @intCast((@as(u32, @bitCast(s)) +% (1 << 30)) >> 11);
    const num: u32 = @bitCast(half *% ch.span +% (ch.min_delay << 20));
    const v: i32 = @bitCast(@as(u32, @truncate((@as(u64, num) * ch.k) >> 32)));
    const wrap: i32 = @intCast(ch.buf_size * ACCURACY);
    return if (v < wrap) v else if (wrap > 0) @rem(v, wrap) else v;
}

fn tap(ch: *const Chorus, d: i32) i32 {
    const base: i32 = @as(i32, @intCast(ch.pos_buf + ch.buf_size)) - @divTrunc(d, ACCURACY);
    const a = ch.line[@intCast(base)];
    const b = ch.line[@intCast(base - 1)];
    return a + @divTrunc((b - a) * @rem(d, ACCURACY), ACCURACY);
}

pub fn output(ch: *Chorus, in_l: i32, in_r: i32, out_l: *i32, out_r: *i32) void {
    ch.pos_buf += 1;
    if (ch.pos_buf >= ch.buf_size) ch.pos_buf = 0;
    ch.line[ch.pos_buf] = in_r;
    ch.line[ch.pos_buf + ch.buf_size] = in_r;
    if (ch.n == 0) { // lut_size 0: pos_l, pos_r stay 0, lut[0] is the unscaled delay
        out_l.* = in_l;
        out_r.* = tap(ch, ch.rate0_delay);
        return;
    }
    step(ch, &ch.pos_l);
    step(ch, &ch.pos_r);
    out_l.* = tap(ch, curve(ch, ch.pos_l.q));
    out_r.* = tap(ch, curve(ch, ch.pos_r.q));
}
