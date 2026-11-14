// --------------------------------------------------------------------------
// The BARD job block (zg.bard.job, system table 1.24): its layout, shared by
// every side that reads or writes it. ONE writer per word:
//   C = the cart (ZIGGY), S = the server (BARD on the board; the page's host,
//   or the cart itself where no coprocessor answers).
//
// The block lives in the cart's own memory (16-aligned): a header, then SLOTS
// job descriptors of 16 words, a ring. The cart fills a slot, writes its `seq`
// LAST (the slot is whole when seq is its post number) and bumps `head`; the
// server serves slots in order, writes its answer words, then `done` LAST.
// Every address in a job is a cart offset (the cart's own pointers): the
// server adds the base where the cart's memory sits (0 in the wasm, the cart's
// DDR window on BARD) and checks every range against the cart's memory size
// before it reads or writes a byte (the cart is not trusted).
// --------------------------------------------------------------------------
pub const MAGIC: u32 = 0x4a424d5a; // "ZMBJ"
pub const SLOTS: u32 = 8; // a power of two
pub const HEAD_WORDS: u32 = 8;
pub const JOB_WORDS: u32 = 16;
pub const ARGS: u32 = 10;
pub const BLOCK_BYTES: u32 = 4 * (HEAD_WORDS + SLOTS * JOB_WORDS);

/// Header words.
pub const H = struct {
    pub const magic = 0; // C
    pub const slots = 1; // C
    pub const head = 2; // C: jobs posted (wraps)
};

/// A job descriptor: 64 bytes, a slot of the ring.
pub const Job = extern struct {
    op: u32, // C
    seq: u32, // C, LAST: the job's post number (head before the post)
    done: u32, // S, LAST: the seq of the job served in this slot (NONE before)
    err: u32, // S: Err
    cycles: u32, // S: what the job cost the server (BARD's cycle counter; 0 where none)
    result: u32, // S: the op's scalar answer (Op says which)
    a: [ARGS]u32, // C: the op's arguments
};

pub const NONE: u32 = 0xFFFF_FFFF;

/// The jobs. Every array is in the cart's memory; the server never allocates.
pub const Op = enum(u32) {
    /// a0 src, a1 src len (a ZX0! container), a2 dst, a3 dst cap. result: bytes written.
    zx0 = 1,
    /// a0 n points, a1 shape A, a2 shape B (n x Point each), a3 morph t (0..256),
    /// a4 the Xform block, a5 out (n x u32: shade << 24 | screen offset, or OFF). result: points on screen.
    xform = 2,
    /// a0 n, a1 state in, a2 state out (n x Particle each, may not overlap), a3 the Physics
    /// block, a4 out (n x u32 screen offsets, or OFF), a5 the frame (the respawn's seed). result: respawned.
    particles = 3,
    /// a0 src, a1 len, a2 chunk (bytes, a multiple of 4, >= 4), a3 out (len / chunk x u32: the
    /// chunks' CRC-32s, IEEE as zlib's). result: the CRC-32 of the whole buffer.
    crc32 = 4,
    _,
};

pub const Err = enum(u32) { ok = 0, bad_op = 1, range = 2, alignment = 3, data = 4, _ };

/// A screen position no pixel is at: off the plane (xform, particles).
pub const OFF: u32 = 0xFFFF_FFFF;

/// A point of a shape: Q14 coordinates (a unit sphere is +-16384).
pub const Point = extern struct { x: i16, y: i16, z: i16, pad: i16 = 0 };

/// The 3D transform (Op.xform), 4-aligned, written by the cart before the post.
pub const Xform = extern struct {
    m: [9]i32, // the rotation, Q14, row-major: x' = (m0 x + m1 y + m2 z) >> 14
    zoff: i32, // the camera's distance, added to z' (> 0 for every point)
    cx: i32, // the screen centre
    cy: i32,
    w: u32, // the plane: width, height, stride (bytes)
    h: u32,
    stride: u32,
    ztab: u32, // the reciprocal table: ztab[(z' + zoff) >> zshift] = focal * 65536 / depth (u32)
    ztab_n: u32,
    zshift: u32, // index = (z' + zoff) >> zshift
    shade_shift: u32, // the shade (out's top byte) = the depth index >> shade_shift
};

/// A particle (Op.particles): Q16.16 position and velocity, pixels and pixels a frame.
pub const Particle = extern struct { x: i32, y: i32, vx: i32, vy: i32 };

/// The physics (Op.particles), 4-aligned.
pub const Physics = extern struct {
    gravity: i32, // added to vy each frame, Q16
    floor: i32, // y of the floor, Q16
    bounce: i32, // vy = -vy * bounce >> 8 on the floor
    rest: i32, // |vy| under this after a bounce: the particle respawns, Q16
    w: u32, // the plane: width, height, stride
    h: u32,
    stride: u32,
    ex: i32, // the emitter, Q16
    ey: i32,
    spread: u32, // vx in [-spread, spread), Q16 (a power of two)
    lift: i32, // vy at birth, Q16 (negative: up), minus up to `spread` more
};
