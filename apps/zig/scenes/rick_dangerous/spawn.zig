// --------------------------------------------------------------------------
// Spawning (the model's a_spawn.py, literal): $39082 the probe rows, $390CE a
// row of the submap's spawn list, and $391C4 a slot filled from its record
// and its type descriptor $377B6 (spawn_fill.zig). Each routine returns the ORIGINAL's cycles for
// the path it took (measured per instruction, checked against the 68000 on
// every submap): the long calls' clock adds them.
//
// A spawn record (6 bytes, the list ends with the word $00FF): row.w (low 3
// bits = the y sub-row), type.b (bit7 = used/killed), flags.b (the trigger
// byte +$46; bit1 = the moving platform in slot 0, bit2 = deadly while idle
// and no y snap), x/8|ysub.b, zone.b.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const fill = @import("spawn_fill.zig").fill;

const SLOT0: i64 = F.ENT;
const OBJECTS: i64 = 0x3A2B4; // slots 4-8
const ENEMIES: i64 = 0x3A430; // slots 9-11
const ENEMIES_END: i64 = 0x3A514; // slot 12

const ROWS_BASE: i64 = 12 + 3 * 20 + 16 + 12;
const BIT_ON: i64 = 8;
const BIT_OFF: i64 = 12;
const PROBE: i64 = 8 + 20;
const SCAN_BUSY: i64 = 64;
const SCAN_FREE: i64 = 48;
const SCAN_END: i64 = 28;
const ROW_ENTRY: i64 = 76;
const ROW_EXIT: i64 = 84;
const ROW_SETUP: i64 = 40;
const REC_END: i64 = 28;
const REC_TEST: i64 = 24;
const REC_SKIP: i64 = 20;

/// $39082: the probe rows in spawn_rows: bit1 -> +8, +16, +24; bit2 -> +0;
/// bit0 -> +32. Returns the cycles.
pub fn rows() i64 {
    const f = m.rb(F.SPAWN_ROWS);
    var n = ROWS_BASE;
    const Probe = struct { bit: i64, dys: []const i64 };
    const probes = [_]Probe{
        .{ .bit = 2, .dys = &.{ 8, 16, 24 } },
        .{ .bit = 4, .dys = &.{0} },
        .{ .bit = 1, .dys = &.{0x20} },
    };
    for (probes) |p| {
        if (f & p.bit == 0) {
            n += BIT_OFF;
            continue;
        }
        n += BIT_ON;
        for (p.dys) |dy| n += PROBE + row(dy);
    }
    return n;
}

const Scan = struct { free: bool, n: i64 };

fn scan(a0: i64, end: i64) Scan {
    var a = a0;
    var n: i64 = 0;
    while (a < end) : (a += 0x4C) {
        if (m.rw(a) == 0) return .{ .free = true, .n = n + SCAN_FREE };
        n += SCAN_BUSY;
    }
    return .{ .free = false, .n = n + SCAN_END };
}

/// $390CE(d0 = row offset): every unused record on row map_row + d0.
pub fn row(d0: i64) i64 {
    var s = scan(OBJECTS, ENEMIES);
    var n = s.n + ROW_ENTRY;
    if (!s.free) {
        s = scan(ENEMIES, ENEMIES_END);
        n += 12 + s.n;
        if (!s.free) {
            n += 16 + 12;
            if (m.rw(SLOT0) != 0) return n + ROW_EXIT;
        }
    }
    n += ROW_SETUP;
    const d1 = (d0 + m.rw(F.MAP_ROW)) & 0xFFFF;
    var a0 = m.rl(F.SPAWN_LIST);
    while (true) : (a0 += 6) {
        const d2 = m.rw(a0);
        n += REC_END;
        if (d2 == 0xFF) return n + ROW_EXIT;
        n += REC_TEST;
        if ((d2 & 0xFFF8) == d1) {
            n += 16 + (if (m.rb(a0 + 2) & 0x80 != 0) 12 else 8 + record(a0, d0));
        }
        n += REC_SKIP;
    }
}

/// From btst #1,3(a0): the cycles up to $391B6.
fn record(a0: i64, d0: i64) i64 {
    if (m.rb(a0 + 3) & 2 != 0) { // the moving platform: slot 0 if empty
        if (m.rw(SLOT0) == 0) return 16 + 8 + 16 + 8 + 12 + 20 + fill(a0, SLOT0, d0) + 12;
        return 16 + 8 + 16 + 12;
    }
    const enemy = m.rb(a0 + 2) < 0x10;
    var a1: i64 = if (enemy) ENEMIES else OBJECTS;
    const a2: i64 = if (enemy) ENEMIES_END else ENEMIES;
    var n: i64 = 16 + 12 + 12 + 12 + 16 + @as(i64, if (enemy) 8 + 12 + 12 else 12);
    while (true) : (a1 += 0x4C) {
        n += 8;
        if (a1 >= a2) return n + 12;
        n += 8 + 12;
        if (m.rw(a1) == 0) {
            n += 8 + 16;
            if (enemy) {
                const o = alreadyOut(a0);
                n += 8 + 4 + 12 + o.n;
                if (o.free) return n; // (free = "already out" here)
            } else {
                n += 12;
            }
            return n + 20 + fill(a0, a1, d0) + 12;
        }
        n += 12 + 8 + 12;
    }
}

/// An enemy slot already holds this record (+$26 = the record's address).
fn alreadyOut(a0: i64) Scan {
    var a3 = ENEMIES;
    var n: i64 = 0;
    while (true) : (a3 += 0x4C) {
        n += 16;
        if (a3 == ENEMIES_END) return .{ .free = false, .n = n + 12 };
        n += 8 + 12;
        if (m.rw(a3) != 0) {
            n += 8 + 20;
            if (m.rl(a3 + 0x26) == a0) return .{ .free = true, .n = n + 12 };
            n += 8;
        } else {
            n += 12;
        }
        n += 8 + 12;
    }
}
