// --------------------------------------------------------------------------
// The main loop at $000E, as a table instead of thirteen hand-unrolled loops.
//
// Each part is `pre; do { Vsync; body } while (C < until)`, so its first body
// runs at C = the previous limit + 1 and its last AT the limit. The palette is
// the movem.l each part does before its first Vsync. The limits are the cmpi.l
// constants.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const st = @import("st.zig");
const wobble = @import("wobble.zig");
const curtain = @import("curtain.zig");
const typer = @import("typer.zig");
const prism = @import("prism.zig");
const distort = @import("distort.zig");

const Body = enum { wobble, curtain, typer, wipe, prism, distort };

const Pre = struct {
    fill: bool = false, // $0316: both screens to $FF
    pic1: bool = false, // $007A: the eye picture into both screens
    strip: bool = false, // $0452 on scrA
    clear_list: bool = false, // $04A0
    reset_typer: bool = false, // $254A = 0
};

const Part = struct { until: u32, palette: A.Palette, pre: Pre, body: Body, page: u8 = 0 };

pub const PARTS = [_]Part{
    .{ .until = 384, .palette = .porno, .pre = .{}, .body = .wobble }, // $004E
    .{ .until = 576, .palette = .eye, .pre = .{ .pic1 = true, .strip = true, .reset_typer = true }, .body = .curtain }, // $00B0
    .{ .until = 1100, .palette = .eye, .pre = .{}, .body = .typer, .page = 0 }, // $00DC
    .{ .until = 1200, .palette = .eye, .pre = .{}, .body = .wipe }, // $0110
    .{ .until = 1968, .palette = .prism, .pre = .{}, .body = .prism }, // $0156
    .{ .until = 2160, .palette = .eye, .pre = .{ .strip = true, .clear_list = true, .reset_typer = true }, .body = .curtain }, // $019A
    .{ .until = 2636, .palette = .eye, .pre = .{}, .body = .typer, .page = 1 }, // $01C6
    .{ .until = 2736, .palette = .eye, .pre = .{}, .body = .wipe }, // $01FA
    .{ .until = 3504, .palette = .distort, .pre = .{}, .body = .distort }, // $0240
    .{ .until = 3696, .palette = .eye, .pre = .{ .strip = true, .reset_typer = true }, .body = .curtain }, // $0280: no list clear
    .{ .until = 4172, .palette = .eye, .pre = .{}, .body = .typer, .page = 2 }, // $02AC
    .{ .until = 4272, .palette = .eye, .pre = .{}, .body = .wipe }, // $02E0
    .{ .until = 4656, .palette = .porno, .pre = .{ .fill = true }, .body = .wobble }, // $033A
};

pub const END: u32 = PARTS[PARTS.len - 1].until;

/// The part whose bodies cover counter value `c` (1..END).
pub fn partAt(c: u32) usize {
    for (PARTS, 0..) |p, i| {
        if (c <= p.until) return i;
    }
    return PARTS.len - 1;
}

/// The part's once-only steps, before its first Vsync.
pub fn enter(m: *st.Machine, i: usize) void {
    const p = PARTS[i];
    if (p.pre.fill) st.fillBoth();
    if (p.pre.pic1) st.copyPic1();
    if (p.pre.strip) st.stripFill(m.scrA());
    if (p.pre.clear_list) @memset(&m.list, 0);
    if (p.pre.reset_typer) m.typed = 0;
    m.palette = p.palette;
}

/// One body, at the counter the VBL has just advanced to.
pub fn body(m: *st.Machine, i: usize) void {
    const p = PARTS[i];
    switch (p.body) {
        .prism => prism.frame(m.flip(), m.f),
        .distort => distort.frame(m.flip(), m.f, &m.list),
        else => {
            // The single-buffered parts: base := scrA, and draw on screen.
            m.base = m.scr_a;
            const scr = m.scrA();
            switch (p.body) {
                .wobble => {
                    wobble.rows(m.f, &m.list);
                    wobble.draw(scr, m.f, &m.list);
                },
                .typer => typer.typeChar(scr, m, p.page),
                .wipe => typer.wipe(scr, m.c - PARTS[i - 1].until),
                else => {},
            }
            if (p.body != .wobble) {
                curtain.draw(scr, m);
                curtain.rows(m.f, &m.list);
            }
        },
    }
}
