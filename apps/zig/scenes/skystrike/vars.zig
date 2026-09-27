// --------------------------------------------------------------------------
// The program's variables, named as in the listing (prototypes/skystrike_re/
// SKYSTRKE.LST): STOS integers are 32-bit, `sp#` and `fps#` the only floats
// (sp_f, fps_f), a `$` name is a string (k_s), an array carries `_a` (STOS
// keeps `dx` and `dx()` apart). DIM n gives indices 0..n. Everything starts
// at 0 / "" as the compiled program's variable area does.
// --------------------------------------------------------------------------
pub const Str = struct {
    buf: [300]u8 = undefined,
    len: usize = 0,

    pub fn get(s: *const Str) []const u8 {
        return s.buf[0..s.len];
    }
    pub fn set(s: *Str, t: []const u8) void {
        const n = @min(t.len, s.buf.len);
        @memmove(s.buf[0..n], t[0..n]);
        s.len = n;
    }
    pub fn eql(s: *const Str, t: []const u8) bool {
        return @import("std").mem.eql(u8, s.get(), t);
    }
};

pub const Name = struct {
    buf: [20]u8 = undefined,
    len: usize = 0,

    pub fn get(s: *const Name) []const u8 {
        return s.buf[0..s.len];
    }
    pub fn set(s: *Name, t: []const u8) void {
        const n = @min(t.len, s.buf.len);
        @memcpy(s.buf[0..n], t[0..n]);
        s.len = n;
    }
};

pub const V = struct {
    // addresses (START(n) << 16 based, scr.zig)
    s7: i32 = 0, so9: i32 = 0, sno9: i32 = 0, sc9: i32 = 0, ghx9: i32 = 0, lc9: i32 = 0,
    scbt: i32 = 0, a: i32 = 0, sx: i32 = 0, planes: i32 = 0, strt: i32 = 0, z2: i32 = 0,
    cl: i32 = 0, epcf: i32 = 0, rqsx: i32 = 0, th: i32 = 0, rc: i32 = 0, ld: i32 = 0,
    en: i32 = 0, dy: i32 = 0, dx: i32 = 0, jd: i32 = 0, ju: i32 = 0, bale: i32 = 0,
    crsh: i32 = 0, fre: i32 = 0, st: i32 = 0, mxsp: i32 = 0, sp_f: f64 = 0, r: i32 = 0,
    r2: i32 = 0, uc: i32 = 0, x: i32 = 0, y: i32 = 0, xo: i32 = 0, yo: i32 = 0,
    main: i32 = 0, al: i32 = 0, fuel: i32 = 0, fust: i32 = 0, fuxo: i32 = 0, eng: i32 = 0,
    oen: i32 = 0, lk2: i32 = 0, s2: i32 = 0, s3: i32 = 0, ammo: i32 = 0, nf: i32 = 0,
    tao: i32 = 0, fux: i32 = 0, wd: i32 = 0, wd2: i32 = 0, wdx: i32 = 0, s5: i32 = 0,
    s14: i32 = 0, px: i32 = 0, py: i32 = 0, pr: i32 = 0, psx: i32 = 0, pal: i32 = 0,
    exf: i32 = 0, gtg: i32 = 0, gtg2: i32 = 0, xo2: i32 = 0, yo2: i32 = 0, dxo: i32 = 0,
    turbo: i32 = 0, steam: i32 = 0, gry: i32 = 0, grlx: i32 = 0, grhx: i32 = 0, c: i32 = 0,
    nso: i32 = 0, th2: i32 = 0, leak: i32 = 0, fw: i32 = 0, cz: i32 = 0, kz: i32 = 0,
    arr: i32 = 0, scre: i32 = 0, sk: i32 = 0, carsnk: i32 = 0, btlsnk: i32 = 0,
    mission: i32 = 0, flf: i32 = 0, flgf: i32 = 0, flg: i32 = 0, bf: i32 = 0, bnf: i32 = 0,
    rkf: i32 = 0, net: i32 = 0, gtg4: i32 = 0, tgtx: i32 = 0, fps_f: f64 = 0, rqt: i32 = 0,
    clus: i32 = 0, turbt: i32 = 0, smk: i32 = 0, smkt: i32 = 0, mfin: i32 = 0, ta: i32 = 0,
    t: i32 = 0, zm: i32 = 0, sea: i32 = 0, s5o: i32 = 0, s14o: i32 = 0, ufail: i32 = 0,
    atlf: i32 = 0, lvl: i32 = 0, fl: i32 = 0, dl: i32 = 0, xx: i32 = 0, yy: i32 = 0,
    ss: i32 = 0, swp: i32 = 0, pri: i32 = 0, ex: i32 = 0, ey: i32 = 0, esx: i32 = 0,
    ew: i32 = 0, esy: i32 = 0, d: i32 = 0, rd: i32 = 0, xt: i32 = 0, yt: i32 = 0,
    sxt: i32 = 0, alt: i32 = 0, epsx: i32 = 0, epal: i32 = 0, epy: i32 = 0, epx: i32 = 0,
    epv: i32 = 0, brdf: i32 = 0, brk: i32 = 0, tta: i32 = 0, csx: i32 = 0, cal: i32 = 0,
    ghx: i32 = 0, kls: i32 = 0, bosx: i32 = 0, boal: i32 = 0, bnx: i32 = 0, bny: i32 = 0,
    bns: i32 = 0, brd: i32 = 0, brx: i32 = 0, bry: i32 = 0, brdx: i32 = 0, bdy: i32 = 0,
    bdx: i32 = 0, br: i32 = 0, bx: i32 = 0, by: i32 = 0, bsx: i32 = 0, bal: i32 = 0,
    z: i32 = 0, vh: i32 = 0, b: i32 = 0, rky: i32 = 0, rkx: i32 = 0, rkdx: i32 = 0,
    rkdy: i32 = 0, rkr: i32 = 0, rksx: i32 = 0, rkal: i32 = 0, rkrg: i32 = 0, lxt: i32 = 0,
    f: i32 = 0, nvs: i32 = 0, trksx: i32 = 0, vsx: i32 = 0, sn: i32 = 0, gtg3: i32 = 0,
    fx: i32 = 0, fy: i32 = 0, fv: i32 = 0, fdv: i32 = 0, bonus: i32 = 0, meb: i32 = 0,
    nv: i32 = 0, c2: i32 = 0, cc: i32 = 0, q: i32 = 0, h: i32 = 0, esf: i32 = 0,
    p: i32 = 0, k2: i32 = 0, s: i32 = 0, l: i32 = 0, shrk: i32 = 0, x1: i32 = 0,
    x2: i32 = 0, go: i32 = 0, y1: i32 = 0, y2: i32 = 0, w: i32 = 0, a1: i32 = 0,
    a2: i32 = 0, g: i32 = 0, az: i32 = 0, bc: i32 = 0, bse: i32 = 0, ms: i32 = 0,
    scrb: i32 = 0, brdg: i32 = 0, sglf: i32 = 0, gtg1: i32 = 0, tsc: i32 = 0, lx: i32 = 0,
    gh: i32 = 0, dbl: i32 = 0, ly: i32 = 0, nght: i32 = 0, vy: i32 = 0, vx: i32 = 0,
    nsa: i32 = 0, strtx: i32 = 0, misf: i32 = 0, msb: i32 = 0, trkf: i32 = 0, rp: i32 = 0,
    rp2: i32 = 0, hf: i32 = 0, a9: i32 = 0, ti: i32 = 0, dif: i32 = 0, nk: i32 = 0,
    alien: i32 = 0, recal: i32 = 0, olrec: i32 = 0, oalien: i32 = 0, i: i32 = 0,
    ok: i32 = 0, s4: i32 = 0, m1: i32 = 0, y0: i32 = 0, ts: i32 = 0, tb: i32 = 0,
    alp: i32 = 0, ntr: i32 = 0, rqf: i32 = 0, junf: i32 = 0, vv: i32 = 0, // vv: BASIC's v

    mes_s: Str = .{}, k_s: Str = .{}, a_s: Str = .{}, bon_s: Str = .{}, m_s: Str = .{},
    md_s: Str = .{}, l_s: Str = .{}, f_s: Str = .{}, hs_s: Name = .{},

    // arrays (DIM n -> n + 1 entries)
    kls_a: [10]i32 = [_]i32{0} ** 10,
    hs_s_a: [10]Name = [_]Name{.{}} ** 10,
    hs_a: [10]i32 = [_]i32{0} ** 10,
    snox_a: [52][4]i32 = [_][4]i32{[_]i32{0} ** 4} ** 52,
    vcp_a: [7]i32 = [_]i32{0} ** 7, vt_a: [7]i32 = [_]i32{0} ** 7,
    vsx_a: [7]i32 = [_]i32{0} ** 7, vx_a: [7]i32 = [_]i32{0} ** 7,
    vdx_a: [7]i32 = [_]i32{0} ** 7, vh_a: [7]i32 = [_]i32{0} ** 7,
    vs_a: [7]i32 = [_]i32{0} ** 7, vb_a: [7]i32 = [_]i32{0} ** 7,
    vpt_a: [7]i32 = [_]i32{0} ** 7, vw_a: [7]i32 = [_]i32{0} ** 7,
    bm_s_a: [16]Name = [_]Name{.{}} ** 16,
    bns_a: [16]i32 = [_]i32{0} ** 16, mif_a: [31]i32 = [_]i32{0} ** 31,
    gt_a: [16]i32 = [_]i32{0} ** 16, scrb_a: [16]i32 = [_]i32{0} ** 16,
    fl_a: [16]i32 = [_]i32{0} ** 16,
    ebale_a: [2]i32 = .{ 0, 0 }, esx_a: [2]i32 = .{ 0, 0 }, eal_a: [2]i32 = .{ 0, 0 },
    ex_a: [2]i32 = .{ 0, 0 }, ey_a: [2]i32 = .{ 0, 0 }, er_a: [2]i32 = .{ 0, 0 },
    ea_a: [2]i32 = .{ 0, 0 }, exo_a: [2]i32 = .{ 0, 0 }, eyo_a: [2]i32 = .{ 0, 0 },
    esp_a: [2]i32 = .{ 0, 0 }, fre_a: [2]i32 = .{ 0, 0 }, eth_a: [2]i32 = .{ 0, 0 },
    st_a: [2]i32 = .{ 0, 0 }, wd_a: [2]i32 = .{ 0, 0 },
    dx_a: [16]i32 = [_]i32{0} ** 16,
    dy_a: [16][2]i32 = [_][2]i32{.{ 0, 0 }} ** 16,
    exx_a: [5]i32 = [_]i32{0} ** 5, exy_a: [5]i32 = [_]i32{0} ** 5,
    exdx_a: [5]i32 = [_]i32{0} ** 5, exdy_a: [5]i32 = [_]i32{0} ** 5,
    di_a: [9]i32 = [_]i32{0} ** 9, bse_a: [42]i32 = [_]i32{0} ** 42,
    b_a: [11]i32 = [_]i32{0} ** 11,
    s_a: [16][2]i32 = [_][2]i32{.{ 0, 0 }} ** 16,
};

pub var v: V = .{};
