// --------------------------------------------------------------------------
// The cart's front: the Empire cracktro (cracktro.zig) runs first, on the
// game's plane and the ST's 50 Hz VBL clock, and owns the keyboard until its
// last trainer answer; then the game starts (rick_dangerous.zig) with the
// trainer flags set. Keys pressed during the cracktro keep their release to
// themselves, so the game never hears a break code it saw no make for.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const cracktro = @import("cracktro.zig");

pub const Front = struct {
    crack: cracktro.Cracktro,
    /// VBLs the cracktro has run.
    vbls: u64 = 0,
    /// Keys (code points < 128) that went down during the cracktro.
    held: u128 = 0,
    /// The game has taken over (its clock started, colour 0 black).
    handed: bool = false,

    /// The cracktro from its start, typing `txt` (cracktro_text.zig). The VBL
    /// count runs on: it is the host's clock, not the cracktro's.
    pub fn start(self: *Front, fb: *zg.LogicalFB, font: []const u8, txt: []const u8) void {
        self.crack = .{ .vt = .{ .fb = fb, .font = font }, .text = txt };
        self.held = 0;
        self.crack.start();
    }

    pub fn active(self: *const Front) bool {
        return self.crack.phase != .done;
    }

    /// Run the cracktro up to the host's time (`limit` VBLs).
    pub fn run(self: *Front, limit: u64) void {
        while (self.active() and self.vbls < limit) : (self.vbls += 1) self.crack.vbl();
    }

    pub fn key(self: *Front, cp: u32) void {
        if (cp < 128) self.held |= @as(u128, 1) << @intCast(cp);
        self.crack.key(cp);
    }

    /// True while a key pressed during the cracktro is still down: the host's
    /// auto-repeat of it is not a make the game should hear.
    pub fn holds(self: *const Front, cp: u32) bool {
        return cp < 128 and self.held & (@as(u128, 1) << @intCast(cp)) != 0;
    }

    /// True if the release is the cracktro's (swallowed).
    pub fn keyUp(self: *Front, cp: u32) bool {
        if (cp >= 128) return self.active();
        const bit = @as(u128, 1) << @intCast(cp);
        if (self.held & bit == 0) return self.active();
        self.held &= ~bit;
        if (self.active()) self.crack.keyUp(cp);
        return true;
    }
};
