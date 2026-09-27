// --------------------------------------------------------------------------
// The ProTracker effect commands the MOD player (mod.zig) implements: those
// read on a row's first tick (rowEffect) and those run on every other tick
// (tickEffect). They change the channel's state and reach the chip only
// through the player's own setters, which leave alone a channel lent to a
// sound effect (sfx_voice.zig).
// --------------------------------------------------------------------------
const std = @import("std");
const ModPlayer = @import("mod.zig").ModPlayer;

/// The effect's first-tick part (tick 0, after the note).
pub fn rowEffect(p: *ModPlayer, ch: usize) void {
    const cs = &p.chan[ch];
    switch (cs.eff) {
        0x0 => cs.arp = cs.param,
        0xC => cs.volume = @min(cs.param, 64),
        0xF => if (cs.param < 0x20) {
            if (cs.param > 0) p.speed = cs.param;
        } else p.setBpm(cs.param),
        0xB => p.jump_pos = cs.param,
        0xD => p.break_row = @intCast((cs.param >> 4) * 10 + (cs.param & 0x0F)),
        0x9 => p.setPos(ch, @as(u32, cs.param) * 256),
        else => {},
    }
}

/// The effect's part on ticks 1..speed-1.
pub fn tickEffect(p: *ModPlayer, ch: usize) void {
    const cs = &p.chan[ch];
    switch (cs.eff) {
        0x0 => if (cs.arp != 0) arpeggio(p, ch),
        0x1 => {
            cs.period = if (cs.period > cs.param + 113) cs.period - cs.param else 113;
            p.setStep(ch, ModPlayer.periodToStep(cs.period));
        },
        0x2 => {
            cs.period = @min(856, cs.period + @as(u16, cs.param));
            p.setStep(ch, ModPlayer.periodToStep(cs.period));
        },
        0x3 => tonePorta(p, ch),
        0xA => {
            const up = cs.param >> 4;
            const down = cs.param & 0x0F;
            const v: i16 = @as(i16, cs.volume) + up - down;
            cs.volume = @intCast(std.math.clamp(v, 0, 64));
            p.setVolume(ch, cs.volume);
        },
        else => {},
    }
}

fn arpeggio(p: *ModPlayer, ch: usize) void {
    const cs = &p.chan[ch];
    const semi: u8 = switch (p.tick % 3) {
        0 => 0,
        1 => cs.arp >> 4,
        else => cs.arp & 0x0F,
    };
    const mul = std.math.pow(f32, 2.0, @as(f32, @floatFromInt(semi)) / 12.0);
    p.setStep(ch, @intFromFloat(@as(f32, @floatFromInt(ModPlayer.periodToStep(cs.period))) * mul));
}

fn tonePorta(p: *ModPlayer, ch: usize) void {
    const cs = &p.chan[ch];
    if (cs.target_period == 0 or cs.porta_speed == 0) return;
    if (cs.period < cs.target_period) {
        cs.period = @min(cs.target_period, cs.period + cs.porta_speed);
    } else if (cs.period > cs.target_period) {
        cs.period = if (cs.period > cs.target_period + cs.porta_speed) cs.period - cs.porta_speed else cs.target_period;
    }
    p.setStep(ch, ModPlayer.periodToStep(cs.period));
}
