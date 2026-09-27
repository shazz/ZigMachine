// --------------------------------------------------------------------------
// The world's long calls, resumable (the model's pkg_a.py + a_pass.py):
//   Redraw       $395D4 (call 6, the respawn; and every submap entry): the
//                24 tile rows to the back screen, that to the playfield copy
//                $66010, erase, spawn, entity pass, flip, wait; the copy to
//                the other screen, erase, entity pass, flip, wait
//   EnterSubmap  $39444: bank, attributes, map, spawn list, the checkpoint,
//                then Redraw
//   (Scroll, calls 7 / 8, is world_scroll.zig: it shares the pieces below)
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
pub fn back() i64 {
    return ((m.rl(F.SCREEN_PTR) ^ 0x8000) + world.SCREEN_OFF) & 0xFFFFFFFF;
}

pub fn build() void {
    world.buildTilemap();
    clock.work(clock.BUILD);
}

pub fn tiles(a0: i64, a1: i64, d0: i64) void {
    world.drawTiles(a0, a1, d0);
    clock.work(if (d0 != 0) clock.DRAW_ROWS_24 else clock.DRAW_ROW);
}

pub fn copy(a0: i64, a1: i64) void {
    world.copyRows(a0, a1, 0xBF);
    clock.work(clock.COPY);
}

/// a_pass.erase: the cost as the slots are before the erase.
pub fn erase() void {
    const n = costs.eraseCost();
    draw.erase();
    clock.work(n);
}

pub fn spawnRows() void {
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
