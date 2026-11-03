// The ZIG-mode half of apps/grodan_kvack_headless.mjs (Z toggles the KESTREL
// showcase: apps/zig/scenes/grodan_kvack/zig_*.zig). Called with the main
// harness's machine, cart and model; every check is against an independent
// re-derivation, not the cart's own numbers:
//
//   green    the plane is drawn ONCE and only panned: its window is the tile
//            mask at the original's (moveX, moveY), every pixel, borders too
//   roto     every plane-2 pixel the foreground leaves is the rotozoom's texel,
//            recomputed here from the tick and X/Y (fixtrig, Q16, u32 wrap)
//   borders  the two side-border scrolltexts carry the vertical text, over
//            the overscan rows too, and the plane really opens its borders
//   copper   both planes' lists have a FLICK on all 280 rows; PINK is written
//            on every row, and the colours are off the ST's 3-bit grid
//   back     Z again: plane 0 alone, and the window is the original's model
const W = 400, H = 280, OX = 40, OY = 40, TW = 512, TH = 256;
const ROT_STEP = 3579139, ZOOM_STEP = 9544372, ZOOM_AMP = 26214;
const PINK = 2, VERT = 5, K_Z = 122;
const mod32 = (n) => ((n % 4294967296) + 4294967296) % 4294967296;
const modp = (n, p) => ((n % p) + p) % p;

export async function zigChecks(c) {
    const { machine, demo, memory, ok, step, fsin, fcos, fmul, bit, bgG, bgP } = c;
    const mem = () => new Uint8Array(memory.buffer);
    const u32 = (p, n) => new Uint32Array(memory.buffer, p, n);

    demo.key(K_Z);
    step();
    ok(demo.gkZig() === 1, "Z switches ZIG mode on");
    ok(!demo.isPlaneEnabled(0) && demo.isPlaneEnabled(1) && demo.isPlaneEnabled(2),
       "ZIG mode shows planes 1 (green) and 2 (main) instead of plane 0");

    const stats = { green: 0, roto: 0, rotoDiff: 0, borderVert: 0, overscanVert: 0, vertPairs: 0, frames: 0 };
    let blitsMin = Infinity, blitsMax = 0, copperOk = true, pinkRows = new Set(), offGrid = 0, openSides = 0, closedSides = 0;
    const FRAMES = 240;
    for (let i = 0; i < FRAMES; i++) {
        if (i > 0) step();
        const st = c.st, t = demo.gkTick();
        blitsMin = Math.min(blitsMin, demo.gkZigBlits());
        blitsMax = Math.max(blitsMax, demo.gkZigBlits());
        if (i % 8) continue; // the pixel checks on every 8th frame
        stats.frames++;
        checkGreen(c, st, stats);
        const idx = mem().slice(demo.gkPlanePtr(2), demo.gkPlanePtr(2) + W * H);
        if (demo.gkPlaneStride(2) !== W) throw new Error(`main plane stride ${demo.gkPlaneStride(2)}`);
        checkRoto(idx, st, t, stats);
        checkBorders(idx, stats);
        // copper lists
        for (const p of [1, 2]) {
            const rows = parseCopper(u32(demo.gkCopperPtr(p), demo.gkCopperLen(p)));
            let pinkWrites = 0; // copper.build() skips a row whose colour equals the row above
            for (let r = 0; r < H; r++) {
                const rec = rows.get(r);
                if (!rec || !rec.flick) copperOk = false;
                if (p === 2 && rec && rec.pal.has(PINK)) {
                    pinkWrites++;
                    const v = rec.pal.get(PINK);
                    pinkRows.add(v);
                    if ((v & 0xFF) % 32 || ((v >> 8) & 0xFF) % 32 || ((v >> 16) & 0xFF) % 32) offGrid++;
                }
            }
            if (p === 2 && pinkWrites < 270) copperOk = false;
        }
        // The main plane's borders are open: a border-text pixel reaches the raster in
        // the same colour as the first copy's pixel of that row (rendered over plane 1's
        // picture, so a closed border would show the green plane there instead).
        machine.hwRenderPlane(2);
        const pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), 800 * H * 4);
        const px = (x, y) => { const i = (y * 800 + 2 * x) * 4; return pfb[i] | pfb[i + 1] << 8 | pfb[i + 2] << 16 | pfb[i + 3] << 24; };
        for (let y = 0; y < H; y++)
            for (let dx = 0; dx < 16; dx++)
                for (const bx of [12, 372])
                    if (idx[y * W + bx + dx] === VERT && idx[y * W + 40 + dx] === VERT) {
                        if (px(bx + dx, y) === px(40 + dx, y) && pfb[(y * 800 + 2 * (bx + dx)) * 4 + 3] === 255) openSides++;
                        else closedSides++;
                    }
    }
    ok(demo.gkZigGreen(2) === 1, `the green plane was drawn once (${demo.gkZigGreen(2)}) and only panned since`);
    ok(stats.green === stats.frames, `the green plane's window is the tile at the original's pan, every pixel, ${stats.green}/${stats.frames} frames${stats.greenWhy ? " (last miss: " + stats.greenWhy + ")" : ""}`);
    ok(stats.roto > stats.frames * W * H * 0.6,
       `${stats.roto} plane-2 pixels are the rotozoom's texel, recomputed from tick and X/Y (none differs)`);
    ok(stats.rotoDiff > stats.frames * 2000, `the pink layer is not the plain mode's (${stats.rotoDiff} pixels moved by the rotozoom)`);
    ok(stats.borderVert > 0 && stats.vertPairs === 0,
       `the side borders carry the vertical scrolltext (${stats.borderVert} pixels, the same glyphs as the first copy)`);
    ok(stats.overscanVert > 0, `the border scrolltexts run through the overscan rows (${stats.overscanVert} pixels above/below the 200 lines)`);
    ok(openSides > 0 && closedSides === 0,
       `the main plane's side borders are open (${openSides} border-text pixels reach the raster in the text's colour, ${closedSides} do not)`);
    ok(copperOk, "both planes' copper lists: a FLICK on all 280 rows, the pink entry rewritten on >= 270 rows of plane 2");
    ok(pinkRows.size > 100 && offGrid > 0, `true-colour pink cycle: ${pinkRows.size} distinct colours, ${offGrid} off the ST's 3-bit grid`);
    ok(blitsMin >= 20 && blitsMax <= 40, `a ZIG frame is 1 AFFINE + keyed blits: ${blitsMin}..${blitsMax} CHISEL ops (ceiling 40)`);

    // Z again: the original, pixel for pixel.
    demo.key(K_Z);
    let same = true;
    for (let i = 0; i < 60; i++) {
        step();
        if (i === 0) {
            ok(demo.gkZig() === 0, "Z again switches ZIG mode off");
            ok(demo.isPlaneEnabled(0) && !demo.isPlaneEnabled(1) && !demo.isPlaneEnabled(2), "and plane 0 alone is shown");
        }
        const want = c.draw(c.st), got = c.windowRGB();
        for (let k = 0; k < want.length; k++) if (got[k] !== want[k]) { same = false; break; }
    }
    ok(same, "back from ZIG mode, 60 frames are the original's model pixel for pixel");
}

/// Plane 1 rendered: each window pixel is the green ink where the tile mask is
/// set at the original's pan, else the row's background colour (one a row,
/// the same in the borders as inside them).
function checkGreen(c, st, stats) {
    const { machine, memory, demo, bit, bgG } = c;
    const xo = Math.floor(st.moveX / 2), yo = Math.floor(st.moveY / 2);
    if (demo.gkZigGreen(0) !== modp(-OX - xo, 320) || demo.gkZigGreen(1) !== modp(-OY - yo, 200))
        return void (stats.greenWhy = `pan ${demo.gkZigGreen(0)},${demo.gkZigGreen(1)} for moveX ${st.moveX} moveY ${st.moveY}`);
    machine.hwRenderPlane(1);
    const pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), 800 * H * 4);
    for (let y = 0; y < H; y++) {
        let bg = null;
        const ty = modp(y - OY - yo, 200);
        for (let x = 0; x < W; x++) {
            const i = (y * 800 + 2 * x) * 4;
            const rgb = pfb[i] | pfb[i + 1] << 8 | pfb[i + 2] << 16;
            const ink = ty < 199 && bit(bgG, modp(x - OX - xo, 320), ty, 320);
            const why = `(${x},${y}) is ${rgb.toString(16)}, ink ${ink}, row colour ${bg?.toString(16)}`;
            if (ink) { if (rgb !== (64 | 96 << 8 | 32 << 16)) return void (stats.greenWhy = why); }
            else if (bg === null) bg = rgb;
            else if (rgb !== bg) return void (stats.greenWhy = why);
        }
    }
    stats.green++;
}

/// Every plane-2 pixel left as 0 or PINK is the texel the AFFINE spans name.
function checkRoto(idx, st, t, stats) {
    const { fsin, fcos, fmul, bit, bgP } = checkRoto.c;
    const ang = mod32(t * ROT_STEP), k = 65536 + fmul(fsin(mod32(t * ZOOM_STEP)), ZOOM_AMP);
    const a = fmul(fcos(ang), k), b = fmul(fsin(ang), k);
    const du = Math.floor(a * 8 / 5), dv = Math.floor(b * 32 / 25);
    const ru = Math.floor(-b * 8 / 5), rv = Math.floor(a * 32 / 25);
    const cu = Math.floor((160 - Math.floor(st.X / 2)) * 524288 / 5);
    const cv = Math.floor((100 - Math.floor(st.Y / 2)) * 2097152 / 25);
    const xo = Math.floor(st.X / 2), yo = Math.floor(st.Y / 2);
    for (let y = 0; y < H; y++) {
        const u0 = cu - du * 200 - ru * 140 + ru * y, v0 = cv - dv * 200 - rv * 140 + rv * y;
        for (let x = 0; x < W; x++) {
            const p = idx[y * W + x];
            if (p !== 0 && p !== PINK) continue;
            const U = (mod32(u0 + du * x) >>> 16) & (TW - 1), V = (mod32(v0 + dv * x) >>> 16) & (TH - 1);
            const tx = (U * 5) >> 3, ty = (V * 25) >> 5;
            const want = ty < 199 && bit(bgP, tx, ty, 320) ? PINK : 0;
            if (p !== want) throw new Error(`ZIG tick ${t}: plane 2 pixel (${x},${y}) is ${p}, the rotozoom says ${want}`);
            stats.roto++;
            // the plain mode's pink at this pixel (unrotated, unzoomed)
            const py = modp(y - OY - yo, 200), plain = py < 199 && bit(bgP, modp(x - OX - xo, 320), py, 320);
            if (plain !== (p === PINK)) stats.rotoDiff++;
        }
    }
}

/// The border copies (x 12 and 372) are the first copy's glyphs (x 40), row
/// for row, wherever nothing else is drawn over either.
function checkBorders(idx, stats) {
    for (let y = 0; y < H; y++)
        for (let dx = 0; dx < 16; dx++) {
            const ref = idx[y * W + 40 + dx];
            for (const bx of [12, 372]) {
                const v = idx[y * W + bx + dx];
                if (v === VERT) { stats.borderVert++; if (y < OY || y >= OY + 200) stats.overscanVert++; }
                const clean = (q) => q === 0 || q === PINK || q === VERT;
                if (clean(ref) && clean(v) && (ref === VERT) !== (v === VERT)) stats.vertPairs++;
            }
        }
}

/// machine/copper.zig records: HEAD (0xF, row << 19 | n), FLICK (0x3), PAL (0x1, entry << 20).
function parseCopper(words) {
    const rows = new Map();
    let w = 0;
    while (w < words.length) {
        const h = words[w++];
        if (h >>> 28 !== 0xF) break;
        const row = (h >>> 19) & 511, n = h & 0x7FFFF;
        if (row === 511) break;
        const rec = { flick: false, pal: new Map() };
        const end = w + n;
        while (w < end) {
            const op = words[w++];
            if (op >>> 28 === 0x3) rec.flick = true;
            else if (op >>> 28 === 0x1) { rec.pal.set((op >>> 20) & 0xFF, words[w++]); }
        }
        rows.set(row, rec);
    }
    return rows;
}
export function bindModel(c) { checkRoto.c = c; }
