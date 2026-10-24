// Headless NOEXTRA ("RASTERS", NoExtra Team / DHS 2005) driver. Boots the sealed
// machine as apps/composite_hash.mjs does and runs the cart 2,400 frames (the
// whole intro, the main screen, and ~880 frames of the bob, 12 passes of its table), and checks:
//   frames  every 10th frame, the WHOLE 400x280 physical picture (borders
//           included) equals a model built here straight from the ripped assets
//           (apps/zig/assets/screens/noextra/, out of the original RASTERS.PRG):
//           the D.H.S logo at its bob-table height; then the NOEXTRA and ZORRO 2
//           logos pixel for pixel in their ST palettes, the gradient bars, every
//           band line's 35 colour-0 blocks from ramp.pal + the two sine reads,
//           the scroller's 32x16 one-plane glyphs on the wave table, the bob
//           table from frame 767 of the main screen, nothing above the first line shown
//           (capture row 9), and the bob and scroller one frame behind the band's colours
//   music   the cart asks for mega4_disk_mag.sndh, subtune 1, and nothing else
//   raster  every band line shows only ramp colours (no pixel image of a band)
//   node apps/noextra_headless.mjs [outdir]
//   node apps/noextra_headless.mjs --break ste   the model decodes the STE way:
//            passes only if the frame checks catch it
//   node apps/noextra_headless.mjs --break bob   the model's bob starts a frame late:
//            passes only if the frame checks catch it
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const W = 400, H = 280, RW = 800;
const FRAMES = 2400, EVERY = 10;
const PAD = 7, SX = 40, MAIN = 749, BOB_WAIT = 767; // noextra/rasters.zig, timeline.zig
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (broke && broke !== "ste" && broke !== "bob") throw new Error("--break ste | bob");
const outdir = process.argv.slice(2).find((a, i, v) => !a.startsWith("--") && v[i - 1] !== "--break") || "/tmp/noextra";

// --- the rip ----------------------------------------------------------------
const DIR = "apps/zig/assets/screens/noextra/";
const bin = async (n) => new Uint8Array(await readFile(DIR + n));
const words = (b) => Array.from({ length: b.length / 2 }, (_, i) => (b[2 * i] << 8) | b[2 * i + 1]);
const [top, bottom, dhs, font, charset, text] = await Promise.all(
    ["toplogo.raw", "bottomlogo.raw", "dhs.raw", "font.bin", "charset.bin", "scrolltext.bin"].map(bin));
const [palTop, palBot, palDhs, ramp, grad, sine, wave, bobT] = (await Promise.all(
    ["pal_top.pal", "pal_bottom.pal", "pal_dhs.pal", "ramp.pal", "gradbar.pal", "sine.bin", "wave.bin", "bob.bin"].map(bin))).map(words);
const ch = (n) => broke === "ste" ? (((n & 7) << 1) | ((n >> 3) & 1)) * 17 : (n & 7) * 32;
const rgba = (w) => (0xff000000 | (ch(w) << 16) | (ch(w >> 4) << 8) | ch(w >> 8)) >>> 0;
const BLACK = rgba(0), INK = rgba(palTop[1]);
const glyph = new Map([...charset].map((c, i) => [c, i]));

// --- the model: what RASTERS.PRG shows at frame f ----------------------------
function introFrame(f) {
    const px = new Uint32Array(W * H).fill(BLACK);
    if (f >= MAIN - 1) return px; // the cut to black
    const n = f < 254 ? -1 : Math.min(f - 254, 254);
    const y = bobT[(n + 1) % bobT.length];
    for (let r = 0; r < 112; r++) for (let x = 0; x < 192; x++) {
        const i = dhs[r * 192 + x];
        if (i) px[(29 + PAD + y + r) * W + SX + 64 + x] = rgba(palDhs[i]);
    }
    return px;
}
function bobAt(k) {
    const late = broke === "bob" ? 1 : 0;
    // the word before the table (0) first, then the table: timeline.zig's Bob
    return k <= BOB_WAIT + late ? 0 : bobT[(k - BOB_WAIT - 1 - late) % bobT.length];
}
function stripBit(b, y, bit) {
    if (b < 0) return 0;
    const g = glyph.get(text[((b >> 2) + 1) % text.length]) ?? 0, q = b & 3;
    return (font[g * 64 + (q >> 1) * 32 + 2 * y + (q & 1)] >> (7 - bit)) & 1;
}
function mainPixel(k, L, x, off) {
    if (L === 77 || L === 224) { const j = (x + 15) / 12 | 0; return rgba(grad[j]); }
    if (L >= 78 && L < 224) return rgba(ramp[off[L - 78] + ((x + 11) / 12 | 0)]);
    const lx = x - SX;
    if (lx < 0 || lx >= 320) return BLACK;
    if (L >= 9 && L < 78) { const i = top[(L - 9) * 320 + lx]; return i ? rgba(palTop[i]) : BLACK; }
    if (L >= 227 && L < 327) { const i = bottom[(L - 227) * 320 + lx]; return i ? rgba(palBot[i - 15]) : BLACK; } // stored +15
    return BLACK;
}
// main frame k shows frame k's band colours, but frame k - 1's bob and scroller (app.zig)
function mainFrame(k) {
    const bob = k ? bobAt(k - 1) : 0, p1 = 252 - 3 * (k % 84), p2 = k % 252, j = k - 1;
    const off = Array.from({ length: 146 }, (_, r) => (sine[(p1 + r) % 252] + sine[(p2 + 2 * r) % 252]) >> 1);
    const px = new Uint32Array(W * H).fill(BLACK);
    for (let p = PAD + 9; p < H; p++) for (let x = 0; x < W; x++) px[p * W + x] = mainPixel(k, p - PAD + bob, x, off);
    for (let c = 0; c < 20 && j >= 0; c++) {
        const line = 50 + wave[((j + 1) % 180) + c] / 160, b = j - 39 + 2 * c;
        for (let y = 0; y < 16; y++) for (let i = 0; i < 16; i++) {
            if (!stripBit(b + (i >> 3), y, i & 7)) continue;
            const p = line + y - bob + PAD;
            if (p >= PAD + 9 && p < H) px[p * W + SX + 16 * c + i] = INK;
        }
    }
    return px;
}

// --- the cart ----------------------------------------------------------------
async function boot() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile("docs/demo-noextra.wasm");
    const env = { memory, ...rom, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
    for (const k of Object.keys(machine)) if (k.startsWith("hwRam") || k.startsWith("hwRomRam")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}
function physical(memory, machine) {
    const pfb = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), RW * H);
    const px = new Uint32Array(W * H);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) px[y * W + x] = pfb[y * RW + 2 * x];
    return px;
}
async function shot(px, path) {
    const rgb = Buffer.alloc(W * H * 3);
    for (let i = 0; i < W * H; i++) { rgb[3 * i] = px[i] & 255; rgb[3 * i + 1] = (px[i] >> 8) & 255; rgb[3 * i + 2] = (px[i] >> 16) & 255; }
    await writeFile(path, Buffer.concat([Buffer.from(`P6\n${W} ${H}\n255\n`), rgb]));
}

await mkdir(outdir, { recursive: true });
const { memory, machine, demo } = await boot();
const songs = [], rampSet = new Set(ramp.map(rgba));
let bad = 0, checked = 0, badBand = 0, extraPlanes = 0;
for (let f = 0; f < FRAMES; f++) {
    machine.hwClear();
    demo.frame(20);
    if (demo.pollSongRequest()) {
        const name = new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
        songs.push(name);
    }
    if (demo.isPlaneEnabled(0)) machine.hwRenderPlane(0);
    for (let p = 1; p < 4; p++) if (demo.isPlaneEnabled(p)) extraPlanes++; // ONE plane, as the cart says
    if (f % EVERY && f !== 994 && f !== 1564) continue;
    const got = physical(memory, machine);
    const want = f < MAIN ? introFrame(f) : mainFrame(f - MAIN);
    checked++;
    let diff = 0, first = -1;
    for (let i = 0; i < got.length; i++) if (got[i] !== want[i]) { diff++; if (first < 0) first = i; }
    if (diff) {
        if (bad < 4) console.log(`  FAIL frame ${f}: ${diff} px differ, first at (${first % W}, ${(first / W) | 0}): ${got[first].toString(16)} vs model ${want[first].toString(16)}`);
        if (bad === 0) { await shot(got, `${outdir}/fail-${f}.ppm`); await shot(want, `${outdir}/fail-${f}-model.ppm`); }
        bad++;
    }
    if (f >= MAIN) { // a band line holds ramp colours and the ink, nothing else
        const k = f - MAIN, bob = k ? bobAt(k - 1) : 0;
        for (let p = PAD + 78 - bob; p < PAD + 224 - bob; p++)
            for (let x = 0; x < W; x++) if (!rampSet.has(got[p * W + x]) && got[p * W + x] !== INK) { badBand++; break; }
    }
    if (f === 600 || f === 994 || f === 1564) await shot(got, `${outdir}/noextra-${f}.ppm`);
}
console.log(`  frames: ${checked - bad}/${checked} identical to the model built from the rip`);
console.log(`  music: ${songs.join(", ") || "(none)"}`);
if (broke) {
    console.log(bad ? `noextra: PASS (--break ${broke} caught: ${bad} frames differ)` : `noextra: FAILED — --break ${broke} was not caught`);
    process.exit(bad ? 0 : 1);
}
const errors = [];
if (bad) errors.push(`${bad} frames differ from the model`);
if (extraPlanes) errors.push(`a second plane was enabled on ${extraPlanes} frame-planes`);
if (badBand) errors.push(`${badBand} band lines hold a colour that is not a raster's`);
if (JSON.stringify(songs) !== JSON.stringify(["mega4_disk_mag.sndh"])) errors.push(`music requests ${JSON.stringify(songs)}`);
if (machine.hwRamAllocFailures()) errors.push(`${machine.hwRamAllocFailures()} zg.mem allocation(s) refused`);
console.log(errors.length ? `noextra: FAILED — ${errors.join("; ")}` : "noextra: all pass");
process.exit(errors.length ? 1 : 0);
