// --------------------------------------------------------------------------
// blit.zig's way onto CHISEL. blit.zig imports no ZigOS (so it tests natively),
// so ZigOS.init installs these (libs/zig/chisel.zig fillRect / copyRect); they
// stay null where there is no machine, as in the native tests.
//
// Each returns true when it did the op on CHISEL, byte-identically (the box is
// in a video plane, the source in a window the blitter may read, the two do not
// overlap), else false having written nothing, and the caller does it on the
// CPU. On the board a memset is ~86 cycles a word of blocking DDR stores and a
// keyed byte loop ~20 cycles a pixel, CHISEL ~1-2 cycles a pixel; below
// MIN_BYTES the register setup (~20-30 stores) costs more than it saves.
// --------------------------------------------------------------------------

pub const MIN_BYTES = 256;

/// Fill the w x h box whose top-left byte is `at` (rows `stride` apart) with `v`.
pub var fill: ?*const fn (at: [*]u8, stride: usize, w: usize, h: usize, v: u8) bool = null;

/// Copy the w x h box at `from` (rows `from_stride` apart) onto the box at
/// `at`, leaving out source pixels equal to `key`.
pub var copy: ?*const fn (at: [*]u8, stride: usize, from: [*]const u8, from_stride: usize, w: usize, h: usize, key: ?u8) bool = null;
