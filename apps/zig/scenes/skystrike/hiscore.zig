// --------------------------------------------------------------------------
// The hall of fame, "The Aces": 2260-2291 (HIPIC.PAC with the table pasted
// on, faded and APPEARed, then a key), 2281 (the title's timeout), 2300
// (the table from SPITFIRE.HSC, once), 2310-2328 (a new record: its place,
// the hall, the name typed in -- Enter ends, Backspace erases).
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const scr = @import("scr.zig");
const sprite = @import("sprite.zig");
const pal = @import("pal.zig");
const input = @import("input.zig");
const blocks = @import("blocks.zig");
const B = @import("basic.zig");
const flow = @import("flow.zig");
const boot = @import("boot.zig");
const scene = @import("scene.zig");
const snd = @import("sound.zig");
const assets = @import("assets.zig");
const table = @import("histable.zig");
const appear = @import("appear.zig");
const hooks = @import("zig_hooks.zig");
const V = @import("vars.zig");
const v = &V.v;

pub const steps = [_]flow.Entry{
    .{ .l = .l2260, .f = l2260 },   .{ .l = .l2280, .f = l2280 },   .{ .l = .l2280b, .f = l2280b },
    .{ .l = .l2280c, .f = l2280c },
    .{ .l = .l2290, .f = l2290 },   .{ .l = .l2291, .f = l2291 },   .{ .l = .l2291b, .f = l2291b },
    .{ .l = .l2281, .f = l2281 },   .{ .l = .l2281b, .f = l2281b }, .{ .l = .l2320, .f = l2320 },
    .{ .l = .l2320b, .f = l2320b }, .{ .l = .l2310, .f = l2310 },   .{ .l = .l2311, .f = l2311 },
};

fn clearAll() void {
    S.ink(0);
    S.bar(0, 0, 319, 199);
}

/// 2260-2275: the picture, the table drawn on back and pasted over it.
fn l2260() flow.Act {
    snd.samstop();
    scene.off();
    clearAll();
    sprite.mouse(false, sprite.spr[0].img, sprite.spr[0].x, sprite.spr[0].y);
    S.fadeBlack(1);
    boot.unpackTo(assets.HIPIC, .b5);
    snd.music(2, .title);
    S.bar(0, 0, 319, 199);
    scene.toLogic();
    scr.logic = .back;
    clearAll();
    blocks.copyAll(.b5, .physic);
    hooks.shows(.hall);
    if (v.hs_a[0] == 0) table.load2300();
    table.draw2270();
    S.fadeBlack(1);
    return .{ .go = .l2280 };
}

/// 2280: logic = physic : fade 3 to logic : wait 21
fn l2280() flow.Act {
    scr.logic = .physic;
    S.fadeTo(3, .physic);
    return .{ .wait = .{ .vbls = 21, .then = .l2280b } };
}

/// ... fade 2,$0,$677,$150,$7,$204 : appear back : gosub 2290
fn l2280b() flow.Act {
    pal.fadeList(2, &.{ 0x000, 0x677, 0x150, 0x007, 0x204 });
    appear.start(.back);
    return .{ .go = .l2280c };
}

/// The dissolve, VBL by VBL, then 2290.
fn l2280c() flow.Act {
    if (appear.vbl()) return .{ .wait = .{ .vbls = 1, .then = .l2280c } };
    return .{ .go = .l2290 };
}

/// 2290: if nk then return (a record is being entered: no key wait)
fn l2290() flow.Act {
    if (v.nk != 0) return .ret;
    input.clearKey();
    return .{ .go = .l2291 };
}

/// 2291: while mouse key <> 0 : wend
fn l2291() flow.Act {
    if (S.mouseKey() != 0) return .{ .wait = .{ .vbls = 1, .then = .l2291 } };
    return .{ .go = .l2291b };
}

/// ... while mouse key = 0 and inkey$ = "" : wend : return
fn l2291b() flow.Act {
    if (S.mouseKey() == 0 and input.inkey() == null) return .{ .wait = .{ .vbls = 1, .then = .l2291b } };
    return .ret;
}

/// 2281: the title's timeout: the hall, then the title again.
fn l2281() flow.Act {
    return .{ .call = .{ .to = .l2260, .ret = .l2281b } };
}

fn l2281b() flow.Act {
    S.fadeBlack(1);
    clearAll();
    boot.unpackTo(assets.SKYPIC1, .b5);
    scr.logic = .back;
    clearAll();
    blocks.copyAll(.back, .physic);
    scr.logic = .physic;
    snd.musicEnd(.title);
    return .{ .go = .l2000 };
}

/// 2320: the table loaded; the first place the score beats (2321's loop).
fn l2320() flow.Act {
    if (v.hs_a[0] == 0) table.load2300();
    v.nk = 1;
    v.i = 0;
    return .{ .go = .l2320b };
}

fn l2320b() flow.Act {
    while (v.i <= 9) : (v.i += 1) {
        if (v.scre > v.hs_a[B.ix(10, v.i)]) {
            table.insert2315();
            return .{ .call = .{ .to = .l2260, .ret = .l2310 } };
        }
    }
    v.nk = 0;
    v.scre = 0;
    return .ret;
}

/// 2310: "Enter Your Name !", the score and kills on the new line.
fn l2310() flow.Act {
    scene.off();
    table.prompt2310();
    input.clearKey();
    v.ok = 0;
    return .{ .go = .l2311 };
}

/// 2311-2314: one key a VBL; the cursor cell drawn in paper 15.
fn l2311() flow.Act {
    const c = input.inkey() orelse {
        table.cursor2311();
        return .{ .wait = .{ .vbls = 1, .then = .l2311 } };
    };
    if (table.key2311(c)) return .{ .wait = .{ .vbls = 1, .then = .l2311 } };
    v.hs_s_a[B.ix(10, v.i)] = v.hs_s;
    S.fadeBlack(1);
    clearAll();
    boot.unpackTo(assets.SKYPIC1, .b5);
    S.bar(0, 0, 319, 199);
    v.i = 99;
    S.fadeBlack(1);
    v.i += 1;
    v.nk = 0;
    v.scre = 0;
    return .ret;
}

