// --------------------------------------------------------------------------
// The game: 25-49 (a new game, a new plane) and the main loop 50-149 as
// flow steps. A pass runs at once and then waits the VBLs its code took on
// the ST (clock.zig); 130's "goto 40" (a new screen) waits them too.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const scr = @import("scr.zig");
const input = @import("input.zig");
const B = @import("basic.zig");
const flow = @import("flow.zig");
const clock = @import("clock.zig");
const boot = @import("boot.zig");
const scene = @import("scene.zig");
const hud = @import("hud.zig");
const sfx = @import("sfx.zig");
const fly = @import("fly.zig");
const land = @import("land.zig");
const keys = @import("keys.zig");
const pass = @import("pass.zig");
const life = @import("enemy_life.zig");
const snd = @import("sound.zig");
const mission = @import("mission.zig");
const V = @import("vars.zig");
const v = &V.v;

pub const steps = [_]flow.Entry{
    .{ .l = .l25, .f = l25 },     .{ .l = .l34, .f = l34 },     .{ .l = .l34b, .f = l34b },
    .{ .l = .l40, .f = l40 },     .{ .l = .l50, .f = l50 },     .{ .l = .l56, .f = l56 },
    .{ .l = .l68, .f = l68 },     .{ .l = .l88b, .f = l88b },   .{ .l = .l90, .f = l90 },
    .{ .l = .l151a, .f = l151a }, .{ .l = .l151b, .f = l151b }, .{ .l = .l90b, .f = l90b },
    .{ .l = .l101b, .f = l101b }, .{ .l = .l102, .f = l102 },
};

/// 25-30: planes = 3 : fade 7 : gosub 2500 : hide on : gosub 300 : strt = 1
fn l25() flow.Act {
    v.planes = 3;
    S.fadeBlack(7);
    boot.newWorld();
    life.both300();
    v.strt = 1;
    S.timer = 0;
    v.z2 = 1;
    clock.atVbl();
    return .{ .go = .l34 };
}

/// 34: off : a crash-landing's message, and a key.
fn l34() flow.Act {
    scene.off();
    if (v.cl == 0) return .{ .go = .l34b };
    v.mes_s.set("You Managed to Crash Land !");
    scene.message1506();
    return .{ .call = .{ .to = .l190a, .ret = .l34b } };
}

/// 35-39: a fresh plane on the runway at the main base.
fn l34b() flow.Act {
    freshPlane();
    v.s2 = v.sx;
    v.s3 = v.al;
    v.ammo = 100;
    sfx.engine();
    scr.poke(v.ghx9 + v.sx, 0);
    v.bse_a[B.ix(42, B.div(v.sx, 10))] = -1;
    scr.poke(v.sno9 + v.sx, 0);
    if (v.b_a[8] == 0) {
        v.b_a = [_]i32{0} ** 11;
        v.b_a[3] = 4;
        v.b_a[4] = 8;
    } else v.b_a[8] -= 1;
    scene.panel();
    hud.panel710();
    hud.kills720();
    v.nf = 1;
    v.tao = 999;
    return .{ .go = .l40 };
}

fn freshPlane() void {
    inline for (.{ "epcf", "cl", "th", "rc", "en", "dy", "dx", "jd", "ju", "bale", "crsh", "fre", "st", "r", "r2", "al", "eng", "lk2" }) |n| @field(v.*, n) = 0;
    v.rqsx = -1;
    v.ld = 1;
    v.mxsp = 9;
    v.sp_f = 0;
    v.uc = 1;
    v.x = 260;
    v.y = 154;
    v.xo = v.x;
    v.yo = v.y;
    v.sx = v.main;
    v.fuel = v.fust;
    v.fuxo = 99;
    v.oen = 1;
}

/// 40-49: gosub 1000 : sx = s2 : al = s3 : en = 0 : fux = 99
fn l40() flow.Act {
    scene.draw();
    v.sx = v.s2;
    v.al = v.s3;
    v.en = 0;
    v.fux = 99;
    if (v.strt != 0) v.strt = 0;
    return .{ .go = .l50 };
}

/// 50-55
fn l50() flow.Act {
    fly.sprites50();
    fly.move55();
    return .{ .go = .l56 };
}

/// 56-67
fn l56() flow.Act {
    fly.wrap56();
    fly.speed60();
    fly.stall61();
    if (fly.bale67()) return .{ .go = .l220 };
    return .{ .go = .l68 };
}

/// 68-89
fn l68() flow.Act {
    switch (land.ground68()) {
        .to34 => return .{ .go = .l34 },
        .to56 => return .{ .go = .l56 },
        .to225 => return .{ .go = .l225 },
        else => {},
    }
    land.touch72();
    land.stick80();
    if (land.caught88()) return .{ .wait = .{ .vbls = 5, .then = .l88b } };
    land.after88(false);
    return .{ .go = .l90 };
}

fn l88b() flow.Act {
    land.after88(true);
    return .{ .go = .l90 };
}

/// 90: k$ = upper$(inkey$) : sk = scancode : clear key : gosub 150
fn l90() flow.Act {
    const c = input.inkey();
    v.sk = input.last_scan;
    input.clearKey();
    if (c) |ch| {
        v.k_s.set(&[_]u8{if (ch >= 'a' and ch <= 'z') ch - 32 else ch});
    } else v.k_s.len = 0;
    if (v.k_s.len == 0) return .{ .go = .l90b };
    if (!keys.keys150()) {
        keys.keys152();
        return .{ .go = .l90b };
    }
    S.locate(1, 10);
    snd.samstop();
    snd.music(1 + S.rnd(1) * 2, .title);
    return .{ .go = .l151a };
}

/// 151: P -- the music until a key.
fn l151a() flow.Act {
    const c = input.inkey() orelse return .{ .wait = .{ .vbls = 1, .then = .l151a } };
    v.a_s.set(&[_]u8{c});
    return .{ .go = .l151b };
}

fn l151b() flow.Act {
    snd.musicEnd(.flying);
    if (v.a_s.eql("M")) mission.freeMem();
    keys.keys152();
    return .{ .go = .l90b };
}

/// 91-101: on our airfield, stopped: 530 (a mission done: 1660).
fn l90b() flow.Act {
    pass.part91();
    if (!pass.atBase101()) return .{ .go = .l102 };
    if (mission.done530()) return .{ .call = .{ .to = .l1660, .ret = .l101b } };
    return .{ .go = .l101b };
}

fn l101b() flow.Act {
    mission.refit532();
    return .{ .go = .l102 };
}

/// 102-149: the rest of the pass, then the VBLs it took.
fn l102() flow.Act {
    pass.part102();
    pass.part120();
    clock.spend(clock.PASS);
    pass.timer128();
    if (v.nf != 0) return .{ .wait = .{ .vbls = clock.take(), .then = .l40 } };
    pass.part131();
    return .{ .wait = .{ .vbls = clock.take(), .then = .l50 } };
}

