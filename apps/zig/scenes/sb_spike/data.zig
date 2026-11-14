// --------------------------------------------------------------------------
// SB SPIKE: Suicide Barbie's mix3 (TBL, PSP 2007, MIT) as data the frame indexes.
//
// mix3.bin and mix3_layout.zig come from tools/sb_mix3/convert.py, run once by hand
// on the shipped PSP blobs (prototypes/ is not in git): the 9 textures as one
// 256-wide 8-bit atlas under one palette (atlas.py), the 30 Hz camera and actor
// keys in i16, and every mesh at four LODs (decimate.py). The blob is copied into
// an aligned array at compile time, so every i16 view of it is aligned (a
// misaligned load traps on the board).
// --------------------------------------------------------------------------
pub const layout = @import("../../assets/screens/sb_spike/mix3_layout.zig");

const RAW = @embedFile("../../assets/screens/sb_spike/mix3.bin");
const blob: [RAW.len]u8 align(16) = RAW.*;

/// A vertex: position Q12 (scene units), normal Q14, u 8.8 texels, v the atlas row in 11.5.
pub const Vert = extern struct { x: i16, y: i16, z: i16, nx: i16, ny: i16, nz: i16, u: u16, v: u16 };
/// A 30 Hz key: translation Q12, rotation quaternion (x, y, z, w) Q14.
pub const Key = extern struct { t: [3]i16, q: [4]i16, _pad: i16 };
pub const Tri = [3]u16;

pub const ATLAS_W = 256;
pub const atlas: []const u8 = blob[0 .. ATLAS_W * layout.ATLAS_ROWS];
pub const LODS = layout.lods.len;
pub const ITEMS = layout.items.len;

fn slice(comptime T: type, off: u32, n: usize) []const T {
    const p: [*]const T = @ptrCast(@alignCast(&blob[off]));
    return p[0..n];
}

pub fn keys(node: u8) []const Key {
    const n = layout.nodes[node];
    return slice(Key, n.off, n.keys);
}

pub fn verts(lod: usize, item: usize) []const Vert {
    const m = layout.lods[lod][item];
    return slice(Vert, m.vert_off, m.nverts);
}

pub fn tris(lod: usize, item: usize) []const Tri {
    const m = layout.lods[lod][item];
    return slice(Tri, m.tri_off, m.ntris);
}

/// The LOD's totals (the HUD and the measurements).
pub fn counts(lod: usize) struct { verts: u32, tris: u32 } {
    var v: u32 = 0;
    var t: u32 = 0;
    for (layout.lods[lod]) |m| {
        v += m.nverts;
        t += m.ntris;
    }
    return .{ .verts = v, .tris = t };
}

pub const MAX_VERTS: usize = blk: {
    var best: usize = 0;
    for (layout.lods) |l| {
        var n: usize = 0;
        for (l) |m| n += m.nverts;
        best = @max(best, n);
    }
    break :blk best;
};

pub const MAX_TRIS: usize = blk: {
    var best: usize = 0;
    for (layout.lods) |l| {
        var n: usize = 0;
        for (l) |m| n += m.ntris;
        best = @max(best, n);
    }
    break :blk best;
};
