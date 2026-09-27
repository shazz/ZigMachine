// --------------------------------------------------------------------------
// The world's long calls, resumable (the model's pkg_a.py + a_pass.py):
//   Redraw       $395D4 (call 6, the respawn; and every submap entry): the
//                24 tile rows to the back screen, that to the playfield copy
//                $66010, erase, spawn, entity pass, flip, wait; the copy to
//                the other screen, erase, entity pass, flip, wait
//   EnterSubmap  $39444: bank, attributes, map, spawn list, the checkpoint,
//                then Redraw
//   Scroll       $39658 / $396FA (calls 7 / 8): 8 steps of one new tile row
//                and 8 lines of scroll, the actors frozen and shifted, then
//                the end $3979A
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const clock = @import("clock.zig");
const costs = @import("costs.zig");
const hud = @import("hud.zig");
const draw = @import("draw.zig");
const pass = @import("pass.zig");
const spawn = @import("spawn.zig");
const screen = @import("screen.zig");
const world = @import("world.zig");
const Status = @import("fade.zig").Status;

/// A flip then a wait (a_pass.flip + a_pass.wait_vbl), resumable at each.
pub const FlipWait = struct {
    ph: u1 = 0,

    pub fn step(self: *FlipWait) Status {
        if (self.ph == 0) {
            if (hud.flipBlocked()) return .yield;
            screen.flipA();
            self.ph = 1;
        }
        if (hud.waitBlocked()) return .yield;
        screen.waitA();
        self.ph = 0;
        return .done;
    }
};

/// The playfield corner of the back screen: bchg #15 of screen_ptr, + $510.
fn back() i64 {
    return ((m.rl(F.SCREEN_PTR) ^ 0x8000) + world.SCREEN_OFF) & 0xFFFFFFFF;
}

fn build() void {
    world.buildTilemap();
    clock.work(clock.BUILD);
}

fn tiles(a0: i64, a1: i64, d0: i64) void {
    world.drawTiles(a0, a1, d0);
    clock.work(if (d0 != 0) clock.DRAW_ROWS_24 else clock.DRAW_ROW);
}

fn copy(a0: i64, a1: i64) void {
    world.copyRows(a0, a1, 0xBF);
    clock.work(clock.COPY);
}

/// a_pass.erase: the cost as the slots are before the erase.
fn erase() void {
    const n = costs.eraseCost();
    draw.erase();
    clock.work(n);
}

fn spawnRows() void {
    clock.work(spawn.rows());
}

pub const Redraw = struct {
    pc: enum { first, fw1, fw2, done } = .first,
    fw: FlipWait = .{},

    pub fn start(self: *Redraw) void {
        self.* = .{};
    }

    pub fn step(self: *Redraw) Status {
        while (true) switch (self.pc) {
            .first => {
                build();
                const b = back();
                tiles(world.TILEMAP + 0x100, b, 0x17);
                copy(b, world.PLAYFIELD);
                erase();
                spawnRows();
                pass.world();
                self.pc = .fw1;
            },
            .fw1 => {
                if (self.fw.step() == .yield) return .yield;
                copy(world.PLAYFIELD, back());
                erase();
                pass.world();
                self.pc = .fw2;
            },
            .fw2 => {
                if (self.fw.step() == .yield) return .yield;
                self.pc = .done;
            },
            .done => return .done,
        };
    }
};

pub const EnterSubmap = struct {
    redraw: Redraw = .{},

    /// $39444: bank word 0 -> $CAA0/$399A0, else $EAA0/$39AA0; map_ptr,
    /// spawn_list, spawn_rows = 7, scroll off, the checkpoint; then Redraw.
    pub fn start(self: *EnterSubmap) void {
        const a0 = m.rl(F.SUBMAP);
        const bank0 = m.rw(a0) == 0;
        m.wl(F.TILE_BANK, if (bank0) 0xCAA0 else 0xEAA0);
        m.wl(F.TILE_ATTR, if (bank0) 0x399A0 else 0x39AA0);
        m.wl(F.MAP_PTR, m.rl(a0 + 2));
        m.wl(F.SPAWN_LIST, m.rl(a0 + 0xA));
        m.wb(F.SPAWN_ROWS, 7);
        m.wb(F.SCROLL_ON, 0);
        world.saveCheckpoint();
        clock.work(clock.CHECKPOINT);
        self.redraw.start();
    }

    pub fn step(self: *EnterSubmap) Status {
        return self.redraw.step();
    }
};

pub const Scroll = struct {
    pc: enum { step_, fw, end1, fwe1, fwe2, done } = .step_,
    up: bool = true,
    fw: FlipWait = .{},

    /// $39658 (up: map_row -= 8, the rows 15..8 appear from the top, the
    /// actors +8 a step, probe +0) / $396FA (down: +8, rows 24..31 from the
    /// bottom, -8 a step, probe +32).
    pub fn start(self: *Scroll, up: bool) void {
        self.* = .{ .up = up };
        m.ww(F.MAP_ROW, m.rw(F.MAP_ROW) + @as(i64, if (up) -8 else 8));
        build();
        m.wb(F.SCROLL_ON, 0xFF);
        m.ww(F.SCROLL_DY, if (up) 8 else 0xFFF8);
        m.ww(F.DRAW_TMP, 0);
    }

    pub fn step(self: *Scroll) Status {
        while (true) switch (self.pc) {
            .step_ => {
                const k = m.rw(F.DRAW_TMP);
                const band = if (self.up) world.WORK + (7 - k) * 0x500 else world.WORK_DOWN + k * 0x500;
                const row = if (self.up) world.TILEMAP + 0x1E0 - 0x20 * k else world.TILEMAP + 0x300 + 0x20 * k;
                tiles(row, band, 0);
                copy(if (self.up) band else band - 0x7300, back());
                if (m.rw(F.DRAW_TMP) == 7) {
                    self.pc = .end1;
                    continue;
                }
                erase();
                pass.world();
                self.pc = .fw;
            },
            .fw => {
                if (self.fw.step() == .yield) return .yield;
                m.ww(F.DRAW_TMP, m.rw(F.DRAW_TMP) + 1);
                self.pc = .step_;
            },
            .end1 => { // $3979A
                m.wb(F.SPAWN_ROWS, if (self.up) 4 else 1);
                copy(back(), world.PLAYFIELD);
                erase();
                pass.world();
                self.pc = .fwe1;
            },
            .fwe1 => {
                if (self.fw.step() == .yield) return .yield;
                copy(world.PLAYFIELD, back());
                erase();
                m.wb(F.SCROLL_ON, 0);
                m.ww(F.SCROLL_DY, 0);
                spawnRows();
                pass.world();
                self.pc = .fwe2;
            },
            .fwe2 => {
                if (self.fw.step() == .yield) return .yield;
                self.pc = .done;
            },
            .done => return .done,
        };
    }
};
