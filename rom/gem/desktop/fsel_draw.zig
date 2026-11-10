// --------------------------------------------------------------------------
// The ITEM SELECTOR's frame on the GEM 5 engine (G21): fsel_tree.zig's TOS 4
// tree built from the selector's state, hit-tested by its object indices, drawn
// in the program look (gui/proglook.zig: flat TOS 1 or 3D TOS 4).
//
// What a press does (TOS 4's fsel_input, our way): a drive button re-roots the
// spec at that drive (`X:\` + the mask) and answers `relist`; the closer goes up
// a folder, a folder row opens it, a file row fills Selection:; the arrows step
// a row and the track pages; the Directory: line takes the caret (Return or a
// click in the list re-reads it); OK (or Return) and Cancel close. A button
// fires on the frame the press starts, as every ROM button does.
// --------------------------------------------------------------------------
const std = @import("std");
const gui = @import("../gui.zig");
const obj = @import("../engine/obj.zig");
const draw = @import("../engine/draw.zig");
const Rect = @import("../engine/rect.zig").Rect;
const T = @import("fsel_tree.zig");
const fpath = @import("filesel_path.zig");
const listCells = @import("namefield.zig").listCells;
const proglook = gui.proglook;
const FileSel = @import("filesel.zig").FileSel;
const Result = @import("filesel.zig").Result;
const Id = T.Id;

const DIR_CELLS = 37;

// The text the tree shows, kept for the frame (the tree points into it).
const Texts = struct {
    dir: [DIR_CELLS]u8 = @splat('_'),
    sel: [12]u8 = undefined,
    rows: [T.ROWS][14]u8 = undefined,
};

fn view(f: *const FileSel, tx: *Texts) T.View {
    const spec = f.path.text();
    const shown = spec[spec.len -| DIR_CELLS..];
    @memcpy(tx.dir[0..shown.len], shown);
    var v: T.View = .{ .title = spec, .dir = &tx.dir, .sel = f.name.cells(&tx.sel), .mask = fpath.mask(spec), .rows = undefined, .picked = f.list.sel, .top = f.list.top, .n = f.list.n, .drives = f.drivesShown(), .drive = f.driveOf() };
    for (0..T.ROWS) |i| {
        const idx = f.list.top + i;
        var cells: [12]u8 = undefined;
        tx.rows[i][0] = ' ';
        tx.rows[i][1] = ' ';
        @memcpy(tx.rows[i][2..], listCells(if (idx < f.list.n) f.list.nameAt(idx) else "", &cells));
        v.rows[i] = &tx.rows[i];
        v.folder[i] = f.list.isDir(idx);
    }
    return v;
}

fn hit(t: []const obj.Object, i: i16, g: *const gui.Gui) bool {
    const r = obj.offset(t, i) orelse return false;
    return r.contains(g.px, g.py);
}

/// The object under the pointer among those a press acts on, NIL for none.
fn under(t: []const obj.Object, g: *const gui.Gui) i16 {
    const ids = [_]i16{ Id.OK, Id.CANCEL, Id.CLOSER, Id.UP, Id.DOWN, Id.SLIDER, Id.TRACK, Id.DIR, Id.SEL };
    for (ids) |i| if (hit(t, i, g)) return i;
    for (0..T.DRIVES) |k| if (hit(t, Id.DRIVE0 + @as(i16, @intCast(k)), g)) return Id.DRIVE0 + @as(i16, @intCast(k));
    for (0..T.ROWS) |k| if (hit(t, T.ROW0 + @as(i16, @intCast(k)), g)) return T.ROW0 + @as(i16, @intCast(k));
    if (hit(t, T.LIST, g)) return T.LIST;
    return obj.NIL;
}

pub fn frame(f: *FileSel, g: *gui.Gui) Result {
    var tx: Texts = .{};
    var s: T.Store = .{};
    var v = view(f, &tx);
    const t0 = T.build(&s, &v, g.screen.w, g.screen.h);
    const at = under(t0, g);
    const slider = (obj.offset(t0, Id.SLIDER) orelse Rect{}).y;
    const res = act(f, g, at, slider);
    v = view(f, &tx); // drawn as the press left it
    if (g.down and (at == Id.OK or at == Id.CANCEL)) v.pressed = at;
    if (!f.active) return res; // closed: the caller repaints what was under it
    const sig = signature(f, g, &tx, &v);
    const box = boxOf(g, &s, &v);
    if (sig == f.painted and probe(g, box) == f.probe) { // the same box, still on screen: no repaint
        gui.clip.record(g, .{ .x = box.x, .y = box.y, .w = box.w, .h = box.h }); // (the board shows a repaint half drawn: it flashed, 10 Nov)
        return res;
    }
    paint(f, g, &s, &v);
    f.painted = sig;
    f.probe = probe(g, box);
    return res;
}

// The box's middle row and middle column as they are on screen: a program that painted over the
// box (its windows behind, a mode change) changes them, so the box is drawn again. ~500 reads.
fn probe(g: *const gui.Gui, r: Rect) u64 {
    var hs = std.hash.Wyhash.init(0xF5E1);
    const h: i32 = @min(@as(i32, g.screen.h), @as(i32, g.fb.fb_h));
    const x0: i32 = @max(r.x, 0);
    const x1: i32 = @min(@as(i32, r.x) + r.w, @as(i32, g.screen.w));
    const y0: i32 = @max(r.y, 0);
    const y1: i32 = @min(@as(i32, r.y) + r.h, h);
    if (x1 <= x0 or y1 <= y0) return 0;
    const st: usize = g.fb.stride;
    const ym: usize = @intCast(@divTrunc(y0 + y1, 2));
    hs.update(g.fb.fb[ym * st + @as(usize, @intCast(x0)) ..][0..@intCast(x1 - x0)]);
    const xm: usize = @intCast(@divTrunc(x0 + x1, 2));
    var y: i32 = y0;
    while (y < y1) : (y += 1) hs.update(&[_]u8{g.fb.fb[@as(usize, @intCast(y)) * st + xm]});
    return hs.final();
}

// Everything the box's pixels depend on: its texts, list position, pressed button, caret, look,
// screen and clip. A frame with the same signature would draw the same pixels.
fn signature(f: *const FileSel, g: *const gui.Gui, tx: *const Texts, v: *const T.View) u64 {
    var h = std.hash.Wyhash.init(0x5E1);
    h.update(v.title);
    h.update(std.mem.asBytes(tx));
    h.update(std.mem.asBytes(&v.folder));
    const nums = [_]i64{ v.picked, @intCast(v.top), @intCast(v.n), v.drives, v.drive, v.pressed, @intFromBool(f.on_path), f.path.caret, f.name.caretCol(), @intFromBool(proglook.three_d), g.screen.w, g.screen.h };
    h.update(std.mem.asBytes(&nums));
    if (g.clip) |c| h.update(std.mem.asBytes(&[_]i32{ c.x, c.y, c.w, c.h }));
    return h.final() | 1; // never 0: 0 is "not painted yet"
}

fn boxOf(g: *gui.Gui, s: *T.Store, v: *const T.View) Rect {
    const t = T.build(s, v, g.screen.w, g.screen.h);
    const lk = proglook.look(g);
    const e = draw.extent(&lk, &t[0], obj.offset(t, 0).?);
    return .{ .x = e.x, .y = e.y, .w = e.w, .h = e.h };
}

fn act(f: *FileSel, g: *gui.Gui, at: i16, slider_y: i16) Result {
    const reread = f.on_path and (g.enter or (g.edge and (at == T.LIST or (at >= T.ROW0 and at < T.ROW0 + T.ROWS))));
    if (reread) return f.relist();
    if (g.enter) return f.close(.ok);
    if (!g.edge or at == obj.NIL) return .none;
    if (at == Id.OK) return f.close(.ok);
    if (at == Id.CANCEL) return f.close(.cancel);
    if (at == Id.CLOSER) return if (f.path.up()) f.relist() else .none;
    const dead = proglook.breaks & proglook.BREAK_NODRIVE != 0; // the mutant: drive buttons do nothing
    if (at >= Id.DRIVE0 and at < Id.DRIVE0 + T.DRIVES) return if (dead) .none else f.toDrive(@intCast(at - Id.DRIVE0));
    if (at >= T.ROW0 and at < T.ROW0 + T.ROWS) return f.pickRow(f.list.top + @as(usize, @intCast(at - T.ROW0)));
    if (at == Id.UP) f.list.step(-1);
    if (at == Id.DOWN) f.list.step(1);
    if (at == Id.TRACK) f.list.step(if (g.py < slider_y) -@as(i32, T.ROWS) else T.ROWS);
    if (at == Id.DIR and fpath.dir(f.path.text()).len > 0) f.on_path = true;
    if (at == Id.SEL) f.on_path = false;
    return .none;
}

fn paint(f: *const FileSel, g: *gui.Gui, s: *T.Store, v: *const T.View) void {
    const t = T.build(s, v, g.screen.w, g.screen.h);
    const lk = proglook.look(g);
    var cv = proglook.canvasOf(g);
    draw.draw(&cv, &lk, t, 0, draw.MAX_DEPTH);
    const field: i16 = if (f.on_path) Id.DIR else Id.SEL;
    const r = obj.offset(t, field).?;
    const col: i16 = if (f.on_path) @intCast(@min(f.path.caret -| (f.path.len -| DIR_CELLS), DIR_CELLS)) else f.name.caretCol();
    cv.fill(.{ .x = r.x + col * 8, .y = r.y - 1, .w = 2, .h = 9 }, lk.ink(1)); // the caret
    const e = draw.extent(&lk, &t[0], obj.offset(t, 0).?);
    gui.clip.record(g, .{ .x = e.x, .y = e.y, .w = e.w, .h = e.h });
}
