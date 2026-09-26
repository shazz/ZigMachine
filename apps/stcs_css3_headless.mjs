// Headless STCS 3RD CSS CONVENTION driver: boots the sealed machine + the cart
// the way sealed-loader.js does and checks the displayed frames against the
// reference model of stcs_3.prg.
//
//   node apps/stcs_css3_headless.mjs [--break noclear|timerb|skip] [outdir]
//
// Host frames run in the host's order (hwClear -> frame -> hwRenderPlane),
// because hwClear is where the global HBL paints the border, 20 ms each (one
// ST VBL). The cart shows the state the border was built from, so host frame
// k shows the state after k-1 VBLs.
//
// apps/stcs_css3_expected.json holds, per sampled VBL count, a sha256 of the
// whole displayed frame as the model renders it (tools/private_tools/
// stcs_css3_assets.py): for each of the 280 physical rows the border's RGB,
// then on the 200 visible rows the 320 pixels' RGB. Covered: the black
// pre-roll, the picture, the star release, the warp, the main loop, the
// scroller, its pauses, and the letters turning round (VBL 4565).
//
// Then the raster checks on every 5th lit frame: every row's two borders
// agree; the grey bands (colour 0 = $222) and the moving bar reach the border
// on their lines; the top border is black. Then keys: Space leaves (as the
// original), Escape leaves; the tune is requested with the picture, not before.
//
// --break noclear: hwClear skipped, the border never painted per line.
// --break timerb:  the plane's HBL dropped, so one palette for all lines.
// --break skip:    one VBL lost at host frame 400.
// Each must fail the frame checks.
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { createHash } from "node:crypto";
import { performance } from "node:perf_hooks";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const HBL_GLOBAL_ID = 5; // machine/sdk/memmap.zig
const CART = "docs/demo-stcs_css3.wasm";

const args = process.argv.slice(2);
const BREAK = args[0] === "--break" ? args[1] : null;
if (BREAK && !["noclear", "timerb", "skip"].includes(BREAK)) throw new Error(`unknown --break ${BREAK}`);
const out = (BREAK ? args[2] : args[0]) || "/tmp/stcs_css3";
await mkdir(out, { recursive: true });

async function boot() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const hbl = (id, p, l, x) => {
        if (BREAK === "timerb" && id !== HBL_GLOBAL_ID) return;
        demo.hblDispatch(id, p, l, x);
    };
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: hbl },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const noop = () => {};
    const cartBytes = await readFile(CART);
    demo = (await WebAssembly.instantiate(cartBytes, {
        env: {
            memory,
            jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop, consoleLogJS: noop,
            hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit,
            hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop,
            hwRamSize: machine.hwRamSize, hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
            hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
            hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
            hwRomRamFree: machine.hwRomRamFree,
            ...rom,
            audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop,
            diskReadBlock: noop, hostAudioStreamStart: noop, hostAudioFeed: noop,
            hostAudioStreamStop: noop,
        },
    })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
    const pfb = () => new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
    let frames = 0;
    const step = (dt = 20) => {
        if (BREAK !== "noclear") machine.hwClear();
        demo.frame(dt);
        machine.hwRenderPlane(0);
        frames++;
    };
    const song = () => demo.pollSongRequest()
        ? new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()))
        : null;
    return { memory, machine, demo, W, H, pfb, step, song, frames: () => frames };
}

const expected = JSON.parse(await readFile("apps/stcs_css3_expected.json", "utf8"));
const S = await boot();
const { W, H } = S;
const X0 = 80, Y0 = 40; // the 320x200 window in the 800x280 raster (x doubled)

function frameHash() {
    const b = S.pfb(), h = createHash("sha256");
    const row = new Uint8Array(3 * 321);
    for (let y = 0; y < H; y++) {
        const i = y * W * 4;
        row[0] = b[i]; row[1] = b[i + 1]; row[2] = b[i + 2];
        if (y < Y0 || y >= Y0 + 200) { h.update(row.subarray(0, 3)); continue; }
        for (let x = 0; x < 320; x++) {
            const j = i + (X0 + 2 * x) * 4;
            row[3 + 3 * x] = b[j]; row[4 + 3 * x] = b[j + 1]; row[5 + 3 * x] = b[j + 2];
        }
        h.update(row);
    }
    return h.digest("hex").slice(0, 16);
}

const px = (x, y) => { const b = S.pfb(), i = (y * W + x) * 4; return (b[i] << 16) | (b[i + 1] << 8) | b[i + 2]; };
const hex = (c) => "#" + c.toString(16).padStart(6, "0");
const GREY = 0x484848; // ST $222: 2 * 255 / 7 = 72
const errors = [];
let greyRows = 0, barRows = 0, frameChecks = 0, songAt = null;

function checkBorders(v) {
    for (let y = 0; y < H; y++) {
        const left = px(0, y), right = px(W - 1, y);
        if (left !== right) errors.push(`VBL ${v} row ${y}: left border ${hex(left)} != right ${hex(right)}`);
        if (y < Y0 && left !== 0) errors.push(`VBL ${v} row ${y}: top border ${hex(left)}, want black`);
        if (y < Y0 || y >= Y0 + 200) continue;
        if (left === GREY) greyRows++;
        else if (left !== 0 && y - Y0 >= 52 && y - Y0 < 170) barRows++; // the bar lies inside the grey
    }
}

const last = Math.max(...Object.keys(expected.frames).map(Number));
for (let v = 0; v <= last; v++) {
    // host frame v+1 shows the state after v VBLs
    S.step(BREAK === "skip" && v === 400 ? 0 : 20);
    const name = S.song();
    if (name !== null && songAt === null) songAt = { v, name };
    const want = expected.frames[String(v)];
    if (want !== undefined) {
        frameChecks++;
        const got = frameHash();
        if (got !== want) errors.push(`VBL ${v}: frame ${got}, model ${want}`);
    }
    if (v > expected.preroll && v % 5 === 0) checkBorders(v);
    if (v === 818 || v === 1200) await shot(`${out}/vbl${String(v).padStart(5, "0")}.ppm`);
}

async function shot(path) {
    const hdr = new TextEncoder().encode(`P6\n${W / 2} ${H}\n255\n`);
    const buf = new Uint8Array(hdr.length + (W / 2) * H * 3);
    buf.set(hdr);
    const b = S.pfb();
    for (let y = 0; y < H; y++)
        for (let x = 0; x < W / 2; x++)
            for (let c = 0; c < 3; c++) buf[hdr.length + (y * (W / 2) + x) * 3 + c] = b[(y * W + x * 2) * 4 + c];
    await writeFile(path, buf);
}

if (greyRows === 0) errors.push("the grey bands never reached the border");
if (barRows === 0) errors.push("the bar never reached the border");
// the music starts with the picture: requested during host frame 25 (VBL 24 -> 25)
if (!songAt || songAt.name !== "thrust.sndh" || songAt.v !== expected.preroll)
    errors.push(`song request ${JSON.stringify(songAt)}, want thrust.sndh with the picture (host frame ${expected.preroll + 1})`);

// cost of a host frame in the main loop
const N = 600;
const t0 = performance.now();
for (let i = 0; i < N; i++) S.step();
const cost = (performance.now() - t0) / N;

// keys: Space leaves (the original's exit), Escape too
for (const [label, cp] of [["Space", 32], ["Escape", 0xE012]]) {
    const K = await boot();
    for (let i = 0; i < 30; i++) K.step();
    if (K.demo.pollCartRequest() !== 0) errors.push(`${label}: a cart request before any key`);
    K.demo.key(cp);
    if (K.demo.pollCartRequest() !== -1) errors.push(`${label} does not leave to the menu`);
}

const unique = [...new Set(errors)];
if (BREAK) {
    if (unique.length === 0) { console.log(`stcs_css3: FAIL, --break ${BREAK} was NOT caught`); process.exit(1); }
    console.log(`stcs_css3: PASS (--break ${BREAK} caught: ${unique.length} errors, first: ${unique[0]})`);
    process.exit(0);
}
if (unique.length) {
    console.log("stcs_css3: WRONG");
    for (const e of unique.slice(0, 12)) console.log("  " + e);
    process.exit(1);
}
console.log(`stcs_css3: ${frameChecks} frames = the model's, borders included (VBL 0..${last}); grey band on ${greyRows} and bar on ${barRows} border rows, both borders equal on every row; thrust.sndh requested with the picture; Space and Escape leave; ${cost.toFixed(3)} ms/host frame (clear + cart + plane); shots in ${out}`);
