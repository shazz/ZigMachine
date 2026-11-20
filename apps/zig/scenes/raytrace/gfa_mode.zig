// Keys 4 and 5 of RAYTRACE: NUCLEUS's GfA Punch Raytrace (ST Magazine), as the ST drew
// it (gfa_st.zig, a 16-colour 8-bit plane) and the KESTREL way (gfa_tc.zig, the
// true-colour plane, refined over 16 samples). app.zig owns the planes and the keys;
// this runs a frame's work and the HUD (gfa_hud.zig).
//
// A frame works as the other modes do (bench.zig): for 8 ms of the host's clock, read
// every CHUNK items, or a fixed 512 items without a clock (the harness's deterministic
// frames). An item is one turn of the listing's loops (key 4) or one sample (key 5).
const zg = @import("zigos");
const bench = @import("bench.zig");
const colour = @import("colour.zig");
const work = @import("work.zig");
const hud = @import("gfa_hud.zig");
const St = @import("gfa_st.zig").St;
const tcm = @import("gfa_tc.zig");

pub const Key = enum(u8) { st = 4, kestrel = 5 };
const CHUNK: u32 = 16;

pub const Gfa = struct {
    key: Key,
    st: St,
    work: tcm.Work,
    lfb: *zg.LogicalFB, // key 4's plane
    fb: zg.tc.Fb, // key 5's plane
    bench: bench.Bench,
    frames: u32,
    items: [CHUNK]work.Item,

    /// Starts `key` from the top: a cleared screen, the title, the loops' first turn.
    pub fn restart(self: *Gfa, zigos: *zg.ZigOS, key: Key, lfb: *zg.LogicalFB, fb: zg.tc.Fb) void {
        self.key = key;
        self.lfb = lfb;
        self.fb = fb;
        self.frames = 0;
        self.bench.reset();
        switch (key) {
            .st => self.st.start(zigos, lfb),
            .kestrel => {
                self.work.start();
                fb.fill(0);
                tcm.printTitle(zigos, fb);
            },
        }
        hud.draw(zigos, self.target(), self.counters());
    }

    pub fn finished(self: *const Gfa) bool {
        return switch (self.key) {
            .st => self.st.finished(),
            .kestrel => self.work.converged(),
        };
    }

    pub fn frame(self: *Gfa, zigos: *zg.ZigOS, acc: []colour.Acc) void {
        if (self.finished()) return;
        self.frames += 1;
        if (self.bench.begin()) |t0| {
            while (self.chunk(acc)) {
                if (self.bench.spent(t0, true)) break;
            } else self.bench.finish(t0, true);
        } else {
            var n: u32 = 0;
            while (n < bench.FIXED_PIXELS and self.chunk(acc)) n += CHUNK;
        }
        hud.draw(zigos, self.target(), self.counters());
    }

    /// CHUNK items; false once the picture (key 4) or a pass (key 5) has ended.
    fn chunk(self: *Gfa, acc: []colour.Acc) bool {
        switch (self.key) {
            .st => {
                self.st.step(CHUNK);
                return !self.st.finished();
            },
            .kestrel => {
                const p = self.work.pass;
                const n = self.work.take(&self.items);
                const scr = tcm.Screen{ .fb = self.fb };
                for (self.items[0..n]) |it| tcm.show(self.fb, acc, p, it, tcm.sample(scr, it.x, it.y, it.j));
                return self.work.pass == p;
            },
        }
    }

    fn target(self: *const Gfa) hud.Target {
        return switch (self.key) {
            .st => .{ .st = self.lfb },
            .kestrel => .{ .tc = self.fb },
        };
    }

    fn counters(self: *const Gfa) hud.Counters {
        const done = self.finished();
        return .{
            .key = @intFromEnum(self.key),
            .name = switch (self.key) {
                .st => "4 GFA PUNCH (ST MAGAZINE)",
                .kestrel => "5 GFA PUNCH, KESTREL",
            },
            .frames = self.frames,
            .finished = done,
            .pass = if (self.key == .st) @intFromBool(done) else self.work.pass,
            .line = if (self.key == .st) self.st.line() else 0,
            .trace_ms = @intCast(@min(self.bench.totalMicros() / 1000, 0xFF_FFFF)),
            .clocked = self.bench.clocked,
        };
    }
};
