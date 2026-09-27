// --------------------------------------------------------------------------
// The handler table $3A562[type - 1] (the model's rick_model.HANDLERS): Rick
// (1), the bullet (2), the dynamite (3), the enemies (4-15), the boxes (16,
// 17), the treasures (18-21), the bonus zones (22, 23), the traps (24-73), the
// intro picture (74). A handler gets the slot; a0 = the slot's address.
// --------------------------------------------------------------------------
const F = @import("fields.zig");
const rick = @import("rick.zig");
const actors = @import("actors.zig");
const enemy = @import("enemy.zig");
const trap = @import("trap.zig");

/// Types the model has no handler for: the entity pass would have raised.
pub var unknown: u32 = 0;

pub fn run(ty: i64, slot: i64) void {
    const a0 = F.ENT + F.ENT_SZ * slot;
    switch (ty) {
        1 => rick.handler(),
        2 => actors.bullet(a0),
        3 => actors.dynamite(a0),
        4...15 => enemy.handler(a0, ty),
        16, 17 => actors.box(a0, ty),
        18...21 => actors.treasure(a0, ty),
        22, 23 => actors.bonusZone(a0, ty),
        24...73 => trap.trap(a0),
        74 => trap.introPicture(a0),
        else => unknown += 1,
    }
}
