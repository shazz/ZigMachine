// --------------------------------------------------------------------------
// TCB #1's set-up ($E192: $DFA2, $DA34 + $DAB0, $E13C). The noise is not
// random at run time: $DFA2 fills $70000.. ONCE from a fixed generator, and the
// screen only ever shows that buffer from 16 shuffled bases. The TCB logo
// (64x18, $DAF0) is preshifted 4..15 pixels right into 12 blocks at $49DCC,
// and every pixel the logo leaves empty is filled with the noise under it, so
// the logo's box is noise too. Checked against Hatari: init plus 75 VBLs is the
// intro dump, byte for byte (tcb1_test.zig).
// --------------------------------------------------------------------------
const st = @import("st.zig");
const T = @import("tcb1.zig");

const Ram = st.Ram;

const LOGO: u32 = 0xDAF0; // 4 groups x 4 plane words, 18 lines
const NOISE_SEED: u32 = 0x7583_1639;
const NOISE_CLEAR: usize = (0x3A98 + 1) * 4;
const NOISE_WORDS = 0x7530 + 1;
const STREAM_LOOP: u32 = 0x32AD0; // where the music part of the stream loops from
const STREAM_END: u32 = 0x41234; // and 4004 bytes of it copied after its end

pub fn init(r: *const Ram) void {
    noise(r);
    preshift(r);
    mergeNoise(r);
    r.cp(STREAM_END, STREAM_LOOP, 1001 * 4); // $E13C: the replay reads past the end
}

/// $DFA2: eor.l a long over every WORD step (the longs overlap).
fn noise(r: *const Ram) void {
    r.zero(T.NOISE, NOISE_CLEAR);
    r.sl(T.SHOWN, T.NOISE);
    r.sl(T.LAST_DRAW, T.NOISE + 0x7D0);
    var d1: u32 = NOISE_SEED;
    var a: u32 = T.NOISE;
    for (0..NOISE_WORDS) |_| {
        r.sl(a, r.l(a) ^ d1);
        a += 2;
        d1 = d1 +% 0x7492_8123;
        d1 ^= 0x5234_5679;
        d1 = (d1 << 3) | (d1 >> 29);
    }
}

/// $DA34: shift s = 4..15 (block 0 = 4), each plane's spill carried into the
/// next group; a fifth group takes the last spills. 40 bytes a line.
fn preshift(r: *const Ram) void {
    var dst: u32 = T.PRESHIFTS;
    for (4..16) |s| {
        var src: u32 = LOGO;
        for (0..18) |_| {
            var carry = [4]u16{ 0, 0, 0, 0 };
            for (0..4) |_| {
                for (0..4) |p| {
                    const v = @as(u32, r.w(src)) << 16 >> @intCast(s);
                    r.sw(dst, @as(u16, @truncate(v >> 16)) | carry[p]);
                    carry[p] = @truncate(v);
                    src += 2;
                    dst += 2;
                }
            }
            for (carry) |c| {
                r.sw(dst, c);
                dst += 2;
            }
        }
    }
}

/// $DAB0: in every group, the pixels no plane sets take the noise's planes.
fn mergeNoise(r: *const Ram) void {
    var a: u32 = T.PRESHIFTS;
    var n: u32 = T.NOISE;
    for (0..0x438) |_| {
        const empty = ~(r.w(a) | r.w(a + 2) | r.w(a + 4) | r.w(a + 6));
        for (0..4) |_| {
            r.sw(a, r.w(a) | (r.w(n) & empty));
            a += 2;
            n += 2;
        }
    }
}
