// falcon_ays: the beat flashes, border and screen together, frame by frame (Matt, board, 14 Nov:
// "the on beat flashes (white then fast fade to black) not sync between borders and visible
// screen"). The host paints the border from BACKGROUND in hwClear BEFORE the cart's frame and the
// planes AFTER it (sealed-loader.js, the board's vseq_clear / vseq_plane in fpga/cycles/bmain.c),
// so this runs the cart in exactly that order and looks at every frame shown around each flash
// command of the script (81A/81B the grey fade, 823/824 white):
//   - a frame whose 320x200 picture is ONE colour (a flash) has the border in that colour;
//   - a frame whose border is lit (not black) shows that colour as the picture's commonest;
//   - the border is one colour all round (top, bottom, both sides);
//   - every flash command is seen, and the fade's levels are many (not one colour held).
//   node apps/falcon_ays_flash.mjs [--break lag]
//   (--break lag compares each picture with the NEXT frame's border: the fade a frame apart, caught)
import { readFile } from "node:fs/promises";
import { boot, RW, RH, W, H, X0, Y0 } from "./falcon_ays_boot.mjs";

const BRK = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
const FLASHES = new Set([0x1A, 0x1B, 0x23, 0x24]);
const BEFORE = 3, AFTER = 40; // frames around a flash command: the grey fade is 31 timer ticks (~19 frames)
const errors = [];
const want = (ok, msg) => { if (!ok && errors.length < 12) errors.push(msg); return ok; };

// The script's rows (script.zig): a row is 7 ticks of 50 Hz, the frame clock ticksAt(f) = f*5/6.
const src = await readFile("apps/zig/scenes/falcon_ays/script.zig", "utf8");
const cmds = [...src.matchAll(/\.\{ (\d+), 0x([0-9A-F]{2}) \}/g)].map((x) => [+x[1], parseInt(x[2], 16)]);
const firstFrame = (row) => { let f = Math.floor((row * 7 * 6) / 5); while (Math.floor((f * 5) / 6) < row * 7) f++; return f; };
const windows = cmds.filter(([, v]) => FLASHES.has(v)).map(([row]) => firstFrame(row));
const inWindow = (f) => windows.some((w) => f >= w - BEFORE && f <= w + AFTER);
const last = Math.max(...windows) + AFTER;

// One frame as the hosts show it: hwClear (the border), the cart's frame, then each enabled plane.
function step(m) {
    m.machine.hwClear();
    m.demo.frame(1000 / 60);
    m.frame++;
}
function composite(m) {
    const comp = new Uint32Array(RW * RH);
    for (let p = 0; p < 8; p++) {
        if (!m.demo.isPlaneEnabled(p)) continue;
        m.machine.hwRenderPlane(p);
        const px = new Uint32Array(m.memory.buffer, m.machine.hwPhysicalPtr(), RW * RH);
        for (let i = 0; i < comp.length; i++) if (px[i] >>> 24) comp[i] = px[i];
    }
    if (!comp.some((v) => v >>> 24)) comp.set(new Uint32Array(m.memory.buffer, m.machine.hwPhysicalPtr(), RW * RH));
    return comp;
}
const px = (comp, x, y) => comp[y * RW + x * 2] & 0xFFFFFF; // x, y in the 400x280 raster
function border(comp) {
    const s = [px(comp, 5, 5), px(comp, 200, 10), px(comp, 5, 140), px(comp, 395, 140), px(comp, 200, 270), px(comp, 395, 275)];
    return { c: s[0], uniform: s.every((v) => v === s[0]) };
}
function picture(comp) {
    const n = new Map();
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const v = px(comp, X0 + x, Y0 + y);
        n.set(v, (n.get(v) ?? 0) + 1);
    }
    const [top] = [...n.entries()].sort((a, b) => b[1] - a[1]);
    return { c: top[0], uniform: n.size === 1 };
}

const m = await boot();
const seen = []; // per checked frame: { f, border, picture }
let prevF = -2;
while (m.frame <= last) {
    step(m);
    if (!inWindow(m.frame)) continue;
    const comp = composite(m);
    seen.push({ f: m.frame, b: border(comp), p: picture(comp), cont: m.frame === prevF + 1 });
    prevF = m.frame;
}

let flashFrames = 0, lit = 0;
const levels = new Set();
for (let i = 0; i < seen.length; i++) {
    const { f, p } = seen[i];
    const b = BRK === "lag" ? (seen[i + 1]?.cont ? seen[i + 1].b : seen[i].b) : seen[i].b;
    const t = (f / 60).toFixed(2);
    want(b.uniform, `border: frame ${f} (${t} s) not one colour all round`);
    if (p.uniform) {
        flashFrames++;
        levels.add(p.c);
        want(b.c === p.c, `flash: frame ${f} (${t} s) screen ${p.c.toString(16)}, border ${b.c.toString(16)}`);
    }
    if (b.c !== 0) {
        lit++;
        want(p.c === b.c, `flash: frame ${f} (${t} s) border ${b.c.toString(16)}, picture mostly ${p.c.toString(16)}`);
    }
}
want(windows.length >= 20, `setup: ${windows.length} flash commands in the script`);
want(flashFrames >= windows.length * 4, `setup: only ${flashFrames} one-colour frames around ${windows.length} flash commands`);
want(levels.size >= 12, `setup: the fades showed ${levels.size} levels`);

if (BRK) {
    const hit = errors.find((e) => e.startsWith("flash:"));
    console.log(hit ? `falcon_ays_flash: PASS (--break ${BRK} caught: ${hit})` : `falcon_ays_flash: FAILED -- --break ${BRK} not caught`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `falcon_ays_flash: FAILED -- ${errors.join("; ")}`
        : `falcon_ays_flash: all pass (${windows.length} flash commands, ${seen.length} frames, ${flashFrames} flash frames at ${levels.size} levels, ${lit} lit borders, border = screen on every one)`);
    process.exitCode = errors.length ? 1 : 0;
}
