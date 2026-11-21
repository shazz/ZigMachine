// --------------------------------------------------------------------------
// The VGM engine (HW audio 1.3.0): our own YM2612 + SN76489 (libs/c/ym2612,
// libs/c/sn76489) and VGM sequencer (libs/c/vgm) behind three calls. A player
// stages a .vgm / .vgz in song RAM, loads it here, then asks for stereo samples
// at the engine's rate (the YM2612's clock / 288, 26.6 kHz) into its own
// buffer; it puts them on the Paula channels itself (libs/zig/players/vgm.zig).
// On the board BARD runs the same C natively (fpga/host/audio_vgm.c): this is
// the page's copy.
// --------------------------------------------------------------------------
extern fn zm_vgm_load(file: [*]u8, len: u32, cap: u32) u32;
extern fn zm_vgm_rate() u32;
extern fn zm_vgm_render(dst: [*]i16, n: u32) void;

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
