// --------------------------------------------------------------------------
// RACER: the LOCAL real-track benchmark (build option -Dracer_vr=true). freds72's three Virtua Racing tracks, decoded from his
// PICO-8 data carts by tools/racer/vr_import.py into apps/zig/assets/screens/racer_vr/vr_{1,2,3}.ktrk, a git-ignored directory:
// the data is derived from Sega's game and is never committed or shipped. Without the option this file holds no blob and the
// embedFile calls are never analysed, so the files need not exist and the cart is as before. docs/ports/kestrel_racing/M5_VR.md.
// --------------------------------------------------------------------------
const opts = @import("cart_opts");

pub const on: bool = opts.racer_vr;

fn aligned(comptime s: []const u8) []align(4) const u8 {
    const H = struct {
        const blob: [s.len]u8 align(16) = s[0..s.len].*; // WHY: a misaligned word load traps on the board
    };
    return &H.blob;
}

pub const blobs = if (on) [_][]align(4) const u8{
    aligned(@embedFile("../../assets/screens/racer_vr/vr_1.ktrk")),
    aligned(@embedFile("../../assets/screens/racer_vr/vr_2.ktrk")),
    aligned(@embedFile("../../assets/screens/racer_vr/vr_3.ktrk")),
} else [_][]align(4) const u8{};
pub const names = [_][]const u8{ "VR1", "VR2", "VR3" };
/// The oval's ramp 1 is grass; the importer puts each track's ground colour on ramp 1 too.
pub const GROUND_RAMP: usize = 1;
