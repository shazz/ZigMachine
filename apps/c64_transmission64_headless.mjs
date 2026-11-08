// TRANSMISSION64 (cart "c64_transmission64", apps/zig/scenes/c64_transmission64.zig): Padua's
// C64 invitation to Transmission64 2021. Boots the committed cart over the real machine + ROM,
// runs it frame by frame (60 Hz machine frames, a C64 frame every 6/5) and composites plane 0
// through the machine (hwClear runs the border raster) at checkpoints.
//   setup    plane 0 alone, FB_MODE 4 (the overscan plane of 1988; no border opens here)
//   vice     at C64 frames across the show (PINS) the picture is VICE's, pixel for pixel: the
//            SHA-256 of VICE 3.9 x64sc's 384x272 view in colodore indices
//            (tools/c64/pin_frames.py over tools/c64/capture.py's shots, C64_ENTRY=2B7B),
//            physical rows 5..276, columns 8..391
//   escape   Escape asks to leave (pollCartRequest -1)
//   node apps/c64_transmission64_headless.mjs [outdir]       (outdir: a PPM per checkpoint)
//   node apps/c64_transmission64_headless.mjs --break pixel  the view one pixel to the right must fail
import { readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 128, RW = 800, W = 384, H = 272, X0 = 8, Y0 = 5, REG_FB_MODE = 0x54;
const CART = "docs/demo-c64_transmission64.wasm";
const BRK = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
const outdir = process.argv.slice(2).find((a, i, all) => !a.startsWith("--") && all[i - 1] !== "--break");
const COLODORE = [0x000000, 0xFFFFFF, 0x96282E, 0x5BD6CE, 0x9F2DAD, 0x41B936, 0x2724C4, 0xEFF347,
    0x9F4815, 0x5E3500, 0xDA5F66, 0x474747, 0x787878, 0x91FF84, 0x6864FF, 0xAEAEAE];
// C64 frame (VICE's raster clock: frame 1 holds part 1's first IRQ, $2B7B) -> SHA-256 of VICE's view
const PINS = {
    1: "df41dbcb88720d0430e8fd62b9ccfbe75971dc712d2775ebacd35bcd32724c18", // the boot screen as part 1 starts
    101: "22193542e3d57c4f9bc98590a13166227dfe6555c326a3a63df297cfd8b6582c", // rings over the boot screen
    602: "6fec527ec4815be8f6138fe479fca32da04314d85936b5cffc677ceff8c17a39", // the rings late in part 1
    800: "03c487704461e181f143ccf88f28df56bc40c19a60de82a52569ca52c3c45225", // the first wipe's bars
    1500: "6954dc092d67905e61cc0ac08fe8a28bbad4bc4687f29803b6e2c83595dd625f", // the logo, arc coloured, radio rings
    2500: "a6f88978edff6cede669f9e2d4f66cf1aa3784f5c666d7e3c19289a74174f34b", // the logo later (music flashes)
    3006: "94e95b0122a7de8132ac020063cf4cbe05651a450be023d1fd38afc78471aa2a", // the arc fading out
    3060: "47177c15d6ea2a79a007d90b72fd7bc933877e5c612f8ffe3c2f56885e283901", // the second wipe's bars
    3500: "cbc853420473c5ecd22ca58f39c6962ca2ce17992975076d833e011c54dae442", // the dots, first shape
    3800: "28e3c7697cceb7540841cde1e5d3692c0f8d73811e425a9ff3943f7505aa5097", // the info panel rolling in
    4050: "0c0b4e044775eb0941326d3d5aba4ba82e67c7eb3d235ed6004ad4646eb62801", // the panel rolling out
    4200: "00c6052c26498a57afc5a298ebbece09a8fc635d6e0f48be3cb9996c4c6400cd", // the dots, second shape
    5000: "3975eba1f594ac096cc046ecf37a432245c46f96a1538ee0f5c03c5cfe13d50d", // the panel, second time
};

async function boot() {
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
    const cartBytes = await readFile(CART);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo, video: machine.hwVideoBase(), frame: 0 };
}

// Run to C64 frame n (machine frame ceil(6n/5)), composite, return VICE's view as C64 indices.
function at(m, n) {
    const target = Math.ceil((6 * n) / 5);
    while (m.frame < target) { m.machine.hwClear(); m.demo.frame(1000 / 60); m.frame++; }
    m.machine.hwClear();
    for (let p = 0; p < 4; p++) if (m.demo.isPlaneEnabled(p)) m.machine.hwRenderPlane(p);
    const px = new Uint32Array(m.memory.buffer, m.machine.hwPhysicalPtr(), RW * 280);
    const shift = BRK === "pixel" ? 1 : 0;
    const lut = new Map(COLODORE.map((c, i) => [((c & 255) << 16) | (c & 0xFF00) | (c >> 16), i]));
    return Uint8Array.from({ length: W * H }, (_, i) => {
        const v = px[(Y0 + Math.floor(i / W)) * RW + (X0 + (i % W) + shift) * 2] & 0xFFFFFF;
        return lut.has(v) ? lut.get(v) : 255;
    });
}

async function ppm(name, img) {
    if (!outdir) return;
    const body = Buffer.alloc(W * H * 3);
    img.forEach((c, i) => { const v = COLODORE[c & 15]; body[i * 3] = v >> 16; body[i * 3 + 1] = (v >> 8) & 255; body[i * 3 + 2] = v & 255; });
    await writeFile(`${outdir}/c64_transmission64_${name}.ppm`, Buffer.concat([Buffer.from(`P6 ${W} ${H} 255\n`), body]));
}

const errors = [];
const want = (ok, msg) => { if (!ok) errors.push(msg); };
const m = await boot();

// setup
m.demo.frame(1000 / 60); m.frame++;
const dv = new DataView(m.memory.buffer);
want(m.demo.isPlaneEnabled(0), "setup: plane 0 not enabled");
for (let p = 1; p < 4; p++) want(!m.demo.isPlaneEnabled(p), `setup: plane ${p} enabled`);
want(dv.getUint8(m.video + REG_FB_MODE) === 4, `setup: plane 0 FB_MODE ${dv.getUint8(m.video + REG_FB_MODE)}, not 4 (overscan)`);

// vice
let same = 0;
for (const [n, sha] of Object.entries(PINS).map(([k, v]) => [Number(k), v])) {
    const img = at(m, n);
    await ppm(n, img);
    const got = createHash("sha256").update(img).digest("hex");
    const off = img.reduce((k, c) => k + (c === 255), 0);
    want(got === sha, `vice: C64 frame ${n} differs from VICE's (${off} pixels off the palette)`);
    same += got === sha;
}
console.log(`  vice: ${same}/${Object.keys(PINS).length} C64 frames pixel-identical to VICE 3.9`);

// escape
m.demo.key(0xE012);
want(m.demo.pollCartRequest() === -1, "escape: Escape did not ask to leave");

// exitCode, never process.exit() (node 24 deadlocks at exit: apps/mod_sfx_check.mjs).
if (BRK) {
    const hit = errors.find((e) => e.startsWith("vice:"));
    console.log(hit ? `c64_transmission64: PASS (--break ${BRK} caught: ${hit})` : `c64_transmission64: FAILED -- --break ${BRK} not caught`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `c64_transmission64: FAILED -- ${errors.join("; ")}` : "c64_transmission64: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
