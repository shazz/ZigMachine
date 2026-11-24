// --------------------------------------------------------------------------
// SID-WIZARD Z: Hermit's SID-Wizard 1.97 tracker with its UI in native Zig (apps/zig/scenes/sidwizard_z/:
// the editor library, a port of the C64 program's screens and key handlers) and the original 6502 PLAYER
// on the repo's 6502 (libs/zig/players/cpu6502.zig), its SID writes on the BARD queue. The sibling cart
// "sidwizard" (apps/ports/sidwizard) runs the whole C64 program on an emulated 6502 + libcRSID: this one
// is for comparing the two on the board. WTFPL (Hermit): docs/ports/sidwizard_z/README.md.
//
// A GEM program: BOOT.WSM on a data disk, opened from the desktop; Shift+F8, Y (or the menu's quit) goes back.
// One overscan plane (400x280), drawn only where it changed (sidwizard_z/video.zig). Integer only.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const dsp = @import("sidwizard_z/display.zig");
const border = @import("sidwizard_z/border.zig");
const kh = @import("sidwizard_z/keys.zig");
const Editor = @import("sidwizard_z/editor.zig").Editor;
const keymap = @import("sidwizard_z/keymap.zig");
const video = @import("sidwizard_z/video.zig");
const Session = @import("sidwizard_z/session.zig").Session;
const c64 = @import("sidwizard_z/c64mem.zig");
const dialog = @import("sidwizard_z/dialog.zig");

const PLANE = 0;
const FLASH_FRAMES = 6; // the cursor's colour flasher
const IO_BYTES = 40 * 1024;
// pepto's C64 palette, then the sprite and raster-bar greys frame.zig measured (indices 16, 17)
const PALETTE = [18][3]u8{
    .{ 0, 0, 0 },       .{ 255, 255, 255 }, .{ 104, 55, 43 },   .{ 112, 164, 178 }, .{ 111, 61, 134 },  .{ 88, 141, 67 },
    .{ 53, 40, 121 },   .{ 184, 199, 111 }, .{ 111, 79, 37 },   .{ 67, 57, 0 },     .{ 154, 103, 89 },  .{ 68, 68, 68 },
    .{ 108, 108, 108 }, .{ 154, 210, 132 }, .{ 108, 94, 181 },  .{ 149, 149, 149 }, .{ 162, 162, 162 }, .{ 223, 223, 223 },
};
const EXIT_TEXT = "DO YOU REALLY WANT TO EXIT? (Y/N)";

pub const App = struct {
    fb: *zg.LogicalFB = undefined,
    s: Session = undefined,
    pad: keymap.Pad = .{},
    sh: video.Shadow = .{},
    scr: dsp.Screen = undefined,
    over: dsp.Overlay = .{},
    bord: border.Border = .{},
    dirty: bool = true,
    frames: u32 = 0,

    pub fn init(self: *App, os: *zg.ZigOS) void {
        g_app = self;
        self.* = .{};
        const ed = &zg.mem.mustAlloc(Editor, 1)[0];
        ed.view = .{}; // field by field: `ed.* = .{}` would put the whole Editor's defaults (~35 KB) in the cart's data
        ed.startup = .{ .open = false };
        ed.reset();
        ed.view.jammode = true; // the C editor starts in jam mode (displayer2.inc: `jammode ldy #1`); Space switches to edit
        self.s = .{ .ed = ed, .io = zg.mem.mustAlloc(u8, IO_BYTES) };
        c64.attach(@ptrCast(zg.mem.mustAlloc(u8, 65536).ptr), @ptrCast(zg.mem.mustAlloc(c64.SidWrite, c64.QCAP).ptr));
        self.bord = border.Border.init();
        const fb = &os.lfbs[PLANE];
        self.fb = fb;
        fb.is_enabled = true;
        fb.openBorders(.all); // 400x280, the flicker HBL on every line: the C64's border is part of the picture
        for (PALETTE, 0..) |c, i| fb.setPaletteEntry(@intCast(i), .{ .r = c[0], .g = c[1], .b = c[2], .a = 255 });
        os.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        self.sh.invalidate();
        if (!self.s.openStart()) zg.Console.log("sidwizard_z: no start song ({?})\n", .{self.s.last_fail});
    }

    pub fn ownsKeyboard(self: *App) u32 {
        _ = self;
        return 1;
    }
    pub fn pollCart(self: *App) i32 {
        return if (self.s.wants_quit) 4 else 0; // 4: back to the desktop
    }

    pub fn key(self: *App, cp: u32) void {
        self.deliver(self.pad.press(cp));
    }
    pub fn input(self: *App, dir: u32) void {
        self.deliver(self.pad.arrow(dir));
    }
    pub fn inputRelease(self: *App, dir: u32) void {
        self.pad.arrowUp(dir);
    }

    fn deliver(self: *App, out: keymap.Out) void {
        switch (out) {
            .none => {},
            .exit_dialog => self.s.exit_ask = true,
            .key => |k| self.handle(k),
        }
        self.dirty = true;
    }

    fn handle(self: *App, k: kh.Key) void {
        if (self.s.exit_ask) { // the C64 program's host dialog: Y quits, any other key goes on
            self.s.exit_ask = false;
            if (k.code == kh.y_) self.s.quit();
            return;
        }
        self.s.apply(self.s.ed.key(k));
    }

    pub fn update(self: *App, os: *zg.ZigOS, dt: f32) void {
        _ = os;
        _ = dt;
        self.frames +%= 1;
        if (self.pad.tick()) |k| self.deliver(.{ .key = k });
        if (self.s.play.pump(self.s.ed)) self.dirty = true;
        if (self.frames % FLASH_FRAMES == 0) {
            self.s.ed.view.curcolc +%= 1;
            if (!self.s.ed.view.filer.open) self.dirty = true; // a dialog does not flash
        }
    }

    pub fn render(self: *App, os: *zg.ZigOS, dt: f32) void {
        _ = dt;
        if (!self.dirty) return;
        self.dirty = false;
        const ed = self.s.ed;
        if (ed.view.filer.open) self.s.label();
        ed.render(&self.scr);
        if (self.s.exit_ask) text(&self.scr, 11, 3, EXIT_TEXT);
        if (ed.view.filer.open) { // the file dialog: text in the system font, the editor repaints whole after it
            dialog.draw(os, self.fb, &self.scr);
            self.sh.invalidate();
            return;
        }
        ed.overlay(&self.over);
        self.s.play.readouts(&self.over);
        border.upperRender(&self.bord, &self.over);
        border.lowerRender(&self.bord, &self.over);
        const cur: video.Cursor = .{ .x = self.over.cursor_x, .y = self.over.cursor_y, .wide = self.over.cursor_2x, .col = self.over.cursor_col };
        video.present(&self.sh, self.fb.fb[0 .. video.W * video.H], &self.scr, &self.over, &self.bord, if (ed.view.menumode) null else cur);
    }
};

fn text(scr: *dsp.Screen, row: usize, col: usize, s: []const u8) void {
    for (s, 0..) |c, i| {
        scr.chars[row][col + i] = c;
        scr.colours[row][col + i] = 1;
    }
}

// keyUp: Shift, Control and held keys come up. demo_main forwards no release, so the cart exports its own
// (notepad.zig's pattern), guarded so only this cart carries it.
var g_app: ?*App = null;
fn keyUp(cp: u32) callconv(.c) void {
    (g_app orelse return).pad.release(cp);
}
comptime {
    if (@import("../cart.zig").Cart == App) @export(&keyUp, .{ .name = "keyUp" });
}
