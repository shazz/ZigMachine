// --------------------------------------------------------------------------
// The SYNC load (F1 on the menu): SYNC #1, then Space, SYNC #2 -- both run on
// the part's own memory (st.zig) at the original's 50 Hz: one main-loop pass
// (SYNC #1) or one VBL (SYNC #2) every 20 ms of host time, so a 60 Hz host
// shows five frames in six, as a 50 Hz demo on a 60 Hz display does.
// Every entry is a fresh start, as on the ST, where F1 reads the part from the
// disk again.
// --------------------------------------------------------------------------
const st = @import("st.zig");
const show = @import("st_show.zig");
const sync1 = @import("sync1.zig");
const sync2 = @import("sync2.zig");
const assets = @import("assets.zig");
const ram = @import("ram.zig");

pub const Sync = struct {
    r: st.Ram,
    shown: sync1.Shown,
    second: bool, // SYNC #2
    screen2: u32,
    colour1: u16, // SYNC #2's flash
    acc: f32,

    /// The part's tracks are in the part buffer (assets.load(.sync)).
    pub fn enter(self: *Sync) void {
        const part = ram.buf.part[0..assets.SYNC_RAM];
        @memset(part[assets.SYNC_IMAGE..], 0);
        self.r = .{ .base = sync1.BASE, .m = part };
        sync1.init(&self.r);
        self.second = false;
        self.colour1 = 0;
        self.acc = 0;
        self.vbl();
        self.capture();
    }

    /// Space in SYNC #1.
    pub fn toSecond(self: *Sync) void {
        self.screen2 = sync2.enter(&self.r);
        self.second = true;
        self.colour1 = 0;
        self.capture();
    }

    /// One host frame: show what was captured, run the VBLs due, capture.
    pub fn frame(self: *Sync, fb: []u8, dt: f32) void {
        show.present(fb);
        self.acc += dt;
        while (self.acc >= st.VBL_MS) : (self.acc -= st.VBL_MS) self.vbl();
        self.capture();
    }

    fn vbl(self: *Sync) void {
        if (self.second) {
            self.colour1 = sync2.vbl(&self.r);
        } else {
            self.shown = sync1.iteration(&self.r);
        }
    }

    fn capture(self: *Sync) void {
        var pal: show.Palettes = undefined;
        if (self.second) {
            for (&pal) |*line| {
                for (line, 0..) |*c, i| c.* = self.r.w(sync2.PALETTE + 2 * @as(u32, @intCast(i)));
                line[1] = self.colour1;
            }
            show.capture(&self.r, self.screen2, &pal, pal[0][0], pal[0][0]);
            return;
        }
        for (&pal, 0..) |*line, y| {
            line[0] = sync1.lineColour0(&self.r, self.shown, y);
            for (1..16) |i| line[i] = sync1.lineColour(&self.r, self.shown, y, i);
        }
        const last = self.r.w(sync1.RASTERS + 2 * 199); // Timer B's last write
        show.capture(&self.r, self.shown.screen, &pal, self.r.w(self.shown.palette), last);
    }
};
