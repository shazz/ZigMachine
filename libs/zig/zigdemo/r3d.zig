//! MOCK, types only: the 3D renderer's vocabulary, so a part can name its
//! meshes and cameras before the renderer exists. The renderer itself (Q16
//! transform, project and cull, subset ordering, an affine span emitter onto
//! chisel_v2.affine) is in ANALYSIS.md §7 (3), the r3d/ row. Nothing here does
//! any maths yet.

/// A position in Q16.16 world units.
pub const Vec3 = struct { x: i32 = 0, y: i32 = 0, z: i32 = 0 };

/// A mesh by id into the cart's mesh table; its counts size the draw.
pub const Mesh = struct { id: u16, vertices: u16, faces: u16 };

pub const Material = struct {
    texture: u16 = 0,
    /// 0 transparent, 255 opaque. A fade animates this.
    alpha: u8 = 255,
    visible: bool = true,
};

/// A mesh with a material and, optionally, an animation track to sample.
pub const Actor = struct {
    mesh: u16,
    material: u16,
    anim_track: ?u16 = null,
};

pub const Camera = struct {
    eye: Vec3 = .{},
    target: Vec3 = .{},
    /// Field of view in Q8 degrees.
    fov_q8: u16 = 60 * 256,
};
