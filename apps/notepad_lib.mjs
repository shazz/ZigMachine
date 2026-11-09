// NOTEPAD's harness rig (apps/notepad_check.mjs): the machine + ROM of apps/ports_machine.mjs, C: an
// image in memory served as the page serves it (kosDriveRead, kosFileOp through KFS), the cart started
// from GEM (apps/ports_gem.mjs, request 3 off its data disk) or straight after a desktop that ran in a
// given mode (the ROM keeps the desktop's screen: aes.screenMode). Input as the page sends it: the
// pointer in host coordinates (low res x doubled), keys through demo.key / keyUp, arrows demo.input.
import { readFile } from "node:fs/promises";
import { machine, startCart, step, picture, sha } from "./ports_machine.mjs";
import { launchFromGem } from "./ports_gem.mjs";
import { makeCDrive, makeCFile } from "./scene_hash_disk.mjs";

export const CART = "docs/demo-notepad.wasm", DISK = "docs/demo-notepad.zmd", C_IMAGE = "docs/gemdos-c.img";
export const K = { CTRL: 0xe014, SHIFT: 0xe015, DEL: 0xe00c, ESC: 0xe012, HOME: 0xe01a, END: 0xe01b, PGUP: 0xe01c, PGDN: 0xe01d };
const REG_RES = 0x00, REG_FB_BASE = 0x44, REG_FB_STRIDE = 0x34;

// The C: image's host: reads and writes, `brk` sabotaging them (write: every write refused; bytes: a byte
// of the data changed on its way).
function cHost(m, img, brk) {
    const serve = makeCFile(m.memory, img);
    const op = (req) => {
        if (brk === "write") return -13;
        const w = new Uint32Array(m.memory.buffer, req, 12);
        if (brk === "bytes" && w[5] > 8) new Uint8Array(m.memory.buffer, w[6], w[5])[4] ^= 0x20;
        op.calls++;
        return serve(req);
    };
    op.calls = 0;
    return op;
}

async function rig(img, brk) {
    const m = await machine(new Uint8Array(await readFile(DISK)));
    m.env.kosDriveRead = makeCDrive(m.memory, img);
    m.env.kosFileOp = cHost(m, img, brk);
    m.env.jsConsoleLogWrite = () => {}; // a Zig cart's log (the page's console): nothing here
    m.env.jsConsoleLogFlush = () => {};
    m.brk = brk;
    return m;
}

/** GEM boots over Notepad's data disk and runs BOOT.WSM, as on the page. */
export async function fromGem(img, brk = "") {
    const m = await rig(img, brk);
    m.launch = await launchFromGem(m, CART);
    return driver(m);
}

/** Notepad started after a desktop ran in `mode` (0 low, 1 medium, 2 desk; null: no desktop). */
export async function afterDesktop(img, mode, brk = "") {
    const m = await rig(img, brk);
    m.machine.hwInit();
    if (mode !== null) {
        const dv = new DataView(m.memory.buffer, m.machine.hwVideoBase());
        dv.setUint8(REG_RES, [0, 2, 3][mode]);
        m.rom.deskInitPlane(0, mode === 0 ? 320 : 640, mode === 2 ? 480 : 200);
    }
    startCart(m, await readFile(CART), CART);
    return driver(m);
}

function driver(m) {
    const d = {
        m,
        frames(n = 1) { for (let i = 0; i < n; i++) step(m); },
        res: () => new DataView(m.memory.buffer, m.machine.hwVideoBase()).getUint8(REG_RES),
        low: () => d.res() === 0,
        /** The pointer at (x, y) in the program's coordinates, buttons, then a frame. */
        point(x, y, b = 0) { m.demo.pointer(d.low() ? x * 2 : x, y, b); d.frames(1); },
        click(x, y) { d.point(x, y, 0); d.point(x, y, 1); d.point(x, y, 0); d.frames(2); },
        drag(x0, y0, x1, y1) {
            d.point(x0, y0, 0); d.point(x0, y0, 1);
            for (let i = 1; i <= 4; i++) d.point(x0 + ((x1 - x0) * i) / 4 | 0, y0 + ((y1 - y0) * i) / 4 | 0, 1);
            d.point(x1, y1, 0); d.frames(2);
        },
        type(s) { for (const c of s) { m.demo.key(c === "\n" ? 13 : c.charCodeAt(0)); d.frames(1); } },
        key(k) { m.demo.key(k); d.frames(1); },
        arrow(dir, n = 1) { for (let i = 0; i < n; i++) { m.demo.input(dir); d.frames(1); } },
        ctrl(letter) {
            if (m.brk !== "ctrl") m.demo.key(K.CTRL);
            m.demo.key(letter.charCodeAt(0));
            d.frames(1);
            if (m.brk !== "ctrl") m.demo.keyUp(K.CTRL);
            d.frames(2);
        },
        /** wind_get through the ROM: the program's one window (gui handle 1, window 1). */
        win(what) { return m.rom.winGet(1, 1, what); },
        work: () => [0, 1, 2, 3].map((i) => d.win(i)),
        /** Plane 0's bytes (what the program drew), a hash. */
        plane() {
            const v = new DataView(m.memory.buffer, m.machine.hwVideoBase());
            const r = d.res(), base = v.getUint32(REG_FB_BASE, true);
            const stride = r === 3 ? 640 : v.getUint16(REG_FB_STRIDE, true);
            const h = r === 3 ? 480 : 200;
            return sha(new Uint8Array(m.memory.buffer, m.machine.hwVideoBase() + base, stride * h));
        },
        /** The same screen painted whole: the digit that re-enters the mode (a full repaint). */
        repainted() {
            const mode = [0, 0, 1, 2][d.res()];
            m.demo.setShadeMode(mode);
            d.frames(2);
            return d.plane();
        },
        picture: () => picture(m),
    };
    return d;
}
