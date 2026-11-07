// --------------------------------------------------------------------------
// The SID engine (HW audio 1.3.0): cRSID (libs/c/crsid, Hermit's light SID +
// 6502 player) behind two calls. A player stages a .sid in song RAM, loads it
// here, then asks for 22.05 kHz mono samples into its own buffer; it puts them
// on the Paula channels itself (libs/zig/players/sid.zig). On the board BARD
// runs the same C natively (fpga/host/audio_sid.c): this is the page's copy.
// --------------------------------------------------------------------------
extern fn zm_sid_load(file: [*]u8, len: u32, subtune: u32) u32;
extern fn zm_sid_render(dst: [*]i16, n: u32) void;

/// Load the .sid staged at `file_abs` (it must stay there while it plays) and start `subtune`
/// (1-based, 0 = its default). 0 ok, 1 not a .sid, 2 RSID (not supported), 3 a bad length.
export fn machineSidLoad(file_abs: u32, len: u32, subtune: u32) u32 {
    return zm_sid_load(@ptrFromInt(file_abs), len, subtune);
}

/// The next `n` s16 mono samples at 22050 Hz into `dst_abs` (2-byte aligned).
export fn machineSidRender(dst_abs: u32, n: u32) void {
    zm_sid_render(@ptrFromInt(dst_abs), n);
}
