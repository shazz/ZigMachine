// Headless BLADERUNNERS "DUNGEON" check (apps/zig/scenes/bladerunners.zig).
//
// 1. ONE RASTER LINE, BORDER TO BORDER. On an ST the background raster is colour
//    0, ONE register changed per scanline, and the border is painted from that
//    same register: a visible line is one colour from the left border through the
//    picture to the right border. The board showed three (Matt, 2026-10-23): the
//    border's table index was (line + 12) where the picture's was (line - 40), and
//    the border was painted before the frame advanced the raster. So on every
//    frame and every physical line 40..239 of the COMPOSED picture (the browser's
//    stacked canvases): the 80 left-border pixels, the 80 right-border pixels and
//    every picture pixel that is not scroller ink are back[(ly + R) % 255]
//    (ly = line - 40, R = floor(frame / 2) as a byte, the raster's 2-frame tick),
//    and the ink is font[ly]; lines 0..39 and 240..279 are transparent (the tube).
// 2. THE PICTURE DID NOT MOVE. The picture area (x 80..719, lines 40..239) of
//    every frame hashes, per block of frames, to apps/bladerunners_expected.json,
//    recorded from the cart BEFORE the fix (two planes, CPU-cleared strip,
//    37477829): the ring strip and the merged plane draw the same scroller.
//
//   node apps/bladerunners_headless.mjs [--break shift] [--cart X.wasm] [--write]
//     --break shift  the cart's border HBL is told line+1 from line 1 on (line 0, the
//                    raster's tick, unchanged): one table line off, caught
//     (the cart as it was, 37477829's wasm as --cart, fails check 1 on line 40's border)
//     --write        (re)write the picture hashes from --cart (never in the gate)
import { readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const FRAMES = 10500, BLOCK = 500; // the whole scroll text (625 letters x 16 frames) and its wrap
const W = 800, TOP = 40, BX = 80;
const EXPECTED = "apps/bladerunners_expected.json";
const ASSETS = "apps/zig/assets/screens/bladerunners";

const argv = process.argv.slice(2);
const opt = (name, dflt) => { const i = argv.indexOf(name); return i < 0 ? dflt : argv[i + 1]; };
const brk = opt("--break", null);
if (brk && brk !== "shift") throw new Error(`--break takes shift, not ${brk}`);
const cart = opt("--cart", "docs/demo-bladerunners.wasm");

// the RGBA words the machine stores (a<<24 | b<<16 | g<<8 | r) from the .dat tables
const table = (f) => {
    const d = readFileSync(`${ASSETS}/${f}`);
    return Array.from({ length: 256 }, (_, i) => d.readUInt32LE(i * 4));
};
const BACK = table("raster_back_pal.dat"), FONT = table("raster_font_pal.dat");

async function boot() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const st = { demo: null, clearing: false };
    // --break shift: the global (border) handler, called from hwClear, sees line + 1
    const shift = (l) => (brk === "shift" && st.clearing && l >= 1 ? l + 1 : l);
    const hbl = (id, p, l, x) => st.demo.hblDispatch(id, p, shift(l), x);
    const machine = (await WebAssembly.instantiate(readFileSync("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: hbl },
    })).instance.exports;
    const romBytes = readFileSync("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = readFileSync(cart);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine))
        if (/^hw(Rom)?Ram|^hwVideoBase$|^hwBlit$/.test(k)) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    st.demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    st.demo.boot();
    st.demo.skipBoot();
    return { memory, machine, st };
}

// one frame as the browser shows it: clear, frame, every enabled plane stacked
function compose(m, comp) {
    const { memory, machine, st } = m;
    st.clearing = true;
    machine.hwClear();
    st.clearing = false;
    st.demo.frame(16.6);
    comp.fill(0);
    const n = comp.length;
    for (let p = 0; p < machine.hwPlanesNumber(); p++) {
        if (!st.demo.isPlaneEnabled(p)) continue;
        machine.hwRenderPlane(p);
        const snap = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), n);
        for (let i = 0; i < n; i++) if (snap[i] >>> 24) comp[i] = snap[i];
    }
}

// check 1 on one frame: the first wrong line, or null
function rasterError(comp, f) {
    const R = Math.floor(f / 2) & 255;
    for (let y = 0; y < 280; y++) {
        const row = comp.subarray(y * W, y * W + W);
        if (y < TOP || y >= TOP + 200) {
            if (row.some((v) => v >>> 24)) return `line ${y}: border band not transparent`;
            continue;
        }
        const ly = y - TOP, bg = BACK[(ly + R) % 255], ink = FONT[ly];
        for (let x = 0; x < W; x++) {
            const v = row[x], inPic = x >= BX && x < W - BX;
            if (v === bg || (inPic && v === ink)) continue;
            const where = x < BX ? "left border" : inPic ? "picture" : "right border";
            return `line ${y} x ${x} (${where}): ${v.toString(16)}, raster ${bg.toString(16)}`;
        }
    }
    return null;
}

const m = await boot();
const comp = new Uint32Array(W * 280);
const blocks = [];
let firstBad = null, badFrames = 0, h = createHash("sha256");
for (let f = 1; f <= FRAMES; f++) {
    compose(m, comp);
    const err = rasterError(comp, f);
    if (err) { badFrames++; firstBad ??= `frame ${f}, ${err}`; }
    for (let y = TOP; y < TOP + 200; y++) h.update(new Uint8Array(comp.buffer, (y * W + BX) * 4, (W - 2 * BX) * 4));
    if (f % BLOCK === 0) { blocks.push(h.digest("hex")); h = createHash("sha256"); }
}

if (argv.includes("--write")) {
    writeFileSync(EXPECTED, JSON.stringify({ frames: FRAMES, block: BLOCK, cart, blocks }, null, 1) + "\n");
    console.log(`bladerunners: wrote ${EXPECTED} from ${cart}`);
    process.exit(0);
}
const want = JSON.parse(readFileSync(EXPECTED, "utf8"));
const badBlocks = blocks.filter((b, i) => b !== want.blocks[i]).length;
const rasterOk = badFrames === 0, pictureOk = badBlocks === 0 && want.frames === FRAMES;
console.log(`  ${rasterOk ? "ok  " : "FAIL"} one raster colour per line, borders included (${FRAMES - badFrames}/${FRAMES} frames)${firstBad ? `; first: ${firstBad}` : ""}`);
console.log(`  ${pictureOk ? "ok  " : "FAIL"} picture area = the pre-fix cart's (${blocks.length - badBlocks}/${blocks.length} blocks of ${BLOCK})`);
if (brk) {
    const caught = !rasterOk;
    console.log(caught ? `bladerunners: PASS (--break ${brk} caught)` : `bladerunners: FAIL, --break ${brk} was NOT caught`);
    process.exit(caught ? 0 : 1);
}
const pass = rasterOk && pictureOk;
console.log(pass ? `bladerunners: PASS, ${FRAMES} frames` : "bladerunners: FAIL");
process.exit(pass ? 0 : 1);
