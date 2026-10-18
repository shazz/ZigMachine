// --------------------------------------------------------------------------
// Monty's first INIT ($1FC, Grazey's): the driver, assembled at $46A86 with
// its song at $60000 and its drums at $40500, is made to run where it is.
//
//   1  every long in the driver (stepping a word, to the first sample's long
//      inclusive) that falls in $46A86..$47616 moves with the driver
//   2  five NOPs: the SR writes around play's YM loop, and a move to $484
//   3  the 20 drum pointers move with the drums, five song pointers in the
//      code with the song, and every song long in $60000..$60D2A with it
//
// A word-stepped scan of code can relocate a coincidence as well as a pointer:
// it is done here exactly as the 68000 does it, coincidences included, so the
// RAM is the same either way.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");
const at = @import("digi_monty_map.zig");

const NOP2: u32 = 0x4E71_4E71;

pub fn relocate(comptime Bus: type, b: u32) void {
    const m = digi.Access(Bus);
    const drv = b + at.DRV;
    const old = m.rd32(b + at.OLD_BASE);
    if (old == drv) return;
    m.wr32(b + at.OLD_BASE, drv);
    driver(Bus, drv, b + at.SAMPLES, old);
    m.wr16(drv + 0x500, @truncate(NOP2)); // play's move.w sr,-(a7)
    m.wr32(drv + 0x502, NOP2); // ...and move.w #$2700,sr
    m.wr16(drv + 0x572, @truncate(NOP2)); // ...and move.w (a7)+,sr
    m.wr32(drv + 0xB48, NOP2); // song init's move.b #2,$484
    m.wr32(drv + 0xB4C, NOP2);
    const drums = (b + at.SAMPLES) -% at.SAMPLES_ORIG;
    var p = drv + 0x148; // DRUM_START, then DRUM_STOP
    for (0..20) |_| {
        m.wr32(p, m.rd32(p) +% drums);
        p += 4;
    }
    const song = (b + at.MUSIC) -% at.MUSIC_ORIG;
    for ([_]u32{ 0x8CA, 0x8D4, 0xAE2, 0xB10, 0xB40 }) |o| m.wr32(drv + o, m.rd32(drv + o) +% song);
    music(Bus, b + at.MUSIC);
}

/// cmp.l / blt / bgt: signed, as the 68000 compares them.
fn driver(comptime Bus: type, drv: u32, end: u32, old: u32) void {
    const m = digi.Access(Bus);
    const lo: i32 = @bitCast(old);
    const hi: i32 = @bitCast(old +% at.DRV_LEN);
    var a = drv;
    while (true) {
        const v: i32 = @bitCast(m.rd32(a));
        if (v >= lo and v <= hi) {
            m.wr32(a, @bitCast(v -% lo +% @as(i32, @bitCast(drv))));
            a +%= 2;
        }
        a +%= 2;
        if (@as(i32, @bitCast(a)) > @as(i32, @bitCast(end))) return;
    }
}

/// cmp.l / bcs / bhi: unsigned this time.
fn music(comptime Bus: type, song: u32) void {
    const m = digi.Access(Bus);
    var a = song;
    while (true) {
        const v = m.rd32(a);
        a +%= 4;
        if (v >= at.MUSIC_ORIG and v <= at.MUSIC_TOP) m.wr32(a -% 4, v - at.MUSIC_ORIG +% song);
        if (@as(i32, @bitCast(a)) >= @as(i32, @bitCast(song + at.MUSIC_LEN))) return;
    }
}
