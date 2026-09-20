// The B.I.G. Demo, KEY 2 — the 512-colour Psych-O-Screen.
//
// A FULL 16-COLOUR PALETTE PER SCANLINE for 150 scanlines, from a table at
// $1BD00 with stride $20, played by the HBL at $18DAE from Timer B = 45. So
// display lines 45..194 each get their own sixteen colours — 2,400 palette
// words a frame — and everything outside them shows the VBL's base palette at
// $18F24. That is the demo boasting about "512 COLOR PSYCH-O-SCREENS" in its
// own scrolltext, and it is why the spheres sit on a rainbow floor that no
// 16-colour bitmap could hold.
//
// WE DO IT THE SAME WAY, with our own per-plane HBL. The bitmap is blitted ONCE
// on entry and never touched again: its pens are the demo's own 0..15, and the
// handler rewrites those sixteen palette entries before every composited line
// (machine/video.zig calls the plane's HBL per row). A 256-colour plane could
// not hold this screen any other way — the aged table alone carries 488
// distinct words, twice what a single palette has room for.
//
// THE TABLE IS GENERATED, NOT SHIPPED, and its generator is seeded from
// HARDWARE ENTROPY: $18F44 mixes the 200 Hz clock at $4BA with the live beam
// position from $FF8206 and a running seed, and burns a variable number of
// cycles from that seed. Two runs of the real demo do not produce the same
// plane. This screen CANNOT be byte-reproduced, and a byte-identity harness
// against a capture would be the wrong test for it. Said plainly here so nobody
// later concludes the port is broken when it fails to match a reference.
//
// WHAT IS REPRODUCED, all read from $18B96 and $18F9A:
//   * the diagonal shift — entry E of line L takes entry E+1 of line L+1, every
//     frame, over the WHOLE 212-row region, so the visible 150 are fed from the
//     rows below them. In a row-major table that is one flat ROTATION of 17
//     words: 200 blocks of $22 = 34 bytes = 17 words covering all 6,800, with
//     the head saved at $18B36 and written back at the far end by $18B98.
//     That is also why the table FILLS rather than drains — it conserves what
//     it holds and the feed adds one cell a frame, so a dump taken two seconds
//     into the screen is 94% empty and one taken 34 seconds in is half full.
//   * the feed — ONE cell, at a fixed place: the word 18 back from the end of
//     the region is copied into a one-word scratch at $19240, stepped by one
//     level in ONE OF THE THREE CHANNELS (big/walk.zig), and written into the
//     LAST word. That is why the plane is a smooth gradient and not noise —
//     every new value is within one level of a value already on it — and why it
//     fills from the BOTTOM: values enter at the end of the region and the
//     diagonal shift carries them up and left.
//   * the four-way roll, one outcome of which re-rolls.
//
// WHAT IS INVENTED, and it is one thing: the PRNG. A hardware-seeded one cannot
// be ported, so this is a plain xorshift. The statistics match; the pixels never
// will.
//
// It was TWO things until Matt looked at the screen. Only the blue stepper had
// been read; the other two roll outcomes were guessed as cursor moves, and with
// one channel walking the rotation carried a single value across all 3,400
// words — 203 distinct colours down to EIGHT by frame 4,300. A documented gap
// still ships a wrong screen.
//
// THE STARTING STATE is a dump taken 34 SECONDS into the screen. An earlier one
// taken two seconds in was 94% zeros — the table starts cleared and fills from
// the feed — and porting against it produced a correctly black screen. A state
// this screen reaches is not the same thing as the state it starts in.
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;
const ZigOS = zg.ZigOS;
const D = @import("key2_data.zig");
const walk = @import("walk.zig");

pub const W: usize = 320;
pub const H: usize = 200;
const X0: usize = (zg.PHYSICAL_WIDTH - W) / 2;
const Y0: usize = (zg.PHYSICAL_HEIGHT - H) / 2;
const BLACK: u8 = 0;

const screen = @embedFile("../../assets/screens/big_demo/key2_screen.raw");
const start_table = @embedFile("../../assets/screens/big_demo/key2_table.bin");

/// Module scope because HBL handlers take no user pointer (see
/// libs/zig/effects/copper.zig on why the machine works that way). One screen,
/// one table; the cart never has two of these up at once.
var table: [D.ROWS][D.PENS]u16 = undefined;
var seed: u32 = undefined;
var dirs: walk.Dirs = undefined;

/// An ST colour word is three 3-bit levels; level n displays at n*255/7.
fn colour(w: u16) zg.Color {
    return .{
        .r = @intCast((w >> 8 & 7) * 255 / 7),
        .g = @intCast((w >> 4 & 7) * 255 / 7),
        .b = @intCast((w & 7) * 255 / 7),
        .a = 255,
    };
}

/// The per-line palette, written before the machine composites that row. The
/// plane is the jukebox's overscan buffer, so `line` is PHYSICAL 0..279 and the
/// display's first line is Y0 (libs/zig/zigos.zig, hblLinesArePhysical).
fn hbl(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    const y = @as(i32, line) - @as(i32, Y0);
    const t = y - @as(i32, D.FIRST_LINE);
    const row: *const [D.PENS]u16 = if (t >= 0 and t < D.LINES)
        &table[@intCast(t)]
    else
        &D.BASE;
    for (row, 0..) |w, i| fb.setPaletteEntry(@intCast(i), colour(w));
}

pub const Key2 = struct {
    pub fn enter(_: *Key2, zigos: *ZigOS, fb: *LogicalFB) void {
        for (&table, 0..) |*row, l| {
            for (row, 0..) |*w, e| {
                const o = (l * D.PENS + e) * 2;
                w.* = @as(u16, start_table[o]) | (@as(u16, start_table[o + 1]) << 8);
            }
        }
        seed = 0x1BD00;
        dirs = .{};
        // The borders are shut and black on this screen, so the plane's own
        // flicker HBL goes and ours takes over. big/sub.zig puts the jukebox's
        // back on the way out.
        fb.setFrameBufferHBLHandler(0, hbl);
        fb.clearFrameBuffer(BLACK);
        // The sides are shut on this screen, so the margins show the HARDWARE
        // border, not the plane. It is the jukebox's panel grey until told
        // otherwise, and this screen's border is black.
        zigos.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        // The bitmap is STATIC: its pens are the demo's own, and all the motion
        // is in the palette. Blit once.
        for (0..H) |y| {
            @memcpy(fb.fb[(Y0 + y) * zg.PHYSICAL_WIDTH + X0 ..][0..W], screen[y * W ..][0..W]);
        }
    }

    pub fn draw(_: *Key2, _: *LogicalFB) void {
        // One flat rotation of 17 words: entry E of line L takes entry E+1 of
        // line L+1, and the words that fall off the front come back at the end.
        // A colour travels up and left one cell a frame, for ever.
        //
        // IT IS A ROTATION IN THE CODE TOO, and the half that closes it sits
        // BEFORE the loop, not after: `movem.l (a1),d2-d7` at $18B36 saves
        // TWELVE words of the head before a single word moves, and $18B98
        // writes them at the far end afterwards — eleven verbatim, the twelfth
        // replaced by the perturbed neighbour the feed produces.
        //
        // It was ported as a rotation before that was found, on the evidence
        // that a plain shift cannot run: column 15 and the last row have
        // nothing above-right of them, so within twenty frames the whole table
        // is one column smeared diagonally, which renders as horizontal streaks
        // and not as this screen. A mechanism that drains its own input in four
        // seconds is worth disbelieving.
        const flat: *[N]u16 = @ptrCast(&table);
        var held: [STEP]u16 = undefined;
        @memcpy(&held, flat[0..STEP]);
        @memmove(flat[0 .. N - STEP], flat[STEP..N]);
        @memcpy(flat[N - STEP ..], &held);
        feed();
    }
};

/// $18B96 then $18F9A. The POSITION is not random: a1 is left at the end of
/// the shift loop, `move.w -$24(a1),(a2)` reads 18 words back from it and
/// `move.w (a2),-$2(a1)` writes the stepped value into the last word. The roll
/// picks WHICH CHANNEL moves — red, green, blue, or re-roll.
const N: usize = D.ROWS * D.PENS;
/// One line plus one entry: the diagonal, flattened.
const STEP: usize = D.PENS + 1;
const SRC: usize = N - 18; // -$24 bytes from the region's end
const DST: usize = N - 1; // -$2 bytes

fn feed() void {
    const flat: *[N]u16 = @ptrCast(&table);
    for (0..8) |_| { // the machine re-rolls; bound it so a port cannot hang
        const roll = next();
        if (roll & 3 == 3) continue;
        flat[DST] = walk.step(flat[SRC], roll, &dirs);
        return;
    }
}

fn next() u32 {
    seed ^= seed << 13;
    seed ^= seed >> 17;
    seed ^= seed << 5;
    return seed;
}

comptime {
    if (screen.len != W * H) @compileError("key2_screen.raw is not 320x200");
    if (start_table.len != D.ROWS * D.PENS * 2) @compileError("key2_table.bin is not ROWSx16 words");
    if (D.FIRST_LINE + D.LINES > H) @compileError("the table's band runs off the screen");
}
