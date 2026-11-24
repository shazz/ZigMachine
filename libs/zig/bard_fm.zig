// --------------------------------------------------------------------------
// zg.bard.fm: the BARD queue's FM device (docs/project/DECISIONS.md 2026-11-24 "The BARD queue's FM
// device", docs/guide/ZIGOS_API.md 8d). A cart's timed register writes to the YM2612 + SN76489 that
// play the VGM tune (zg.requestSong("x.vgm")): the cart owns some channels (sound effects, an engine
// note), the tune keeps the others. Ask first: zg.caps.has(.bard_fm) (a system without the device
// refuses these writes: they are counted, nothing sounds).
//
//   zg.bard.open(2048)                       the queue (a lead of >= LEAD_MIN samples: the engine
//   zg.bard.fm.own(t, fm.SFX_DEFAULT)        takes a write ~430 samples ahead of what it plays)
//   zg.requestSong("race.vgm")               the tune: its writes to the cart's channels are kept aside
//   zg.bard.fm.ym(t, 1, 0x28 ...), psg(t, b) the cart's writes, on its own channels only
//   zg.bard.fm.tuneStop(t)                   the tune stops (zg.stopSong would end the queue too)
//
// A write to a channel the cart does not own is refused here (false, nothing queued) and by the
// device (counted in its refusals). Channels: FM 0..5 (FM 1-6), PSG tone 0..2 and the noise (3).
// The YM2612's 0x22-0x27 (LFO, timers, channel 3's mode) stay the tune's; 0x2A / 0x2B (the DAC) are
// FM 5's (the DAC replaces it). Each side has its own A4-A6 latch and PSG latch on the device.
// --------------------------------------------------------------------------
const bard = @import("bard.zig");

pub const BASE: u32 = 0xC000; // sid_live.zig FM_BASE: addr = BASE + the engine's SFX address (zm_vgm.h)
pub const YM1: u32 = 0x100;
pub const PSG: u32 = 0x200;
pub const OWN: u32 = 0x300;
pub const TUNE: u32 = 0x301;
pub const OWNABLE: u32 = 0x0F3F;
/// The cart lead the device needs for its writes to land on their stamp (zm_vgm_out.c reads 256 engine
/// frames ahead: ~430 output samples), with a frame's room.
pub const LEAD_MIN: u32 = 1024;

pub fn fmBit(ch: u3) u32 {
    return @as(u32, 1) << ch;
}
pub fn psgBit(c: u2) u32 {
    return @as(u32, 1) << (8 + @as(u5, c));
}
/// FM 5 and 6 (an engine note, an impact), PSG tone 3 and the noise: the tune keeps FM 1-4 and PSG 1-2.
pub const SFX_DEFAULT: u32 = (1 << 4) | (1 << 5) | (1 << 10) | (1 << 11);

pub const OWNER_TUNE: u32 = 6;
pub const OWNER_NOBODY: u32 = 7;

/// The FM channel (0..5) a YM2612 write is for, OWNER_TUNE (a global register) or OWNER_NOBODY (libs/c/vgm/zm_vgm_own.c's rule).
pub fn ymOwner(port: u1, reg: u8, val: u8) u32 {
    if (reg == 0x28) return if (port == 1 or val & 3 == 3) OWNER_NOBODY else (val & 3) + @as(u32, if (val & 4 != 0) 3 else 0);
    if (reg == 0x2A or reg == 0x2B) return if (port == 1) OWNER_NOBODY else 5;
    if (reg < 0x30) return if (port == 1) OWNER_NOBODY else OWNER_TUNE;
    if (reg >= 0xA8 and reg < 0xB0) return OWNER_NOBODY; // channel 3's special frequencies: never the cart's
    if (reg >= 0xB8 or reg & 3 == 3) return OWNER_NOBODY;
    return @as(u32, port) * 3 + (reg & 3);
}

/// What the cart has said it owns (the last `own`), and its PSG latch: the local check of each write.
var owned: u32 = 0;
var psg_latch: u8 = 0;

/// The channels the cart owns from sample `t` (OWNABLE bits only): one taken is keyed off / silenced on
/// the device, one let go gets back the tune's state.
pub fn own(t: u32, mask: u32) bool {
    if (mask & ~OWNABLE != 0) return false;
    if (!bard.pushRaw(t, BASE + OWN, mask)) return false;
    owned = mask;
    return true;
}

pub fn owns(mask_bit: u32) bool {
    return owned & mask_bit != 0;
}

/// YM2612 register `reg` of port `port` to `val` at `t`; false: not on a channel the cart owns, or the queue refused it.
pub fn ym(t: u32, port: u1, reg: u8, val: u8) bool {
    const ch = ymOwner(port, reg, val);
    if (ch >= 6 or owned & fmBit(@intCast(ch)) == 0) return false;
    return bard.pushRaw(t, BASE + @as(u32, port) * YM1 + reg, val);
}

/// A byte to the SN76489 at `t` (a latch byte names its channel; a data byte goes to the cart's last latch).
pub fn psg(t: u32, byte: u8) bool {
    const latch = if (byte & 0x80 != 0) (byte >> 4) & 7 else psg_latch;
    if (owned & psgBit(@intCast(latch >> 1)) == 0) return false;
    if (!bard.pushRaw(t, BASE + PSG, byte)) return false;
    psg_latch = latch;
    return true;
}

/// The tune stops at `t` (its file ends there); the cart's channels play on. A new tune is a requestSong.
pub fn tuneStop(t: u32) bool {
    return bard.pushRaw(t, BASE + TUNE, 0);
}

/// Key FM channel `ch` (0..5) on with `slots` (bits 0-3: operators 1-4), or off with 0.
pub fn key(t: u32, ch: u3, slots: u4) bool {
    const code: u8 = if (ch < 3) ch else @as(u8, ch) + 1;
    return ym(t, 0, 0x28, @as(u8, slots) << 4 | code);
}

/// FM channel `ch`'s pitch: block 0..7, F-number 0..2047 (A4 then A0, as the chip latches them).
pub fn freq(t: u32, ch: u3, block: u3, fnum: u11) bool {
    const port: u1 = @intCast(ch / 3);
    const r: u8 = ch % 3;
    return ym(t, port, 0xA4 + r, @as(u8, block) << 3 | @as(u8, @intCast(fnum >> 8))) and
        ym(t, port, 0xA0 + r, @truncate(fnum));
}

/// One operator's registers (as the chip has them): dt_mul 0x30, tl 0x40, ks_ar 0x50, am_dr 0x60, sr 0x70, sl_rr 0x80.
pub const Op = struct { dt_mul: u8 = 1, tl: u8 = 127, ks_ar: u8 = 31, am_dr: u8 = 0, sr: u8 = 0, sl_rr: u8 = 15 };
/// A voice: four operators in register order S1, S3, S2, S4 (offsets 0, 4, 8, C), algorithm + feedback (0xB0), pans + LFO depths (0xB4).
pub const Patch = struct { ops: [4]Op, fb_alg: u8, pan: u8 = 0xC0 };

/// Every register of a patch to FM channel `ch` (30 writes, SSG-EG off): false if one is refused.
pub fn patch(t: u32, ch: u3, p: *const Patch) bool {
    const port: u1 = @intCast(ch / 3);
    const r: u8 = ch % 3;
    for (p.ops, 0..) |o, i| {
        const at = r + @as(u8, @intCast(i)) * 4;
        const vals = [_]u8{ o.dt_mul, o.tl, o.ks_ar, o.am_dr, o.sr, o.sl_rr, 0 };
        for (vals, 0..) |v, k| if (!ym(t, port, 0x30 + @as(u8, @intCast(k)) * 0x10 + at, v)) return false;
    }
    return ym(t, port, 0xB0 + r, p.fb_alg) and ym(t, port, 0xB4 + r, p.pan);
}

/// PSG tone `c` (0..2) at `period` (10 bits: clock / 32 / period Hz) and attenuation `att` (0 loudest, 15 off).
pub fn tone(t: u32, c: u2, period: u10, att: u4) bool {
    const cc: u8 = @as(u8, c) << 5;
    return psg(t, 0x80 | cc | @as(u8, @truncate(period & 15))) and psg(t, @intCast(period >> 4)) and psg(t, 0x90 | cc | att);
}

/// The noise: `mode` (bit 2 white, bits 0-1 the rate; 3 = tone 3's) and attenuation `att`.
pub fn noise(t: u32, mode: u3, att: u4) bool {
    return psg(t, 0xE0 | @as(u8, mode)) and psg(t, 0xF0 | @as(u8, att));
}

/// Forget the local state (the queue closed or reopened): nothing owned.
pub fn reset() void {
    owned = 0;
    psg_latch = 0;
}
