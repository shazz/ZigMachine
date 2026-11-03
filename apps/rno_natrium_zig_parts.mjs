// The part-by-part checks of apps/rno_natrium_zig.mjs (see its header), in timeline order.
import * as Z from "./rno_natrium_zig_model.mjs";

const wrap = (d) => Math.abs((((d + 64) % 128) + 128) % 128 - 64);

/** The tunnel map is the original table's formula, entry for entry. */
function checkMap(map, ok) {
    let wu = 0, wv = 0, holes = 0, bad = 0;
    for (let j = 0; j < Z.MH; j++) for (let i = 0; i < Z.MW; i++) {
        const e = map[j * Z.MW + i], m = Z.tunnelUV(i, j);
        if (!m) { holes++; if (e !== 0) bad++; continue; }
        const du = wrap((e & 127) - m[0]), dv = wrap((e >> 8) - m[1]);
        // u rounds, v truncates (the 68000's divs), so a texel either way; r < 20 is the
        // hole's rim, where 1024 / r moves two texels a pixel
        wu = Math.max(wu, du);
        if (m[2] > 20) wv = Math.max(wv, dv);
        if (du > 1 || dv > (m[2] > 20 ? 2 : 4)) bad++;
    }
    ok(bad === 0 && holes > 700, `the tunnel map is u = 64 + angle 64/pi, v = 64 + 1024/r at every one of 600x360 entries (worst u ${wu.toFixed(2)}, v ${wv.toFixed(2)} texels, hole ${holes} px)`);
}

/** The open borders: every border pixel reaches the raster in its index's colour. */
function checkBorders(c, ok) {
    const idx = c.zig.plane(1), ras = c.zig.raster(), col = new Map();
    for (let y = 40; y < 240; y++) for (let x = 40; x < 360; x++) col.set(idx[y * Z.W + x], ras[y * Z.W + x]);
    let open = 0, closed = 0;
    for (let y = 0; y < Z.H; y++) for (let x = 0; x < Z.W; x++) {
        if (x >= 40 && x < 360 && y >= 40 && y < 240) continue;
        const want = col.get(idx[y * Z.W + x]);
        if (want === undefined) continue;
        if (ras[y * Z.W + x] === want && want !== 0) open++; else if (ras[y * Z.W + x] !== want) closed++;
    }
    ok(open > 20000 && closed === 0, `the overscan plane's borders are open (${open} border pixels in their colour, ${closed} not)`);
}

/** An effect part: every window pixel the model's, on every `every`-th frame; the
 *  girl panel (ST x `stx`, 98 x 200) on the raster as the original shows it. */
function effect(c, name, to, every, stx, model) {
    let frames = 0, misses = 0, why = "", seen = 0, panel = 0;
    c.zigRun(to, name, every, (idx, t) => {
        const m = model(t);
        const [bad, first] = c.against(idx, (x, y) => m(x, y));
        frames++;
        if (bad) { misses += bad; why = `t ${t}: ${first}`; }
        for (let i = 0; i < idx.length; i++) if (idx[i] >= Z.SHADE0) seen++;
        const a = c.zig.raster(), b = c.ref.raster();
        for (let y = Z.OY; y < Z.OY + 200; y++)
            for (let x = Z.OX + stx; x < Z.OX + stx + 98; x++) if (a[y * Z.W + x] !== b[y * Z.W + x]) panel++;
    });
    c.ok(frames >= 4 && misses === 0 && seen > frames * 50000,
        `${name}: ${frames} frames, every pixel of the 400x280 window is the original's maths at f + fraction${misses ? ` (${misses} differ, last ${why})` : ""}`);
    c.ok(panel === 0, `${name}: the girl panel over it is the original's, pixel for pixel (${panel} differ)`);
}

/** An env part: the picture off the object, true-colour levels on it, a new frame every VBL. */
function env(c, pic, to) {
    let frames = 0, off = 0, moved = 0, prev = null;
    const levels = new Set();
    c.zigRun(to, "env", 1, (idx) => {
        const d = c.zig.demo, b = [0, 1, 2, 3].map((k) => d.natZigEnv(k));
        for (let y = 0; y < Z.H; y++) for (let x = 0; x < Z.W; x++) {
            const i = y * Z.W + x, inBox = x >= b[0] && x < b[2] && y >= b[1] && y < b[3];
            if (!inBox && idx[i] !== pic[i]) off++;
            if (inBox && idx[i] >= Z.SHADE0) levels.add(idx[i]);
        }
        if (prev && !c.same(prev, idx)) moved++;
        prev = idx;
        frames++;
    });
    c.ok(frames >= 16 && off === 0, `env: off the object the window is the girl picture, ${frames} frames (${off} pixels not)`);
    c.ok(levels.size >= 8, `env: the object shows ${levels.size} of the 13 levels as true colours (entries 16..28), no dither`);
    c.ok(moved === frames - 1, `env: a new picture every VBL (${moved} of ${frames - 1} frames moved; the original: one in 3)`);
}

/** A part with no ZIG version: the original's frame at (40, 40), black borders. */
function classic(c, name, to) {
    let frames = 0, diff = 0, border = 0;
    while (c.ref.vbls < to) {
        c.zigRun(c.ref.vbls + 1, null, 1, null);
        if (c.zig.demo.natZigPart() !== 0) continue;
        if (!c.same(c.ref.window(), c.zig.window())) diff++;
        const r = c.zig.raster();
        for (let x = 0; x < Z.W; x++) if (r[x] !== 0 || r[279 * Z.W + x] !== 0) border++;
        frames++;
    }
    c.ok(frames > 8 && diff === 0 && border === 0, `${name}: the original's frame at (40, 40), black borders, ${frames} frames (${diff} differ)`);
}

export async function checkParts(c) {
    c.zigRun(0x700, null, 1, null);
    const ram = c.zig.machine.hwRamUsed();
    c.ok(c.zig.demo.natZigPart() === 1, "Z at $6F0: ZIG mode is on, in the tunnel");
    const map = c.zig.u16(c.zig.demo.natZigBuf(0), Z.MW * Z.MH);
    checkMap(map, c.ok);
    checkBorders(c, c.ok);
    effect(c, "tunnel", 0x760, 4, 207, (t) => (x, y) => Z.expectTunnel(map, t, x, y));
    await c.shot("tunnel");
    c.zigRun(0x9F0, null, 1, null);
    effect(c, "wobble", 0xA60, 6, 207, (t) => (x, y) => Z.expectWobble(t, x, y));
    await c.shot("wobble");
    c.zigRun(0xCF0, null, 1, null);
    env(c, Z.picture("girl_grey.bin"), 0xD30);
    await c.shot("cube");
    c.roundTrip(0xD30);
    c.both(0xD60);
    c.zig.demo.key(c.K_Z);
    c.zigRun(c.ref.vbls + 1, null, 1, null);
    c.ok(c.zig.demo.natZig() === 1 && c.zig.machine.hwRamUsed() === ram, "Z again at $D60: ZIG mode is back, built once (no new cart RAM)");
    c.zigRun(0x10F0, null, 1, null);
    classic(c, "credits", 0x1110);
    await c.shot("credits");
    c.zigRun(0x14F0, null, 1, null);
    classic(c, "twister", 0x1510);
    c.zigRun(0x18F0, null, 1, null);
    env(c, Z.picture("girl_red.bin"), 0x1930);
    await c.shot("prism");
    c.zigRun(0x1BF0, null, 1, null);
    effect(c, "roto", 0x1C30, 3, 15, (t) => { const s = Z.rotoStep(t); return (x, y) => Z.expectRoto(s, x, y); });
    await c.shot("roto");
    c.roundTrip(0x1C30);
}
