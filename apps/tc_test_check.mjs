// TC TEST (cart "tc_test", apps/zig/scenes/tc_test.zig): HW 1.15.0's true-colour plane. Boots the
// cart over the real machine + ROM, presses keys 1..7 (setShadeMode, as the loader and the board's
// glass send digits) and renders plane 0 through the machine (hwClear + hwRenderPlane), as
// apps/scene_hash.mjs does.
//   mode      plane 0 is the only plane enabled and it is FB_MODE 6 (TRUECOLOR_FULL)
//   colours   gamut: all 65,536; plasma and hues > 4,096 (more than any palette mode shows);
//             compare: 565 band (> 4,096) > 256-palette band (<= 256) > ST band (<= 16);
//             ramps: R 32, G 64, B 32, grey 64 steps; dither: more colours than the plain half
//   moving    the plasma's frames differ while the pixel memory (plane buffer + texture, all VRAM
//             below the copper list) hashes the same every frame: only the list moves it
//   still     every other view is the same frame twice; the eight views are eight pictures
//   fade      key 8: a whole fade cycle equals a model of the fade registers over the unchanged
//             pixel memory, and reaches black, white, a flash and the plain picture (tc_test_fade.mjs)
//   pictures  N / P step through local pictures when the cart has any (ZM_TC_ART builds), and
//             do nothing without; the git-tracked cart (HEAD and index) carries NO local picture
//             (tools/tc_art.py's marker), whatever the working tree's cart holds
//   node apps/tc_test_check.mjs [outdir] [cart.wasm]   (outdir: one PPM per view)
//   node apps/tc_test_check.mjs --break   each mutant (mode, colours, pixels, frozen, marker,
//                                         fadeoff, softfade, model) must
//                                         be caught by the checks above
import { readFile, writeFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { OFF_VRAM, REG_FB_COPPER } from "./linebase_model.mjs";
import { fadeChecks } from "./tc_test_fade.mjs";

const PAGES = 128, RW = 800, W = 400, H = 280, REG_FB_MODE = 0x54, MARKER = "TC_TEST_LOCAL_ART";
const CART_PATH = "docs/demo-tc_test.wasm";
const NAMES = ["gamut", "plasma", "compare", "ramps", "hues", "sky", "dither"];
const BROKE = process.argv.includes("--break");
const [outdir, cart = CART_PATH] = process.argv.slice(2).filter((a) => !a.startsWith("--"));

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
    const cartBytes = await readFile(cart);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo, video: machine.hwVideoBase() };
}

// The machine side of one host frame: the cart's frame, then plane 0 into the PFB; the logical
// 400x280 picture (every other raster pixel: mode 6 doubles) as 0xRRGGBB. `hook` runs between.
function frame(m, hook) {
    m.machine.hwClear();
    m.demo.frame(1000 / 60);
    hook?.(m);
    m.machine.hwRenderPlane(0);
    const px = new Uint32Array(m.memory.buffer, m.machine.hwPhysicalPtr(), RW * H);
    return Uint32Array.from({ length: W * H }, (_, i) => px[Math.floor(i / W) * RW + (i % W) * 2] & 0xFFFFFF);
}

const dv = (m) => new DataView(m.memory.buffer);
const md5 = (bytes) => createHash("md5").update(bytes).digest("hex");
const same = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
// The pixel memory: every VRAM byte below plane 0's copper list (allocated after the buffers).
function pixelHash(m) {
    const list = OFF_VRAM + dv(m).getUint16(m.video + REG_FB_COPPER, true) * 16;
    return md5(new Uint8Array(m.memory.buffer, m.video + OFF_VRAM, list - OFF_VRAM));
}
function distinct(img, rows = [0, H], cols = [0, W], brk) {
    const seen = new Set();
    for (let y = rows[0]; y < rows[1]; y++)
        for (let x = cols[0]; x < cols[1]; x++) seen.add(brk === "colours" ? img[y * W + x] & 0xE0E0E0 : img[y * W + x]);
    return seen.size;
}
const want = (errors, ok, msg) => { if (!ok) errors.push(msg); };

function colourChecks(errors, v, img, brk) {
    const n = (r, c, b = brk) => distinct(img, r, c, b);
    if (v === 0) want(errors, n() >= 65536, `gamut: ${n()} colours, not all 65,536`);
    if (v === 1 || v === 4) want(errors, n() > 4096, `${NAMES[v]}: ${n()} colours, not more than 4,096`);
    if (v === 2) {
        const [tc, pal, st] = [0, 1, 2].map((k) => n([k * 92 + 16, k * 92 + 92]));
        want(errors, tc > 4096 && pal <= 256 && pal > st && st <= 16, `compare: bands ${tc} / ${pal} / ${st} colours`);
    }
    if (v === 3) {
        const got = [0, 1, 2, 3].map((k) => n([k * 70 + 14, k * 70 + 70]));
        want(errors, got.join() === "32,64,32,64", `ramps: ${got.join(" / ")} steps, not 32 / 64 / 32 / 64`);
    }
    if (v === 6) {
        const [plain, dith] = [n([16, H], [0, 200]), n([16, H], [200, W])];
        want(errors, dith > plain, `dither: ${dith} colours dithered, ${plain} plain`);
    }
}

// One view: shot, colours, then motion over 8 frames (the hook is a mutant's).
function viewChecks(m, errors, v, brk, shots) {
    m.demo.setShadeMode(v);
    const a = frame(m), h0 = pixelHash(m);
    colourChecks(errors, v, a, brk);
    let saved = null;
    const hook = (mm) => {
        if (brk === "pixels" && v === 1) dv(mm).setUint16(mm.video + OFF_VRAM + 2 * 1000, (dv(mm).getUint16(mm.video + OFF_VRAM + 2 * 1000, true) + 1) & 0xFFFF, true);
        if (brk === "frozen" && v === 1) { const l = list(mm); saved ? l.set(saved) : (saved = l.slice()); }
    };
    let b = a, moved = 0;
    for (let f = 0; f < 8; f++) { const s = frame(m, hook); moved += !same(s, b); b = s; }
    const h1 = pixelHash(m);
    if (v === 1) want(errors, moved === 8 && h0 === h1, `plasma: ${moved}/8 frames moved, pixel memory ${h0 === h1 ? "unchanged" : "CHANGED"}`);
    else want(errors, moved === 0 && h0 === h1, `${NAMES[v]}: ${moved} frames moved (a still view)`);
    if (!brk) console.log(`  key ${v + 1} ${NAMES[v].padEnd(7)} ${distinct(a)} colours, ${moved}/8 frames moved, pixel memory ${h0 === h1 ? "unchanged" : "CHANGED"}`);
    shots.push(a);
    return a;
}
const list = (m) => new Uint8Array(m.memory.buffer, m.video + OFF_VRAM + dv(m).getUint16(m.video + REG_FB_COPPER, true) * 16, 280 * 6 * 4 + 4);

// N / P: with pictures each press shows one and stays still; without, nothing changes.
function pictureChecks(m, errors) {
    m.demo.setShadeMode(0);
    const base = frame(m);
    m.demo.key("n".charCodeAt(0));
    const first = frame(m);
    if (same(first, base)) { console.log("  no local pictures in this cart: N / P do nothing"); return; }
    want(errors, same(frame(m), first), "pictures: a local picture moved");
    m.demo.key("p".charCodeAt(0));
    m.demo.key("n".charCodeAt(0));
    want(errors, same(frame(m), first), "pictures: P then N is not the same picture");
    console.log("  local pictures in this cart (a ZM_TC_ART build): never commit it");
}

// The cart git tracks (HEAD and the index) must not carry a local picture.
async function gitChecks(errors, brk) {
    const blobs = [];
    for (const rev of ["HEAD", ""]) {
        try { blobs.push([rev || "index", execFileSync("git", ["show", `${rev}:${CART_PATH}`], { maxBuffer: 1 << 26, stdio: ["ignore", "pipe", "ignore"] })]); }
        catch { /* not tracked there yet: a new cart */ }
    }
    if (brk === "marker" && !blobs.length) blobs.push(["(the built cart, nothing tracked yet)", await readFile(CART_PATH)]);
    for (let [where, bytes] of blobs) {
        if (brk === "marker") bytes = Buffer.concat([bytes, Buffer.from(MARKER)]);
        want(errors, !bytes.includes(MARKER), `git ${where}: ${CART_PATH} carries local pictures (rebuild with a plain ./build.sh)`);
    }
}

async function run(brk) {
    const m = await boot(), errors = [], shots = [];
    const on = [0, 1, 2, 3].filter((p) => m.demo.isPlaneEnabled(p));
    const mode = dv(m).getUint8(m.video + REG_FB_MODE);
    want(errors, on.join() === "0" && mode === (brk === "mode" ? 5 : 6), `planes ${on.join(",")} enabled, plane 0 mode ${mode} (only plane 0, mode 6, expected)`);
    for (let v = 0; v < NAMES.length; v++) viewChecks(m, errors, v, brk, shots);
    shots.push(fadeChecks(m, errors, brk, shots[4], { frame, pixelHash, dv, want }));
    want(errors, new Set(shots.map((s) => md5(new Uint8Array(s.buffer)))).size === NAMES.length + 1, "keys: the eight views are not eight pictures");
    if (!brk) pictureChecks(m, errors);
    await gitChecks(errors, brk);
    return { errors, shots };
}

async function ppm(path, img) {
    const rgb = Buffer.alloc(W * H * 3);
    img.forEach((c, i) => { rgb[3 * i] = c & 255; rgb[3 * i + 1] = (c >> 8) & 255; rgb[3 * i + 2] = c >> 16; });
    await writeFile(path, Buffer.concat([Buffer.from(`P6\n${W} ${H}\n255\n`), rgb]));
}

if (!BROKE) {
    const { errors, shots } = await run(null);
    if (outdir) for (const [v, s] of shots.entries()) await ppm(`${outdir}/tc_test-${v + 1}-${NAMES[v] ?? "fade"}.ppm`, s);
    for (const e of errors) console.log(`  FAIL ${e}`);
    console.log(errors.length ? `tc_test_check: ${errors.length} FAILED` : "tc_test_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
} else {
    let missed = 0;
    for (const brk of ["mode", "colours", "pixels", "frozen", "marker", "fadeoff", "softfade", "model"]) {
        const { errors } = await run(brk);
        console.log(`  ${errors.length ? "ok  " : "FAIL"} the '${brk}' mutant is caught${errors.length ? `: ${errors[0]}` : ""}`);
        missed += !errors.length;
    }
    console.log(missed ? `tc_test_check --break: ${missed} mutant(s) NOT caught` : "tc_test_check --break: every mutant caught");
    process.exitCode = missed ? 1 : 0;
}
