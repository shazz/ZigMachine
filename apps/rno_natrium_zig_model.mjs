// The ZIG mode of RNO / NATRIUM re-derived independently for apps/rno_natrium_zig.mjs:
// what plane 1 must hold at the time the cart reports (natZigTime, Q10 VBLs of the
// part), from the ripped assets and fixtrig, never from the cart's own tables.
// Each `expect*` returns the palette index of window pixel (x, y), or -1 where
// another layer (the girl panel, the hole) is drawn over the effect.
import { readFileSync } from "node:fs";

const DIR = "apps/zig/assets/screens/rno_natrium/";
export const W = 400, H = 280, OX = 40, OY = 40, SHADE0 = 16;
export const asset = (n) => new Uint8Array(readFileSync(DIR + n));
const SKIN = asset("tex_skin.bin"), FACE = asset("tex_face.bin");

// ---- fixtrig (identical to libs/zig/effects/fixtrig.zig) -------------------
const NTAB = 1024;
const zround = (x) => Math.sign(x) * Math.floor(Math.abs(x) + 0.5);
const TABLE = new Int32Array(NTAB + 1);
for (let i = 0; i <= NTAB; i++) TABLE[i] = zround(Math.sin(i * (2 * Math.PI / NTAB)) * 65536.0);
TABLE[0] = 0; TABLE[256] = 65536; TABLE[512] = 0; TABLE[768] = -65536; TABLE[1024] = 0;
export const mod32 = (n) => ((n % 4294967296) + 4294967296) % 4294967296;
export const fsin = (a) => {
    a = mod32(a);
    const i = Math.floor(a / 4194304), f = Math.floor(a / 64) & 0xFFFF, s0 = TABLE[i];
    return s0 + (((TABLE[i + 1] - s0) * f) >> 16);
};
export const fcos = (a) => fsin(a + 0x40000000);
const mulsh16 = (a, b) => Math.floor((a * b) / 65536);
const IDX = 4194304; // one SIN index (1024 a turn) as an angle

// The girl panel over the box parts: ST x 207 (part 2) or 15 (part 7), 98 x 200.
const inPanel = (x, y, stx) => x >= OX + stx && x < OX + stx + 98 && y >= OY && y < OY + 200;

// ---- tunnel (zig_tunnel.zig): the map is checked against atan2 / sqrt on its own ----
export const MW = 600, MH = 360, PX = 100, PY = 40;
export function tunnelPan(t) {
    const cl = (v, m) => Math.min(Math.max(v, 0), m);
    return [cl(PX + mulsh16(fsin(t * (3 << 12)), PX), 2 * PX), cl(PY + mulsh16(fsin(t * (4 << 12)), PY), 2 * PY)];
}
/** The map entry's (u, v) by the original table's formula, in float: u = 64 + angle 64/pi, v = 64 + 1024 / r. */
export function tunnelUV(i, j) {
    const dx = i + 0.5 - MW / 2, dy = j + 0.5 - MH / 2, r = Math.hypot(dx, dy);
    if (r < 16) return null;
    return [((64 + Math.atan2(dy, dx) * 64 / Math.PI) % 128 + 128) % 128, (64 + 1024 / r) % 128, r];
}
export function expectTunnel(map, t, x, y) {
    if (inPanel(x, y, 207)) return -1;
    const [ox, oy] = tunnelPan(t);
    const cx = MW / 2 - ox, cy = MH / 2 - oy; // the hole's centre, between pixels
    if ((2 * x + 1 - 2 * cx) ** 2 + (2 * y + 1 - 2 * cy) ** 2 < 1024) return 0;
    const e = map[(oy + y) * MW + ox + x];
    const u = ((e & 127) + ((t >> 11) & 127)) & 127, v = ((e >> 8) + ((t >> 10) & 127)) & 127;
    return SHADE0 + SKIN[v * 128 + u];
}

// ---- wobble (zig_wobble.zig) ----------------------------------------------------
export function expectWobble(t, x, y) {
    if (inPanel(x, y, 207)) return -1;
    const c = Math.floor(x / 3) - 27, r = Math.floor(y / 3) - 7;
    const sc = fsin(t * (17 << 11) + c * 5 * IDX) + fsin(t * -(11 << 11) + c * 11 * IDX);
    const sr = fsin(t * (13 << 11) + r * 7 * IDX) + fsin(t * -(19 << 11) + r * 9 * IDX);
    const rows = Math.floor((sc * 12) / 65536), shift = ((Math.floor((sr * 24) / 131072) % 128) + 128) % 128;
    const U = (((24 + c + shift) % 128) + 128) % 128, V = (((24 + r + rows) % 128) + 128) % 128;
    return SHADE0 + FACE[V * 128 + U];
}

// ---- rotozoom (zig_roto.zig) ------------------------------------------------------
export function rotoStep(t) {
    const z = 0x480 + (fsin(t * (6 << 12)) >> 6), a = t * (3 << 11);
    const X = mulsh16(fsin(a), z), Y = mulsh16(fcos(a), z);
    return { X, Y, du: Y * 128, dv: X * 256, ru: -X * 128, rv: Y * 256 };
}
export function expectRoto(s, x, y) {
    if (inPanel(x, y, 15)) return -1;
    const bx = OX + 144, by = OY + 20;
    const u = mod32((0x4000 - 32 * s.Y) * 128 + (x - bx) * s.du + (y - by) * s.ru);
    const v = mod32(0x7FFE * 256 + (x - bx) * s.dv + (y - by) * s.rv);
    return SHADE0 + SKIN[(Math.floor(v / 65536) & 127) * 128 + (Math.floor(u / 65536) & 127)];
}

// ---- the env parts' picture (an ILBM body: row = plane 0..3, 40 bytes each) -------
export function picture(name) {
    const body = asset(name), out = new Uint8Array(W * H);
    for (let y = 0; y < 200; y++)
        for (let x = 0; x < 320; x++) {
            let c = 0;
            for (let p = 0; p < 4; p++) c |= ((body[y * 160 + p * 40 + (x >> 3)] >> (7 - (x & 7))) & 1) << p;
            out[(y + OY) * W + x + OX] = c;
        }
    return out;
}
