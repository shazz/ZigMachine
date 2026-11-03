// ZIGGY (cart "ziggy", apps/zig/scenes/ziggy.zig): the cart CPU's showcase. Boots the cart over the real
// machine + ROM (the ROM answers the ZM-X imports with libs/zig/zmx.zig's twins), drives it through
// setShadeMode (0 ROTO, 1 VOXEL, 2 ZM-X off, 3 on, 4..6 texture 64/128/256) and reads plane 0's indices.
//   same      ZM-X on and off give the SAME picture, frame for frame (ROTO at each texture size, VOXEL):
//             the custom ops change the cost, never a pixel
//   full      every pixel of the picture area (rows 0..183) is the mode's own: no HUD paper/ink there,
//             VOXEL's top row is sky and its bottom row ground
//   moves     consecutive frames differ; the texture size changes the picture's pixels
//   hud       rows 186..201 carry the HUD's ink, and its text changes with the mode
//   escape    Escape asks to leave (pollCartRequest -1)
//   node apps/ziggy_check.mjs [--break] [--png <dir>]
//     --break: ZM-X off is compared one frame later, so the four "same" checks must fail (then exit 0)
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 128, W = 320, ROWS = 184, PAPER = 254, INK = 255, SKY0 = 200, REG_FB_BASE = 0x44;
const BROKE = process.argv.includes("--break");
const PNG = process.argv.includes("--png") ? process.argv[process.argv.indexOf("--png") + 1] : null;
let failed = 0, sameFails = 0;
const ok = (c, m) => { console.log(`  ${c ? "ok  " : "FAIL"} ${m}`); if (!c) { failed++; if (m.includes("draw the same picture")) sameFails++; } };

async function bootCart() {
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
    const cartBytes = await readFile("docs/demo-ziggy.wasm");
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => 0; // hostMicros: no clock
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    const plane = () => {
        const base = machine.hwVideoBase();
        const off = new DataView(memory.buffer).getUint32(base + REG_FB_BASE, true);
        return new Uint8Array(memory.buffer, base + off, W * 200).slice();
    };
    return { memory, demo, machine, plane };
}

/** A cart set up by the switches, run `frames` frames; plane 0's indices. */
async function shot(switches, frames) {
    const c = await bootCart();
    for (const s of switches) c.demo.setShadeMode(s);
    for (let f = 0; f < frames; f++) c.demo.frame(16.6);
    return { c, px: c.plane() };
}

const eq = (a, b, n = W * ROWS) => { for (let i = 0; i < n; i++) if (a[i] !== b[i]) return false; return true; };
const hud = (p) => p.subarray(186 * W, 200 * W);

console.log("ziggy");
for (const [name, sw] of [["ROTO 64", [0, 4]], ["ROTO 128", [0, 5]], ["ROTO 256", [0, 6]], ["VOXEL", [1]]]) {
    const on = await shot([...sw, 3], 40);
    const off = await shot([...sw, 2], BROKE ? 41 : 40);
    ok(eq(on.px, off.px), `${name}: ZM-X on and off draw the same picture (frame 40)`);
    const pic = on.px.subarray(0, W * ROWS);
    ok(!pic.includes(PAPER) && !pic.includes(INK), `${name}: the picture area is the mode's own (no HUD index in rows 0..183)`);
    on.c.demo.frame(16.6);
    ok(!eq(on.px, on.c.plane()), `${name}: the next frame moves`);
    ok(hud(on.px).includes(INK), `${name}: the HUD's text is drawn under the picture`);
    if (PNG) await png(on.c, `${PNG}/ziggy_${name.replace(" ", "_").toLowerCase()}.png`);
}
const r64 = (await shot([0, 4], 40)).px, r256 = (await shot([0, 6], 40)).px;
ok(!eq(r64, r256), "the texture size changes the picture's pixels (64 vs 256)");
const vox = (await shot([1], 40)).px;
ok(vox.subarray(0, W).every((v) => v >= SKY0 && v < SKY0 + 48), "VOXEL: the top row is sky");
ok(vox.subarray((ROWS - 1) * W, ROWS * W).every((v) => v < SKY0), "VOXEL: the bottom row is ground");
ok(!eq(hud(r64), hud(vox), 14 * W), "the HUD text changes with the mode");
const q = await bootCart();
q.demo.key(0xE012);
ok(q.demo.pollCartRequest() === -1, "Escape asks to leave");
// exitCode, never process.exit() (apps/mod_sfx_check.mjs: node 24 deadlocks at exit).
if (BROKE) {
    // Caught = every "same picture" check failed (ZM-X off one frame late) and nothing else did.
    const caught = sameFails === 4 && failed === 4;
    console.log(caught ? "ziggy: PASS (--break caught: ZM-X off a frame late differs)" : "ziggy: FAILED -- --break not caught");
    process.exitCode = caught ? 0 : 1;
} else {
    console.log(failed ? `ziggy: FAILED (${failed})` : "ziggy: PASS");
    process.exitCode = failed ? 1 : 0;
}

/** Plane 0 composited by the machine, as an RGB PNG (a look, not a check). */
async function png(c, path) {
    c.machine.hwClear();
    c.machine.hwRenderPlane(0);
    const w = c.machine.hwPhysWidth(), h = c.machine.hwPhysHeight();
    const rgba = new Uint8Array(c.memory.buffer, c.machine.hwPhysicalPtr(), w * h * 4);
    const raw = Buffer.alloc((w * 3 + 1) * h);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) for (let k = 0; k < 3; k++)
        raw[y * (w * 3 + 1) + 1 + x * 3 + k] = rgba[(y * w + x) * 4 + k];
    const crc = (b) => { let c2 = ~0; for (const v of b) { c2 ^= v; for (let k = 0; k < 8; k++) c2 = (c2 >>> 1) ^ (0xEDB88320 & -(c2 & 1)); } return ~c2 >>> 0; };
    const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const cr = Buffer.alloc(4); cr.writeUInt32BE(crc(td)); return Buffer.concat([l, td, cr]); };
    const ih = Buffer.alloc(13); ih.writeUInt32BE(w, 0); ih.writeUInt32BE(h, 4); ih[8] = 8; ih[9] = 2;
    await mkdir(PNG, { recursive: true });
    await writeFile(path, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ih), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}
