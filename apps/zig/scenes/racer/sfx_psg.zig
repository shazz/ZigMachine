// --------------------------------------------------------------------------
// RACER: the effects' PSG-ONLY layout (R82 board batch, item 2: "set music and sfx as defaults"). The local
// 32X VGM tunes (-Dracer_music) use all six FM channels (FM 6 as the DAC's drums) and never the SN76489; the
// FM layout (sfx.zig: engine FM 6, impact FM 5) took the drums and a melody part away while the effects were
// on, so they started OFF there. This layout puts every effect on the PSG, which those tunes leave silent:
//   engine    PSG tone 1, a square whose period follows the rpm (IDLE_PERIOD ~112 Hz .. TOP_PERIOD ~294 Hz)
//   impact    the noise, a loud white burst that fades over IMPACT_FRAMES (it pre-empts a skid, which resumes)
//   skid      the noise, as in the FM layout
//   beeps     PSG tone 3, as in the FM layout (sfx.zig's phrases)
// The tune keeps FM 1-6, the DAC and PSG tone 2: nothing of the music is muted, so the effects are on by
// default with every tune. Integer only. No ZigOS import.
// --------------------------------------------------------------------------
const sfx = @import("sfx.zig");

pub const ENGINE_CH: u8 = 0; // PSG tone 1
pub const IDLE_PERIOD: u32 = 1000; // 3,579,545 / 32 / 1000 = ~112 Hz
pub const TOP_PERIOD: u32 = 380; // ~294 Hz at max rpm
pub const ENGINE_ATT: u8 = 4;
const PERIOD_STEP: u32 = 4; // a smaller move is not written
const SKID_ATT: u8 = 5;
/// The PSG channels this layout owns, as zg.bard.fm's OWNABLE bits (psgBit 0, 2, 3: tone 1, tone 3, the noise).
pub const MASK: u32 = (1 << 8) | (1 << 10) | (1 << 11);

pub fn enginePeriod(rpm: i32) u32 {
    const r: u32 = @intCast(@max(0, @min(rpm, sfx.MAX_RPM)));
    return IDLE_PERIOD - r * (IDLE_PERIOD - TOP_PERIOD) / @as(u32, sfx.MAX_RPM);
}

fn vol(out: *sfx.Out, ch: u8, att: u8) void {
    out.put(.{ .kind = .psg, .val = 0x90 | ch << 5 | att });
}

fn period(self: *sfx.Sfx, p: u32, out: *sfx.Out) void {
    self.fnum = p;
    out.put(.{ .kind = .psg, .val = 0x80 | ENGINE_CH << 5 | @as(u8, @intCast(p & 15)) });
    out.put(.{ .kind = .psg, .val = @intCast(p >> 4) });
}

pub fn engine(self: *sfx.Sfx, s: sfx.Snap, out: *sfx.Out) void {
    if (s.racing != self.engine) {
        if (s.racing) period(self, enginePeriod(s.rpm), out);
        vol(out, ENGINE_CH, if (s.racing) ENGINE_ATT else 15);
        self.engine = s.racing;
    }
    if (!s.racing) return;
    const p = enginePeriod(s.rpm);
    const d = if (p > self.fnum) p - self.fnum else self.fnum - p;
    if (d >= PERIOD_STEP) period(self, p, out);
}

/// The noise: an impact's burst (fading one attenuation step every frame or so) over a skid's hiss.
pub fn noise(self: *sfx.Sfx, s: sfx.Snap, out: *sfx.Out) void {
    const want_skid = s.slide and s.racing and s.state == .race;
    if (s.knocks > self.prev.knocks) {
        out.put(.{ .kind = .psg, .val = 0xE4 }); // white noise, clock / 512
        vol(out, 3, 0);
        self.impact_left = sfx.IMPACT_FRAMES;
        self.skid = false; // the burst took the noise: a slide afterwards starts it again
        return;
    }
    if (self.impact_left > 0) {
        self.impact_left -= 1;
        if (self.impact_left > 0) return vol(out, 3, @intCast(15 - @as(u32, self.impact_left) * 15 / sfx.IMPACT_FRAMES));
        vol(out, 3, 15);
    }
    if (want_skid == self.skid) return;
    if (want_skid) out.put(.{ .kind = .psg, .val = 0xE5 }); // white noise, clock / 1024
    vol(out, 3, if (want_skid) SKID_ATT else 15);
    self.skid = want_skid;
}

/// Everything this layout sounds, silenced (the beeps are sfx.quiet's).
pub fn quiet(self: *const sfx.Sfx, out: *sfx.Out) void {
    if (self.engine) vol(out, ENGINE_CH, 15);
    if (self.skid or self.impact_left > 0) vol(out, 3, 15);
}
