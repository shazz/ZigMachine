// --------------------------------------------------------------------------
// RACER: the course select's models (board batch, coursemesh.zig), one a listed track (~430 bytes), carved at the
// library's scan with its previews, baked when each track is previewed; with no RAM for them the select draws no model.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const cm = @import("coursemesh.zig");
const trk = @import("trk.zig");

var meshes: []cm.Mesh = &.{};

/// Room for `n` models (the library's listed tracks), or none.
pub fn carve(n: usize) void {
    meshes = zg.mem.alloc(cm.Mesh, n) orelse &.{};
    for (meshes) |*m| m.* = .{};
    if (meshes.len == 0 and n != 0) zg.Console.log("racer,courses,no RAM,{}", .{n});
}

pub fn bake(i: usize, t: *const trk.Track) void {
    if (i < meshes.len) meshes[i] = cm.bake(t);
}

/// Entry `i`'s model, or null (none carved, none baked: a refused file keeps the empty model).
pub fn get(i: usize) ?*const cm.Mesh {
    if (i >= meshes.len or meshes[i].nr == 0) return null;
    return &meshes[i];
}
