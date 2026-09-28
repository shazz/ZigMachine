// --------------------------------------------------------------------------
// The MOD player's sequencer (mod.zig): one tick at a time, a row read on
// the first tick of each (its notes and effects), then on to the next row,
// order entry, Bxx jump or Dxx break. Like mod_effects.zig, it reaches the
// chip only through the player's setters, which leave alone a channel lent
// to a sound effect (sfx_voice.zig).
// --------------------------------------------------------------------------
const fmt = @import("mod_format.zig");
const effects = @import("mod_effects.zig");
const ModPlayer = @import("mod.zig").ModPlayer;

/// One sequencer tick: the row on tick 0, the running effects on the others.
pub fn tick(p: *ModPlayer) void {
    if (!p.active) return;
    if (p.tick == 0) {
        processRow(p);
    } else {
        for (0..fmt.NUM_CH) |ch| effects.tickEffect(p, ch);
    }
    p.tick += 1;
    if (p.tick >= p.speed) {
        p.tick = 0;
        advanceRow(p);
    }
}

fn advanceRow(p: *ModPlayer) void {
    if (p.jump_pos >= 0) {
        p.order_pos = @intCast(p.jump_pos);
        p.row = if (p.break_row >= 0) @intCast(p.break_row) else 0;
        p.jump_pos = -1;
        p.break_row = -1;
    } else if (p.break_row >= 0) {
        p.row = @intCast(p.break_row);
        p.break_row = -1;
        nextOrder(p);
    } else {
        p.row += 1;
        if (p.row >= 64) {
            p.row = 0;
            nextOrder(p);
        }
    }
    // A Bxx past the song or a Dxx past the pattern: wrap, never read
    // past the order list or into the next pattern.
    if (p.order_pos >= p.hdr.song_len) p.order_pos = 0;
    if (p.row >= 64) p.row = 0;
}

fn nextOrder(p: *ModPlayer) void {
    p.order_pos +%= 1;
    if (p.order_pos >= p.hdr.song_len) p.order_pos = 0;
}

fn cellByte(p: *const ModPlayer, ch: usize, n: usize) u8 {
    const pattern = p.hdr.order[p.order_pos];
    const o = p.hdr.pattern_data + @as(u32, pattern) * fmt.PATTERN_BYTES + @as(u32, p.row) * 16 + @as(u32, @intCast(ch)) * 4 + n;
    return if (o < p.data.len) p.data[o] else 0;
}

fn processRow(p: *ModPlayer) void {
    for (0..fmt.NUM_CH) |ch| {
        const b0 = cellByte(p, ch, 0);
        const b1 = cellByte(p, ch, 1);
        const b2 = cellByte(p, ch, 2);
        const b3 = cellByte(p, ch, 3);
        const period: u16 = (@as(u16, b0 & 0x0F) << 8) | b1;
        const sample: u8 = (b0 & 0xF0) | (b2 >> 4);
        const cs = &p.chan[ch];
        cs.eff = b2 & 0x0F;
        cs.param = b3;
        if (sample != 0 and sample <= 31) {
            cs.sample = sample;
            cs.volume = p.hdr.samples[sample].volume;
        }
        if (period != 0) {
            if (cs.eff == 3 or cs.eff == 5) {
                cs.target_period = period;
                if (cs.eff == 3 and cs.param != 0) cs.porta_speed = cs.param;
            } else {
                cs.period = period;
                p.trigger(ch);
            }
        }
        effects.rowEffect(p, ch);
        p.applyToEngine(ch);
    }
}
