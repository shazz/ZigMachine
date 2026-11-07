// The FULLSCREEN checks of apps/rno_natrium_zig.mjs (part 1's dot tunnel, part 5's chrome
// twister), against apps/rno_natrium_zig_full_model.mjs:
//   dots     the map is the original table's formula at all 400x280 entries (the bottom
//            half the top's half turn, inverted); every pixel is REF's pen with bit 0
//            clear (the curtains and logos of planes 1..3, carried out over the borders)
//            ORed with the blob at the original's scroll; the tunnel fills the borders
//   twister  every pixel is the strip at the original's two sines over 100 columns,
//            the bar's 90 lines at the bob, the greetings on the window's edges, the
//            rest colour 15; the bar runs through the side borders and reaches both
//            the top and the bottom border
// `skew` (--break) shifts the models' time by one VBL: both pixel checks must then fail.
import * as Z from "./rno_natrium_zig_model.mjs";
import * as F from "./rno_natrium_zig_full_model.mjs";

const inWindow = (x, y) => x >= Z.OX && x < Z.OX + 320 && y >= Z.OY && y < Z.OY + 200;

function checkDotMap(c) {
    const map = c.zig.u16(c.zig.demo.natZigBuf(5), Z.W * Z.H);
    let bad = 0, holes = 0, turn = 0;
    for (let y = 0; y < Z.H; y++) for (let x = 0; x < Z.W; x++) {
        const e = map[y * Z.W + x], m = F.dotUV(x, y), low = y >= Z.H / 2 ? 16 : 0;
        if (map[(Z.H - 1 - y) * Z.W + Z.W - 1 - x] !== (e ^ 16)) turn++;
        if ((e & 16) !== low) { bad++; continue; }
        if (!m) { holes++; if (e !== low) bad++; continue; }
        const u = e & 15, v = (e >> 8) / 4;
        // u exact (or one off a rounding edge), v within a texel (1.6 at the hole's rim)
        const near = m.some(([mu, mv]) => Math.min((u - mu + 16) % 16, (mu - u + 16) % 16) <= 1 &&
            Math.min((v - mv + 32) % 32, (mv - v + 32) % 32) <= 1.6);
        if (!near) bad++;
    }
    c.ok(bad === 0 && turn === 0 && holes > 700, `dots: the map is U8 = angle, V8 = 128.75 + 2048/r ($C2DC's u, v) at all 400x280 entries, the bottom the top's half turn inverted (${bad} off, ${turn} not symmetric, hole ${holes} px)`);
}

/** Part 1 until `to`: the pixel model every `every` frames, the borders' tunnel. */
function checkDots(c, to, every, skew) {
    const stride = c.ref.demo.natPlaneStride(0);
    let frames = 0, misses = 0, why = "", border = 0, moved = 0, prev = null;
    c.zigRun(to, "dots", every, (idx, t0) => {
        const t = t0 + skew, voff = F.dotVoff(t), map = c.zig.u16(c.zig.demo.natZigBuf(5), Z.W * Z.H);
        const st = c.ref.plane(0, 320 * 200, stride);
        let bad = 0, lit = 0;
        for (let y = 0; y < Z.H; y++) for (let x = 0; x < Z.W; x++) {
            const e = map[y * Z.W + x], i = y * Z.W + x;
            const want = (st[F.stLine(y) * stride + F.stCol(x)] & 14) | F.dotTexel(e & 31, ((e >> 8) + voff) & 127);
            if (idx[i] !== want && !bad++) why = `t ${t0}: (${x},${y}) ${idx[i]} != ${want}`;
            if (!inWindow(x, y) && (idx[i] & 1)) lit++;
        }
        const ring = idx.subarray(0, Z.W * Z.OY);
        if (prev && !c.same(prev, ring)) moved++;
        prev = ring.slice();
        misses += bad;
        border = Math.max(border, lit);
        frames++;
    });
    c.ok(frames >= 20 && misses === 0, `dots: ${frames} frames, every pixel of the 400x280 window is the ST's planes 1..3 | the blob at the original's scroll${misses ? ` (${misses} differ, ${why})` : ""}`);
    c.ok(border > 20000 && moved >= frames - 2, `dots: fullscreen, the tunnel lights up to ${border} border pixels and scrolls there (${moved} of ${frames - 1} checks moved)`);
}

/** Part 5 until `to`: the pixel model every `every` frames, the bar's reach every frame. */
function checkTwister(c, to, every, skew) {
    let frames = 0, misses = 0, why = "", minTop = 999, maxEnd = 0, sides = 0, checked = 0;
    c.zigRun(to, "twister", 1, (idx, t0) => {
        const top = c.zig.demo.natZigTwistTop();
        minTop = Math.min(minTop, top);
        maxEnd = Math.max(maxEnd, top + F.BAR);
        let side = 0;
        for (let y = top; y < top + F.BAR; y++) for (const x of [0, 13, 27, 39, 360, 371, 385, 399]) if (idx[y * Z.W + x] !== 15) side++;
        if (side > 100) sides++;
        checked++;
        if (c.zig.vbls % every) return;
        const m = F.twistModel(t0 + skew, c.zig.vbls);
        const [bad, first] = c.against(idx, m);
        if (bad) { misses += bad; why = `t ${t0}: ${first}`; }
        frames++;
    });
    c.ok(frames >= 20 && misses === 0, `twister: ${frames} frames, every pixel of the 400x280 window is the strip at the original's sines, bob and greetings${misses ? ` (${misses} differ, ${why})` : ""}`);
    c.ok(sides === checked && minTop < Z.OY && maxEnd > Z.OY + 200, `twister: fullscreen, the bar crosses both side borders on ${sides} of ${checked} frames and bobs over lines ${minTop}..${maxEnd - 1}`);
}

export function checkFull(c, part, to, skew) {
    if (part === "dots") {
        checkDotMap(c);
        checkDots(c, to, 16, skew);
    } else checkTwister(c, to, 8, skew);
}
