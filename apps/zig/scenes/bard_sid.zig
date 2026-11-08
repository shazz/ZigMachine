// --------------------------------------------------------------------------
// BARD SID: the BARD queue's test cart (zg.bard, system table 1.12). No .sid
// file: the cart is the C64 player. Each 50 Hz tick of its tune
// (bard_sid/tune.zig) is a few SID register writes stamped with the cart's
// sample clock (tick k plays at sample 882 k) and put on the cart's ring;
// the sound side (BARD on the board, the AudioWorklet on the page) plays each
// at its sample on cRSID's raw SID, and nobody waits. zg.bard.due paces the
// ticks on the sound side's clock, so the tune keeps time at any frame rate.
// Each beat the cart asks for a mark; when it comes back the background
// flashes (a palette write, the picture never redrawn for it).
//   1  6581   2  8580 (a SID reset at the next tick)
// The text plane is redrawn only every 30 frames, when its numbers changed.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const tune = @import("bard_sid/tune.zig");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const bard = zg.bard;

const PLANE = 0;
const BG: u8 = 0;
const INK: u8 = 1;
const SEL: u8 = 2;
const DIM: u8 = 3;
/// Samples a tick on the cart's 44.1 kHz clock (50 Hz).
pub const TICK: u32 = 882;
/// How late a write may reach the sound side: ~139 ms, a 20 fps board frame and BARD's render.
pub const LEAD: u32 = 6144;
const MAX_TICKS_A_FRAME: u32 = 16;

pub const Demo = struct {
    next: u32, // the next tick to write
    model: bard.Model,
    reset_asked: bool,
    open: bool,
    tries: u32,
    beats: u32,
    flash: u8,
    frames: u32,
    shown: [4]u32,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.* = .{ .next = 0, .model = .mos6581, .reset_asked = false, .open = false, .tries = 0, .beats = 0,
            .flash = 0, .frames = 0, .shown = .{ 0xFFFF_FFFF, 0, 0, 0 } };
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        setBg(fb, 0);
        fb.setPaletteEntry(INK, Color{ .r = 112, .g = 164, .b = 178, .a = 255 });
        fb.setPaletteEntry(SEL, Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
        fb.setPaletteEntry(DIM, Color{ .r = 108, .g = 94, .b = 181, .a = 255 });
    }

    /// Digits from the host (mode = digit - 1): 1 a 6581, 2 an 8580, from the next tick.
    pub fn setShadeMode(self: *Demo, mode: u32) void {
        if (mode > 1) return;
        self.model = if (mode == 0) .mos6581 else .mos8580;
        self.reset_asked = true;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.frames +%= 1;
        // The players come up after the cart's init on some hosts: ask until one answers.
        if (!self.open and self.tries < 120) {
            self.tries += 1;
            self.open = bard.open(LEAD);
        }
        if (!self.open) return;
        var n: u32 = 0;
        while (n < MAX_TICKS_A_FRAME and bard.due(self.next * TICK)) : (n += 1) {
            if (!self.writeTick(self.next)) break; // the ring is full: this tick again next frame
            self.next += 1;
        }
        while (bard.pollEvent()) |e| {
            if (e.kind == @intFromEnum(bard.Kind.mark)) {
                self.beats +%= 1;
                self.flash = 15;
            }
        }
    }

    /// Tick k's writes, all at its sample, or none (false: no room); a SID reset first on tick 0
    /// or when a key asked.
    fn writeTick(self: *Demo, k: u32) bool {
        const t = k * TICK;
        const reset = k == 0 or self.reset_asked;
        const tk = tune.tick(k, reset);
        if (bard.room() < tk.n + 2) return false;
        if (reset) _ = bard.sidReset(t, self.model);
        self.reset_asked = false;
        for (tk.w[0..tk.n]) |w| _ = bard.sidWrite(t, w.reg, w.val);
        if (tk.beat) _ = bard.mark(t, @intCast(tk.row));
        return true;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        if (self.flash > 0) {
            self.flash -= 1;
            setBg(fb, self.flash);
        }
        const now = [4]u32{ self.next, self.beats, bard.dropped() +% bard.eventsLost(), @intFromEnum(self.model) };
        if (self.frames % 30 != 1 or std.mem.eql(u32, &now, &self.shown)) return;
        self.shown = now;
        fb.clearFrameBuffer(BG);
        zigos.printText(fb, "ZIGMACHINE BARD SID", 16, 16, SEL, BG);
        zigos.printText(fb, "THE CART WRITES THE SID, BARD PLAYS IT", 16, 28, DIM, BG);
        zigos.printText(fb, "1  6581    2  8580", 16, 52, INK, BG);
        var buf: [40]u8 = undefined;
        const lines = [_][]const u8{
            std.fmt.bufPrint(&buf, "SID {d}  TICKS {d}", .{ now[3], now[0] }) catch "?",
        };
        zigos.printText(fb, lines[0], 16, 76, INK, BG);
        var b2: [40]u8 = undefined;
        const l2 = std.fmt.bufPrint(&b2, "BEATS {d}  LOST {d}", .{ now[1], now[2] }) catch "?";
        zigos.printText(fb, l2, 16, 90, INK, BG);
        if (!self.open) zigos.printText(fb, "NO BARD QUEUE ON THIS HOST", 16, 114, SEL, BG);
    }
};

/// The C64's blue, brighter by `f` (0..15) on a beat.
fn setBg(fb: anytype, f: u8) void {
    const k: u8 = f * 8;
    fb.setPaletteEntry(BG, Color{ .r = 53 + k, .g = 40 + k, .b = 121 + k, .a = 255 });
}
