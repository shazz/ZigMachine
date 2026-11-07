// ZIGGY (cart "ziggy", apps/zig/scenes/ziggy.zig): the cart CPU's showcase. Boots the cart over the real
// machine + ROM (the ROM answers the ZM-X imports with libs/zig/zmx.zig's twins), drives it through
// setShadeMode (0 ROTO, 1 VOXEL, 2 ZM-X off, 3 on, 4..6 texture 64/128/256, 7 generated, 8 photo) or
// key() (P, + / -, Escape) and reads plane 0's indices.
//   same      ZM-X on and off give the SAME picture, frame for frame (ROTO at each texture size, VOXEL):
//             the custom ops change the cost, never a pixel
//   full      every pixel of the picture area (rows 0..183) is the mode's own: no HUD paper/ink there,
//             VOXEL's top row is sky and its bottom row ground
//   moves     consecutive frames differ; the texture size changes the picture's pixels
//   hud       rows 184..199 carry the HUD's ink (the 8 px font fits the plane), its text follows the mode
//   spin      + turns ROTO faster: the same frame with + pressed is another picture; - back is the same
//   photo     P (or switch 8) swaps ROTO's texture for the parrot photo at 64 / 128 / 256: ZM-X on and
//             off still agree, only the photo's indices (56..247) are drawn, the picture is not the
//             generated one, the palette holds the photo's colours, the HUD says PHOTO
//   escape    Escape asks to leave (pollCartRequest -1)
//   node apps/ziggy_check.mjs [--break | --break photo] [--png <dir>]
//     --break: ZM-X off is compared one frame later, so the seven "same" checks must fail (then exit 0)
//     --break photo: the swap is never asked for (no P, no 8), so every photo check must fail
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 128, W = 320, ROWS = 184, PAPER = 254, INK = 255, SKY0 = 200, REG_FB_BASE = 0x44;
const arg = (k) => (process.argv.includes(k) ? process.argv[process.argv.indexOf(k) + 1] ?? "" : null);
const BREAK_PHOTO = arg("--break") === "photo", BROKE = arg("--break") !== null && !BREAK_PHOTO;
const PNG = arg("--png");
const P_KEY = 112, PHOTO = 8, PHOTO_LO = 56, PHOTO_HI = 247, OFF_PAL = 0x100;
let failed = 0, sameFails = 0, photoFails = 0;
const ok = (c, m) => {
    console.log(`  ${c ? "ok  " : "FAIL"} ${m}`);
    if (!c) { failed++; if (m.includes("draw the same picture")) sameFails++; if (m.startsWith("PHOTO")) photoFails++; }
};

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

/** A cart set up by the switches (then the keys), run `frames` frames; plane 0's indices.
 *  --break photo drops the photo switch and P: the swap is never asked for. */
async function shot(switches, frames, keys = []) {
    const c = await bootCart();
    for (const s of switches) if (!(BREAK_PHOTO && s === PHOTO)) c.demo.setShadeMode(s);
    for (const k of keys) if (!(BREAK_PHOTO && k === P_KEY)) c.demo.key(k);
    for (let f = 0; f < frames; f++) c.demo.frame(16.6);
    return { c, px: c.plane() };
}

const eq = (a, b, n = W * ROWS) => { for (let i = 0; i < n; i++) if (a[i] !== b[i]) return false; return true; };
const hud = (p) => p.subarray(184 * W, 200 * W);

console.log("ziggy");
const LOOKS = [["ROTO 64", [0, 4]], ["ROTO 128", [0, 5]], ["ROTO 256", [0, 6]], ["VOXEL", [1]],
    ["ROTO PHOTO 64", [0, 4, PHOTO]], ["ROTO PHOTO 128", [0, 5, PHOTO]], ["ROTO PHOTO 256", [0, 6, PHOTO]]];
for (const [name, sw] of LOOKS) {
    const on = await shot([...sw, 3], 40);
    const off = await shot([...sw, 2], BROKE ? 41 : 40);
    ok(eq(on.px, off.px), `${name}: ZM-X on and off draw the same picture (frame 40)`);
    const pic = on.px.subarray(0, W * ROWS);
    ok(!pic.includes(PAPER) && !pic.includes(INK), `${name}: the picture area is the mode's own (no HUD index in rows 0..183)`);
    on.c.demo.frame(16.6);
    ok(!eq(on.px, on.c.plane()), `${name}: the next frame moves`);
    ok(hud(on.px).includes(INK), `${name}: the HUD's text is drawn under the picture`);
    if (PNG) await png(on.c, `${PNG}/ziggy_${name.replaceAll(" ", "_").toLowerCase()}.png`);
}
const r64 = (await shot([0, 4], 40)).px, r256 = (await shot([0, 6], 40)).px;
ok(!eq(r64, r256), "the texture size changes the picture's pixels (64 vs 256)");
const vox = (await shot([1], 40)).px;
ok(vox.subarray(0, W).every((v) => v >= SKY0 && v < SKY0 + 48), "VOXEL: the top row is sky");
ok(vox.subarray((ROWS - 1) * W, ROWS * W).every((v) => v < SKY0), "VOXEL: the bottom row is ground");
ok(!eq(hud(r64), hud(vox), 16 * W), "the HUD text changes with the mode");
{ // spin: + then - is the default speed again, + alone is a different rotation
    const base = await bootCart(), fast = await bootCart(), back = await bootCart();
    fast.demo.key(43); back.demo.key(43); back.demo.key(45);
    for (const c of [base, fast, back]) for (let f = 0; f < 30; f++) c.demo.frame(16.6);
    ok(!eq(base.plane(), fast.plane()), "ROTO: + turns it faster (frame 30 differs)");
    ok(eq(base.plane(), back.plane(), W * 200), "ROTO: + then - is the default speed again (frame 30 identical)");
}
{ // photo: P at each size is the photo (its indices, its palette), not the generated texture
    const pal = new Uint8Array(await readFile("apps/zig/assets/screens/parrot/parrot_pal.bin"));
    for (const [side, size] of [[64, 4], [128, 5], [256, 6]]) {
        const gen = (await shot([0, size], 40)).px, p = await shot([0, size], 40, [P_KEY]);
        const pic = p.px.subarray(0, W * ROWS);
        ok(!eq(p.px, gen) && pic.every((v) => v >= PHOTO_LO && v <= PHOTO_HI), `PHOTO ${side}: P draws the photo (its indices 56..247 only, not the generated picture)`);
        ok(eq(p.px, (await shot([0, size, PHOTO], 40)).px), `PHOTO ${side}: P and switch 8 give the same picture`);
        const rgba = new Uint8Array(p.c.memory.buffer, p.c.machine.hwVideoBase() + OFF_PAL, 256 * 4);
        const used = [...new Set(pic)];
        ok(used.length > 64 && used.every((v) => [0, 1, 2].every((k) => rgba[v * 4 + k] === pal[(v - PHOTO_LO) * 3 + k])), `PHOTO ${side}: the palette holds the photo's colours (${used.length} used)`);
        ok(!eq(hud(p.px), hud(gen), 16 * W), `PHOTO ${side}: the HUD names the texture (PHOTO, not GEN)`);
        if (PNG) await png(p.c, `${PNG}/ziggy_photo_${side}.png`);
    }
}
const q = await bootCart();
q.demo.key(0xE012);
ok(q.demo.pollCartRequest() === -1, "Escape asks to leave");
// exitCode, never process.exit() (apps/mod_sfx_check.mjs: node 24 deadlocks at exit).
if (BROKE) {
    // Caught = every "same picture" check failed (ZM-X off one frame late) and nothing else did.
    const caught = sameFails === 7 && failed === 7;
    console.log(caught ? "ziggy: PASS (--break caught: ZM-X off a frame late differs)" : "ziggy: FAILED -- --break not caught");
    process.exitCode = caught ? 0 : 1;
} else if (BREAK_PHOTO) {
    // Caught = the photo, palette and HUD checks failed at all three sizes (9) and nothing else did.
    const caught = photoFails === 9 && failed === 9;
    console.log(caught ? "ziggy: PASS (--break photo caught: no swap, no photo)" : `ziggy: FAILED -- --break photo not caught (${photoFails}/${failed})`);
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
