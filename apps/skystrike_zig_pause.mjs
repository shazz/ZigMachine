// SKYSTRIKE ZIG-mode harness, the pause (apps/skystrike_zig.mjs drives):
// P in flight (line 151: the music until a key). In ZIG the key-help panel
// (zig_help.zig) shows over the game while it waits, framed and written as
// the game's boxed messages; in ORIGINAL it does not. The same pause in
// both, pass for pass: the logic CRC the same before it, all through it and
// after the key that ends it -- the panel changes nothing.
// --break help: ORIGINAL's pause checked for the panel.
import { readFile } from "node:fs/promises";
import { onRunway, WIN_W } from "./skystrike_zig_session.mjs";
import { grab, lowres, png } from "./skystrike_zig_frame.mjs";

const START = 200, P = 0x50, Q = 0x51;
const PANEL = { x: 16 + 8, y: 39 + 8, title: "          K E Y S", pen: 1 }; // zig_help.zig X0/Y0 + a cell (Y0 = (VIEW_H 246 - 168) / 2)

async function pausedRun(zig, outdir) {
    const s = await onRunway(zig);
    while (s.val(10) < START) s.pass();
    s.press(0x39); // '9': the engine on
    for (let p = 0; p < 20; p++) s.pass();
    const crcs = [s.z("crc") >>> 0];
    s.demo.skyTestKey(P, 1); s.demo.skyTestKey(P, 0);
    for (let i = 0; i < 20 && s.label() !== 10; i++) s.run(1);
    s.run(50);
    const paused = s.label();
    crcs.push(s.z("crc") >>> 0);
    const help = s.val(363);
    if (outdir) await png(`${outdir}/zig_pause_help.png`, lowres(grab(s)), 400, 280);
    const ov = s.overlay().slice();
    s.run(10);
    crcs.push(s.z("crc") >>> 0);
    s.demo.skyTestKey(Q, 1); s.demo.skyTestKey(Q, 0);
    for (let p = 0; p < 5; p++) { s.pass(); crcs.push(s.z("crc") >>> 0); }
    return { s, crcs, paused, help, ov };
}

/// The panel's title in the game's font at its place in the overlay.
async function titleDrawn(ov) {
    const font = await readFile("apps/zig/assets/screens/skystrike/font.bin");
    let bad = 0;
    for (let k = 0; k < PANEL.title.length; k++) for (let j = 0; j < 8; j++) for (let i = 0; i < 8; i++) {
        if (!(font[(PANEL.title.charCodeAt(k) - 32) * 8 + j] >> (7 - i) & 1)) continue;
        if (ov[(PANEL.y + j) * WIN_W + PANEL.x + k * 8 + i] !== PANEL.pen) bad++;
    }
    return bad;
}

export async function pause(outdir, broke) {
    const errors = [];
    const z = await pausedRun(true, outdir), o = await pausedRun(false, null);
    const L151 = 10; // flow.zig's l151a
    if (z.paused !== L151 || o.paused !== L151) errors.push(`pause: P did not pause (labels ${z.paused}, ${o.paused})`);
    const zBad = await titleDrawn(z.ov);
    if (!z.help || zBad) errors.push(`pause: ZIG's pause shows no key help (shown ${z.help}, ${zBad} title pixels missing)`);
    const oShown = broke === "help" ? !o.help : o.help || o.s.demo.isPlaneEnabled(2);
    if (oShown) errors.push(`pause: ORIGINAL's pause ${broke === "help" ? "has no key help to find" : "shows the key help"}`);
    const at = z.crcs.findIndex((c, i) => c !== o.crcs[i]);
    if (at >= 0) errors.push(`pause: the logic state differs between the modes at checkpoint ${at} (before, paused, later, then 5 passes)`);
    if (z.crcs[1] !== z.crcs[2]) errors.push("pause: the logic state moved while paused under the panel");
    console.log(`  pause: P -> line 151 in both; the key help over ZIG's (its title in the game's font), none in ORIGINAL's; the CRC the same in both before, during and after`);
    return errors;
}
