// --------------------------------------------------------------------------
// 190 (a key or a click, then the button let go), 220-229 (the pilot on the
// ground: SPLAT without a parachute; a plane lost; no more planes or killed:
// game over, music 2, a key, the title), 2700 (the error trap).
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const input = @import("input.zig");
const text = @import("text.zig");
const flow = @import("flow.zig");
const scene = @import("scene.zig");
const vehicles = @import("vehicles.zig");
const sfx = @import("sfx.zig");
const snd = @import("sound.zig");
const levels = @import("levels.zig");
const hooks = @import("zig_hooks.zig");
const V = @import("vars.zig");
const v = &V.v;

pub const steps = [_]flow.Entry{
    .{ .l = .l190a, .f = l190a }, .{ .l = .l190b, .f = l190b }, .{ .l = .l190c, .f = l190c },
    .{ .l = .l220, .f = l220 },   .{ .l = .l225, .f = l225 },   .{ .l = .l227b, .f = l227b },
    .{ .l = .l23, .f = l23 },     .{ .l = .l2700, .f = l2700 }, .{ .l = .l2700b, .f = l2700b },
};

/// 190: clear key : while inkey$ = "" and mouse key = 0 : wend
fn l190a() flow.Act {
    input.clearKey();
    return .{ .go = .l190b };
}

fn l190b() flow.Act {
    if (input.inkey() == null and S.mouseKey() == 0) return .{ .wait = .{ .vbls = 1, .then = .l190b } };
    return .{ .go = .l190c };
}

/// ... while mouse key <> 0 : wend : return
fn l190c() flow.Act {
    if (S.mouseKey() != 0) return .{ .wait = .{ .vbls = 1, .then = .l190c } };
    return .ret;
}

/// 23: goto 2000
fn l23() flow.Act {
    return .{ .go = .l2000 };
}

/// 220-222: down without the canopy open: SPLAT and the title; else a
/// plane lost -- the next one, or the end.
fn l220() flow.Act {
    if (v.pr != 63) {
        S.sprite_(1, v.px, 160, 58);
        return .{ .call = .{ .to = .l190a, .ret = .l23 } };
    }
    v.planes -= 1;
    vehicles.ownWreck980();
    if (v.planes > 0) return .{ .go = .l34 };
    v.crsh = 0;
    v.eng = 0;
    sfx.engine();
    return .{ .go = .l225 };
}

/// 225-227: the verdict boxed, music 2, a key.
fn l225() flow.Act {
    v.mes_s.set(if (v.crsh == 0) "No More Aircraft !" else "You Were Killed !");
    snd.samstop();
    snd.music(2, .gameover);
    scene.message1506();
    return .{ .call = .{ .to = .l190a, .ret = .l227b } };
}

/// ... music off : 229 goto 23
fn l227b() flow.Act {
    snd.musicEnd(.title);
    return .{ .go = .l2000 };
}

/// 2700: mode 0 : print "Error#"; errn ;" in "; errl : wait key : end.
/// A missing MISSIONS.DAT record leads here, and a disk's level file that
/// levels.zig refused (its reason printed instead); END is the title.
fn l2700() flow.Act {
    hooks.shows(.picture);
    if (levels.err != null) {
        @import("pal.zig").plain();
        text.pen = 1;
        text.paper = 0;
        text.clw();
    }
    text.locate(0, 0);
    text.write(levels.err orelse "Error# 62  in  1665");
    text.newline();
    input.clearKey();
    return .{ .go = .l2700b };
}

fn l2700b() flow.Act {
    // A refused level file is not played around: the built-in set would pass
    // for the disk's. The cart stays on the message (Escape leaves).
    if (input.inkey() == null or levels.err != null) return .{ .wait = .{ .vbls = 1, .then = .l2700b } };
    return .{ .go = .l2000 };
}
