// --------------------------------------------------------------------------
// The VGM engine (HW audio 1.3.0): our own YM2612 + SN76489 (libs/c/ym2612,
// libs/c/sn76489) and VGM sequencer (libs/c/vgm) behind four calls. A player
// stages a .vgm / .vgz in song RAM, loads it here, then asks for stereo samples
// at the engine's rate (the YM2612's clock / 288, 26.6 kHz), or, as the
// player does (libs/zig/players/vgm.zig), the Paula channels' bytes at 44.1 kHz.
// On the board BARD runs the same C natively (fpga/host/audio_vgm.c): this is
// the page's copy.
// --------------------------------------------------------------------------
extern fn zm_vgm_load(file: [*]u8, len: u32, cap: u32) u32;
extern fn zm_vgm_rate() u32;
extern fn zm_vgm_render(dst: [*]i16, n: u32) void;
extern fn zm_vgm_render_paula(hl: [*]i8, hr: [*]i8, ll: [*]i8, lr: [*]i8, n: u32) void;
extern fn zm_vgm_sfx_on(on: u32) void;
extern fn zm_vgm_sfx_push(stamp: u32, addr: u32, value: u32) u32;
extern fn zm_vgm_sfx_stat(i: u32) u32;

/// Load the file staged at `file_abs` (it must stay there while it plays); a .vgz is inflated in place
/// into the `cap` bytes from `file_abs`. 0 ok, 1 not a VGM, 2 no YM2612 / SN76489, 3 truncated, 4 a bad
/// or too big .vgz.
export fn machineVgmLoad(file_abs: u32, len: u32, cap: u32) u32 {
    return zm_vgm_load(@ptrFromInt(file_abs), len, cap);
}

/// The engine's rate in Hz (the loaded file's YM2612 clock / 288).
export fn machineVgmRate() u32 {
    return zm_vgm_rate();
}

/// The next `n` stereo frames (s16 L, R) at machineVgmRate into `dst_abs` (2-byte aligned).
export fn machineVgmRender(dst_abs: u32, n: u32) void {
    zm_vgm_render(@ptrFromInt(dst_abs), n);
}

/// The player's output: the next `n` 44.1 kHz frames, the engine resampled linearly and split into the four
/// Paula channels' bytes at `hl_abs`, `hr_abs` (high L, R) and `ll_abs`, `lr_abs` (low L, R): 128 hi + lo = x >> 1.
export fn machineVgmRenderPaula(hl_abs: u32, hr_abs: u32, ll_abs: u32, lr_abs: u32, n: u32) void {
    zm_vgm_render_paula(@ptrFromInt(hl_abs), @ptrFromInt(hr_abs), @ptrFromInt(ll_abs), @ptrFromInt(lr_abs), n);
}

/// The SFX device (HW audio 1.4.0, libs/c/vgm/zm_vgm_sfx.c): a cart's timed writes to these chips on the channels
/// it owns while the tune plays. On (1): its clocks start at 0, the chips play (silent ones with no tune loaded);
/// off (0): the tune gets every channel back.
export fn machineVgmSfxOn(on: u32) void {
    zm_vgm_sfx_on(on);
}

/// A write for output frame `stamp` (44.1 kHz since the on): `addr` 0x000 + reg / 0x100 + reg the YM2612's ports,
/// 0x200 a byte to the SN76489, 0x300 the owned channels (value: FM n = bit n, PSG n = bit 8 + n), 0x301 value 0
/// the tune stops. 1 queued, 0 off or the ring (512) full.
export fn machineVgmSfxPush(stamp: u32, addr: u32, value: u32) u32 {
    return zm_vgm_sfx_push(stamp, addr, value);
}

/// A counter: 0 applied, 1 refused, 2 waiting, 3 late, 4 output frames since the on, 5 the owned channels, 6 on.
export fn machineVgmSfxStat(i: u32) u32 {
    return zm_vgm_sfx_stat(i);
}
