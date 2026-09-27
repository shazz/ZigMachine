// SKYSTRIKE ZIG-mode harness, the picture (apps/skystrike_zig.mjs drives):
//   (d) a ZIG frame in flight, as the host composites it, = the ring at the
//       hardware's pan with the overlay over it, EVERY pixel of 400 x 280:
//       so all four borders are open (a closed one shows the background, a
//       missed flicker noise); the panel sits in the bottom border, the bonus
//       bar in the top one, both = the game's back screen; the ammo counter
//       is the game's font
//   tracers  FIRE in ZIG leaves streaks on the plane's heading line; in
//       ORIGINAL none; the ammo goes down the same in both
// and the screenshots.
import { readFile } from "node:fs/promises";
import { onRunway, takeOff, steer, Z, RING_W, WIN_W } from "./skystrike_zig_session.mjs";
import { grab, lowres, png } from "./skystrike_zig_frame.mjs";

const FIRE = 0x80, SP = 11, AMMO_X = 364, HUD_Y = 256; // zig_hud.zig
const gun = (n) => Math.floor((n & 7) * 255 / 7);
const rgba = (w) => (0xff000000 | gun(w) << 16 | gun(w >> 4) << 8 | gun(w >> 8)) >>> 0;

function palette(s) {
    return [...new Uint16Array(s.memory.buffer.slice(s.demo.skyTestPtr(4), s.demo.skyTestPtr(4) + 32))].map(rgba);
}

/// The frame against ring + overlay, pixel for pixel; then the HUD's parts.
function frameChecks(s, frame, errors) {
    const pal = palette(s), ring = s.ring(), ov = s.overlay(), back = s.screen("back");
    const sx = s.z("sx"), sy = s.z("sy");
    let bad = 0, border = 0, lit = 0, first = null;
    for (let y = 0; y < 280; y++) for (let x = 0; x < WIN_W; x++) {
        const o = ov[y * WIN_W + x];
        const want = pal[o !== 255 ? o : ring[(sy + y) * RING_W + sx + x]];
        const inBorder = (x < 40 || x >= 360 || y < 40 || y >= 240) && y < HUD_Y;
        if (inBorder && frame[y * WIN_W + x] >>> 0 !== pal[0]) lit++;
        if (frame[y * WIN_W + x] >>> 0 === want) continue;
        bad++;
        if (inBorder) border++;
        first ??= `x ${x} y ${y}`;
    }
    const total = 400 * HUD_Y - 320 * 200;
    if (bad) errors.push(`(d) ${bad} of 112000 pixels are not the ring + overlay (${border} in the borders; first ${first})`);
    if (lit < total / 2) errors.push(`(d) the borders are shut: ${lit} of their ${total} pixels above the HUD show anything but colour 0`);
    let hud = 0;
    for (let y = 0; y < 24; y++) for (let x = 0; x < 320; x++) if (frame[(HUD_Y + y) * WIN_W + 40 + x] >>> 0 !== pal[back[(176 + y) * 320 + x]]) hud++;
    for (let y = 2; y <= 12; y++) for (let x = 14; x <= 306; x++) if (frame[y * WIN_W + 40 + x] >>> 0 !== pal[back[y * 320 + x]]) hud++;
    if (hud) errors.push(`(d) ${hud} pixels of the panel (bottom border) or the bonus bar (top border) are not the game's`);
    return `${lit} of ${total} border pixels lit`;
}

/// "AMMO" and the count in the game's 8x8 font, pen on black.
async function ammoCheck(s, errors) {
    const font = await readFile("apps/zig/assets/screens/skystrike/font.bin");
    const ov = s.overlay(), pen = s.val(361);
    const lines = [["AMMO", HUD_Y + 3], [" " + String(s.v("ammo")).padStart(3, "0"), HUD_Y + 13]];
    let bad = 0;
    for (const [text, y0] of lines) for (let k = 0; k < text.length; k++) for (let j = 0; j < 8; j++) for (let i = 0; i < 8; i++) {
        const on = font[(text.charCodeAt(k) - 32) * 8 + j] >> (7 - i) & 1;
        if (ov[(y0 + j) * WIN_W + AMMO_X + k * 8 + i] !== (on ? pen : 0)) bad++;
    }
    if (bad) errors.push(`(d) the ammo counter differs from "${lines[1][0].trim()}" in the game's font in ${bad} pixels`);
}

/// Tracer pixels in the overlay, and how far the worst lies off the line
/// through the plane along heading r (turned 90 degrees for --break tracer).
function tracerLine(s, broke) {
    const ov = s.overlay(), ink = s.val(361), tail = s.val(362);
    const camX = ((s.z("cx") - 1) * 320 + s.z("sx")), camY = -(s.z("base") + 2) * 160 + s.z("sy");
    const px = s.v("sx") * 320 + s.v("x") - camX, py = -s.v("al") * 160 + s.v("y") - camY;
    const table = [[-6, 0], [-5, -1], [-4, -3], [-2, -4], [0, -5], [2, -4], [4, -3], [5, -1], [6, 0], [5, 2], [4, 4], [2, 5], [0, 6], [-2, 5], [-4, 4], [-5, 2]];
    let [dx, dy] = table[s.v("r") & 15];
    if (broke === "tracer") [dx, dy] = [-dy, dx];
    const n = Math.hypot(dx, dy);
    let count = 0, off = 0;
    for (let y = 0; y < 256; y++) for (let x = 0; x < WIN_W; x++) {
        const o = ov[y * WIN_W + x];
        if (o !== ink && o !== tail) continue;
        const wx = ((x - px) % 16320 + 24480) % 16320 - 8160;
        count++;
        off = Math.max(off, Math.abs(wx * dy - (y - py) * dx) / n);
    }
    return { count, off };
}

async function tracers(broke, errors, notes) {
    const ammo = [];
    for (const zig of [true, false]) {
        const s = await onRunway(zig);
        takeOff(s, 60);
        const before = s.v("ammo");
        s.stick(FIRE);
        let most = { count: 0, off: 0 };
        for (let p = 0; p < 5; p++) s.pass(() => { const t = tracerLine(s, broke); if (t.count > most.count) most = t; });
        s.stick(0);
        ammo.push(before - s.v("ammo"));
        if (zig && (most.count < 3 || most.off > 4)) errors.push(`tracers: ZIG fired ${ammo[0]} rounds, ${most.count} tracer pixels up to ${most.off.toFixed(1)} px off the heading line`);
        if (!zig && (s.val(360) || s.demo.isPlaneEnabled(2))) errors.push(`tracers: ORIGINAL shows ${s.val(360)} streaks (overlay plane ${s.demo.isPlaneEnabled(2) ? "on" : "off"})`);
        if (zig) notes.push(`tracers: ${most.count} px on the heading line (<= ${most.off.toFixed(1)} px off)`);
    }
    if (ammo[0] !== ammo[1] || !ammo[0]) errors.push(`tracers: FIRE took ${ammo[0]} rounds in ZIG, ${ammo[1]} in ORIGINAL`);
    notes.push(`ammo -${ammo[0]} in both modes, none drawn in ORIGINAL`);
}

export async function view(outdir, broke) {
    const errors = [], notes = [];
    const s = await onRunway(broke !== "border");
    takeOff(s, 20);
    for (let p = 0; p < 60 && s.v("sx") === 0; p++) { s.poke(SP, 11000); s.pass(); }
    await png(`${outdir}/zig_cross_h.png`, lowres(grab(s)), 400, 280);
    for (let p = 0; p < 6; p++) s.pass();
    const frame = lowres(grab(s));
    await png(`${outdir}/zig_flight.png`, frame, 400, 280);
    const borders = frameChecks(s, frame, errors);
    await ammoCheck(s, errors);
    steer(s, 5);
    for (let p = 0; p < 200 && s.v("al") === 0; p++) { s.poke(SP, 11000); s.pass(); }
    await png(`${outdir}/zig_cross_v.png`, lowres(grab(s)), 400, 280);
    s.stick(FIRE); s.pass(); s.pass(); s.stick(0);
    await png(`${outdir}/zig_tracers.png`, lowres(grab(s)), 400, 280);
    s.mode(false); s.run(1);
    await png(`${outdir}/original_same_moment.png`, lowres(grab(s)), 400, 280);
    await tracers(broke, errors, notes);
    console.log(`  (d) the flight frame = ring + overlay in all 112000 pixels, ${borders}; panel + bar = the game's; ammo in its font; ${notes.join("; ")}; shots in ${outdir}`);
    return { errors, s };
}
