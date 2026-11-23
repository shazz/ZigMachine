// --------------------------------------------------------------------------
// NFO VIEWER: the zigdemo NFO / ASCII-art viewer (libs/zig/zigdemo/nfo.zig) in the look of an
// Amiga ASCII viewer, on the desk plane (640x480, square pixels). The sample NFO is our own
// (nfo_viewer/sample.nfo.txt, UTF-8, converted to CP437 while the cart compiles). It paints the
// whole text once into a tall buffer and only pans the plane's base (1 px every 2 frames after
// 1.5 s, back to the top after the end); a bar at the bottom stays put. A loader cart does the
// same with its own NFO and its own meaning for the keys: here A restarts from the top, B jumps
// to the end, up/down scroll by hand, Esc leaves. Where the machine has no desk mode
// (hwDeskAvailable() = 0) it says so in low res. apps/harness/nfo_viewer_check.mjs checks the pixels.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const nfo_lib = @import("nfo");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const K_ESC: u32 = 0xE012; // docs/sealed-loader.js KEY_CODES
const K_PGUP: u32 = 0xE01C;
const K_PGDN: u32 = 0xE01D;
const sample = nfo_lib.cp437.comptimeFromUtf8(@embedFile("nfo_viewer/sample.nfo.txt"));
const config = nfo_lib.Config{
    .frames_per_px = 2,
    .start_delay = 90,
    .end = .bounce, // back up at the same speed (Matt, 16 Nov), not a jump to the top
    .end_hold = 180,
    .prompt = "up/down or PgUp/PgDn to scroll, SPACE to leave",
    .keys = "",
};

pub const Demo = struct {
    nfo: nfo_lib.Nfo,
    shown: bool,
    unavailable: bool,
    wants_quit: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.nfo = nfo_lib.Nfo.init(sample, config) catch |e| @panic(@errorName(e));
        self.shown = false;
        self.unavailable = false;
        self.wants_quit = false;
        // The desk's bars around the 640x480 show the border colour: the NFO's own background blue (Matt, 16 Nov).
        zigos.setBackgroundColor(Color{ .r = 0x40, .g = 0x5F, .b = 0x89, .a = 255 });
        zigos.lfbs[0].is_enabled = true;
    }

    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1; // the keys are the cart's: Esc leaves it
    }

    /// Space (or Esc) leaves; PgUp / PgDn scroll a page (Matt, 16 Nov), which stops the automatic scroll.
    pub fn key(self: *Demo, cp: u32) void {
        const page: i32 = @intCast(self.nfo.page());
        switch (cp) {
            ' ', K_ESC => self.wants_quit = true,
            K_PGUP => self.nfo.userScroll(-page),
            K_PGDN => self.nfo.userScroll(page),
            else => {},
        }
    }

    /// The d-pad / arrows: 0 up, 1 down.
    pub fn input(self: *Demo, dir: u32) void {
        if (dir == 0) self.nfo.userScroll(-18);
        if (dir == 1) self.nfo.userScroll(18);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[0];
        if (self.unavailable) return;
        if (!self.shown) {
            nfo_lib.plane.attach(&self.nfo, fb) catch return self.noDesk(zigos);
            self.shown = true;
            return;
        }
        nfo_lib.plane.frame(&self.nfo, fb);
    }

    // No desk mode here (an older board bitstream): a plain low-res message, once.
    fn noDesk(self: *Demo, zigos: *ZigOS) void {
        self.unavailable = true;
        const fb = &zigos.lfbs[0];
        fb.palette[0] = 0xFF00_0000;
        fb.palette[1] = 0xFFFF_FFFF;
        fb.clearFrameBuffer(0);
        zigos.printText(fb, "NFO VIEWER NEEDS THE DESK MODE", 16, 16, 1, 0);
    }
};
