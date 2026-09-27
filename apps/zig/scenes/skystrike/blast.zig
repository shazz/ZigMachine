// --------------------------------------------------------------------------
// Smoke and fire: 195-206 (the plane's smoke trail and flames, its wreck's
// fireballs, an enemy's smoke), 400-415 (an explosion's four flying pieces,
// which also wreck a vehicle standing there). Every puff is stamped into the
// back screen (900), so a trail stays until the screen is redrawn.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const B = @import("basic.zig");
const O = @import("objects.zig");
const damage = @import("damage.zig");
const vehicles = @import("vehicles.zig");
const V = @import("vars.zig");
const v = &V.v;

fn stampAt(x: i32, y: i32, img: i32) void {
    v.xx = x;
    v.yy = y;
    v.ss = img;
    O.stamp();
}

/// 195-197: the plane's fire / steam and its turbo smoke.
pub fn smoke195() void {
    if (v.fre + v.steam > 0 and (v.bale == 0 or (v.sx == v.psx and v.al == v.pal)))
        stampAt(v.xo2, v.yo2, 63 + @min(4, @max(0, v.fre) + B.sgn(v.steam)));
    if (v.smkt != 0) {
        v.smkt -= 1;
        stampAt(v.xo2, v.yo2, v.smk);
    }
}

/// 198-199: enemy a's smoke.
pub fn smoke198() void {
    const a = B.ix(2, v.a);
    if (v.fre_a[a] != 0 and v.esx_a[a] == v.sx and v.eal_a[a] == v.al)
        stampAt(v.exo_a[a], v.eyo_a[a], 63 + @min(4, v.fre_a[a]));
}

/// 200-201: the wreck's fireballs falling away.
pub fn fireballs200() void {
    v.a = 1;
    while (v.a <= v.en) : (v.a += 1) {
        const a = B.ix(5, v.a);
        if (v.exx_a[a] > 0 and v.exy_a[a] > 0 and v.exx_a[a] < 320 and v.exy_a[a] < 165 and
            (v.bale == 0 or (v.bale == 1 and v.sx == v.psx and v.al == v.pal)))
        {
            stampAt(v.exx_a[a], v.exy_a[a], 24 + S.rnd(2));
            v.exx_a[a] -= v.exdx_a[a];
            v.exy_a[a] += v.exdy_a[a];
            v.exdx_a[a] -= B.sgn(v.exdx_a[a]);
            v.exdy_a[a] += 2;
        }
    }
}

/// 205-206: the burning plane itself.
pub fn burn205() void {
    if (v.bale == 0 or (v.bale == 1 and v.psx == v.sx and v.pal == v.al))
        stampAt(v.x, v.y, 24 + S.rnd(2));
}

/// 400-406: an explosion at ex,ey (sector esx): unless one is still flying
/// (within 50 VBLs), four pieces start; a vehicle there is wrecked.
pub fn explode400() void {
    damage.water650();
    if (!(v.exf == 0 or S.timer - v.lxt > 50)) return;
    v.exf = 1;
    v.lxt = S.timer;
    for (0..5) |z| {
        v.exx_a[z] = v.ex;
        v.exy_a[z] = v.ey;
    }
    for (0..5) |z| {
        v.exdx_a[z] = S.rnd(16) - 8;
        v.exdy_a[z] = -S.rnd(12);
    }
    v.z = 0;
    while (v.z <= 5) : (v.z += 1) {
        const z = B.ix(7, v.z);
        const reach = 16 + v.vw_a[z] * 16;
        if (v.esx == v.vsx_a[z] and v.ex > v.vx_a[z] - reach and v.ex < v.vx_a[z] + reach) {
            v.vh = v.z;
            vehicles.wreck480();
            v.z = 99;
        }
    }
}

/// 405-406: an explosion whose pieces fly every way.
pub fn scatter405() void {
    v.exf = 1;
    v.lxt = S.timer;
    for (0..5) |z| {
        v.exx_a[z] = v.ex;
        v.exy_a[z] = v.ey;
        v.exdx_a[z] = S.rnd(16) - 8;
        v.exdy_a[z] = S.rnd(16) - 8;
    }
}

/// 410-415: the pieces fly (drawn when in view) until all four are gone.
pub fn pieces410() void {
    v.f = 0;
    v.z = 0;
    while (true) {
        const z = B.ix(5, v.z);
        if (v.exx_a[z] > 0 and v.esx == v.sx and v.esy == v.al) {
            stampAt(v.exx_a[z], v.exy_a[z], 24 + S.rnd(2));
            fly(z);
        }
        if (v.exx_a[z] > 0) fly(z);
        if (v.exx_a[z] < 0 or v.exx_a[z] > 319 or v.exy_a[z] < 50 or v.exy_a[z] > 160) {
            v.exx_a[z] = -1;
            v.f += 1;
        }
        v.z += 1;
        if (v.z == 4) break;
    }
    if (v.f == 4) v.exf = 0;
}

fn fly(z: usize) void {
    v.exx_a[z] += v.exdx_a[z];
    v.exy_a[z] += v.exdy_a[z];
    v.exdy_a[z] += 1;
}
