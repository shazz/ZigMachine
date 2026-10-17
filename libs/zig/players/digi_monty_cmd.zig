// --------------------------------------------------------------------------
// Monty's row reader ($B98) and its commands. `p` is the 68000's a1, the
// pattern pointer; a command returns where reading carries on, and whether it
// ends the row (as $80, $90 and $91 do, through $BE2).
// --------------------------------------------------------------------------
const digi = @import("digi.zig");
const at = @import("digi_monty_map.zig");
const V = at.V;

/// Bytes are read until a note or a row-ending command; then the row's tail ($BE2).
pub fn row(comptime Bus: type, b: u32, v: u32, from: u32) void {
    const m = digi.Access(Bus);
    var p = from;
    while (true) {
        const c = m.rd8(p);
        p +%= 1;
        if (c < 0x80) {
            note(Bus, b, v, c);
            break;
        }
        const n = command(Bus, b, v, c, p);
        p = n.p;
        if (n.ends) break;
    }
    tail(Bus, v, p);
}

fn note(comptime Bus: type, b: u32, v: u32, c: u8) void {
    const m = digi.Access(Bus);
    m.bclr(v + V.EFX, 2);
    m.wr8(v + V.NOTE, c);
    if (m.rd8(v + V.NOISE_SET) != 0) m.wr8(b + at.NOISE, c);
    var env = m.rd32(v + V.ENV_POS);
    if (m.rd8(v + V.TIE) == 0) {
        env = m.rd32(v + V.ENV);
        m.wr32(v + V.ENV_POS, env);
    }
    m.wr8(v + V.ENV_LEVEL, m.rd8(env));
    m.wr8(v + V.VOLUME, m.rd8(env));
    m.wr8(v + V.ENV_WAIT, m.rd8(v + V.ENV_SPEED));
    m.bset(v + V.FLAGS, 5);
}

/// $BE2: the row's length, the vibrato's delay, the arpeggio and decay counters.
fn tail(comptime Bus: type, v: u32, p: u32) void {
    const m = digi.Access(Bus);
    m.wr8(v + V.ROW_WAIT, m.rd8(v + V.ROW_LEN));
    const tie = m.rd8(v + V.TIE) == 1;
    m.wr8(v + V.VIB_WAIT, m.rd8(v + V.VIB_DELAY));
    m.wr8(v + V.VIB_GO, @intFromBool(tie));
    m.wr8(v + V.ARP_WAIT, m.rd8(v + V.ARP_SPEED));
    m.wr8(v + V.DECAY_WAIT, m.rd8(v + V.DECAY_SPEED));
    m.wr32(v + V.PATTERN, p);
    m.wr8(v + V.SWEEP, 0x30);
}

/// $C48: by range, then $80..$B7 through CMDS ($CC6). A byte the table does not
/// cover would send the 68000 into code as data; no row of the song has one
/// (docs/FPGA_SOUND_CPU.md), and here it ends the row instead, counted.
const Next = struct { p: u32, ends: bool = false };

fn command(comptime Bus: type, b: u32, v: u32, c: u8, p: u32) Next {
    const m = digi.Access(Bus);
    if (c >= 0xE0) {
        m.wr8(v + V.ROW_LEN, c - 0xE0 + 1);
    } else if (c >= 0xD0) {
        const e = m.rd32(m.rd32(b + at.ENVS) +% @as(u32, c - 0xD0) * 4);
        m.wr32(v + V.ENV, e);
        m.wr8(v + V.ENV_SPEED, m.rd8(e -% 1));
    } else if (c >= 0xC0) {
        const a = m.rd32(b + at.ARPS + @as(u32, c - 0xC0) * 4);
        m.wr32(v + V.ARP, a);
        m.wr32(v + V.ARP_START, a);
        m.wr8(v + V.ARP_SPEED, m.rd8(m.rd32(v + V.ARP_START) -% 1));
        m.wr8(v + V.ARP_WAIT, m.rd8(v + V.ARP_SPEED));
    } else if (c >= 0xB8) {
        m.wr8(b + at.SPEED, c - 0xB8 + 1);
    } else {
        const target = m.rd32(b + at.CMDS + @as(u32, c & 0x7F) * 4) -% b;
        return table(Bus, b, v, target, p);
    }
    return .{ .p = p };
}

pub var unknown: u32 = 0; // commands this replay could not follow

fn table(comptime Bus: type, b: u32, v: u32, target: u32, p: u32) Next {
    const m = digi.Access(Bus);
    switch (target) {
        0xB72 => { // $80: the note off
            m.wr8(v + V.VOLUME, 0);
            m.bclr(v + V.EFX, 2);
            return .{ .p = p, .ends = true };
        },
        0xB38 => m.wr8(v + V.VIB_MODE, 0x00), // $81..$83: vibrato off, on, on every other frame
        0xB42 => m.wr8(v + V.VIB_MODE, 0x40),
        0xB4C => m.wr8(v + V.VIB_MODE, 0xC0),
        0xAF0 => { // $84 x y: slide by x after y frames
            m.wr16(v + V.SLIDE, 0);
            m.bset(v + V.FLAGS, 2);
            m.wr8(v + V.SLIDE_STEP, m.rd8(p));
            m.wr8(v + V.SLIDE_WAIT, m.rd8(p +% 1));
            return .{ .p = p +% 2 };
        },
        0xB28, 0xB2C => { // $86 x: bend up, $85 x: down
            if (target == 0xB28) m.bset(v + V.FLAGS, 7);
            m.bset(v + V.FLAGS, 3);
            m.wr8(v + V.BEND, m.rd8(p));
            return .{ .p = p +% 1 };
        },
        0x9FE => return .{ .p = @import("digi_monty_track.zig").next(Bus, b, v) }, // $87: the pattern's end
        0xB10 => { // $88 step depth delay
            m.wr8(v + V.VIB_STEP, m.rd8(p));
            m.wr8(v + V.VIB_DEPTH, m.rd8(p +% 1));
            m.wr8(v + V.VIB_POS, m.rd8(p +% 1));
            m.wr8(v + V.VIB_WAIT, m.rd8(p +% 2));
            m.wr8(v + V.VIB_DELAY, m.rd8(p +% 2));
            return .{ .p = p +% 3 };
        },
        0xB06 => { // $89 x: the song's transpose
            m.wr8(b + at.TRANSPOSE, m.rd8(p));
            return .{ .p = p +% 1 };
        },
        0xAAA => mix(Bus, b, v, 0x38, 0), // $8A: the channel's noise
        0xA52 => mix(Bus, b, v, 0x07, 1), // $8B: its tone, and it sets the noise
        0xAD0 => { // $8C: its bits off
            const x = (m.rd8(v + V.MIX) ^ 0xFF) & m.rd8(b + at.MIX_MASK);
            m.wr8(b + at.MIX_MASK, m.rd8(b + at.MIX_MASK) & x);
            m.wr8(v + V.NOISE_SET, 1);
        },
        0xB56 => m.bset(v + V.FLAGS, 1), // $8D
        0x9F4 => m.wr8(v + V.TIE, 1), // $8E: the next note keeps the envelope
        0xA78 => { // $8F: $8B, a noise sweep from $40, and $8B again
            mix(Bus, b, v, 0x07, 1);
            m.bset(v + V.EFX, 1);
            m.wr8(v + V.SWEEP, 0x40);
            mix(Bus, b, v, 0x07, 1);
        },
        0xB5E => { // $90 x: decay the volume every x frames; ends the row
            m.bset(v + V.EFX, 2);
            m.wr8(v + V.DECAY_SPEED, m.rd8(p));
            m.wr8(v + V.DECAY_WAIT, m.rd8(v + V.DECAY_SPEED));
            return .{ .p = p +% 1, .ends = true };
        },
        0x9D4 => { // $91 n: drum n; ends the row
            m.wr8(b + at.DRUM_NO + 3, m.rd8(p));
            trigger(Bus, b, v, p +% 1);
            m.wr8(v + V.VOLUME, 0);
            return .{ .p = p +% 1, .ends = true };
        },
        0x9E8 => { // $92 / $93 x: x = 1, the drums take channel C
            m.wr8(b + at.DRUMS_ON_C, m.rd8(p));
            return .{ .p = p +% 1 };
        },
        else => {
            unknown +%= 1;
            return .{ .p = p, .ends = true };
        },
    }
    return .{ .p = p };
}

/// $8A / $8B: MIX_MASK takes the voice's bits under `bits` (the eor/and/eor merge).
fn mix(comptime Bus: type, b: u32, v: u32, bits: u8, noise: u8) void {
    const m = digi.Access(Bus);
    const want = m.rd8(v + V.MIX);
    const old = m.rd8(b + at.MIX_MASK);
    m.wr8(b + at.MIX_MASK, (((want & bits) ^ old) & want) ^ old);
    m.wr8(v + V.NOISE_SET, noise);
}

/// $4D6: the drum's start and end from the tables, and the handler woken.
/// Its movem save of d7/a0/a1 is stored as the 68000 would, d7 as 0 above the
/// byte the effects left in it: that area is only ever read back into registers.
fn trigger(comptime Bus: type, b: u32, v: u32, p: u32) void {
    const m = digi.Access(Bus);
    m.wr32(b + at.MOVEM, @import("digi_monty_fx.zig").d7);
    m.wr32(b + at.MOVEM + 4, v);
    m.wr32(b + at.MOVEM + 8, p);
    const w: u16 = @truncate(m.rd32(b + at.DRUM_NO) << 2); // lsl.w, then (a0,d7.w)
    const i: u32 = @bitCast(@as(i32, @as(i16, @bitCast(w))));
    m.wr32(b + at.DRUM_CUR, m.rd32(b + at.DRUM_START +% i));
    m.wr32(b + at.DRUM_END, m.rd32(b + at.DRUM_STOP +% i));
    m.wr16(b + at.DRUM_IDLE, 0);
}
