// --------------------------------------------------------------------------
// OBJ demo: RNO's chamfered cube from Natrium (rno_natrium/envmap.zig, $14128),
// the object of its env-mapped parts 3 and 6: 24 vertices, 44 faces. Its data is
// big-endian words: nv, nf, six more header words, nv x (x, y, z) (|c| <= 88),
// then nf x three vertex indices times two. Scaled to Q14 so its corners sit
// where the unit models' do; fmesh.finish() orients the faces and makes the
// vertex normals ENVMAP reads. Its env texture (env_tex.bin, 13 grey levels)
// is textures.zig's NATRIUM map.
// No ZigOS import: obj/tests.zig tests it natively.
// --------------------------------------------------------------------------
const fmesh = @import("fmesh.zig");

pub const DATA = @embedFile("../../assets/screens/rno_natrium/cube.bin");
const SCALE: i32 = 180; // 88 * 180 = 15840, just under ONE (16384)

fn word(i: usize) i32 {
    return @as(i16, @bitCast(@as(u16, DATA[2 * i]) << 8 | DATA[2 * i + 1]));
}

pub fn build(m: *fmesh.Mesh) void {
    const nv: usize = @intCast(word(0));
    const nf: usize = @intCast(word(1));
    m.nverts = @intCast(nv);
    for (0..nv) |i| m.verts[i] = .{ @intCast(word(8 + 3 * i) * SCALE), @intCast(word(9 + 3 * i) * SCALE), @intCast(word(10 + 3 * i) * SCALE), 0 };
    m.nfaces = @intCast(nf);
    const f0 = 8 + 3 * nv;
    for (0..nf) |i| m.faces[i] = .{
        .a = @intCast(word(f0 + 3 * i) >> 1),
        .b = @intCast(word(f0 + 3 * i + 1) >> 1),
        .c = @intCast(word(f0 + 3 * i + 2) >> 1),
    };
    m.finish();
}
