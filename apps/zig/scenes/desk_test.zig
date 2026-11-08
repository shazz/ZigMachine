// --------------------------------------------------------------------------
// DESK TEST: the desk mode (HW 1.17.0, docs/HW_API.md "Desk mode"): plane 0 alone, 640x480
// palette indices shown 1:1. It boots into the desk and draws a known picture once:
//
//   - 256 cells of 40x30 pixels, cell c = column + 16 * row in colour c (all of palette 0);
//   - a one-pixel checker (colours 0 and 255) in the top-left cell: 1:1, no line doubling;
//   - a one-pixel frame in colour 255 round the whole 640x480;
//   - two lines of 8x8 text.
//
// Key 1 enters the desk again, key 2 leaves it for a low-res plane (a different picture on the
// same buffer). Both redraw once, so the cart costs nothing a frame. Where the machine has no
// desk mode (an older board bitstream: hwDeskAvailable() = 0) it stays low-res and says so.
// apps/desk_check.mjs checks the pixels; desk_test/picture.zig is the picture both share.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const pic = @import("desk_test/picture.zig");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const Mode = enum { desk, low, unavailable };

pub const Demo = struct {
    want: Mode,
    shown: ?Mode,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.* = .{ .want = .desk, .shown = null };
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        for (0..256) |i| fb.palette[i] = pic.paletteWord(@intCast(i));
    }

    /// Digits from the host (mode = digit - 1): 1 the desk, 2 low res.
    pub fn setShadeMode(self: *Demo, mode: u32) void {
        if (mode == 0) self.want = .desk;
        if (mode == 1) self.want = .low;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[0];
        var mode = self.want;
        if (mode == .desk and self.shown == .unavailable) return; // asked once: no desk here
        if (mode == .desk and self.shown != .desk) fb.setDeskPlane() catch {
            mode = .unavailable;
        };
        if (mode != .desk and self.shown == .desk) fb.leaveDesk();
        if (self.shown == mode) return;
        self.shown = mode;
        if (mode == .desk) return drawDesk(zigos, fb);
        fb.clearFrameBuffer(pic.LOW_BG);
        zigos.printText(fb, "ZIGMACHINE DESK TEST", 16, 16, pic.INK, pic.LOW_BG);
        const line = if (mode == .low) "LOW RES. KEY 1: THE DESK" else "NO DESK MODE ON THIS MACHINE";
        zigos.printText(fb, line, 16, 32, pic.INK, pic.LOW_BG);
    }
};

fn drawDesk(zigos: *ZigOS, fb: *zg.LogicalFB) void {
    pic.paint(fb.fb[0 .. pic.W * pic.H]);
    zigos.printText(fb, pic.TITLE, pic.TEXT_X, pic.TEXT_Y, pic.INK, 0);
    zigos.printText(fb, pic.HELP, pic.TEXT_X, pic.TEXT_Y + 10, pic.INK, 0);
}
