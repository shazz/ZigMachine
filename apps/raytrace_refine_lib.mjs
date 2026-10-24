// What the f32 raytrace cart's refinement passes must change in the picture
// (apps/zig/scenes/raytrace/refine.zig), measured off the RGB frame by mapping
// each pixel back to its palette index: the palette is rebuilt here with the
// same integer maths as palette.zig's install(), so the mapping is exact.
//
//   classOf(rgb)   per-pixel ramp class (sky, floor tone 0/1, sphere 0..4)
//   penumbra(rgb)  floor pixels at shade levels 4..6: a hard shadow (shade 80
//                  or 256 of 256) dithers only to levels 2, 3 and 7, so these
//                  appear only where samples of lit and shadowed floor average
//   classEdges(rgb) horizontal neighbours of different classes: a silhouette or
//                  tile edge is one step per row point-sampled, and becomes a
//                  coverage dither (several steps) once the samples average.
//                  (A smoothness measure on the box-filtered picture moved only
//                  2 %: the ordered dither's own texture swamps it.)
//   checkRefined   the f32 cart's converged picture against its first one
export const W = 320, IMG_H = 176;

const mix = (a, b, num, den) => a.map((av, i) => av + Math.trunc((b[i] - av) * num / den));
const scaled = (c, num, den) => mix([0, 0, 0], c, num, den);
function ramp(c, i, lv) {
    const n = Math.trunc(i * 100 / (lv - 1));
    return n <= 78 ? scaled(c, n, 78) : mix(c, [255, 255, 255], n - 78, 22);
}

const HORIZON = [255, 168, 112], MIDSKY = [168, 92, 150], ZENITH = [36, 56, 170];
const TONES = [[236, 226, 204], [128, 28, 48]];
const MATS = [[200, 208, 226], [226, 36, 36], [240, 178, 36], [40, 96, 240], [40, 200, 90]];
const SKY_LV = 40, FOG_LV = 5, SHADE_LV = 8, MAT_LV = 22;

// rgb key -> { cls, shade } (cls: 0 sky, 1..2 floor tones, 3..7 spheres; -1 ambiguous)
const LUT = new Map();
function put(c, cls, shade = -1) {
    const k = (c[0] << 16) | (c[1] << 8) | c[2], had = LUT.get(k);
    LUT.set(k, had && (had.cls !== cls || had.shade !== shade) ? { cls: -1, shade: -1 } : { cls, shade });
}
for (let i = 0; i < SKY_LV; i++)
    put(i < SKY_LV / 2 ? mix(HORIZON, MIDSKY, i, SKY_LV / 2) : mix(MIDSKY, ZENITH, i - SKY_LV / 2, SKY_LV / 2), 0);
for (let t = 0; t < 2; t++) for (let f = 0; f < FOG_LV; f++) for (let s = 0; s < SHADE_LV; s++)
    put(mix(scaled(TONES[t], s, SHADE_LV - 1), HORIZON, f, FOG_LV - 1), 1 + t, f < FOG_LV - 1 ? s : -1);
for (let m = 0; m < 5; m++) for (let i = 0; i < MAT_LV; i++) put(ramp(MATS[m], i, MAT_LV), 3 + m);

const at = (rgb, i) => LUT.get((rgb[i * 3] << 16) | (rgb[i * 3 + 1] << 8) | rgb[i * 3 + 2]);

export function classOf(rgb) {
    const out = new Int8Array(W * IMG_H);
    for (let i = 0; i < W * IMG_H; i++) out[i] = at(rgb, i)?.cls ?? -2;
    return out;
}

export function unknownPixels(rgb) {
    let n = 0;
    for (let i = 0; i < W * IMG_H; i++) if (!at(rgb, i)) n++;
    return n;
}

export function penumbra(rgb) {
    let n = 0;
    for (let i = 0; i < W * IMG_H; i++) { const e = at(rgb, i); if (e && e.cls >= 1 && e.cls <= 2 && e.shade >= 4 && e.shade <= 6) n++; }
    return n;
}

export function classEdges(rgb) {
    const c = classOf(rgb);
    let n = 0;
    for (let y = 0; y < IMG_H; y++) for (let x = 1; x < W; x++) if (c[y * W + x] !== c[y * W + x - 1]) n++;
    return n;
}

// Pinned: the f32 cart's converged picture, rows 0..175 of the RGB frame.
export const PINNED_CONVERGED = "c5976db424a576c7250e89aed6831616f4d3536095e410ef1c953d256fa06055";

// ctx: { check, sha, checkPicture, checkChrome } from the harness.
export function checkRefined(ctx, name, first, conv, convAt) {
    const { check } = ctx, hash = ctx.sha(conv);
    const pen = [penumbra(first), penumbra(conv)], edges = [classEdges(first), classEdges(conv)];
    console.log(`  converged at frame ${convAt}: penumbra ${pen.join(" -> ")} px, class edges ${edges.join(" -> ")}`);
    console.log(`  converged fingerprint ${hash}`);
    check(hash === PINNED_CONVERGED, `${name}: converged fingerprint ${hash.slice(0, 16)} != pinned ${PINNED_CONVERGED.slice(0, 16)}`);
    check(unknownPixels(first) === 0 && unknownPixels(conv) === 0, `${name}: pixels off the palette (${unknownPixels(first)}, ${unknownPixels(conv)})`);
    check(pen[0] === 0 && pen[1] > 500, `${name}: no soft-shadow penumbra after refinement (${pen.join(" -> ")})`);
    check(edges[1] > 1.4 * edges[0], `${name}: edges did not become coverage dithers (${edges.join(" -> ")})`);
    ctx.checkPicture(`${name} converged`, conv);
    ctx.checkChrome(`${name} converged`, conv);
}
