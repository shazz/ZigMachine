// --------------------------------------------------------------------------
// The scroll, resumable (the model's pkg_a.py + a_pass.py): $39658 / $396FA
// (calls 7 / 8): 8 steps of one new tile row and 8 lines of scroll, the
// actors frozen and shifted, then the end $3979A. The pieces it shares with
// the redraw (the tile rows, the copies, the erase, the spawn probe, each
// with its cost on the long calls' clock) are world_calls.zig's.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const pass = @import("pass.zig");
const world = @import("world.zig");
const wc = @import("world_calls.zig");
const Status = @import("fade.zig").Status;

pub const Scroll = struct {
    pc: enum { step_, fw, end1, fwe1, fwe2, done } = .step_,
    up: bool = true,
    fw: wc.FlipWait = .{},

    /// $39658 (up: map_row -= 8, the rows 15..8 appear from the top, the
    /// actors +8 a step, probe +0) / $396FA (down: +8, rows 24..31 from the
    /// bottom, -8 a step, probe +32).
    pub fn start(self: *Scroll, up: bool) void {
        self.* = .{ .up = up };
        m.ww(F.MAP_ROW, m.rw(F.MAP_ROW) + @as(i64, if (up) -8 else 8));
        wc.build();
        m.wb(F.SCROLL_ON, 0xFF);
        m.ww(F.SCROLL_DY, if (up) 8 else 0xFFF8);
        m.ww(F.DRAW_TMP, 0);
    }

    pub fn step(self: *Scroll) Status {
        while (true) switch (self.pc) {
            .step_ => self.band(),
            .fw => {
                if (self.fw.step() == .yield) return .yield;
                m.ww(F.DRAW_TMP, m.rw(F.DRAW_TMP) + 1);
                self.pc = .step_;
            },
            .end1, .fwe1 => if (self.end() == .yield) return .yield,
            .fwe2 => {
                if (self.fw.step() == .yield) return .yield;
                self.pc = .done;
            },
            .done => return .done,
        };
    }

    /// One of the 8 steps: the new tile row into its band, the band to the
    /// back screen; the actors (not after the 8th step), then flip + wait.
    fn band(self: *Scroll) void {
        const k = m.rw(F.DRAW_TMP);
        const b = if (self.up) world.WORK + (7 - k) * 0x500 else world.WORK_DOWN + k * 0x500;
        const row = if (self.up) world.TILEMAP + 0x1E0 - 0x20 * k else world.TILEMAP + 0x300 + 0x20 * k;
        wc.tiles(row, b, 0);
        wc.copy(if (self.up) b else b - 0x7300, wc.back());
        if (m.rw(F.DRAW_TMP) == 7) {
            self.pc = .end1;
            return;
        }
        wc.erase();
        pass.world();
        self.pc = .fw;
    }

    /// $3979A: the playfield copy both ways around a flip + wait, the scroll off.
    fn end(self: *Scroll) Status {
        if (self.pc == .end1) {
            m.wb(F.SPAWN_ROWS, if (self.up) 4 else 1);
            wc.copy(wc.back(), world.PLAYFIELD);
            wc.erase();
            pass.world();
            self.pc = .fwe1;
            return .done;
        }
        if (self.fw.step() == .yield) return .yield;
        wc.copy(world.PLAYFIELD, wc.back());
        wc.erase();
        m.wb(F.SCROLL_ON, 0);
        m.ww(F.SCROLL_DY, 0);
        wc.spawnRows();
        pass.world();
        self.pc = .fwe2;
        return .done;
    }
};
