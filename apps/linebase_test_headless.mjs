// Headless LINE LIST TEST (cart 110, apps/zig/scenes/linebase_test.zig): the proof cart of the
// copper LBASE + overscan HSCROLL (HW 1.10.0, fpga/review/COPPER_LINEBASE.md). Boots the sealed
// machine + the cart as sealed-loader.js does and, every frame of a run, reads back the list the
// cart built for the plane it shows and checks:
//   - the picture equals apps/linebase_model.mjs's rule applied to that list, pixel for pixel,
//     borders included (LBASE, the counter running on, HSCROLL per line, colour 0 per line);
//   - phase B (frames 151..300, plane 1, scroll): an LBASE on every 8th visible line and no record
//     between (bands of rows the CPU draws into, in reverse order, the lines between running on); phase A (frames 1..150, plane 0, overscan): one FLICK record a line (all
//     borders open, no HBL handler), HSCROLL > 0 in the wobble, run-on lines (no LBASE) in the
//     straight bands, an LBASE on every line of a flipped band, colour 0 changing down the frame.
//
//   node apps/linebase_test_headless.mjs [frames=420]
//   node apps/linebase_test_headless.mjs --break persist|hscroll   the model loses that rule: passes
//                                                                  only if the pixel check catches it
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { RH, REG_HSCROLL, REG_FB_COPPER, OFF_VRAM, decodeList, model, firstMismatch } from "./linebase_model.mjs";

const PAGES = 128, REG_BACKGROUND = 0x04, REG_FB_BASE = 0x44, OFF_PAL = 0x100, RW = 800, PHASE = 150;
const bi = process.argv.indexOf("--break"), brk = bi > 0 ? process.argv[bi + 1] : null;
const FRAMES = Number(process.argv.slice(2).find((a) => /^\d+$/.test(a)) || 420);

const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const romBytes = await readFile("docs/rom.wasm");
const rom = (await WebAssembly.instantiate(romBytes, {
    env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
})).instance.exports;
machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
const noop = () => {};
const cartBytes = await readFile("docs/demo-linebase_test.wasm");
const hw = Object.fromEntries(Object.entries(machine).filter(([k]) => k.startsWith("hwRam") || k.startsWith("hwRomRam")));
demo = (await WebAssembly.instantiate(cartBytes, {
    env: {
        memory, jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop, consoleLogJS: noop,
        hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit, ...hw, ...rom,
        audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop, diskReadBlock: noop,
        hostAudioStreamStart: noop, hostAudioFeed: noop, hostAudioStreamStop: noop,
    },
})).instance.exports;
machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
machine.hwInit();
demo.boot();
demo.skipBoot();

const V = machine.hwVideoBase();
const dv = () => new DataView(memory.buffer);
const r8 = (o) => dv().getUint8(V + o), r16 = (o) => dv().getUint16(V + o, true), r32 = (o) => dv().getUint32(V + o, true);

// What phase A's list must show over the run (each set the first time it is seen).
function noteA(recs, seen) {
    const has = (i, op) => recs[i][1].some((o) => o[0] === op);
    for (let y = 0; y < 100; y++) if (recs[y][1].some((o) => o[0] === "hs" && o[1] > 0)) seen.hs = true;
    for (let y = 180; y < RH; y++) if (!has(y, "lbase")) seen.runon = true;
    for (let b = 180; b < RH; b += 16) {
        let all = true;
        for (let y = b; y < Math.min(b + 16, RH); y++) all &&= has(y, "lbase");
        if (all) seen.flip = true;
    }
    if (recs.filter((_, i) => has(i, "pal")).length > 10) seen.raster = true;
}

// Plane p's picture this frame against the model of its list; the error, or null.
function plane(p, f, seen) {
    const v = r16(REG_FB_COPPER + 2 * p);
    if (!v) return `frame ${f}: no copper list on plane ${p}`;
    const recs = decodeList(r32, OFF_VRAM + 16 * v), ovs = p === 0;
    const cfg = { ovs, scroll: !ovs, stride: ovs ? 400 : 320, fb: r32(REG_FB_BASE + 4 * p), hs0: r16(REG_HSCROLL + 2 * p),
        pal: Array.from({ length: 256 }, (_, i) => r32(OFF_PAL + 1024 * p + 4 * i)) };
    machine.hwClear(), machine.hwRenderPlane(p);
    const pfb = machine.hwPhysicalPtr(), bg = r32(REG_BACKGROUND);
    if (ovs) {
        if (recs.length !== RH || recs.some(([y, ops], i) => y !== i || ops[0]?.[0] !== "flick"))
            return `frame ${f}: plane 0 has not one FLICK record a line (${recs.length} records)`;
        noteA(recs, seen);
    } else if (recs.length === 25 && recs.every(([y, ops], i) => y === 40 + 8 * i && ops.some((o) => o[0] === "lbase"))) {
        seen.flipB = true;
    }
    return firstMismatch(model(cfg, recs, brk), r8, (x, y) => dv().getUint32(pfb + (y * RW + 2 * x) * 4, true), bg);
}

const seen = {};
let err = null, f = 1;
for (; f <= FRAMES && !err; f++) {
    demo.frame(16.6);
    err = plane(Math.floor((f - 1) / PHASE) % 2 === 0 ? 0 : 1, f, seen);
}
if (brk) {
    console.log(err ? `linebase_test --break ${brk}: caught (${err})` : `linebase_test --break ${brk}: NOT caught`);
    process.exit(err ? 0 : 1);
}
const missing = ["hs", "runon", "flip", "raster", "flipB"].filter((k) => !seen[k]);
if (!err && missing.length) err = `the list never used: ${missing.join(", ")}`;
console.log(err ? `linebase_test: FAILED at frame ${f - 1}: ${err}` : `linebase_test: ${FRAMES} frames equal the line-list model`);
process.exit(err ? 1 : 0);
