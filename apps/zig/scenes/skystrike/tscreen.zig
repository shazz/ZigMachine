// --------------------------------------------------------------------------
// Line 2350-2361: the title-style screen -- the home airfield (sector 0 on
// the title, else the player's) drawn and moved down 24 lines, the music
// (tune 1 or 3), the plane flying across -- used by the title, the
// difficulty menu and every mission briefing. On the title (tsc = 1) the
// last game's score is first offered to the hall of fame (2360 -> 2320).
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const scr = @import("scr.zig");
const sprite = @import("sprite.zig");
const pal = @import("pal.zig");
const flow = @import("flow.zig");
const clock = @import("clock.zig");
const scene = @import("scene.zig");
const title = @import("title.zig");
const snd = @import("sound.zig");
const V = @import("vars.zig");
const v = &V.v;

pub const steps = [_]flow.Entry{
    .{ .l = .l2350, .f = l2350 },   .{ .l = .l2350a, .f = l2350a },
    .{ .l = .l2350b, .f = l2350b }, .{ .l = .l2350c, .f = l2350c },
    .{ .l = .l2350d, .f = l2350d },
};

/// 2350-2352 up to 990's WAIT VBL.
fn l2350() flow.Act {
    v.s4 = v.scre;
    v.m1 = v.main;
    v.s2 = v.sx;
    v.s3 = v.al;
    v.y0 = v.y;
    v.main = 0;
    v.al = 0;
    if (v.tsc == 1) v.sx = 0;
    sprite.allOff();
    S.update();
    v.ts = 1;
    v.nf = 1;
    S.fadeBlack(1);
    v.nso = 0;
    v.th = 0;
    return .{ .wait = .{ .vbls = 1, .then = .l2350a } };
}

/// 990's rest (samstop : volume 0), then 2360: on the title, the hall.
fn l2350a() flow.Act {
    snd.samstop();
    snd.volume(0);
    if (v.tsc == 1) return .{ .call = .{ .to = .l2320, .ret = .l2350c } };
    return .{ .go = .l2350b };
}

fn l2350c() flow.Act {
    v.scre = 0;
    v.s4 = 0;
    return .{ .go = .l2350b };
}

/// ... the home airfield as ours, drawn (1000; its WAIT VBL).
fn l2350b() flow.Act {
    v.ts = scr.peek(v.ghx9);
    v.tb = v.bse_a[0];
    scr.poke(v.ghx9, 0);
    v.bse_a[0] = -1;
    scr.poke(v.sc9, 1);
    scene.draw();
    return .{ .wait = .{ .vbls = clock.take(), .then = .l2350d } };
}

/// ... moved down 24 lines, to back; the music; 2353-2354.
fn l2350d() flow.Act {
    sprite.allOff();
    S.update();
    S.copy(S.lg(), 0, 24, 320, 176, S.lg(), 0, 48);
    scene.toBack();
    pal.flashOff();
    S.fadeTo(5, .b5);
    snd.music(1 + S.rnd(1) * 2);
    title.plane();
    v.sx = v.s2;
    v.al = v.s3;
    v.main = v.m1;
    v.y = v.y0;
    v.yo = v.y;
    v.nf = 1;
    if (v.tsc == 0) v.scre = v.s4;
    scr.poke(v.ghx9, v.ts);
    v.bse_a[0] = v.tb;
    v.tsc = 0;
    return .ret;
}

