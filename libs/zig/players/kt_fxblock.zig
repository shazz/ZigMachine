// --------------------------------------------------------------------------
// An FX bus a block at a time (kt_block.zig): cydfx_output's chorus, reverb
// and crusher over n samples in place, the same values as kt_fx.zig's output
// a sample at a time. The reverb goes tap by tap over the block: the block's
// inputs are written to the line first, then each tap reads its n samples in
// a row with its gains in registers. Exact while no tap reaches back more than
// size - n samples (a tap would read a sample this block wrote over); a bus
// with such a tap runs a sample at a time.
// --------------------------------------------------------------------------
const song = @import("kt_song.zig");
const fx = @import("kt_fx.zig");
const chorus = @import("kt_chorus.zig");

/// The reverb taps all read before this block's writes: blockwise is exact.
fn reverbBlockable(r: *const fx.Reverb, n: usize) bool {
    const size = r.line.len;
    for (r.taps[0..r.n_taps]) |*t| if (t.delay > size - n) return false;
    return true;
}

/// The bus's `n` inputs l[0..n], r[0..n] in, its outputs out, in place.
pub fn output(b: *fx.Bus, l: [*]i32, r: [*]i32, n: usize) void {
    const rv = b.flags & song.FX_REVERB != 0 and b.rvb.line.len != 0;
    if (rv and !reverbBlockable(&b.rvb, n)) {
        for (0..n) |t| fx.output(b, &l[t], &r[t]);
        return;
    }
    if (rv) writeLine(&b.rvb, l, n); // the reverb's input is the bus's left input, before the chorus
    const p0 = b.rvb.position; // the line position of the block's last sample
    if (b.flags & song.FX_CHORUS != 0) for (0..n) |t| {
        const in_l = l[t];
        const in_r = r[t];
        chorus.output(&b.chr, in_l, in_r, &l[t], &r[t]);
    };
    if (rv) taps(&b.rvb, l, r, n, p0);
    if (b.flags & song.FX_CRUSH != 0) for (0..n) |t| fx.crushSample(&b.crush, &l[t], &r[t]);
}

fn writeLine(rv: *fx.Reverb, l: [*]const i32, n: usize) void {
    const line = rv.line.ptr;
    const size: u32 = @intCast(rv.line.len);
    var pos = rv.position;
    for (0..n) |t| {
        pos += 1;
        if (pos >= size) pos = 0;
        line[pos] = l[t];
    }
    rv.position = pos;
}

/// Each tap over the block: sample t was written at p0 - (n - 1 - t), read at that minus the delay.
fn taps(rv: *const fx.Reverb, l: [*]i32, r: [*]i32, n: usize, p0: u32) void {
    const line = rv.line.ptr;
    const size: u32 = @intCast(rv.line.len);
    const back: u32 = @intCast(n - 1);
    for (rv.taps[0..rv.n_taps]) |*tp| {
        const gl = tp.gain_l;
        const gr = tp.gain_r;
        const d = tp.delay + back; // < size: reverbBlockable
        var at = if (p0 >= d) p0 - d else p0 + size - d; // sample 0's read
        for (0..n) |t| {
            const v = line[at];
            const tl = @divTrunc(gl *% v, 2048);
            l[t] +%= tl;
            r[t] +%= if (gr == gl) tl else @divTrunc(gr *% v, 2048);
            at += 1;
            if (at >= size) at = 0;
        }
    }
}
