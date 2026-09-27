// --------------------------------------------------------------------------
// Missions: 530-535 (landed at base: a finished mission pays its bonus and
// the next is briefed; either way the plane is refitted), 1660-1699 the
// briefing (MISSIONS.DAT record lvl + 1 over the title screen), mission 8
// the end: the newspaper (NEWS.PAC) and back to the title with 5,000,000.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const text = @import("text.zig");
const sprite = @import("sprite.zig");
const input = @import("input.zig");
const B = @import("basic.zig");
const flow = @import("flow.zig");
const files = @import("files.zig");
const boot = @import("boot.zig");
const scene = @import("scene.zig");
const hud = @import("hud.zig");
const snd = @import("sound.zig");
const assets = @import("assets.zig");
const V = @import("vars.zig");
const v = &V.v;

pub const steps = [_]flow.Entry{
    .{ .l = .l1660, .f = l1660 },   .{ .l = .l1660b, .f = l1660b },
    .{ .l = .l1661b, .f = l1661b }, .{ .l = .l1690b, .f = l1690b },
    .{ .l = .l1690c, .f = l1690c }, .{ .l = .l1697b, .f = l1697b },
    .{ .l = .l1698b, .f = l1698b }, .{ .l = .l1699, .f = l1699 },
};

/// STOS FREE: the bytes left for strings (not measured on the ST).
pub const FREE: i32 = 60000;

/// 530-531; true: the mission is done (1660 follows).
pub fn done530() bool {
    const m = B.ix(31, v.mission);
    if (v.mission == 17 and v.sx == v.tgtx) v.mif_a[m] = v.mfin;
    if (!(v.mif_a[m] >= v.mfin or v.lvl == 999)) return false;
    v.scre += v.bonus * 1000;
    hud.score();
    v.bns = v.meb;
    hud.level591();
    v.lvl += 1;
    return true;
}

/// 532: refuelled, rearmed, repaired.
pub fn refit532() void {
    v.y = v.gry;
    v.fuel = v.fust + v.b_a[7];
    v.fuxo = 99;
    v.lk2 = 0;
    v.leak = 0;
    v.mxsp = 9 + v.b_a[6];
    v.ammo = 50 + v.b_a[2];
    v.fre = 0;
    v.b_a[3] = 4;
    v.ufail = 0;
    for (&v.b_a) |*b| b.* = @max(0, b.*);
    v.a = 11;
}

/// 1660: samstop : fade 1 : wait 7
fn l1660() flow.Act {
    snd.samstop();
    S.fadeBlack(1);
    return .{ .wait = .{ .vbls = 7, .then = .l1660b } };
}

/// ... sprites off : lvl 1000 -> 0 : 1661 gosub 2350 (the title screen)
fn l1660b() flow.Act {
    sprite.allOff();
    if (v.lvl == 1000) v.lvl = 0;
    return .{ .call = .{ .to = .l2350, .ret = .l1661b } };
}

/// 1661-1685: the briefing.
fn l1661b() flow.Act {
    S.locate(0, 2);
    S.paper(14);
    S.pen(0);
    var buf: [40]u8 = undefined;
    S.centre(join(&buf, "Mission #", v.lvl + 1, ""));
    const rec = files.mission(v.lvl + 1) orelse return .{ .go = .l2700 };
    v.tgtx = rec.tgtx;
    v.strtx = rec.strtx;
    v.mission = rec.mission;
    v.misf = rec.misf - 1;
    v.mfin = rec.mfin;
    v.bonus = rec.bonus;
    v.msb = rec.msb;
    v.meb = rec.meb;
    if (v.strtx != 0) {
        v.sx = B.div(v.strtx, 10) * 10;
        v.s2 = v.sx;
        v.nf = 1;
    }
    v.vs_a[0] = 0;
    v.vsx_a[0] = 999;
    brief1670(rec.text);
    goals1675();
    return .{ .go = .l1690b };
}

/// prefix + STR$(n) + suffix
fn join(buf: []u8, pre: []const u8, n: i32, post: []const u8) []const u8 {
    var nb: [12]u8 = undefined;
    const s = text.str(&nb, n);
    @memcpy(buf[0..pre.len], pre);
    @memcpy(buf[pre.len..][0..s.len], s);
    @memcpy(buf[pre.len + s.len ..][0..post.len], post);
    return buf[0 .. pre.len + s.len + post.len];
}

/// 1670-1674: the text's lines (36 characters each), the bonuses.
fn brief1670(md: []const u8) void {
    S.fadeTo(5, .b5);
    v.a = 0;
    while (v.a < 8) : (v.a += 1) {
        const l = md[@intCast(v.a * 36)..][0..36];
        if (!allSpaces(l)) {
            S.locate(0, v.a + 6);
            S.centre(l);
        }
    }
    v.tao = 999;
    S.locate(1, 3);
    var buf: [40]u8 = undefined;
    S.centre(join(&buf, "Mission Bonus ", v.bonus * 1000, ""));
    if (v.msb != 0) {
        S.locate(3, 4);
        S.print("Start Bonus");
        v.yy = text.ygraphic(4);
        S.sprite_(14, 180, v.yy, v.bns_a[B.ix(16, v.msb - 1)]);
    }
    if (v.meb != 0) {
        S.locate(3, 5);
        S.print("End Bonus");
        v.yy = text.ygraphic(5);
        S.sprite_(15, 180, v.yy, v.bns_a[B.ix(16, v.meb - 1)]);
    }
}

fn allSpaces(l: []const u8) bool {
    for (l) |c| if (c != ' ') return false;
    return true;
}

/// 1675-1685: the goal's counter, and what the world already says.
fn goals1675() void {
    const m = B.ix(31, v.mission);
    v.mif_a[m] = v.misf;
    v.md_s.len = 0;
    const base = v.bse_a[B.ix(42, B.div(v.tgtx, 10))];
    if (v.mission == 6 and base < 1) v.mif_a[6] = 1;
    if (v.mission == 7 and base == -1) v.mif_a[7] = 1;
    if (v.mission == 4 and v.btlsnk != 0) v.mif_a[4] = 1;
    if (v.mission == 11) {
        v.trksx = v.tgtx;
        v.trkf = 1;
        for (0..4) |a| {
            boot.truck(a);
            v.vsx_a[a] = v.tgtx;
            v.vx_a[a] = 40 + 80 * @as(i32, @intCast(a));
        }
        v.a = 4;
        v.mif_a[11] = 0;
    }
}

/// 1690 / 1697: a key (mission 8: then the newspaper).
fn l1690b() flow.Act {
    input.clearKey();
    const next: flow.L = if (v.mission == 8) .l1690c else .l1698b;
    return .{ .call = .{ .to = .l190a, .ret = next } };
}

/// 1690: the paper, music 3, fade to it, a key; the war is won.
fn l1690c() flow.Act {
    boot.unpackTo(assets.NEWS, .physic);
    snd.music(3);
    S.fadeTo(5, .back);
    input.clearKey();
    return .{ .go = .l1697b };
}

/// ... wait key : scre + 5,000,000 : clw : planes = 0 : cl = 1 : pop : goto 23
fn l1697b() flow.Act {
    if (input.inkey() == null) return .{ .wait = .{ .vbls = 1, .then = .l1697b } };
    v.scre += 5000000;
    text.clw();
    v.planes = 0;
    v.cl = 1;
    flow.pop();
    return .{ .go = .l2000 };
}

/// 1698-1699: fade out, the panel, fade in, the start bonus.
fn l1698b() flow.Act {
    S.fadeBlack(1);
    return .{ .wait = .{ .vbls = 7, .then = .l1699 } };
}

fn l1699() flow.Act {
    snd.musicOff();
    text.clw();
    v.nf = 1;
    scene.panel();
    hud.panel710();
    hud.kills720();
    S.fadeTo(12, if (v.nght == 0) .b5 else .b6);
    v.bns = v.msb;
    hud.level591();
    v.tao = 999;
    return .ret;
}

/// 151 with "M": FREE MEM and the frame rate on line 10.
pub fn freeMem() void {
    var buf: [64]u8 = undefined;
    var nb: [12]u8 = undefined;
    const pre = "FREE MEM ";
    @memcpy(buf[0..pre.len], pre);
    const f = text.str(&nb, FREE);
    @memcpy(buf[pre.len..][0..f.len], f);
    var n = pre.len + f.len;
    const fps = text.str(&nb, B.ftoi(v.fps_f));
    @memcpy(buf[n..][0..fps.len], fps);
    n += fps.len;
    v.k_s.set(buf[0..n]);
    S.pen(15);
    S.paper(4);
    S.centre(v.k_s.get());
}

