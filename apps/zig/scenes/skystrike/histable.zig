// --------------------------------------------------------------------------
// The hall of fame's table: 2300-2305 read (SPITFIRE.HSC: name, score,
// kills x 10, then two unused numbers), 2270-2274 drawn, 2315-2319 a new
// place opened, 2310-2313 the name typed into it.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const text = @import("text.zig");
const pal = @import("pal.zig");
const blocks = @import("blocks.zig");
const B = @import("basic.zig");
const files = @import("files.zig");
const assets = @import("assets.zig");
const V = @import("vars.zig");
const v = &V.v;

/// 2302-2305
pub fn load2300() void {
    var r = files.Reader{ .s = assets.SPITFIRE_HSC };
    for (0..10) |a| {
        v.hs_s_a[a].set(r.field(true));
        v.hs_a[a] = r.int();
        v.kls_a[a] = r.int();
    }
    v.alien = r.int();
    v.recal = r.int();
    v.olrec = v.recal;
    v.oalien = v.alien;
}

fn row(a: i32) i32 {
    return a + 6 + B.sgn(a);
}

/// right$(zeros + mid$(str$(n), 2), 9)
fn digits(buf: []u8, zeros: usize, n: i32) []const u8 {
    var nb: [12]u8 = undefined;
    const s = text.str(&nb, n)[1..];
    @memset(buf[0..zeros], '0');
    @memcpy(buf[zeros..][0..s.len], s);
    const all = buf[0 .. zeros + s.len];
    return all[all.len - 9 ..];
}

/// 2270-2274: drawn on logic (= back), pasted row by row over bank 5.
pub fn draw2270() void {
    S.pen(1);
    S.paper(0);
    text.under = true;
    S.locate(1, 2);
    S.centre("The Aces");
    S.ink(0);
    text.under = false;
    const heads = [_]struct { x: i32, s: []const u8 }{ .{ .x = 4, .s = "Pilot" }, .{ .x = 23, .s = "Score" }, .{ .x = 34, .s = "Kills" } };
    for (heads) |h| {
        S.locate(h.x, 4);
        S.print(h.s);
    }
    var a: i32 = 0;
    while (a < 10) : (a += 1) line(a);
    v.a = 10;
    var k: i32 = 1;
    while (k <= 16) : (k += 1) S.move(.b5, 0, k * 10, .back, 0, k * 10, 320, k * 10 + 10);
    blocks.copyAll(.b5, .back);
}

fn line(a: i32) void {
    const i: usize = @intCast(a);
    var nb: [12]u8 = undefined;
    var db: [24]u8 = undefined;
    S.pen(1);
    S.locate(0, row(a));
    S.print(text.str(&nb, a + 1));
    S.locate(5, row(a));
    S.print(v.hs_s_a[i].get());
    S.locate(23, row(a));
    S.print(digits(&db, 9, v.hs_a[i]));
    S.locate(34, row(a));
    S.print(text.str(&nb, v.kls_a[i]));
}

/// 2315-2319: the lower places move down; place i gets dots, the score.
pub fn insert2315() void {
    const i: usize = @intCast(v.i);
    var z: usize = 9;
    while (z > i) : (z -= 1) {
        v.hs_s_a[z] = v.hs_s_a[z - 1];
        v.hs_a[z] = v.hs_a[z - 1];
        v.kls_a[z] = v.kls_a[z - 1];
    }
    v.z = @intCast(z);
    v.hs_s_a[i].set("...............");
    v.hs_a[i] = v.scre;
    v.kls_a[i] = v.kls;
}

/// 2310: the prompt, the flashing colour 2, the score and kills.
pub fn prompt2310() void {
    S.paper(3);
    S.pen(2);
    pal.flash(2, &.{ 0x776, 0x774, 0x772, 0x774, 0x776 }, &.{ 15, 15, 15, 15, 15 });
    S.locate(1, 1);
    S.centre("Enter Your Name !");
    v.vv = row(v.i);
    v.h = 5;
    v.hs_s.set("               ");
    var db: [24]u8 = undefined;
    S.locate(23, v.vv);
    S.print(digits(&db, 8, v.scre));
    S.locate(34, v.vv);
    var nb: [12]u8 = undefined;
    S.write(text.str(&nb, v.kls));
}

/// The inner loop's body: the cursor cell (paper 15, pen 0).
pub fn cursor2311() void {
    S.paper(15);
    S.pen(0);
    v.c = B.mod(v.c + 1, 16);
    S.locate(v.h, v.vv);
    const n = v.hs_s.get();
    const k: usize = @intCast(@max(0, v.h - 5));
    S.write(if (k < n.len) n[k .. k + 1] else "");
}

/// 2311-2313 with the key: false once Enter ends the name.
pub fn key2311(c: u8) bool {
    cursor2311();
    S.pen(2);
    S.paper(3);
    if (c == 13) v.ok = 1;
    if (c == 8) {
        v.h = @max(5, v.h - 1);
        S.locate(5, v.vv);
        S.write(v.hs_s.get());
    }
    if (c >= ' ') {
        const k: usize = @intCast(v.h - 5);
        if (k < v.hs_s.len) v.hs_s.buf[k] = c;
        v.h += 1;
        S.locate(5, v.vv);
        S.write(v.hs_s.get());
        v.h = @min(19, v.h);
    }
    return v.ok == 0;
}
