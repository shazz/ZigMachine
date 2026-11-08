// DESK TEST (cart "desk_test", apps/zig/scenes/desk_test.zig): the desk mode (HW 1.17.0). Boots
// the cart over the real machine + ROM and drives it as apps/scene_hash.mjs does.
//   picture  the machine says desk (hwDeskActive) and its 640x480 picture (hwRenderDesk's two
//            halves) is the cart's model pixel for pixel: 256 cells of palette 0, the 1-px
//            checker and frame, alpha 255; inside the text box only ink and colour 0, ink present
//   pool     plane 0's buffer is 64-aligned and wholly inside the VRAM pool, below the PFB
//   still    the next frame is the same picture: the cart draws once
//   toggle   key 2 leaves the desk (RESOLUTION 0, a low-res picture through hwRenderPlane, on the
//            same buffer), key 1 comes back to the same picture
//   clear    in desk mode hwClear only counts FRAME, and hwRenderPlane draws nothing
//   older    with hwDeskAvailable() = 0 (an older board bitstream) the cart never enters it
//   hash     scene_hash.mjs's sample of a desk frame is "desk" + the picture
//   node apps/desk_check.mjs           node apps/desk_check.mjs --break
//   --break  each mutant (a palette entry, the checker, the halves swapped, the frame counted
//            twice, an older machine said yes, the hash without its tag) must be caught
import { readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 128, W = 640, H = 480, HALF = W * (H / 2) * 4, CART = "docs/demo-desk_test.wasm";
const REG_RES = 0x00, REG_FRAME = 0x30, REG_FB_BASE = 0x44, OFF_VRAM = 0x1100, VRAM_BYTES = 1 << 20;
const RES_DESK = 3, INK = 255;
// The two 8x8 text lines (desk_test/picture.zig TITLE, HELP at TEXT_X, TEXT_Y and + 10): their cells.
const TEXT = [{ x0: 168, y0: 454, n: 28 }, { x0: 168, y0: 464, n: 25 }];
const inText = (x, y) => TEXT.some((t) => y >= t.y0 && y < t.y0 + 8 && x >= t.x0 && x < t.x0 + 8 * t.n);
const MUTANTS = ["palette", "checker", "halves", "frame", "older", "tag"];

async function boot(brk, available = 1) {
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
    machine.hwSetDeskAvailable(brk === "older" ? 1 : available); // older: a machine that says yes anyway
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
    return { memory, machine, demo, video: machine.hwVideoBase(), brk };
}

const dv = (m) => new DataView(m.memory.buffer, m.video);
const frameNo = (m) => dv(m).getUint32(REG_FRAME, true);
function frame(m) {
    m.machine.hwClear();
    if (m.brk === "frame" && m.machine.hwDeskActive()) dv(m).setUint32(REG_FRAME, frameNo(m) + 1, true);
    m.demo.frame(1000 / 60);
}
function picture(m) {
    const out = new Uint8Array(2 * HALF);
    for (let half = 0; half < 2; half++) {
        m.machine.hwRenderDesk(m.brk === "halves" ? 1 - half : half);
        out.set(new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), HALF), half * HALF);
    }
    return out;
}

// The cart's picture (desk_test/picture.zig), before its text.
function palette(i) {
    const rgb = [(i & 7) * 36, ((i >> 3) & 7) * 36, (i >> 6) * 85];
    return rgb;
}
function index(x, y, brk) {
    if (x === 0 || y === 0 || x === W - 1 || y === H - 1) return INK;
    if (x < 40 && y < 30) return ((x ^ y) & 1) === (brk === "checker" ? 0 : 1) ? INK : 0;
    return Math.floor(x / 40) + 16 * Math.floor(y / 30);
}
function checkPicture(px, brk) {
    let bad = 0, ink = 0, first = "";
    const ink3 = palette(INK), zero = palette(0);
    for (let y = 0; y < H; y++)
        for (let x = 0; x < W; x++) {
            const o = (y * W + x) * 4, got = [px[o], px[o + 1], px[o + 2]];
            if (px[o + 3] !== 255) { if (!bad++) first = ` first at (${x}, ${y}): alpha ${px[o + 3]}`; continue; }
            if (inText(x, y)) {
                const isInk = got.every((v, k) => v === ink3[k]);
                ink += isInk;
                if (!isInk && !got.every((v, k) => v === zero[k])) bad++;
                continue;
            }
            const want = palette(index(x, y, brk));
            if (brk === "palette" && index(x, y) === 77) want[1] ^= 4;
            if (!got.every((v, k) => v === want[k]) && !bad++) first = ` first at (${x}, ${y}): ${got} want ${want}`;
        }
    return { ok: bad === 0 && ink > 200, why: `${bad} wrong pixels, ${ink} ink pixels in the text${first}` };
}

async function run(brk) {
    const fails = [];
    const check = (ok, what) => ok || fails.push(what);
    const m = await boot(brk);
    frame(m);
    check(m.machine.hwDeskActive() === 1 && dv(m).getUint8(REG_RES) === RES_DESK, "picture: the cart is not in desk mode");
    const first = picture(m), pic = checkPicture(first, brk);
    check(pic.ok, `picture: ${pic.why}`);
    const base = dv(m).getUint32(REG_FB_BASE, true);
    check(base % 64 === 0 && base >= OFF_VRAM && base + W * H <= OFF_VRAM + VRAM_BYTES, `pool: FB_BASE ${base}`);
    const f0 = frameNo(m);
    frame(m);
    check(frameNo(m) === f0 + 1, `clear: FRAME went ${f0} -> ${frameNo(m)}`);
    const pfb = new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), 16).slice();
    m.machine.hwRenderPlane(0);
    check(pfb.every((v, i) => v === new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), 16)[i]), "clear: hwRenderPlane drew in desk mode");
    check(picture(m).every((v, i) => v === first[i]), "still: the picture moved");
    m.demo.setShadeMode(1);
    frame(m);
    check(!m.machine.hwDeskActive() && dv(m).getUint8(REG_RES) === 0, "toggle: key 2 did not leave the desk");
    check(dv(m).getUint32(REG_FB_BASE, true) === base, "toggle: the low-res plane left the desk buffer");
    m.machine.hwRenderPlane(0);
    const raster = new Uint32Array(m.memory.buffer, m.machine.hwPhysicalPtr(), 800 * 280);
    check(new Set(raster).size > 1, "toggle: the low-res picture is blank");
    m.demo.setShadeMode(0);
    frame(m);
    check(m.machine.hwDeskActive() === 1 && picture(m).every((v, i) => v === first[i]), "toggle: key 1 did not bring the same desk back");
    const old = await boot(brk, 0);
    for (let i = 0; i < 3; i++) frame(old);
    check(!old.machine.hwDeskActive(), "older: the cart entered the desk on a machine without it");
    const hash = createHash("sha256").update(brk === "tag" ? "" : "desk").update(first).digest("hex");
    const json = JSON.parse(execFileSync("node", ["apps/scene_hash.mjs", CART, "10", "10"], { encoding: "utf8" }));
    check(json.samples[0].hash === hash, "hash: scene_hash's desk frame is not \"desk\" + the picture");
    return fails;
}

if (process.argv.includes("--break")) {
    let missed = 0;
    for (const brk of MUTANTS) {
        const fails = await run(brk);
        console.log(`${fails.length ? "caught " : "MISSED "} ${brk}${fails.length ? ": " + fails[0] : ""}`);
        missed += !fails.length;
    }
    process.exit(missed ? 1 : 0);
}
const fails = await run(null);
for (const f of fails) console.log(`FAIL ${f}`);
console.log(fails.length ? "desk_check: FAILED" : "desk_check: the desk mode's picture, pool, toggle, clear, older machine and hash all hold");
process.exit(fails.length ? 1 : 0);
