// --------------------------------------------------------------------------
// SB SPIKE: the 30 Hz keys -> one model-view matrix an item, integers only.
//
// The original (mutalisk/mutant) bakes every clip at 30 Hz: translation + rotation
// quaternion + scale (always 1 in mix3), linear + slerp between keys, row vectors
// (p_world = p * R(q) + t, the PSP's gum), a flat hierarchy under an identity
// RootNode, and the view = the camera node's world matrix inverted. Here the keys
// are i16 (t Q12, q Q14), interpolated linearly (nlerp: keys 1/30 s apart are close
// enough that the renormalisation in quatMatrix covers it), and the model-view is
// R = R_actor * R_cam^T, T = (t_actor - t_cam) * R_cam^T, Q14 / Q12.
// tools/sb_mix3/preview.py renders the same maths in float (the convention check).
// No ZigOS import.
// --------------------------------------------------------------------------
const data = @import("data.zig");

pub const Mat = [3][3]i32; // row vectors: view_k = sum_j p_j * m[j][k], Q14
pub const Vec = [3]i32;
pub const ModelView = struct { r: Mat, t: Vec }; // t Q12

/// Clip time in 30 Hz frames, Q16 (key 480 = 16 s = key 0 again).
pub const LOOP: u32 = 480 << 16;

const Pose = struct { t: Vec, q: [4]i32 };

fn sample(node: u8, time: u32) Pose {
    const ks = data.keys(node);
    if (ks.len == 1) return .{ .t = .{ ks[0].t[0], ks[0].t[1], ks[0].t[2] }, .q = .{ ks[0].q[0], ks[0].q[1], ks[0].q[2], ks[0].q[3] } };
    const i: usize = @min(time >> 16, ks.len - 2);
    const f: i32 = @intCast((time >> 4) & 0xFFF); // Q12 fraction
    const a = ks[i];
    const b = ks[i + 1];
    var p: Pose = undefined;
    for (0..3) |k| p.t[k] = a.t[k] + (((@as(i32, b.t[k]) - a.t[k]) * f) >> 12);
    for (0..4) |k| p.q[k] = a.q[k] + (((@as(i32, b.q[k]) - a.q[k]) * f) >> 12);
    return p;
}

/// The row-vector rotation of quaternion q (x, y, z, w; Q14, any length), Q14.
pub fn quatMatrix(q: [4]i32) Mat {
    const x = q[0];
    const y = q[1];
    const z = q[2];
    const w = q[3];
    const n2: i32 = (x * x + y * y + z * z + w * w) >> 14; // |q|^2 Q14
    const inv: i32 = @divTrunc(@as(i32, 1 << 29), @max(n2, 1)); // 2 / |q|^2, Q14
    const s = struct {
        fn f(t: i32, k: i32) i32 { // t Q28 -> t * k, Q14
            return ((t >> 14) * k) >> 14;
        }
    }.f;
    return .{
        .{ 16384 - s(y * y + z * z, inv), s(x * y + z * w, inv), s(x * z - y * w, inv) },
        .{ s(x * y - z * w, inv), 16384 - s(x * x + z * z, inv), s(y * z + x * w, inv) },
        .{ s(x * z + y * w, inv), s(y * z - x * w, inv), 16384 - s(x * x + y * y, inv) },
    };
}

/// The camera's inverse: its rotation transposed, and where the eye is.
pub const View = struct { r: Mat, eye: Vec };

pub fn camera(time: u32) View {
    const p = sample(data.layout.CAMERA, time);
    const m = quatMatrix(p.q);
    var r: Mat = undefined;
    for (0..3) |i| for (0..3) |j| {
        r[i][j] = m[j][i];
    };
    return .{ .r = r, .eye = p.t };
}

pub fn modelView(node: u8, time: u32, v: *const View) ModelView {
    const p = sample(node, time);
    const m = quatMatrix(p.q);
    var mv: ModelView = undefined;
    for (0..3) |i| for (0..3) |k| {
        mv.r[i][k] = (m[i][0] * v.r[0][k] + m[i][1] * v.r[1][k] + m[i][2] * v.r[2][k]) >> 14;
    };
    const d = Vec{ p.t[0] - v.eye[0], p.t[1] - v.eye[1], p.t[2] - v.eye[2] };
    for (0..3) |k| mv.t[k] = (d[0] * v.r[0][k] + d[1] * v.r[1][k] + d[2] * v.r[2][k]) >> 14;
    return mv;
}
