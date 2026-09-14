// --------------------------------------------------------------------------
// TEX COPIER's state, as screen.js update() moves it (screen.js:168-205, 244-330).
// No ZigOS here: the logic is tested natively (copier_test.zig).
//
// Half-pixel quantities are kept doubled so they stay integers:
//   raster_scroll2 = 2 * rasterScrollY      (+5 a frame, i.e. 2.5)
//   pos2           = 2 * scrollerRastersPos (+1 a frame, -1280..-1)
// --------------------------------------------------------------------------
const text = @import("text.zig");

/// fadeTimes (screen.js:65): the texture steps one fade level at each.
pub const FADE_TIMES = [_]u32{ 5, 10, 15, 20, 25, 30, 35, 40 };
/// A text line is 7 seconds at 60 fps (screen.js:305).
pub const LINE_FRAMES = 7 * 60;
/// globalTime % 104 restarts the raster windows on the next image (screen.js:182).
pub const RASTER_PERIOD = 104;
pub const RASTER_STEP2 = 5; // rasterScrollY += 2.5
pub const TEXTURE_W2 = 2 * 1280; // the texture's width, doubled
pub const FADE_LEVELS = 8;

pub const Set = enum(u1) { blue, orange }; // fontrastersBlue / fontrastersOrange

pub const Copier = struct {
    global_time: u32,
    time: u32,
    texture_time: u32,
    is_copying: bool,
    ask_to_copy: u2,
    fade_out_completed: bool,
    current_text: u8,
    next_text: u8,
    raster_scroll2: i32,
    pos2: i32,
    raster_texture: u32,
    time_to_raster: bool, // undefined in the JS until the first reset: falsy
    set: Set,
    level: u8, // index into fontrasters<Set>: 0 opaque .. 7 faded out

    pub fn init(self: *Copier) void {
        self.global_time = 0;
        self.time = 0;
        self.texture_time = 0;
        self.is_copying = false;
        self.ask_to_copy = 0;
        self.fade_out_completed = true;
        self.current_text = 0;
        self.next_text = 0;
        self.raster_scroll2 = 0;
        self.pos2 = -TEXTURE_W2 / 2;
        self.raster_texture = 0;
        self.time_to_raster = false;
        self.set = .blue; // currentTexture = fontrastersBlue[0]
        self.level = 0;
    }

    /// One update(). `space` is the 'enter' binding (SPACE), read after the texture
    /// and text have moved, as the JS reads it.
    pub fn update(self: *Copier, space: bool) void {
        self.global_time +%= 1;
        self.time += 1;
        self.texture_time += 1;
        self.raster_scroll2 += RASTER_STEP2;
        // `if (rasterScrollY > 96) this.timeToRaster == false;` compares, it does
        // not assign: once on, the windows stay on.
        self.pos2 += 1;
        if (self.pos2 >= 0) self.pos2 = -TEXTURE_W2 / 2;
        if (self.global_time % RASTER_PERIOD == 0) {
            self.time_to_raster = true;
            self.raster_scroll2 = 0;
            self.raster_texture +%= 1;
        }
        self.selectTexture();
        self.selectText();
        if (space) {
            self.time = 0;
            self.ask_to_copy = 1;
        }
    }

    /// The line on screen: null for the missing text[29].
    pub fn line(self: *const Copier) ?*const [text.LEN]u8 {
        return if (self.is_copying) text.COPYING else text.LINES[self.current_text];
    }

    /// Fade levels removed from the texture: blue removes one colour a level, the
    /// orange texture has six colours, so its levels 6 and 7 are the same picture.
    pub fn removed(self: *const Copier) u8 {
        return if (self.set == .blue) self.level else @min(self.level, 6);
    }

    // selectTexture (244-299): fade in (7 -> 0) while fadeOutCompleted, out (0 -> 7)
    // otherwise; past fadeTimes[7] the texture stays, and a fade out completes.
    fn selectTexture(self: *Copier) void {
        var steps: u8 = 0;
        for (FADE_TIMES) |t| steps += @intFromBool(self.texture_time >= t);
        if (steps < FADE_LEVELS) {
            self.set = if (self.is_copying) .orange else .blue;
            self.level = if (self.fade_out_completed) FADE_LEVELS - 1 - steps else steps;
        } else if (!self.fade_out_completed) {
            self.fade_out_completed = true;
        }
    }

    // selectText (301-330). Copying never leaves: the JS has no way back.
    fn selectText(self: *Copier) void {
        if (self.is_copying) return;
        const index = self.time / LINE_FRAMES;
        if (index != self.next_text or self.ask_to_copy == 1) {
            self.texture_time = 0;
            self.next_text = @truncate(index);
            self.fade_out_completed = false;
            if (self.ask_to_copy == 1) self.ask_to_copy = 2;
        }
        if (self.fade_out_completed and self.current_text != self.next_text) {
            self.texture_time = 0;
            self.current_text = self.next_text;
        }
        if (index > text.LINES.len - 1) self.time = 0;
        if (self.ask_to_copy == 2 and self.fade_out_completed) {
            self.is_copying = true;
            self.texture_time = 0;
            self.current_text = 0;
            self.next_text = 0;
        }
    }
};
