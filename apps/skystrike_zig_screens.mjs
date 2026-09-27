// SKYSTRIKE ZIG-mode harness, the other screens (apps/skystrike_zig.mjs
// drives): the title, the difficulty menu, the briefing, the hall of fame
// and its name entry. In ZIG each fills the open 400 x 280 frame on the
// overlay plane (zig_screens.zig): the physic screen scaled by 5/4, nearest
// pixel, at line 15, the bands above and below in the colour most of its
// top / bottom line is. Checked on the composited frame, every pixel. In
// ORIGINAL the same moments show plane 0 alone (the ST's 320 x 200). In the
// name entry Z is a letter: it does not switch the mode.
// --break intro: the frame expected the ST's 320 x 200 centred, unscaled.
import { zsession, WIN_W } from "./skystrike_zig_session.mjs";
import { toPlay, L } from "./skystrike_session.mjs";
import { grab, lowres, png } from "./skystrike_zig_frame.mjs";

const Y0 = 15, SH = 250;
const gun = (n) => Math.floor((n & 7) * 255 / 7);
const rgba = (w) => (0xff000000 | gun(w) << 16 | gun(w >> 4) << 8 | gun(w >> 8)) >>> 0;
const palette = (s) => [...new Uint16Array(s.memory.buffer.slice(s.demo.skyTestPtr(4), s.demo.skyTestPtr(4) + 32))].map(rgba);

function mostly(p, y) {
    const n = new Array(16).fill(0);
    for (let x = 0; x < 320; x++) n[p[y * 320 + x] & 15]++;
    let best = 0;
    for (let c = 1; c < 16; c++) if (n[c] > n[best]) best = c;
    return best;
}

/// The frame this screen should be, as 400 x 280 colour indices.
function expected(p, broke) {
    const out = new Uint8Array(WIN_W * 280);
    const top = mostly(p, 0), bottom = mostly(p, 199);
    for (let y = 0; y < 280; y++) for (let x = 0; x < WIN_W; x++) {
        let c;
        if (broke) c = x >= 40 && x < 360 && y >= 40 && y < 240 ? p[(y - 40) * 320 + x - 40] : 0;
        else if (y < Y0) c = top;
        else if (y >= Y0 + SH) c = bottom;
        else c = p[Math.floor((y - Y0) * 4 / 5) * 320 + Math.floor(x * 4 / 5)];
        out[y * WIN_W + x] = c;
    }
    return out;
}

const pending = [];

/// One screen, in the mode the session is in (synchronous: toPlay does not
/// wait for its callback).
function check(s, name, zig, outdir, broke, errors, notes) {
    s.machine.hwClear();
    s.demo.frame(20); // a displayed frame; lockstep: no VBL runs
    const planes = [0, 1, 2, 3].map((p) => s.demo.isPlaneEnabled(p) ? 1 : 0).join("");
    if (!zig) {
        if (planes !== "1000") errors.push(`screens: ORIGINAL's ${name} shows planes ${planes}, not plane 0 alone`);
        return;
    }
    const frame = lowres(grab(s));
    if (outdir) pending.push(png(`${outdir}/zig_${name.replace(/ /g, "_")}.png`, frame, 400, 280));
    if (planes !== "0010") errors.push(`screens: ZIG's ${name} shows planes ${planes}, not the overlay alone`);
    const pal = palette(s), want = expected(s.screen("physic"), broke === "intro");
    let bad = 0, first = null;
    for (let i = 0; i < want.length; i++) if (frame[i] >>> 0 !== pal[want[i]]) { bad++; first ??= `x ${i % WIN_W} y ${(i / WIN_W) | 0}`; }
    if (bad) errors.push(`screens: ZIG's ${name} differs from the physic screen scaled into the frame in ${bad} of 112000 pixels (first ${first})`);
    else notes.push(name);
}

async function intro(zig, outdir, broke, errors, notes) {
    const s = await zsession(zig);
    await toPlay(s, (what) => (what === "play" ? null : check(s, what, zig, outdir, broke, errors, notes)));
}

/// The title's timeout to the hall of fame; then a game over with a score
/// for the table, to the name entry, where Z is typed.
async function hallOfFame(zig, outdir, broke, errors, notes) {
    const h = await zsession(zig);
    h.run(2200);
    if (h.label() < L.l2260 || h.label() > L.l2311) errors.push(`screens: the title's timeout is not in the hall of fame (label ${h.label()})`);
    else check(h, "hall of fame", zig, outdir, broke, errors, notes);
    const n = await zsession(zig);
    await toPlay(n);
    n.set("scre", 3000000);
    n.set("planes", 1);
    n.set("cl", 1);
    for (let i = 0; i < 400 && n.label() !== L.l227b && n.label() !== L.l190b; i++) n.run(1);
    n.press(32);
    for (let i = 0; i < 2000 && n.label() !== L.l2310 && n.label() !== L.l2311; i++) n.run(1);
    if (n.label() !== L.l2310 && n.label() !== L.l2311) return errors.push(`screens: a game over with 3,000,000 points did not reach the name entry (label ${n.label()})`);
    n.run(10);
    check(n, "name entry", zig, outdir, broke, errors, notes);
    n.press(0x5a);
    if (n.z("zig") !== (zig ? 1 : 0)) errors.push("screens: Z in the name entry switched the mode");
}

export async function screens(outdir, broke) {
    const errors = [], notes = [];
    for (const zig of [true, false]) {
        await intro(zig, zig ? outdir : null, broke, errors, notes);
        await hallOfFame(zig, zig ? outdir : null, broke, errors, notes);
    }
    await Promise.all(pending);
    console.log(`  screens: ZIG fills the open frame with ${notes.join(", ")} (5/4, every pixel); ORIGINAL shows plane 0 alone; Z is a letter in the name entry`);
    return errors;
}
