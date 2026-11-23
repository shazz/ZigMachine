// falcon_ays: the red texts' blur covers every row of the text (Matt, board, 14 Nov: "the effect
// on the text not reaching the lower part"). The original's $691E blurs 1014 x 12 = 12,168 bytes
// from row 1, column 1 of the 320-wide buffer (rows 1..38, row 39 to column 8); the port blurred
// 10,140, stopping at row 32 column 221, so the glyphs' last rows (buffer rows 33..35, the
// descent of "PRESENTS" and "...MAG") stayed sharp and the glow never spread below row 32.
// For each of the five texts (81D, 81E, 82B, 82C, 832), from the frame it is drawn to its last:
//   - SHARP: no lit pixel of band rows 33..38 equals the frame the text was drawn on both ~10
//     passes after the blur starts and on the text's last frame (a pixel the blur never touches
//     keeps its value; one look alone, a dark pixel can match by chance);
//   - REACH: the blur's glow lights band rows 33..38 (the port's old bound left them as drawn:
//     black under the three texts whose ink ends at row 30).
//   node apps/harness/falcon_ays_text.mjs [--break sharp]
//   (--break sharp looks twice before the blur starts: caught)
import { readFile } from "node:fs/promises";
import { boot, at, W } from "./falcon_ays_boot.mjs";

const BRK = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
// text.zig LINES: the band's screen row and the blur's threshold in 100 Hz timer ticks.
const TEXTS = { 0x1D: [80, 160], 0x1E: [88, 160], 0x2B: [84, 20], 0x2C: [84, 20], 0x32: [84, 20] };
const LO = 33, HI = 39; // the band rows the old 10,140-byte blur never reached
const SETTLE = 12; // frames of blur (~10 passes) before the SHARP check
const errors = [];
const want = (ok, msg) => { if (!ok && errors.length < 12) errors.push(msg); return ok; };

const src = await readFile("apps/zig/scenes/falcon_ays/script.zig", "utf8");
const cmds = [...src.matchAll(/\.\{ (\d+), 0x([0-9A-F]{2}) \}/g)].map((x) => [+x[1], parseInt(x[2], 16)]);
const firstFrame = (row) => { let f = Math.floor((row * 7 * 6) / 5); while (Math.floor((f * 5) / 6) < row * 7) f++; return f; };

// The band (40 rows of 320) of the 320x200 window.
const band = (pic, row) => pic.slice(row * W, (row + 40) * W);
const m = await boot();
let checked = 0;
for (let i = 0; i < cmds.length; i++) {
    const [row, v] = cmds[i];
    if (!(v in TEXTS)) continue;
    const [y, thr] = TEXTS[v];
    const f0 = firstFrame(row) + 1, fEnd = firstFrame(cmds[i + 1][0]) - 1;
    const fBlur = f0 + Math.ceil((thr * 60) / 100); // the timer reaches the threshold
    const name = `8${v.toString(16).toUpperCase()}`;
    const drawn = band(at(m, f0 / 60), y);
    let reach = 0, sharp = -1;
    const frozen = new Array(40 * W).fill(false);
    for (let f = f0 + 1; f <= fEnd; f++) {
        const b = band(at(m, f / 60), y);
        for (let r = LO; r < HI; r++) for (let x = 0; x < W; x++) if (b[r * W + x]) reach++;
        // Two looks, ~10 passes apart: a pixel still as drawn at both never took the blur.
        const looks = BRK === "sharp" ? [fBlur - 3, fBlur - 2] : [fBlur + SETTLE, fEnd];
        if (f === looks[0]) for (let k = LO * W; k < HI * W; k++) frozen[k] = b[k] !== 0 && b[k] === drawn[k];
        if (f === looks[1]) {
            sharp = 0;
            for (let k = LO * W; k < HI * W; k++) if (frozen[k] && b[k] === drawn[k]) sharp++;
        }
    }
    const lit = drawn.reduce((n, c) => n + (c ? 1 : 0), 0);
    want(lit > 2000, `setup: ${name} drew ${lit} lit pixels at frame ${f0}`);
    want(sharp === 0, `sharp: ${name} (frame ${f0}..${fEnd}) ${sharp} lit pixels never blurred`);
    want(reach > 0, `reach: ${name} the blur never lit band rows 33..38`);
    checked++;
}
want(checked === 5, `setup: ${checked} texts in the script, not 5`);

if (BRK) {
    const hit = errors.find((e) => e.startsWith(`${BRK}:`));
    console.log(hit ? `falcon_ays_text: PASS (--break ${BRK} caught: ${hit})` : `falcon_ays_text: FAILED -- --break ${BRK} not caught`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `falcon_ays_text: FAILED -- ${errors.join("; ")}`
        : `falcon_ays_text: all pass (${checked} texts: every lit pixel blurred, the glow reaches rows 33..38)`);
    process.exitCode = errors.length ? 1 : 0;
}
