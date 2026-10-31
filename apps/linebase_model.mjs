// The copper line-list rule (HW 1.10.0, fpga/review/COPPER_LINEBASE.md) as an independent model,
// for apps/linebase_check.mjs (machine-only) and apps/linebase_test_headless.mjs (the cart): from a
// plane's records, each line's source address, palette and which of its pixels show.
//   - LBASE v (in VRAM, else the list stops): row r reads v + (r - r0) * stride until the next one;
//   - an overscan or scroll plane adds HSCROLL (read after the record), no wrap;
//   - FLICK at the magic column opens a border band from that row down, and a visible line's sides;
//   - the frame starts from FB_BASE.
// `brk` drops one rule (the harnesses' --break): "persist", "hscroll", "stop", "reset".
export const OFF_VRAM = 0x1100, VRAM_END = OFF_VRAM + 0x100000, RH = 280;
export const REG_HSCROLL = 0x3C, REG_FB_COPPER = 0x78;

// A list's records from memory (region offset `at`, read32(off)): [line, [[op, ...args]]] in order,
// as machine/copper.zig reads them; it stops at the end HEAD or at the first word it cannot read.
export function decodeList(read32, at) {
    const recs = [];
    for (let guard = 0; guard < 4096; guard++) {
        const head = read32(at);
        if (head >>> 28 !== 0xF) break;
        const y = (head >>> 19) & 0x1FF, n = head & 0x3FF;
        if (y === 511) break;
        const ops = [];
        for (let i = 0; i < n; i++) {
            const w = read32(at + 4 + 4 * i), op = w >>> 28;
            if (op === 3) ops.push(["flick"]);
            else if (op === 5) ops.push(["lbase", w & 0x0FFFFFFF]);
            else if (op === 2) ops.push(["hs", w & 0xFFFF]);
            else if (op === 1) {
                const first = (w >>> 20) & 0xFF, k = (w >>> 12) & 0xFF, cols = [];
                for (let j = 0; j < k; j++) cols.push(read32(at + 4 + 4 * (i + 1 + j)));
                ops.push(["pal", first, cols]);
                i += k;
            } else if (op !== 0) ops.push(["bad"]);
        }
        recs.push([y, ops]);
        at += 4 + 4 * n;
    }
    return recs;
}

// cfg: { ovs, scroll, stride, fb (FB_BASE), hs0 (HSCROLL at the frame's start), pal (256 colours) }.
// Returns per covered line { y, addr, pal (this line's palette), open(x) }.
export function model(cfg, recs, brk = null) {
    const { ovs, stride } = cfg, rows = ovs ? RH : 200, oy = ovs ? 0 : 40;
    const byLine = new Map(recs);
    let lb = { off: brk === "reset" ? cfg.fb + 4 * stride : cfg.fb, row: 0, set: -1 };
    let hs = cfg.hs0, live = true, top = false, bot = false, pal = cfg.pal.slice();
    const out = [];
    for (let row = 0; row < rows; row++) {
        const y = oy + row;
        let flick = false;
        for (const [op, a, b] of (live && byLine.get(y)) || []) {
            if (op === "flick") flick = true;
            else if (op === "lbase") {
                if (a < OFF_VRAM || a >= VRAM_END) { if (brk !== "stop") { live = false; break; } continue; }
                lb = { off: a, row, set: row };
            } else if (op === "hs") hs = a;
            else if (op === "pal") { pal = pal.slice(); b.forEach((c, j) => { pal[a + j] = c; }); }
            else if (op === "bad") { live = false; break; }
        }
        const base = brk === "persist" && lb.set !== row ? cfg.fb + row * stride : lb.off + (row - lb.row) * stride;
        const addr = base + ((ovs && brk !== "hscroll") || cfg.scroll ? hs : 0);
        if (ovs && flick && y < 40) top = true;
        if (ovs && flick && y >= 240) bot = true;
        const band = y < 40 ? top : bot, sides = flick;
        out.push({ y, addr, pal, x0: ovs ? 0 : 40, w: ovs ? 400 : 320,
            open: (x) => !ovs || (y < 40 || y >= 240 ? band : sides || (x >= 40 && x < 360)) });
    }
    return out;
}

// The first pixel of `shot(x, y)` (physical colour) that the model's lines disagree with, or null.
export function firstMismatch(lines, read8, shot, bg) {
    for (const l of lines) for (let lx = 0; lx < l.w; lx++) {
        const x = l.x0 + lx, want = l.open(x) ? l.pal[read8(l.addr + lx)] : bg, got = shot(x, l.y);
        if (got !== want) return `line ${l.y} x ${x}: 0x${(got >>> 0).toString(16)}, want 0x${(want >>> 0).toString(16)}`;
    }
    return null;
}
