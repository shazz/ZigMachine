// GEMTEST's rig (apps/gemtest_check.mjs, apps/gemtest_shots.mjs): notepad_lib.mjs's machine + ROM, C: a
// copy of docs/gemdos-c.img (KOS GEMDOS), the cart started from GEM off its data disk or straight after a
// desktop that ran in a given mode (aes.screenMode). Input as the page sends it. A component is opened
// deterministically by the cart's gemtestShow(id) (docs/GEMTEST.md), or by its ^key as Matt would.
// The plane comes out 1:1 (low 320x200, medium 640x200, desk 640x480) through palette 0.
import { readFile } from "node:fs/promises";
import { machine, startCart, step, sha } from "./ports_machine.mjs";
import { launchFromGem } from "./ports_gem.mjs";
import { makeCDrive, makeCFile } from "./scene_hash_disk.mjs";

export const CART = "docs/demo-gemtest.wasm", DISK = "docs/demo-gemtest.zmd", C_IMAGE = "docs/gemdos-c.img";
export const K = { CTRL: 0xe014 };
const REG_RES = 0x00, REG_FB_STRIDE = 0x34, REG_FB_BASE = 0x44, OFF_PAL = 0x100;
export const MODES = ["low", "medium", "desk"];
// The components: an id for gemtestShow, the area's ^key (null: no shortcut, an alert or a selector).
export const COMPONENTS = [
    { name: "windows", id: 1, key: "w" }, { name: "menus", id: 2, key: "e" }, { name: "dialogs", id: 3, key: "d" },
    { name: "alerts", id: 4, key: "a" }, { name: "files", id: 5, key: "f" }, { name: "text", id: 6, key: "t" },
    { name: "icons", id: 7, key: "i" }, { name: "modes", id: 8, key: "r" },
    { name: "alert_note1", id: 13 }, { name: "alert_wait2", id: 17 }, { name: "alert_stop3", id: 21 },
    { name: "alert_none1", id: 10 }, { name: "fsel_a", id: 30 }, { name: "fsel_c", id: 31 }, { name: "fsel_c_txt", id: 32 },
];

async function rig(img) {
    const m = await machine(new Uint8Array(await readFile(DISK)));
    m.env.kosDriveRead = makeCDrive(m.memory, img);
    m.env.kosFileOp = makeCFile(m.memory, img);
    m.env.jsConsoleLogWrite = () => {};
    m.env.jsConsoleLogFlush = () => {};
    return m;
}

/** GEM boots over GEMTEST's data disk and runs BOOT.WSM, as on the page. */
export async function fromGem(img) {
    const m = await rig(img);
    m.launch = await launchFromGem(m, CART);
    return driver(m);
}

/** GEMTEST after a desktop in `mode` (0 low, 1 medium, 2 desk; null: none). brk: the check's mutant. */
export async function afterDesktop(img, mode, brk = "") {
    const m = await rig(img);
    m.machine.hwInit();
    if (mode !== null) {
        new DataView(m.memory.buffer, m.machine.hwVideoBase()).setUint8(REG_RES, [0, 2, 3][mode]);
        m.rom.deskInitPlane(0, mode === 0 ? 320 : 640, mode === 2 ? 480 : 200);
    }
    startCart(m, await readFile(CART), CART);
    m.brk = brk;
    return driver(m);
}

function driver(m) {
    const vd = () => new DataView(m.memory.buffer, m.machine.hwVideoBase());
    const d = {
        m,
        frames(n = 1) { for (let i = 0; i < n; i++) step(m); },
        res: () => vd().getUint8(REG_RES),
        mode: () => ({ 0: 0, 2: 1, 3: 2 })[d.res()],
        /** The pointer at (x, y) in the program's coordinates, buttons, then a frame. */
        point(x, y, b = 0) { m.demo.pointer(d.mode() === 0 ? x * 2 : x, y, b); d.frames(1); },
        click(x, y) { d.point(x, y, 0); d.point(x, y, 1); d.point(x, y, 0); d.frames(2); },
        drag(x0, y0, x1, y1) {
            d.point(x0, y0, 0); d.point(x0, y0, 1);
            for (let i = 1; i <= 4; i++) d.point(x0 + ((x1 - x0) * i) / 4 | 0, y0 + ((y1 - y0) * i) / 4 | 0, 1);
            d.point(x1, y1, 0); d.frames(2);
        },
        key(k) { m.demo.key(k); d.frames(1); },
        type(s) { for (const c of s) d.key(c === "\n" ? 13 : c.charCodeAt(0)); },
        ctrl(letter) {
            if (m.brk !== "ctrl") m.demo.key(K.CTRL);
            m.demo.key(letter.charCodeAt(0));
            d.frames(1);
            if (m.brk !== "ctrl") m.demo.keyUp(K.CTRL);
            d.frames(2);
        },
        show(id) { m.demo.gemtestShow(id); d.frames(4); },
        setMode(mode) { m.demo.setShadeMode(mode); d.frames(3); },
        /** wind_get on the program's window `id` (1-based, gui handle 1). */
        win: (id, what) => m.rom.winGet(1, id, what),
        top: () => d.win(1, 10), // wind_get WF_TOP: the top window's id, 0 none
        rect: (id, base) => [0, 1, 2, 3].map((i) => d.win(id, base + i)),
        /** Plane 0: [W, H, indices] in the program's pixels. */
        indices() {
            const v = vd(), r = d.res(), base = v.getUint32(REG_FB_BASE, true);
            const W = r === 0 ? 320 : 640, H = r === 3 ? 480 : 200;
            const stride = r === 3 ? 640 : v.getUint16(REG_FB_STRIDE, true);
            const src = new Uint8Array(m.memory.buffer, m.machine.hwVideoBase() + base, stride * H);
            const out = new Uint8Array(W * H);
            for (let y = 0; y < H; y++) out.set(src.subarray(y * stride, y * stride + W), y * W);
            return { W, H, idx: out };
        },
        plane: () => sha(d.indices().idx),
        /** The plane as RGBA through palette 0, 1:1. */
        picture() {
            const { W, H, idx } = d.indices();
            const pal = new Uint8Array(m.memory.buffer, m.machine.hwVideoBase() + OFF_PAL, 1024);
            const px = new Uint8Array(W * H * 4);
            for (let i = 0; i < idx.length; i++) px.set(pal.subarray(idx[i] * 4, idx[i] * 4 + 3), i * 4), px[i * 4 + 3] = 255;
            return { W, H, px };
        },
        /** The same screen painted whole: the digit that re-enters the mode (a full repaint). */
        repainted() { m.demo.setShadeMode(d.mode()); d.frames(2); return d.plane(); },
    };
    return d;
}
