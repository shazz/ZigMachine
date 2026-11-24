// SID-WIZARD Z's rig (apps/harness/sidwizard_z_check.mjs): the machine + ROM of apps/harness/ports_machine.mjs, the cart
// started from GEM off its data disk (request 3, apps/harness/ports_gem.mjs), C: an image in memory served as the page
// serves it (KOS GEMDOS), the SID on the page's BARD sound side (apps/harness/bard_queue_lib.mjs pageSound: the loader's
// hostBardAttach / bardFrame and the worklet's queue over the real audio modules; its `commands()` are every SID write the
// cart posted). Input as the page sends it: demo.key / keyUp for keys, demo.input for the arrows.
import { readFile } from "node:fs/promises";
import { machine, step, picture } from "./ports_machine.mjs";
import { launchFromGem, serviceQuit } from "./ports_gem.mjs";
import { makeCDrive, makeCFile } from "./scene_hash_disk.mjs";
import { pageSound } from "./bard_queue_lib.mjs";

export const CART = "site/carts/demo-sidwizard_z.wasm", DISK = "site/carts/demo-sidwizard_z.zmd", C_IMAGE = "site/disks/gemdos-c.img";
export const SONG = "apps/ports/sidwizard/data/FLASHBAK.SWM";
export const K = { TAB: 0xe019, ESC: 0xe012, F1: 0xe001, F3: 0xe003, F8: 0xe008, SHIFT: 0xe015, CTRL: 0xe014, DEL: 0xe00c };
export const UP = 0, DOWN = 1, LEFT = 2, RIGHT = 3;
const W = 400, H = 280;

/** The machine with the cart running. brk: "write" (C: refuses every write), "bard" (no BARD queue on this host),
 *  "nodisk" (the drive is emptied as the program starts: no start song). */
export async function rig({ img = null, brk = "", frames = 4000 } = {}) {
    const m = await machine(new Uint8Array(await readFile(DISK)));
    const cimg = img ?? new Uint8Array(await readFile(C_IMAGE));
    m.env.kosDriveRead = makeCDrive(m.memory, cimg);
    const serve = makeCFile(m.memory, cimg);
    m.cWrites = 0;
    m.env.kosFileOp = (req) => { if (brk === "write") return -13; m.cWrites++; return serve(req); };
    m.env.jsConsoleLogWrite = () => {};
    m.env.jsConsoleLogFlush = () => {};
    const sound = await pageSound(m.memory, { frames });
    m.sound = sound;
    m.env.hostBardAttach = brk === "bard" ? () => 0 : sound.hostBardAttach;
    m.launch = await launchFromGem(m, CART, brk === "nodisk");
    return driver(m, cimg);
}

function driver(m, img) {
    const d = {
        m, img,
        frame(n = 1) {
            for (let i = 0; i < n; i++) {
                step(m); m.sound.frame(735);
                try { serviceQuit(m); } catch (e) { if (m.drive.disk) throw e; m.backs = 1; m.demo = { ...m.demo, pollCartRequest: () => 0 }; } // an emptied drive: GEM cannot come back
            }
        },
        /** A key down, held `hold` frames, up (the page's keydown / keyup), then `gap` frames. */
        key(cp, hold = 2, gap = 2) { m.demo.key(cp); d.frame(hold); m.demo.keyUp?.(cp); d.frame(gap); },
        type(s) { for (const c of s) d.key(c.charCodeAt(0)); },
        arrow(dir, hold = 2) { m.demo.input(dir); d.frame(hold); m.demo.inputRelease?.(dir); d.frame(2); },
        /** Modifier held around `fn` (Shift is 0xe015). */
        with(mod, fn) { m.demo.key(mod); d.frame(1); fn(); m.demo.keyUp?.(mod); d.frame(1); },
        picture: () => picture(m),
        quitAsked: () => m.demo.pollCartRequest?.() === 4,
        /** The plane's palette indices as drawn (the physical 400x280 frame as RGBA -> a stable per-pixel hash). */
        rows(y0, y1) { const p = picture(m); return p.px.subarray(y0 * p.W * 4, (y1 + 1) * p.W * 4); },
        /** The SID writes the cart posted so far: [t, addr, value] triples (addr 0xD400.. = a register, 1 = reset). */
        sid() {
            const c = m.sound.commands(), out = [];
            for (let i = 0; i + 3 < c.length; i += 4) out.push([c[i], c[i + 1], c[i + 2]]);
            return out;
        },
        stats: () => m.sound.stats(),
    };
    return d;
}

export { W, H };

/** The pixels of rows y0..y1 that differ between two pictures. */
export function bandDiff(a, b, y0, y1) {
    let n = 0;
    for (let y = y0; y <= y1; y++) for (let x = 0; x < a.W; x++) {
        const i = (y * a.W + x) * 4;
        if (a.px[i] !== b.px[i] || a.px[i + 1] !== b.px[i + 1] || a.px[i + 2] !== b.px[i + 2]) n++;
    }
    return n;
}

/** The C cart (apps/ports/sidwizard) on the same song: F1, 150 frames, then what changes in the next 30 (header rows 0..35, pattern rows 36..235). */
export async function referenceLive() {
    const m = await machine(new Uint8Array(await readFile("site/carts/demo-sidwizard.zmd")));
    m.env.kosDriveRead = () => 0; m.env.kosFileOp = () => -46;
    m.env.jsConsoleLogWrite = () => {}; m.env.jsConsoleLogFlush = () => {};
    await launchFromGem(m, "site/carts/demo-sidwizard.wasm");
    const fr = (n) => { for (let i = 0; i < n; i++) step(m); };
    fr(320); m.demo.key(K.F1); fr(4); m.demo.keyUp(K.F1);
    fr(150);
    const r = { upper: 0, pattern: 0 };
    for (let prev = picture(m), i = 0; i < 20; i++) { // the same 120 frames, a picture every 6
        fr(6);
        const cur = picture(m);
        r.upper += bandDiff(prev, cur, 0, 35);
        r.pattern += bandDiff(prev, cur, 36, 235);
        prev = cur;
    }
    return r;
}
