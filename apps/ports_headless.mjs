// Headless gate for the C program ports (apps/ports): boots one port's committed cart,
// docs/demo-<tag>.wasm, on the sealed machine with its committed floppy docs/demo-<tag>.zmd in
// the drive (apps/ports_machine.mjs), and drives the program through the input exports the
// browser and the board call. Per port:
//   boot      the cart instantiates with nothing but the host's env imports, boot() and every
//             frame run without a trap, plane 0 is enabled
//   ui        the program's screen is there: at least N colours on the physical frame and, at a
//             pinned frame, the frame's sha256 equals the pin (the program's own UI, pixel for pixel)
//   use       one real interaction, checked by what it changes:
//     pt2        DISK OP (a click), then a click on the first file: HYBRID.MOD loads off the floppy
//                (the song-name row changes to its name), then PLAY: the module is heard
//     grafx2     OK closes the read-only-device warning (Asyncify'd modal loop), then a freehand
//                stroke paints pixels in the picture
//     klystrack  F5 plays STARPORT2.KT (opened off the floppy at boot): the stream is not silent
//     chipnomad  X (the A button) on the song screen's first cell puts chain 00 there
//
//   node apps/ports_headless.mjs <pt2|grafx2|klystrack|chipnomad> [--break <x>] [--png <dir>]
// --break SABOTAGES the interaction and passes only if a check notices:
//   pt2 load (the file is never clicked), grafx2 stroke (the stroke is never drawn) or disk (an
//   empty drive: no skin, no font, and GrafX2 stops in boot),
//   klystrack silent (F5 is never pressed), chipnomad key (X is never pressed).
// Pins: re-bless only for a deliberate change to a cart (print them with PINS=1).
import { readFile, mkdir } from "node:fs/promises";
import { boot, step, picture, colours, sha, rows, png } from "./ports_machine.mjs";

const F_KEY5 = 0xe005, KEY_X = 0x78;
// Coordinates are each program's own; pointer() takes the visible window's (x doubled), and the
// port's kestrel_input_origin maps them back (pt2: its 320x255 screen starts 28 rows above the window).
const click = (x, y, b, dy = 0) => (d) => d.pointer(x * 2, y + dy, b);
const SPECS = {
    pt2: {
        cart: "docs/demo-pt2.wasm", disk: "docs/demo-pt2.zmd", frames: 300, minColours: 10, breaks: ["load"],
        pinAt: 90, pin: "0dda0e9b1204ccf6338165770335f77684ec7d0c3ed527584773c85e6bd2aa41",
        // ProTracker blocks input for a second after boot (an error pointer from its startup); then:
        // DISK OP (182..243, 33..43), the first row of the file list (rows of 6 from y 34), PLAY (120..181, 0..10)
        events: (brk) => [
            ...press(100, 212, 38, -28),
            ...(brk === "load" ? [] : press(130, 100, 36, -28)),
            ...press(200, 150, 5, -28),
        ],
        use: usePt2,
    },
    grafx2: {
        cart: "docs/demo-grafx2.wasm", disk: "docs/demo-grafx2.zmd", frames: 240, minColours: 12, breaks: ["stroke", "disk"],
        pinAt: 90, pin: "611b4ddbec32564355038967a60f34544ccef3cdf5bd7c6a91d29d0c75912a55",
        // OK of the warning box at (160, 163); then a freehand stroke along y = 50 from x 100 to 150
        events: (brk) => [...press(100, 160, 163), ...(brk === "stroke" ? [] : stroke(150, 100, 150, 50)), [200, click(10, 10, 0)]],
        use: useGrafx2,
    },
    klystrack: {
        cart: "docs/demo-klystrack.wasm", disk: "docs/demo-klystrack.zmd", frames: 120, minColours: 24, breaks: ["silent"],
        pinAt: 20, pin: "c535877893c812bf1cb6e491a9e6ebe27c5aecf5258c8e661d630fe6e9608d5b",
        events: (brk) => (brk === "silent" ? [] : [[30, (d) => d.key(F_KEY5)], [33, (d) => d.keyUp(F_KEY5)]]),
        use: useKlystrack,
    },
    chipnomad: {
        cart: "docs/demo-chipnomad.wasm", disk: "docs/demo-chipnomad.zmd", frames: 90, minColours: 5, breaks: ["key"],
        pinAt: 20, pin: "a56c75e3bd11582f4b55e0d0e5098a883bc6bdc8bfd5caa1d3b4df0a227f052c",
        events: (brk) => (brk === "key" ? [] : [[30, (d) => d.key(KEY_X)], [33, (d) => d.keyUp(KEY_X)]]),
        use: useChipnomad,
    },
};

// A left click at frame f: move there the frame before, press, release 6 frames later.
function press(f, x, y, dy = 0) {
    return [[f - 1, click(x, y, 0, dy)], [f, click(x, y, 1, dy)], [f + 6, click(x, y, 0, dy)]];
}
// A drag at frame f: press at (x0, y), move to x1 two pixels a frame, release.
function stroke(f, x0, x1, y) {
    const ev = [[f - 1, click(x0, y, 0)], [f, click(x0, y, 1)]];
    let t = f;
    for (let x = x0 + 2; x <= x1; x += 2) ev.push([++t, click(x, y, 1)]);
    ev.push([t + 1, click(x1, y, 0)]);
    return ev;
}

const args = process.argv.slice(2);
const tag = args[0];
const spec = SPECS[tag];
if (!spec) throw new Error(`usage: node apps/ports_headless.mjs <${Object.keys(SPECS).join("|")}> [--break <x>] [--png <dir>]`);
const opt = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : ""; };
const broke = opt("--break"), pngDir = opt("--png");
if (broke && !spec.breaks.includes(broke)) throw new Error(`--break ${broke}: ${tag} has ${spec.breaks.join(", ")}`);

let failures = 0;
function check(name, ok, detail = "") {
    if (!ok) failures++;
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`);
}

// Run the cart: boot, every frame through step(), the scripted events at their frames, a picture
// kept at each frame the checks ask for. A trap (in boot or a frame) ends the run and fails it.
async function run() {
    const disk = broke === "disk" ? null : await readFile(spec.disk);
    const events = spec.events(broke), shots = new Map(), audio = { peak: 0, n: 0, rate: 0 };
    let trap = "", m = { demo: { isPlaneEnabled: () => 0 }, audio };
    try {
        m = await boot(spec.cart, disk);
        for (let f = 1; f <= spec.frames; f++) {
            for (const [ef, fn] of events) if (ef === f) fn(m.demo);
            step(m);
            if (spec.keep(f)) shots.set(f, picture(m));
        }
    } catch (e) { trap = String(e); }
    return { m, shots, trap };
}

function useCommon(r) {
    check("boot and frames", !r.trap, r.trap || `${spec.frames} frames, no trap`);
    check("plane 0 enabled", r.m.demo.isPlaneEnabled(0) === 1);
    const ui = r.shots.get(spec.pinAt);
    if (!ui) return check("ui", false, `no picture at frame ${spec.pinAt}`);
    const n = colours(ui), h = sha(ui.px);
    check("ui colours", n >= spec.minColours, `${n} colours at frame ${spec.pinAt} (>= ${spec.minColours})`);
    if (process.env.PINS) console.log(`  pin ${tag} @${spec.pinAt}: ${h}`);
    check("ui pin", h === spec.pin, h === spec.pin ? `frame ${spec.pinAt} = ${h.slice(0, 16)}...` : `got ${h}`);
}

// pt2's song-name row is its line y 99..109, at 12 + y on the physical frame.
function usePt2(r) {
    const name = (f) => r.shots.get(f) && sha(rows(r.shots.get(f), 111, 121));
    check("pt2 DISK OP opens", r.shots.get(120) && sha(r.shots.get(120).px) !== sha(r.shots.get(90).px), "the screen changed after the click");
    check("pt2 module loads off the floppy", name(190) && name(190) !== name(90), "the song-name row changed (HYBRID.MOD's 'setup2')");
    check("pt2 module plays", r.m.audio.peak > 8, `peak |s8| ${r.m.audio.peak} after PLAY, ${r.m.audio.n} samples fed`);
}
SPECS.pt2.keep = (f) => [90, 120, 190, 300].includes(f);

// The stroke's line: y 50 is physical row 90, x 100..150 physical 280..380 (low res doubled).
function useGrafx2(r) {
    const before = r.shots.get(90), after = r.shots.get(120), drawn = r.shots.get(240);
    check("grafx2 warning closes on OK", before && after && sha(before.px) !== sha(after.px));
    check("grafx2 main screen", after && colours(after) >= 40, `${after ? colours(after) : 0} colours: tool bar, palette (>= 40)`);
    let lit = 0;
    if (drawn) {
        const line = rows(drawn, 90, 90);
        for (let x = 284; x < 376; x += 2) if (line[x * 4] | line[x * 4 + 1] | line[x * 4 + 2]) lit++;
    }
    check("grafx2 freehand stroke paints", lit >= 40, `${lit} of 46 pixels along the stroke lit`);
}
SPECS.grafx2.keep = (f) => [90, 120, 240].includes(f);

function useKlystrack(r) {
    check("klystrack plays STARPORT2.KT", r.m.audio.peak > 8, `peak |s8| ${r.m.audio.peak}, ${r.m.audio.n} samples at ${r.m.audio.rate} Hz`);
    const a = r.shots.get(20), b = r.shots.get(120);
    check("klystrack screen follows play", a && b && sha(a.px) !== sha(b.px));
}
SPECS.klystrack.keep = (f) => [20, 120].includes(f);

function useChipnomad(r) {
    const a = r.shots.get(20), b = r.shots.get(60);
    check("chipnomad X puts a chain in the song", a && b && sha(rows(a, 70, 79)) !== sha(rows(b, 70, 79)), "row 00 of the song changed");
}
SPECS.chipnomad.keep = (f) => [20, 60].includes(f);

console.log(`${tag}: ${spec.cart} + ${broke === "disk" ? "an EMPTY drive" : spec.disk}${broke ? ` (--break ${broke})` : ""}`);
const r = await run();
useCommon(r);
spec.use(r);
if (pngDir) {
    await mkdir(pngDir, { recursive: true });
    for (const [f, p] of r.shots) await png(p, `${pngDir}/${tag}_${f}.png`);
}
if (broke) {
    console.log(failures ? `\n${tag}: PASS (--break ${broke} was caught)` : `\n${tag}: FAILED - --break ${broke} was not caught`);
    process.exit(failures ? 0 : 1);
}
console.log(failures ? `\n${tag}: ${failures} FAILED` : `\n${tag}: PASS`);
process.exit(failures ? 1 : 0);
