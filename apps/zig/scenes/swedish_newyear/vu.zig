// The volume watch SYNC #2 and OMEGA share (screen.js's oldvoiceA..C and
// hvoiceA..C globals): a voice whose volume CHANGED this frame lights to 7,
// otherwise it decays one a frame to 0.
//   if (oldvoiceA != vol) hvoiceA = 7; else if (hvoiceA-- < 1) hvoiceA = 0;
// The remake reads its YM player's voiceX.vol; here it is the chip's own
// amplitude register (8, 9, 10: level + envelope bit), mirrored into
// zigos.ym_regs from the SNDH the 68000 is playing.
pub const Vu = struct {
    old: [3]u8,
    h: [3]i32,

    pub fn init(self: *Vu) void {
        self.old = .{ 0, 0, 0 };
        self.h = .{ 0, 0, 0 };
    }

    pub fn watch(self: *Vu, regs: *const [16]u8) void {
        for (0..3) |c| {
            const vol = regs[8 + c] & 0x1F;
            if (self.old[c] != vol) {
                self.h[c] = 7;
            } else if (self.h[c] < 1) {
                self.h[c] = 0;
            } else {
                self.h[c] -= 1;
            }
        }
    }

    /// After the frame's drawing: oldvoiceX = voiceX.vol.
    pub fn remember(self: *Vu, regs: *const [16]u8) void {
        for (0..3) |c| self.old[c] = regs[8 + c] & 0x1F;
    }
};
