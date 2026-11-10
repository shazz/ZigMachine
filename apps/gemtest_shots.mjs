// GEMTEST's screenshots: every component (docs/GEMTEST.md) in LOW, MEDIUM and the DESK, one PNG each at
// 1:1 framebuffer pixels (low 320x200, medium 640x200, desk 640x480) plus a copy as the screen shows it
// (low and medium rows doubled, low columns too: 640x400), and an index.html contact sheet putting each
// component's three modes side by side. Headless, deterministic: GEMTEST started after a desktop in the
// mode, the component opened by gemtestShow(id) (or a menu title hovered), a few frames, the plane read.
// "desktop" is GEM's own desktop with A:\ open (its icons: a program cannot draw them).
//   node apps/gemtest_shots.mjs <outdir> [--assets <dir>]
//   --assets  Matt's LOCAL GEM assets page (prototypes/gem_reconstructed/gem_assets): the sheet adds the
//             matching TOS 4 reference images (manifest.json) beside each component. LOCAL ONLY: write
//             <outdir> under prototypes/ (git-ignored); never commit the shots or the assets.
//   ZM_ROM=<rom.wasm>  a scratch ROM (a -Dgem_assets build) instead of docs/rom.wasm; ZM_ENGINE=1 or 2: the
//   desktop in the desk on the engine, flat or TOS 4 3D (deskSetEngine; unset: the ROM's -Dgem_engine default).
import { readFile, writeFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { afterDesktop, COMPONENTS, MODES, C_IMAGE } from "./gemtest_lib.mjs";
import { bootGem } from "./gem_headless.mjs";
import { pickRes, settle } from "./gem_desk_lib.mjs";
import { png } from "./ports_machine.mjs";
import { references } from "./gemtest_refs.mjs";
import { sheetHtml } from "./gemtest_sheet.mjs";

const args = process.argv.slice(2);
const out = args[0];
if (!out || out.startsWith("--")) throw new Error("usage: node apps/gemtest_shots.mjs <outdir> [--assets <dir>]");
const ai = args.indexOf("--assets"), assets = ai >= 0 ? args[ai + 1] : "";
// Menu titles hovered (rom/gem/gui/menu.zig: titles from x 8, each len*8 + 16 wide): Test, Menus, Alerts.
const DROPS = [{ name: "drop_test", at: [60, 4] }, { name: "drop_menus", at: [108, 4] }, { name: "drop_alerts", at: [164, 4] }];

// The screen's look: low doubled both ways, medium rows doubled; the desk as it is.
function onScreen(pic, mode) {
    if (mode === 2) return pic;
    const sx = mode === 0 ? 2 : 1, W = pic.W * sx, H = pic.H * 2, px = new Uint8Array(W * H * 4);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const s = ((y >> 1) * pic.W + ((x / sx) | 0)) * 4;
        px.set(pic.px.subarray(s, s + 4), (y * W + x) * 4);
    }
    return { W, H, px };
}

async function save(name, mode, pic, sheet) {
    const base = `${name}_${MODES[mode]}`;
    await png(pic, `${out}/${base}.png`);
    if (mode !== 2) await png(onScreen(pic, mode), `${out}/${base}_2x.png`);
    (sheet[name] ??= [])[mode] = mode === 2 ? `${base}.png` : `${base}_2x.png`;
}

async function gemtestShots(img, mode, sheet) {
    for (const c of [...COMPONENTS, ...DROPS]) {
        const d = await afterDesktop(img, mode);
        d.frames(3);
        if (c.at) { d.show(2); d.point(...c.at); d.frames(2); } else d.show(c.id);
        if (d.mode() !== mode) console.log(`  ${c.name}: asked ${MODES[mode]}, got ${MODES[d.mode()]}`);
        await save(c.name, mode, d.picture(), sheet);
    }
}

// GEM's desktop in the mode, A:\ open: its icons and its own window, menu bar.
async function desktopShot(mode, sheet) {
    const gem = await bootGem();
    gem.mount([{ name: "BOOT.WSM", type: 0, size: 1234, date: 20261109 }, { name: "README.TXT", type: 1, size: 99, date: 20261109 }]);
    const click = (x, y) => gem.click(new DataView(gem.memory.buffer, gem.machine.hwVideoBase()).getUint8(0) === 0 ? 2 * x : x, y);
    if (mode >= 1) pickRes(gem, click, "medium", 320, 200);
    if (mode === 2) pickRes(gem, click, "desk", 640, 200);
    if (process.env.ZM_ENGINE) gem.rom.deskSetEngine(Number(process.env.ZM_ENGINE)); // as gem_engine_check.mjs
    gem.open(mode === 0 ? 70 : 35, 40); // the drive icon (host x: low res doubles)
    settle(gem, 10);
    const d = { m: { memory: gem.memory, machine: gem.machine } };
    await save("desktop", mode, planeOf(d.m), sheet);
}

// Plane 0 through palette 0, 1:1 (gemtest_lib's picture, for a machine with no driver).
function planeOf(m) {
    const v = new DataView(m.memory.buffer, m.machine.hwVideoBase()), r = v.getUint8(0), base = v.getUint32(0x44, true);
    const W = r === 0 ? 320 : 640, H = r === 3 ? 480 : 200, stride = r === 3 ? 640 : v.getUint16(0x34, true);
    const vb = m.machine.hwVideoBase(), mem = new Uint8Array(m.memory.buffer), px = new Uint8Array(W * H * 4);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const i = mem[vb + base + y * stride + x], o = (y * W + x) * 4;
        px.set(mem.subarray(vb + 0x100 + i * 4, vb + 0x100 + i * 4 + 3), o);
        px[o + 3] = 255;
    }
    return { W, H, px };
}

await mkdir(out, { recursive: true });
const img = new Uint8Array(await readFile(C_IMAGE));
const sheet = {};
for (const mode of [0, 1, 2]) {
    console.log(`gemtest_shots: ${MODES[mode]}`);
    await gemtestShots(img, mode, sheet);
    await desktopShot(mode, sheet);
}
const refs = assets ? await references(assets, out, Object.keys(sheet)) : null;
await writeFile(`${out}/index.html`, sheetHtml(sheet, refs, process.env.ZM_ROM || "docs/rom.wasm"));
console.log(`gemtest_shots: ${Object.keys(sheet).length} components x 3 modes -> ${path.resolve(out)}/index.html`);
