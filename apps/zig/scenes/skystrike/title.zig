// --------------------------------------------------------------------------
// Lines 2000-2134: the title (the credits scroller, the timeout to the hall
// of fame) and the difficulty menu; 2112 / 2285 the title plane and flag.
//
// The scroller loop (2005-2007) has no VBL wait: it runs as fast as the
// compiled code goes, 6.5 passes a VBL on the ST (measured: TI from 9264 to
// 9589 in 50 VBLs), so the text moves ~2.2 pixels a VBL and the title gives
// way to the hall of fame after TI = 10000, ~31 seconds.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const scr = @import("scr.zig");
const text = @import("text.zig");
const sprite = @import("sprite.zig");
const move = @import("move.zig");
const input = @import("input.zig");
const B = @import("basic.zig");
const flow = @import("flow.zig");
const V = @import("vars.zig");
const v = &V.v;

pub const steps = [_]flow.Entry{
    .{ .l = .l2000, .f = l2000 },  .{ .l = .l2000b, .f = l2000b },
    .{ .l = .l2005, .f = l2005 },  .{ .l = .l2005b, .f = l2005b },
    .{ .l = .l2006, .f = l2006 },  .{ .l = .l2010, .f = l2010 },
    .{ .l = .l2120, .f = l2120 },  .{ .l = .l2123, .f = l2123 },
    .{ .l = .l2124, .f = l2124 },  .{ .l = .l2126, .f = l2126 },
    .{ .l = .l2126b, .f = l2126b }, .{ .l = .l2131, .f = l2131 },
};

const CREDITS = " Skystrike ......... Game + Music : Aaron Fothergill .. Graphics: Adam Fothergill .. Test Pilots : Bob & Steven Baker , Paul & Darren O'Donnell , Jason Tucker,Mike Newett & Lee Davey   A Shadow Software Production      ";

/// Loop passes per VBL, as a fraction: 13 / 2 = 6.5.
pub const PASS_NUM: u32 = 13;
pub const PASS_DEN: u32 = 2;

/// 2000: off : tsc = 1 : gosub 2350
fn l2000() flow.Act {
    move.off();
    v.tsc = 1;
    return .{ .call = .{ .to = .l2350, .ret = .l2000b } };
}

/// ... tsc = 0 : the STOS logo : 2004 the SKY STRIKE logo : mes$ = credits
/// 2005: def scroll 1,80,40 to 256,48,-1,0 : paper 14 : pen 0 : clear key
fn l2000b() flow.Act {
    v.tsc = 0;
    logos();
    v.mes_s.set(CREDITS);
    S.paper(14);
    S.pen(0);
    input.clearKey();
    return .{ .go = .l2005 };
}

pub fn logos() void {
    S.copy(.b5, 64, 176, 128, 194, .back, 256, 184);
    S.copy(.back, 256, 184, 320, 200, .physic, 256, 184);
    S.copy(.b6, 96, 64, 192, 76, S.lg(), 112, 16);
}

/// while mouse key <> 0 : wend : ti = 0
fn l2005() flow.Act {
    if (S.mouseKey() != 0) return .{ .wait = .{ .vbls = 1, .then = .l2005 } };
    v.ti = 0;
    return .{ .go = .l2006 };
}

var budget: u32 = 0;

/// while inkey$ = "" and mouse key = 0 and ti < 10000 : ... wend, one
/// VBL's worth of passes at a time.
fn l2006() flow.Act {
    budget += PASS_NUM;
    while (budget >= PASS_DEN) {
        budget -= PASS_DEN;
        if (input.inkey() != null or S.mouseKey() != 0 or v.ti >= 10000) return .{ .go = .l2005b };
        pass();
    }
    return .{ .wait = .{ .vbls = 1, .then = .l2006 } };
}

/// 2005-2006: inc ti : every 24, the next letter at 30,5 ; every 3, scroll.
fn pass() void {
    v.ti += 1;
    if (B.mod(v.ti, 24) == 0) {
        S.locate(30, 5);
        const m = v.mes_s.get();
        S.write(m[0..@min(1, m.len)]);
        text.newline();
        rotate();
    }
    if (B.mod(v.ti, 3) == 0) {
        scroll1();
        S.update();
    }
}

/// mes$ = mid$(mes$,2) + left$(mes$,1)
fn rotate() void {
    const m = v.mes_s.get();
    if (m.len < 2) return;
    var tmp: [300]u8 = undefined;
    @memcpy(tmp[0 .. m.len - 1], m[1..]);
    tmp[m.len - 1] = m[0];
    v.mes_s.set(tmp[0..m.len]);
}

/// SCROLL 1: the zone 80,40 to 256,48 moved one pixel left on logic.
fn scroll1() void {
    const p = scr.get(scr.logic);
    var y: usize = 40;
    while (y < 48) : (y += 1) {
        const row = p[y * 320 ..][0..320];
        @memmove(row[80..255], row[81..256]);
    }
}

/// 2007: wend : if ti >= 10000 then 2281
fn l2005b() flow.Act {
    if (v.ti >= 10000) return .{ .go = .l2281 };
    return .{ .go = .l2010 };
}

/// 2010: gosub 2120 : goto 25
fn l2010() flow.Act {
    return .{ .call = .{ .to = .l2120, .ret = .l25 } };
}

/// 2120: tsc = 1 : gosub 2350 : tsc = 0 : logos
fn l2120() flow.Act {
    v.tsc = 1;
    return .{ .call = .{ .to = .l2350, .ret = .l2123 } };
}

/// 2120 (after the gosub): tsc = 0 : logos  2123: the menu's title
fn l2123() flow.Act {
    v.tsc = 0;
    logos();
    S.paper(4);
    S.pen(15);
    S.locate(0, 4);
    S.centre("Select Difficulty with Joystick");
    return .{ .go = .l2124 };
}

/// 2124: while fire <> 0 : wend   2125: dif = 0
fn l2124() flow.Act {
    if (S.fire() != 0) return .{ .wait = .{ .vbls = 1, .then = .l2124 } };
    v.dif = 0;
    return .{ .go = .l2126 };
}

/// 2126-2128: the three lines, the choice on green; 2129: wait 5
fn l2126() flow.Act {
    menuLines();
    return .{ .wait = .{ .vbls = 5, .then = .l2126b } };
}

fn menuLines() void {
    const items = [_][]const u8{
        "(1) Easy . Fuel + Autoland",
        "(2) Medium . Autoland +50,000 pts",
        "(3) Hard  . 200,000 pts bonus",
    };
    for (items, 0..) |s, k| {
        S.paper(14 + B.t(v.dif == @as(i32, @intCast(k))) * 12);
        S.pen(0);
        S.locate(4, 6 + 2 * @as(i32, @intCast(k)));
        S.print(s);
    }
}

/// 2129-2131: after the wait 5, the stick moves the choice, FIRE takes it.
fn l2126b() flow.Act {
    if (S.jup() != 0) {
        v.dif = B.mod(v.dif - 1 + 3, 3);
        return .{ .go = .l2126 };
    }
    if (S.jdown() != 0) {
        v.dif = B.mod(v.dif + 1, 3);
        return .{ .go = .l2126 };
    }
    if (S.fire() == 0) return .{ .go = .l2126 };
    return .{ .go = .l2131 };
}

/// 2132-2134
fn l2131() flow.Act {
    v.atlf = 1;
    v.fust = 5000;
    if (v.dif > 0) {
        v.fust = 3000;
        v.scre = 50000;
    }
    if (v.dif == 2) {
        v.atlf = 0;
        v.scre = 200000;
    }
    return .ret;
}

/// 2112: the title plane: sprite 2 from -500,130 flying 4 pixels a VBL
/// right then left for ever, changing image every 250 VBLs.
pub fn plane() void {
    S.sprite_(2, -500, 130, 9);
    move.moveX(2, .{ .a = .{ 1, 1, 0, 0, 0, 0, 0, 0 }, .b = .{ 4, -4, 0, 0, 0, 0, 0, 0 }, .c = .{ 250, 250, 0, 0, 0, 0, 0, 0 }, .n = 2, .loop = true });
    move.anim(2, .{ .a = .{ 9, 1, 88, 80, 9, 96, 0, 0 }, .b = .{ 250, 250, 250, 250, 250, 250, 0, 0 }, .n = 6, .loop = true });
    flag();
}

/// 2285-2286: at a base, the flag (sprite 1) waves; anim on : move on
fn flag() void {
    if (B.mod(v.sx, 10) == 0) {
        S.sprite_(1, 50, 136, 68);
        move.anim(1, .{ .a = .{ 68, 69, 0, 0, 0, 0, 0, 0 }, .b = .{ 12, 12, 0, 0, 0, 0, 0, 0 }, .n = 2, .loop = true });
    }
    move.animOn();
    move.moveOn();
}
