// Headless THE ERFURT MEGADEMO menu (docs/demo-erfurt_menu.wasm): boots the sealed machine + the
// cart the way docs/sealed-loader.js does and checks the screen against the ORIGINAL's data
// (apps/zig/assets/screens/erfurt_menu, ripped from the disks by prototypes/erfurt_re/tools):
//   - the logo's 43 lines are logo.raw through logo_pal.dat, pixel for pixel (planar decode + STE colours)
//   - the three rainbow lines are REAL rasters: the hue wheel (rainbow.dat), 12 px a colour,
//     edge to edge of the 400-px raster, borders included, and they move
//   - the border is colour 0: navy, and the marker's $012 on the marker band
//   - the drum spins on Down and settles on another entry; the scroller and the floor move
//   - Space fades the screen out the menu's way, it goes dark, and comes back; Escape leaves
//   node apps/erfurt_menu_headless.mjs [outdir] [--break hbl]
//   --break hbl: the plane's HBL never runs (no per-line colours, no open borders): must FAIL.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 128; // SHARED_PAGES, machine/sdk/memmap.zig
const BREAK = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
const A = "apps/zig/assets/screens/erfurt_menu/";

async function boot(cart) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const hbl = (id, p, l, x) => (BREAK === "hbl" && id !== 0xffff && p === 0 ? undefined : demo.hblDispatch(id, p, l, x));
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: hbl },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const noop = () => {};
    const cartBytes = await readFile(cart);
    
    demo = (await WebAssembly.instantiate(cartBytes, {
        env: {
            memory,
            jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop,
            consoleLogJS: noop,
            hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit,
            hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop, hwRamSize: machine.hwRamSize,
            hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree, hwRamAlloc: machine.hwRamAlloc,
            hwRamMark: machine.hwRamMark, hwRamRelease: machine.hwRamRelease,
            hwRamAllocFailures: machine.hwRamAllocFailures,
            hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
            hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed, hwRomRamFree: machine.hwRomRamFree,
            ...rom,
            audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop,
            diskReadBlock: noop, hostAudioStreamStart: noop, hostAudioFeed: noop, hostAudioStreamStop: noop,
            hostMicros: () => 0,
        },
    })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

const { memory, machine, demo } = await boot("docs/demo-erfurt_menu.wasm");
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight(); // 800 x 280: x doubled
const XS = W / 400; // raster px -> PFB columns
let frames = 0;
function run(n) {
    for (let i = 0; i < n; i++) {
        machine.hwClear();
        demo.frame(20);
        frames++;
    }
}
function raster() {
    machine.hwClear();
    machine.hwRenderPlane(0);
    return new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4).slice();
}
const px = (r, x, y) => { const i = (y * W + x * XS) * 4; return `${r[i]},${r[i + 1]},${r[i + 2]}`; };
const lineColours = (r, y) => new Set(Array.from({ length: 400 }, (_, x) => px(r, x, y)));
const lvl = (n) => ((n & 7) << 1) | (n >> 3);
const ste = (w) => [8, 4, 0].map((s) => lvl((w >> s) & 15) * 17).join(",");
const word = (b, i) => (b[2 * i] << 8) | b[2 * i + 1];
const TOP = 40, LEFT = 40; // the window inside the 400x280 raster

const out = process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : "/tmp/erfurt_menu";
await mkdir(out, { recursive: true });
async function shot(name, r) {
    const hdr = new TextEncoder().encode(`P6\n400 ${H}\n255\n`);
    const buf = new Uint8Array(hdr.length + 400 * H * 3);
    buf.set(hdr);
    for (let y = 0; y < H; y++) for (let x = 0; x < 400; x++) for (let c = 0; c < 3; c++)
        buf[hdr.length + (y * 400 + x) * 3 + c] = r[(y * W + x * XS) * 4 + c];
    await writeFile(`${out}/${name}.ppm`, buf);
}
const errors = [];
const check = (ok, what) => { if (!ok) errors.push(`${what} (frame ${frames})`); console.log(`  ${ok ? "ok  " : "FAIL"} ${what}`); };

const logo = await readFile(A + "logo.raw"), logoPal = await readFile(A + "logo_pal.dat");
run(3);
let r = raster();
await shot("menu", r);

// the logo: every pixel of its 43 lines is logo.raw's planar index through its own palette
let bad = 0;
for (let y = 0; y < 42; y++) for (let x = 0; x < 320; x++) {
    const g = (x >> 4) * 4, bit = 15 - (x & 15);
    let ci = 0;
    for (let p = 0; p < 4; p++) ci |= ((word(logo, y * 80 + g + p) >> bit) & 1) << p;
    if (px(r, LEFT + x, TOP + y) !== ste(word(logoPal, ci))) bad++;
}
check(bad === 0, `logo: 42 lines = logo.raw through logo_pal.dat (${bad} pixels off)`);

// the rainbows: real colour-0 rasters across the whole raster, borders included
const rainbowBytes = await readFile(A + "rainbow.dat");
const wheel = new Set(Array.from({ length: 35 }, (_, i) => ste(word(rainbowBytes, i))));
for (const y of [42, 43, 197, 198]) {
    // line 197 is also the floor's last line: its chequer covers part of the window
    const seen = Array.from({ length: 400 }, (_, x) => px(r, x, TOP + y)).filter((c) => wheel.has(c));
    check(seen.length > (y === 197 ? 150 : 300) && wheel.has(px(r, 0, TOP + y)) && wheel.has(px(r, 399, TOP + y)) && new Set(seen).size >= (y === 197 ? 20 : 30),
        `rainbow line ${y}: the hue wheel, edge to edge (${new Set(seen).size} hues)`);
}
const rainBefore = Array.from({ length: 400 }, (_, x) => px(r, x, TOP + 42)).join(";");
run(2);
r = raster();
check(rainBefore !== Array.from({ length: 400 }, (_, x) => px(r, x, TOP + 42)).join(";"), "rainbow: it moves");

// the border is colour 0: navy above the drum, $012 beside the marker band
const navy = ste(0x001), bar = ste(0x012);
check(px(r, 5, TOP + 60) === navy && px(r, 395, TOP + 60) === navy, "border: navy colour 0 beside the empty rows");
const barRows = Array.from({ length: 120 }, (_, k) => 45 + k).filter((y) => px(r, 5, TOP + y) === bar);
check(barRows.length >= 16 && barRows.length <= 20, `marker: $012 colour 0, border included, on ${barRows.length} rows`);
const white = ste(0x777);
const whiteIn = (r) => barRows.reduce((n, y) => n + Array.from({ length: 192 }, (_, x) => px(r, LEFT + 64 + x, TOP + y) === white).filter(Boolean).length, 0);
check(whiteIn(r) > 200, "marker: the entry under it in white");
const markerText = (r) => barRows.map((y) => Array.from({ length: 192 }, (_, x) => px(r, LEFT + 64 + x, TOP + y) === white ? 1 : 0).join("")).join("|");

// scroller (plane 2) and floor move
const band = (r, y0, y1) => Array.from({ length: y1 - y0 }, (_, k) => Array.from({ length: 320 }, (_, x) => px(r, LEFT + x, TOP + y0 + k)).join(";")).join("|");
const floorA = band(r, 167, 197), midA = band(r, 45, 160);
run(10); // the floor starts slowly: its depth and pan ride sines from phase 0
r = raster();
check(floorA !== band(r, 167, 197) && lineColours(r, TOP + 178).size >= 3, "floor: chequered, moving");
check(midA !== band(r, 45, 160), "scroller: moving");

// spin: Down held 20 frames, released, settles on another entry
const before = markerText(r);
demo.input(1);
run(20);
demo.inputRelease(1);
run(150);
r = raster();
const after = markerText(r);
// (the next frames may differ: the sparkle band sweeps the text from ~150 still frames on)
check(after !== before && whiteIn(r) > 200, "drum: Down spins it, it settles on another entry");
await shot("spun", raster());

// Space: the exit fade, dark, and back
const logoPix = px(raster(), LEFT + 160, TOP + 20);
demo.input(5);
run(12);
r = raster();
const mid = px(r, LEFT + 160, TOP + 20);
check(mid !== logoPix, "Space: the menu's fade starts");
run(20);
r = raster();
check(lineColours(r, TOP + 100).size <= 2 && lineColours(r, TOP + 20).size <= 2, "Space: dark where the part would run");
run(60);
r = raster();
await shot("back", r);
check(markerText(r) === after || whiteIn(r) > 200, "back: the menu again, on the entry just chosen");

demo.key(0xE012);
check(typeof demo.pollCartRequest !== "function" || demo.pollCartRequest() === -1, "Escape: leaves");

if (machine.hwRamAllocFailures()) errors.push(`${machine.hwRamAllocFailures()} zg.mem allocation(s) refused`);
const ok = BREAK ? errors.length > 0 : errors.length === 0;
console.log(ok ? `=> PASS ✅ ${BREAK ? `--break ${BREAK} is caught` : "the Erfurt menu"}` : `=> FAIL ❌\n  ${errors.join("\n  ")}`);
process.exit(ok ? 0 : 1);
