// --------------------------------------------------------------------------
// SB SPIKE: the feasibility spike for porting Suicide Barbie (The Black Lotus, PSP,
// Breakpoint 2007, MIT) to KESTREL. Its heaviest scene, mix3 (12,147 triangles:
// three girls in a blender, chrome, the jar, the room), textured on one 8-bit plane,
// 320x180 letterboxed, the 16 s camera clip looped. It measures how many textured
// triangles ZIGGY (geometry) + CHISEL AFFINE (pixels) draw a frame.
// prototypes/suicide_barbie_re/ANALYSIS.md section 6 is the spec.
//
//   1-4    the LOD: 12,147 / 6,100 / 4,097 / 3,082 triangles (tools/sb_mix3/decimate.py)
//   E      the env-mapped meshes (redENV, silverENV, addENV) on / off
//   A      CHISEL's lazy wait on / off (on: AFFINE runs while the CPU sets up the next spans)
//   C      the per-frame CHISEL clear on / off (the backdrop covers the view)
//   P      pause the clip;  Esc back to the menu
//
// Per frame (integers only): keys -> model-view (anim.zig), vertices -> screen
// (xform.zig), cull + a depth bucket a triangle (frame.zig), far to near spans
// (raster.zig) fired as AFFINE ops of 2,048 spans (sink.zig). Two planes flip: the
// one shown is enabled, the next frame is drawn into the other (disabled planes cost
// FRESCO nothing), both carrying the same palette.
// Not in the spike: bloom, the glass's lerp (its dark texels are the colour key),
// perspective-correct UVs, near-plane clipping, music, streaming.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const data = @import("sb_spike/data.zig");
const anim = @import("sb_spike/anim.zig");
const frame = @import("sb_spike/frame.zig");
const xform = @import("sb_spike/xform.zig");
const sink = @import("sb_spike/sink.zig");
const Hud = @import("sb_spike/hud.zig").Hud;

const K_ESC: u32 = 0xE012;

pub const Demo = struct {
    blitter: zg.Blitter = .{},
    f: frame.Frame = undefined,
    sink: sink.Sink = undefined,
    hud: Hud = .{},
    time: u32 = 0, // anim.zig's clip time, 30 Hz frames Q16
    lod: usize = 0,
    env: bool = true,
    async_: bool = true,
    clear: bool = false,
    paused: bool = false,
    back: usize = 0, // the plane this frame is drawn into (the other one is on screen)
    wants_quit: bool = false,
    frames: u32 = 0,

    pub fn init(self: *Demo, zigos: *zg.ZigOS) void {
        self.* = .{}; // the cart is zeroed, not default-initialised
        self.f = .{
            .pv = zg.mem.mustAlloc(xform.PV, data.MAX_VERTS),
            .depth = zg.mem.mustAlloc(u16, data.MAX_VERTS),
            .kept = zg.mem.mustAlloc(frame.Rec, frame.MAX_KEPT),
            .sorted = zg.mem.mustAlloc(frame.Rec, frame.MAX_KEPT),
            .key = zg.mem.mustAlloc(u16, frame.MAX_KEPT),
            .count = &zg.mem.mustAlloc([frame.BUCKETS + 1]u32, 1)[0],
        };
        self.sink = .{ .buf = zg.mem.mustAlloc(sink.Span, 2 * sink.CHUNK) };
        self.blitter.init();
        var pal: [256]zg.Color = undefined;
        var best: u32 = 0;
        for (data.layout.palette, 0..) |c, i| {
            pal[i] = .{ .r = c[0], .g = c[1], .b = c[2], .a = 255 };
            const lum = @as(u32, c[0]) + c[1] + c[2];
            if (lum > best) {
                best = lum;
                self.hud.ink = @intCast(i);
            }
        }
        for (0..2) |p| {
            const fb = &zigos.lfbs[p];
            fb.setPalette(pal);
            self.blitter.clear(fb, 0);
            fb.is_enabled = p == 0;
        }
        zigos.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        zigos.blitAsync(self.async_);
        zg.Console.log("sb_spike: {} KB of mix3 data, cart RAM free {} KB", .{ data.atlas.len / 1024, zg.mem.free() / 1024 });
    }

    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1;
    }

    pub fn key(self: *Demo, cp: u32) void {
        switch (cp) {
            K_ESC => self.wants_quit = true,
            '1'...'4' => self.lod = cp - '1',
            'e', 'E' => self.env = !self.env,
            'a', 'A' => self.async_ = !self.async_,
            'c', 'C' => self.clear = !self.clear,
            'p', 'P', ' ' => self.paused = !self.paused,
            else => {},
        }
    }

    pub fn update(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = zigos;
        self.hud.workStart();
        if (self.paused) return;
        // The host hands the frame time in ms as an f32; one conversion a frame (not per
        // vertex) turns it into the clip's 30 Hz Q16 clock, capped at 4 keys a frame.
        const step: u32 = @intFromFloat(@min(@max(dt, 0.0), 133.0) * (30.0 * 65536.0 / 1000.0));
        self.time = (self.time + step) % anim.LOOP;
    }

    pub fn render(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = dt;
        zigos.blitAsync(self.async_);
        // Show what the last frame drew, draw this one into the other plane.
        const done = self.back;
        zigos.lfbs[done].is_enabled = true;
        zigos.lfbs[done ^ 1].is_enabled = false;
        self.back = done ^ 1;
        const draw_to = self.back;
        const fb = &zigos.lfbs[draw_to];
        if (self.clear) self.blitter.fill(fb, 0, frame.Y_MIN, 320, frame.Y_MAX - frame.Y_MIN, 0);
        self.f.animate(self.time);
        self.f.transform(self.lod, self.env);
        self.f.cullBin(self.lod);
        self.f.sort();
        self.sink.begin(fb);
        self.f.emit(sink.Sink, &self.sink);
        self.sink.swap();
        self.log();
        self.hud.draw(zigos, fb, draw_to, .{ .lod = self.lod, .tris = data.counts(self.lod).tris, .drawn = self.f.stats.drawn, .ops = self.sink.ops, .env = self.env, .async_ = self.async_, .clear = self.clear });
        self.hud.workEnd();
    }

    /// The measurement's counts, every 64 frames (apps/sb_spike_headless.mjs reads them).
    fn log(self: *Demo) void {
        self.frames +%= 1;
        if (self.frames % 64 != 0) return;
        const st = self.f.stats;
        const c = data.counts(self.lod);
        zg.Console.log("sb_spike: lod {} verts {} tris {} near {} off {} culled {} drawn {} dropped {} spans {} pixels {} ops {}", .{
            self.lod + 1, c.verts, st.submitted, st.near, st.off, st.culled, st.drawn, st.dropped, self.sink.spans, self.sink.pixels, self.sink.ops,
        });
    }
};
