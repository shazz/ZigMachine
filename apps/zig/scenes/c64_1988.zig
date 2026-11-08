// --------------------------------------------------------------------------
// 1988 (Tristar & Red Sector Inc., C64, Only Sprites compo, 16 Jan 2021, out of competition).
// Code Shazz, graphics Elko, music Barney Gumble ("Ultimate Intro 12"). CSDb release 198974.
// Ported from the depacked original (prototypes/1988_re/ANALYSIS.md says how it works).
//
// Only sprites, so only sprites here too: one empty 400x280 overscan plane, and the eight
// hardware sprites drawn into it by c64_1988/vic.zig, a model of the VIC-II's sprite unit,
// replaying the register writes the original's IRQ chains make (c64_1988/logo.zig, wipe.zig,
// grid.zig, sequenced by show.zig) at their raster lines and cycles. The multiplexing, the
// vertical stretch of part 3 and the open borders are the C64's own rules, not effects drawn
// to look like them; the plane holds exactly the C64's picture (VICE x64sc, colodore palette:
// tools/c64/vicmodel.py and the harness compare). The model decides line by line which row
// each sprite shows; the rows are painted as rectangles at the frame's end (vic_runs.zig,
// vic_paint.zig: CHISEL blits of blocks expanded once).
//
// The C64's borders are the machine's: physical row r = raster line r + 11, column c = sprite
// X c - 16, so the C64's 320x200 window is the machine's. Where the C64 opens a border, the
// plane's copper list opens the machine's with a FLICK on the same rows. The border colour
// is a real raster, as colour 0 is on an ST: per line, BACKGROUND (the closed borders, from
// the global HBL, with BEAM for part 2's mid-line switches) and the plane's colour 0 (the
// window and the opened borders, from the copper list: c64_1988/raster.zig). The C64 runs at
// 50 Hz: a C64 frame every 6/5 machine frames.
//
// Z toggles the ZIG mode (c64_1988/zig_mode.zig): the same frames at 60 Hz, interpolated,
// on a copper list alone. Escape leaves (the cart owns its keys).
//
// Music: Ultimate Intro 12 by Barney Gumble (PSID, init $1000, play $1003, 8580), the intro's
// own tune, played from the cart's memory by the .sid player (cRSID: BARD native, page wasm).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const show_mod = @import("c64_1988/show.zig");
const vic = show_mod.vic;
const assets = @import("c64_1988/assets.zig");
const raster = @import("c64_1988/raster.zig");
const col = @import("c64_1988/colours.zig");
pub const zig_mode = @import("c64_1988/zig_mode.zig");

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const rgba = col.rgba;

pub const MUSIC_SID = true;
pub const SONG = @embedFile("../assets/screens/c64_1988/ultimate_intro_12.sid");
const K_ESC: u32 = 0xE012; // demo_main.zig's code for Escape

var g_out: ?*const vic.Out = null; // HBL handlers take no user pointer

// The border colour, a raster: the C64 line's colour, and BEAM for a switch mid-line (part
// 2's wipe on the border lines). Only black is an exact ST colour among the 16, and black is
// the only colour switched to mid-line on the visible lines.
fn borderHbl(zigos: *ZigOS, line: u16) void {
    const out = g_out orelse return;
    if (line >= vic.ROWS) return;
    zigos.setBackgroundColor(zg.Color.fromRGBA(rgba(out.border[line])));
    if (out.split_x[line] != 0 and out.split_c[line] == 0) {
        zg.beam.begin();
        zg.beam.write(out.split_x[line], 0x000);
    }
}

// Without VRAM for the copper list, the plane's line from its HBL: colour 0 is the line's
// border colour, and the borders open where the C64's are (raster.zig says the same).
fn planeHbl(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    const out = g_out orelse return;
    if (line >= vic.ROWS) return;
    fb.palette[0] = rgba(out.border[line]);
    const band = line < zg.VERTICAL_BORDERS_HEIGHT or line >= zg.VERTICAL_BORDERS_HEIGHT + zg.HEIGHT;
    if (if (band) out.vopen[line] else out.sides[line]) fb.flickerBorder();
}

// CHISEL's keyed copy of an expanded block's rectangle, from cart RAM into the plane.
fn blit(ctx: *anyopaque, x: u16, y: u16, src: []const u8, src_w: u16, sx: u16, sy: u16, w: u16, h: u16) void {
    const self: *Demo = @ptrCast(@alignCast(ctx));
    self.blitter.blitImage(self.fb, @intCast(x), @intCast(y), src, src_w, sx, sy, w, h, 0);
}

pub const Demo = struct {
    show: show_mod.Show = undefined,
    out: vic.Out = undefined,
    zig: zig_mode.Zig = undefined,
    frames: u32 = 0, // machine frames (60 Hz)
    list: []u32 = &.{}, // the plane's copper list (raster.zig); empty: the plane HBL plays it
    blitter: zg.Blitter = .{},
    fb: *LogicalFB = undefined,
    blocks: vic.cache.Cache = undefined, // the sprite blocks, expanded (vic_cache.zig)
    wants_quit: bool = false,
    z_pressed: bool = false,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setOverscanBuffer();
        col.install(fb);
        self.fb = fb;
        self.blitter.init();
        // ~290 KB of expanded blocks, from the RAM arena (zeroed; no bytes in the cart)
        const images = zg.mem.mustAlloc([vic.cache.IMAGE]u8, vic.cache.SLOTS);
        self.blocks = .{ .images = images[0..vic.cache.SLOTS] };
        self.out = .{ .pix = fb.fb[0..vic.Out.ROWS_COLS], .cache = &self.blocks, .blit = .{ .ctx = self, .f = blit } };
        self.show = show_mod.Show.init(assets.all);
        self.zig.reset(); // field by field: `.{}` of a 16 KB struct would be a 16 KB data segment
        zig_mode.current = &self.zig;
        self.frames = 0;
        self.wants_quit = false;
        self.z_pressed = false;
        g_out = &self.out;
        fb.setFrameBufferHBLHandlerPure(zg.OVERSCAN_MAGIC_X, planeHbl);
        // The copper list takes over the handler's job (its FLICK fires at the position the
        // handler was registered at, which clearing the handler keeps); no VRAM: the handler.
        self.list = &.{};
        if (fb.copperList(raster.WORDS)) |l| {
            @memset(l, 0);
            l[0] = 0xF000_0000 | 511 << 19;
            self.list = l;
            fb.clearFrameBufferHBLHandler();
        }
        zigos.setHBLHandler(borderHbl);
        if (MUSIC_SID) _ = zg.requestSongBytes(SONG, .sid, 0);
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) self.wants_quit = true;
        if (cp == 'z' or cp == 'Z') self.z_pressed = true;
    }

    /// C64 frame n is due on machine frame ceil(6n/5): the 50 Hz picture on a 60 Hz machine.
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        self.frames += 1;
        if (self.z_pressed) {
            self.z_pressed = false;
            if (!self.zig.on) self.enterZig(zigos) else self.zig.leaving = true;
        }
        const due = self.frames * 5 / 6;
        if (self.zig.on) {
            if (!self.zig.leaving or self.show.frames != due) return self.updateZig(due);
            self.leaveZig(zigos); // at a C64 frame boundary: the default's picture, as it is
            return;
        }
        if (self.show.frames >= due) return;
        while (self.show.frames < due) self.show.step(&self.out);
        raster.build(self.list, &self.out, rgba, false);
        col.setGroups(self.fb, &self.out.groups);
    }

    // ZIG: the model one C64 frame ahead, a picture every machine frame (zig_mode.zig).
    fn updateZig(self: *Demo, due: u32) void {
        const k: u8 = @intCast(self.frames * 5 % 6);
        const target = if (k == 0) due else due + 1;
        var stepped = false;
        while (self.show.frames < target) {
            self.show.step(&self.out);
            self.zig.stepped(&self.out);
            stepped = true;
        }
        if (stepped) raster.build(self.list, &self.out, rgba, true);
        self.zig.draw(self.out.pen(self.show.mem()), k, self.show.frames == due);
        col.setGroups(self.fb, &self.zig.groups);
    }

    fn enterZig(self: *Demo, zigos: *ZigOS) void {
        if (self.list.len == 0) return; // no copper list: no ZIG mode
        self.out.spans.erase(self.out.pix);
        self.out.paint = false;
        self.zig.on = true;
        self.zig.leaving = false;
        self.zig.b.take(&self.out.runs);
        self.zig.a = self.zig.b;
        zigos.removeHBLHandler();
        raster.build(self.list, &self.out, rgba, true);
    }

    fn leaveZig(self: *Demo, zigos: *ZigOS) void {
        self.zig.spans.erase(self.out.pix);
        self.zig.on = false;
        self.out.paint = true;
        self.out.end(self.show.mem()); // the runs of C64 frame `due`, as the default drew them
        raster.build(self.list, &self.out, rgba, false);
        col.setGroups(self.fb, &self.out.groups);
        zigos.setHBLHandler(borderHbl);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt;
    }
};

// The harness's exports exist only when this scene IS the cart (rno_natrium's pattern).
comptime {
    if (@import("../cart.zig").Cart == Demo) {
        _ = @import("c64_1988/zig_api.zig");
    }
}
