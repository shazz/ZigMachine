// --------------------------------------------------------------------------
// The helpers every unit routine shares, transcribed routine by routine from
// ns.app (flat addresses in the comments): animation step, terrain lookup,
// hit test, first live slot, the y-sorted draw list, spawning, re-forming and
// reserves. Every value keeps its 68000 width (Mem.setw wraps to 16 bits).
// --------------------------------------------------------------------------
const mem = @import("mem.zig");
const ad = @import("addr.zig");
const Game = @import("game.zig").Game;

const B = mem.B;
const s16 = mem.s16;
const obj = ad.obj;

/// $B0B8: next frame of an object's 4-frame script ($FFFF = loop back).
pub fn animStep(g: *Game, o: u32) void {
    const m = &g.m;
    g.cost.add(.anim, 1);
    if (m.w(ad.ANIM_CHANGE) != 0) {
        const st = m.w(o + 6);
        if (st == 0x0A or st == 3 or st == 0x1B) m.setl(o + 8, m.l(ad.ANIM_NEW));
    }
    if (m.derefW(m.l(o + 8)) == -1) m.setl(o + 8, m.l(o + 8) -% 8);
    m.setw(o + 4, m.derefW(m.l(o + 8)));
    m.setl(o + 8, m.l(o + 8) +% 2);
}

/// $ADFE: the terrain cell under (x, y). Out of the 40x50 grid it reads what
/// lies before or after it, as the original does.
pub fn gridAt(g: *Game, x: i32, y: i32) i32 {
    const m = &g.m;
    g.cost.add(.grid, 1);
    const col = s16(if (m.w(ad.SIDE_BASE) != 0) @divTrunc(x + 10, 8) else @divTrunc(x + 2, 8));
    const row = s16(@divTrunc(y - 2, 4));
    return m.sb(@bitCast(@as(i32, ad.GRID) + col * 50 + row));
}

/// $AE5E: the x a hit is measured from; decor slots return the caller's d0.
fn hitX(g: *Game, k: i32, d0: i32) i32 {
    const lims = [_][2]i32{ .{ 3, 10 }, .{ 6, 6 }, .{ 12, 4 }, .{ 15, 18 }, .{ 18, 6 }, .{ 24, 10 } };
    for (lims) |e| if (k < e[0]) return s16(g.m.w(obj(k)) + e[1]);
    return d0;
}

/// $AF24: walk the y-sorted list; mark the first... every object in the box hit.
pub fn hitTest(g: *Game, x: i32, y: i32, dy: i32, dx: i32) bool {
    const m = &g.m;
    var p: u32 = ad.DRAW;
    var hit = false;
    const base = m.w(ad.SIDE_BASE);
    g.cost.add(.hits, 1);
    // The list ends at a y >= 200 sentinel. The bound only stops a list that
    // lost it from spinning forever; running into it counts as a miss.
    while (p < mem.HI) : (p += 1) {
        const k = m.b(p);
        g.cost.add(.hit_it, 1);
        const oy = m.w(obj(k) + 2);
        if (s16(y + dy) <= oy) return hit;
        if (s16(y - dy) > oy) continue;
        const xc = hitX(g, k, (k * 12) & 0xFFFF);
        if (!(s16(x - dx) < xc and xc < s16(x + dx))) continue;
        const own = if (base != 0) ad.SIDE_B else ad.SIDE_A;
        var ok = false;
        if (m.w(own + ad.S_BLAST) == 4 and m.w(own + ad.S_CPU) == 0) {
            ok = true; // the human's shell: friendly fire
        } else if (m.w(own + ad.S_CPU) == 1 and m.w(m.l(ad.AI_SLOT_PTR) -% B + 6) == m.w(own + ad.S_AI_CAN + 6)) {
            ok = true; // the CPU's cannon slot is acting
        } else if (base != 0) {
            ok = k < 12;
        } else {
            ok = k >= 12 and k < 24;
        }
        const st = m.w(obj(k) + 6);
        if (ok and st != 0 and st != 0x17 and st != 0x65 and st != 0x1D and st != 5 and st != 0x13) {
            hit = true;
            m.setw(obj(k) + 6, 0x65);
        }
    }
    mem.misses += 1;
    return hit;
}

/// $D4D0: the first live slot from `first`, or -1 past `end`.
pub fn firstAlive(g: *Game, first: i32, end: i32) i32 {
    var d6: i32 = 0;
    // With no live slot the original reads on past the objects; stop at the
    // end of the RAM window (a miss), which is past `end` too: still -1.
    while (obj(first + d6) < mem.HI) : (d6 += 1) {
        const st = g.m.w(obj(first + d6) + 6);
        if (st != 0 and st != 0x17) break;
    } else mem.misses += 1;
    return if (first + d6 < end) first + d6 else -1;
}

/// $D664: re-sort object idx in the draw list for its new y.
pub fn drawMove(g: *Game, y: i32, idx: i32) void {
    const m = &g.m;
    var c: i32 = -1;
    var a: i32 = -1;
    var i: u32 = 0;
    g.cost.add(.dm, 1);
    while ((c < 0 or a < 0) and ad.DRAW + i < mem.HI) : (i += 1) {
        g.cost.add(.dm_it, 1);
        const k = m.b(ad.DRAW + i);
        if (k == idx and a < 0) a = @intCast(i);
        if (y <= m.w(obj(k) + 2) and c < 0) c = @intCast(i);
    }
    if (c < 0 or a < 0) { // idx not in the list, or no sentinel: a corrupted list
        mem.misses += 1;
        return;
    }
    if (c - a == 1) c = a;
    const D: i32 = ad.DRAW;
    if (c < a) {
        var j = a;
        while (j > c) : (j -= 1) m.setb(@intCast(D + j), m.b(@intCast(D + j - 1)));
    } else if (c > a) {
        var j = a;
        while (j < c) : (j += 1) m.setb(@intCast(D + j), m.b(@intCast(D + j + 1)));
    }
    if (c - a <= 1) m.setb(@intCast(D + c), idx) else m.setb(@intCast(D + c - 1), idx);
}

/// $D7A8: insert object idx into the draw list at its y.
pub fn drawInsert(g: *Game, y: i32, idx: i32) void {
    const m = &g.m;
    const n = m.w(ad.DECOR_END);
    var i: i32 = 0;
    const D: i32 = ad.DRAW;
    while (i < n) : (i += 1) {
        if (y <= m.w(obj(m.b(@intCast(D + i))) + 2)) {
            var j = n;
            while (j > i) : (j -= 1) m.setb(@intCast(D + j), m.b(@intCast(D + j - 1)));
            m.setb(@intCast(D + i), idx);
            i = n;
        }
    }
}

/// $D838: `count` objects in formation `form` (a RAM pointer) from (x, y).
pub fn spawn(g: *Game, first: i32, count: i32, state: i32, x: i32, y: i32, form_in: u32, resort: bool) void {
    const m = &g.m;
    var form = form_in;
    var k = first;
    while (k < first + count) : (k += 1) {
        const o = obj(k);
        g.cost.add(.spawn, 1);
        m.setw(o + 4, state);
        m.setw(o + 6, state);
        m.setw(o, m.derefSb(form) + x);
        form +%= 1;
        m.setw(o + 2, m.derefSb(form) + y);
        form +%= 1;
        if (m.w(o + 6) != 0) {
            if (resort) drawMove(g, m.w(o + 2), k) else drawInsert(g, m.w(o + 2), k);
        }
    }
}

/// $D522: every unit steps 1 px per axis toward leader + formation offset.
/// Returns 2 while someone moved, 0 once all are in place.
pub fn reform(g: *Game, first: i32, o_in: u32, count: i32, form_in: u32) i32 {
    const m = &g.m;
    var o = o_in;
    var form = form_in;
    var k: i32 = 0;
    while (true) {
        const st = m.w(o + 6);
        if (st == 0x0A or st == 3) break;
        o += 12;
        k += 1;
        if (k >= count) break; // == in the original; >= also ends a count <= 0, which returns 0 either way
    }
    const x0 = m.w(o);
    const y0 = m.w(o + 2);
    var flag: i32 = 0;
    var i = k;
    const d = m.w(ad.DIR);
    g.cost.add(.reform, 1);
    while (i < count) : (i += 1) {
        const st = m.w(o + 6);
        if (st != 0 and st != 0x17) {
            const dx = s16(mem.muluW(m.derefSb(form), d) + x0 - m.w(o));
            form +%= 1;
            if (dx > 0) {
                flag = 2;
                m.addw(o, 1);
            }
            if (dx < 0) {
                flag = 2;
                m.addw(o, -1);
            }
            const dy = s16(m.derefSb(form) + y0 - m.w(o + 2));
            form +%= 1;
            if (dy > 0) {
                flag = 2;
                drawMove(g, s16(m.w(o + 2) + 1), first + i);
                m.addw(o + 2, 1);
            }
            if (dy < 0) {
                flag = 2;
                m.addw(o + 2, -1);
            }
        }
        o += 12;
    }
    return flag;
}

/// $D296: a fresh squad from the reserves (t = 6 infantry, 3 cavalry).
pub fn reinforce(g: *Game, t: i32) bool {
    const m = &g.m;
    const b = m.w(ad.SIDE_BASE) != 0;
    const rec = m.l(if (b) ad.REC_B else ad.REC_A) -% B;
    const s = if (b) ad.SIDE_B else ad.SIDE_A;
    const x: i32 = if (b) 0x14A else -30;
    if (t == 6) {
        const n = m.b(rec + 1);
        if (n == 0) return false;
        const first: i32 = if (b) 0x12 else 6;
        spawn(g, first, @min(n, 6), 3, x, if (b) 0x32 else 0x28, ad.T_LINE_A + B, true);
        m.setl(s + ad.S_INFFORM, ad.T_LINE_A + B);
        m.addw(s + ad.S_ENTER, 1);
        m.setw(s + ad.S_INFLEAD, first);
    } else {
        const n = m.b(rec + 2);
        if (n == 0) return false;
        const first: i32 = if (b) 0x0F else 3;
        spawn(g, first, @min(n, 3), 0x0A, x, 0x8C, ad.T_LINE_A + B, true);
        m.setl(s + ad.S_CAVFORM, ad.T_LINE_A + B);
        m.addw(s + ad.S_ENTER, 2);
        m.setw(s + ad.S_CAVLEAD, first);
        m.setw(s + ad.S_CAVHALT, 2);
    }
    return true;
}
