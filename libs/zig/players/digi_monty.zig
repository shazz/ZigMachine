// --------------------------------------------------------------------------
// Auf Wiedersehen Monty - digidrums (Mad Max, 1987; ripped by Mr Styckx,
// converted by Grazey): its whole replay, natively. The 68000 rip and the
// offsets are in docs/FPGA_SOUND_CPU.md "Monty".
//
// The image is a game driver assembled at $46A86 (image $40E) with its song
// at $60000 (image $3A9E) and its drums at $40500 (image $F9E). Grazey's
// wrapper relocates it the first time INIT runs, then the driver's own INIT
// starts Timer D through XBIOS Xbtimer: 2457600 / 4 / 58 = 10593 Hz, from
// the first frame, about 176 interrupts a 60 Hz frame. Idle, the handler
// returns at once; with a drum on, it plays one 4-bit sample onto volume C.
//
//   init   (first time) save the MFP and five vectors, relocate; then the
//          drum's end pointer cleared, Xbtimer, the song's voices set up
//   play   digi_monty_seq.zig: four voices, the 13 YM registers written
//   exit   the MFP and vectors put back, and two writes to the FDC's port
//
// Every access is the 68000's, in its order, on the SNDH player's bus, and
// every state byte lives where the tune keeps it, so Musashi can take over
// from this (or this from Musashi) between any two calls.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");
const sndh = @import("sndh.zig");
pub const seq = @import("digi_monty_seq.zig");
pub const at = @import("digi_monty_map.zig");

const SIGNATURE: u64 = 0x2EADE04B868DBD53; // digi.maskedHash of the code, the tables' holes zeroed
const SIGNED = [2]u32{ 0x86, at.DRUM_NO };
// What the code reads as data: the MFP save, the tables and voices, a flag, the song's state.
const HOLES = [_][2]u32{ .{ at.SAVE, at.SAVE + 0x28 }, .{ at.DRUM_IDLE, at.DRUM_IDLE + 2 }, .{ at.MOVEM, at.PLAY_CODE }, .{ at.DRUMS_ON_C, at.DRUMS_ON_C + 2 }, .{ at.ENVS, at.FX_CODE } };

pub const Driver = struct {
    base: u32, // the image's 68000 address: every offset in digi_monty_map.zig is from it

    pub fn handlerAddr(d: Driver) u32 {
        return d.base + at.HANDLER;
    }
};

/// The image is Monty's (its code byte for byte, outside its data) and long
/// enough for the song INIT relocates. Null: not this driver.
pub fn match(image: []const u8, base: u32) ?Driver {
    if (image.len < at.MUSIC + at.MUSIC_LEN) return null;
    if (digi.maskedHash(image[SIGNED[0]..SIGNED[1]], &shifted) != SIGNATURE) return null;
    return .{ .base = base };
}

/// HOLES, made relative to SIGNED[0].
const shifted = blk: {
    var h: [HOLES.len][2]u32 = undefined;
    for (HOLES, 0..) |r, i| h[i] = .{ r[0] - SIGNED[0], r[1] - SIGNED[0] };
    break :blk h;
};

pub fn call(comptime Bus: type, d: Driver, entry: u32) void {
    switch (entry) {
        sndh.INIT => init(Bus, d),
        sndh.EXIT => exit(Bus, d),
        else => seq.play(Bus, d.base),
    }
}

const MFP: u32 = 0xFFFA00;
const VECTORS = [_]u32{ 0x94, 0x110, 0x114, 0x120, 0x134 };

fn init(comptime Bus: type, d: Driver) void {
    const m = digi.Access(Bus);
    const b = d.base;
    if (m.rd16(b + at.FIRST) == 0) {
        m.wr16(b + at.FIRST, 1);
        for (0..19) |i| Bus.write8(b + at.SAVE + @as(u32, @intCast(i)), Bus.read8(MFP + 1 + 2 * @as(u32, @intCast(i))));
        for (VECTORS, 0..) |v, i| m.wr32(b + at.SAVE + 0x14 + 4 * @as(u32, @intCast(i)), m.rd32(v));
        Bus.write8(MFP + 0x23, 0xC0);
        @import("digi_monty_reloc.zig").relocate(Bus, b);
    }
    m.wr32(b + at.DRUM_END, 0);
    Bus.xbtimer(3, 1, 0x3A, b + at.HANDLER); // Timer D, /4, 58: 10593 Hz
    seq.start(Bus, b);
}

fn exit(comptime Bus: type, d: Driver) void {
    const m = digi.Access(Bus);
    const b = d.base;
    for (0..19) |i| Bus.write8(MFP + 1 + 2 * @as(u32, @intCast(i)), Bus.read8(b + at.SAVE + @as(u32, @intCast(i))));
    for (VECTORS, 0..) |v, i| m.wr32(v, m.rd32(b + at.SAVE + 0x14 + 4 * @as(u32, @intCast(i))));
    Bus.write16(0xFF8606, 0x80); // the FDC: select its command register...
    Bus.write16(0xFF8604, 0xD0); // ...and force an interrupt
    Bus.write8(MFP + 0x23, 0xC0);
}

const PSG: u32 = 0xFF8800;
const ISRB: u32 = MFP + 0x11;

/// One Timer D interrupt ($44C). The pushes, the SR writes and the RTE are
/// left out: nothing reads that stack, and interrupts never nest here.
pub fn irq(comptime Bus: type, d: Driver) void {
    const m = digi.Access(Bus);
    const b = d.base;
    if (m.rd16(b + at.MUTE) == 0 and m.rd16(b + at.BUSY) == 0) {
        m.wr16(b + at.BUSY, 1);
        Bus.write8(ISRB, Bus.read8(ISRB) & 0xEF); // in service: done
        const cur = m.rd32(b + at.DRUM_CUR);
        if (m.rd16(b + at.DRUM_IDLE) != 0xFFFF and cur != m.rd32(b + at.DRUM_END)) {
            const s = Bus.read8(cur);
            m.wr32(b + at.DRUM_CUR, cur +% 1);
            Bus.write8(PSG, 10);
            Bus.write8(PSG + 2, (s >> 1) +% 8); // a 4-bit sample, 8..15 on volume C
            m.wr16(b + at.BUSY, 0);
            return;
        }
        m.wr16(b + at.DRUM_IDLE, 0xFFFF);
        m.wr16(b + at.BUSY, 0);
    }
    Bus.write8(ISRB, Bus.read8(ISRB) & 0xEF);
}
