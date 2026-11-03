// TC TEST's key 8, FADE (HW 1.16.0's true-colour fade, apps/zig/scenes/tc_test/fade.zig), for
// apps/tc_test_check.mjs. Over one whole 256-frame cycle:
//   model     every composited frame equals an independent model of the fade applied to the
//             plane's 565 pixels as they sit in memory, under the registers the cart left
//             (docs/HW_API.md "True-colour fade": the formula written with divisions)
//   pixels    the pixel memory hashes the same every frame: only the registers move the picture
//   reaches   a frame of full black, one of full white, a flash (a positive red offset) and one
//             the same as the hues view (no fade): the cycle is really there
// Mutants (--break): fadeoff (the registers zeroed after each frame), softfade (one pixel
// rewritten a frame, as a Falcon fade would), model (the model forgets the fade).
const W = 400, H = 280, STRIDE = 800, REG_TC_FADE = 0x0C, REG_OFS = [0x14, 0x18, 0x1C], REG_FB_BASE = 0x44;
export const FADE_VIEW = 7, PERIOD = 256;

const expand5 = (v) => (v << 3) | (v >> 2), expand6 = (v) => (v << 2) | (v >> 4);
function channel(x, coef, white, ofs) {
    const w = coef >= 16 ? coef + 1 : coef;
    const t = Math.floor(((white ? 255 - x : x) * (32 - w) + 16) / 32);
    return Math.min(255, Math.max(0, (white ? 255 - t : t) + ofs));
}

function regs(m, dv) {
    const ctl = dv.getUint8(m.video + REG_TC_FADE);
    return { coef: ctl & 31, white: (ctl & 0x20) !== 0, ofs: REG_OFS.map((r) => dv.getInt8(m.video + r)) };
}

function model(m, dv, f, brk) {
    const base = dv.getUint32(m.video + REG_FB_BASE, true) & ~1;
    const out = new Uint32Array(W * H);
    for (let y = 0; y < H; y++)
        for (let x = 0; x < W; x++) {
            const p = dv.getUint16(m.video + base + y * STRIDE + 2 * x, true);
            const rgb = [expand5(p >> 11), expand6((p >> 5) & 63), expand5(p & 31)];
            const c = brk === "model" ? rgb : rgb.map((v, k) => channel(v, f.coef, f.white, f.ofs[k]));
            out[y * W + x] = c[0] | (c[1] << 8) | (c[2] << 16);
        }
    return out;
}

const all = (img, v) => img.every((c) => c === v);
const same = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);

// `t` gives the harness's frame(m, hook), pixelHash(m), dv(m) and want(errors, ok, msg); `hues` is
// key 5's picture. Returns the view's first frame (for the views-are-distinct check).
export function fadeChecks(m, errors, brk, hues, t) {
    m.demo.setShadeMode(FADE_VIEW);
    const h0 = t.pixelHash(m);
    const hook = (mm) => {
        const d = t.dv(mm);
        if (brk === "fadeoff") for (const r of [REG_TC_FADE, ...REG_OFS]) d.setUint8(mm.video + r, 0);
        if (brk === "softfade") {
            const at = mm.video + (d.getUint32(mm.video + REG_FB_BASE, true) & ~1) + 2 * 5000;
            d.setUint16(at, (d.getUint16(at, true) ^ 0x0841), true);
        }
    };
    let first = null, bad = 0, black = 0, white = 0, flash = 0, plain = 0;
    for (let f = 0; f < PERIOD; f++) {
        const img = t.frame(m, hook), d = t.dv(m), r = regs(m, d);
        first ??= img;
        if (!same(img, model(m, d, r, brk))) bad++;
        black += all(img, 0);
        white += all(img, 0xFFFFFF);
        flash += r.ofs[0] > 0 && !same(img, hues);
        plain += same(img, hues);
    }
    const h1 = t.pixelHash(m);
    t.want(errors, bad === 0, `fade: ${bad}/${PERIOD} frames differ from the model of the fade registers`);
    t.want(errors, h0 === h1, "fade: the pixel memory changed (a fade must be the registers alone)");
    t.want(errors, black && white && flash && plain, `fade: black ${black}, white ${white}, flash ${flash}, plain ${plain} frames (each must be > 0)`);
    if (!brk) console.log(`  key 8 fade    ${PERIOD} frames = the model, black ${black} white ${white} flash ${flash} plain ${plain}, pixel memory ${h0 === h1 ? "unchanged" : "CHANGED"}`);
    m.demo.setShadeMode(4);
    t.want(errors, same(t.frame(m), hues), "fade: leaving the view does not give back the hues unfaded");
    return first;
}
