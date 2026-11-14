// --------------------------------------------------------------------------
// The AY engine (the BARD queue's AY device): libs/c/ayumi, eight AY / YM chips
// in integers behind one address space (zm_ay_bank.h). A player writes them at
// their samples and asks for 44.1 kHz stereo into its own buffer, which it puts
// on the Paula channels itself (libs/zig/players/sid.zig). On the board BARD
// runs the same C natively (fpga/host/audio_ay.c): this is the page's copy.
// --------------------------------------------------------------------------
extern fn zm_ay_bank_reset() void;
extern fn zm_ay_bank_write(a: u32, value: u32) c_int;
extern fn zm_ay_bank_render(dst: [*]i16, n: u32) void;

/// Every chip off (silence until a chip's configure).
export fn machineAyReset() void {
    zm_ay_bank_reset();
}

/// A write at offset `a` of the AY device (addr - 0xA000: chip x 16 + reg, 0x80 + chip a gain). 1 applied, 0 refused.
export fn machineAyWrite(a: u32, value: u32) u32 {
    return @intFromBool(zm_ay_bank_write(a, value) != 0);
}

/// The next `n` stereo frames (s16 L, R) at 44100 Hz into `dst_abs` (2-byte aligned): the configured chips summed.
export fn machineAyRender(dst_abs: u32, n: u32) void {
    zm_ay_bank_render(@ptrFromInt(dst_abs), n);
}
