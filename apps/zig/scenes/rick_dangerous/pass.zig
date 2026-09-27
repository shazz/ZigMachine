// --------------------------------------------------------------------------
// The entity pass $3AAB4, in its three callers' forms: every slot up to the
// $FFFF sentinel; type 0 skipped; while the scroll runs ($3A180) the slot is
// shifted by $3A182 (y, home_y, zone y0/y1) instead of handled; else the
// handler, and the draw unless the handler cleared its own type.
//   loop()   call 10 (rick_model.call_3aab4_entities): no clock
//   world()  inside calls 6/7/8/17 (a_pass.entity_pass): the stick is polled
//            before each handler and each unit's cost advances the clock
//   intro()  on the level intro screen (d_intro.entity_pass)
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const draw = @import("draw.zig");
const handlers = @import("handlers.zig");
const clock = @import("clock.zig");
const costs = @import("costs.zig");

fn shift(a: i64) void {
    const dy = m.rw(F.SCROLL_DY);
    for ([_]i64{ 0x06, 0x0E, 0x3E, 0x42 }) |off| m.ww(a + off, m.rw(a + off) + dy);
}

/// Call 10.
pub fn loop() void {
    var a = F.ENT;
    var i: i64 = 0;
    while (m.rw(a) != 0xFFFF) : ({
        a += F.ENT_SZ;
        i += 1;
    }) {
        const t = m.rw(a);
        if (t == 0) continue;
        if (m.rb(F.SCROLL_ON) != 0) {
            shift(a);
            draw.drawSlot(i);
            continue;
        }
        handlers.run(t, i);
        if (m.rw(a) != 0) draw.drawSlot(i);
    }
}

/// a_pass.entity_pass.
pub fn world() void {
    var a = F.ENT;
    var i: i64 = 0;
    var cost = clock.PASS_BASE;
    while (m.rw(a) != 0xFFFF) : ({
        a += F.ENT_SZ;
        i += 1;
    }) {
        const t = m.rw(a);
        if (t == 0) continue;
        if (m.rb(F.SCROLL_ON) != 0) {
            shift(a);
            cost += clock.PASS_SHIFT;
        } else {
            clock.pollJoy();
            handlers.run(t, i);
            cost += clock.PASS_SLOT + costs.handlerCost(t);
        }
        if (m.rb(F.SCROLL_ON) != 0 or m.rw(a) != 0) {
            cost += costs.drawCost(i);
            draw.drawSlot(i);
        }
        clock.work(cost);
        cost = 0;
    }
    clock.work(cost);
}

/// d_intro.entity_pass: handler then draw, one clock step at the end.
pub fn intro() void {
    var a = F.ENT;
    var i: i64 = 0;
    var cost = clock.PASS_BASE;
    while (m.rw(a) != 0xFFFF) : ({
        a += F.ENT_SZ;
        i += 1;
    }) {
        const t = m.rw(a);
        if (t == 0) continue;
        handlers.run(t, i);
        cost += clock.PASS_SLOT + costs.handlerCost(t);
        if (m.rw(a) != 0) {
            cost += costs.drawCost(i);
            draw.drawSlot(i);
        }
    }
    clock.work(cost);
}
