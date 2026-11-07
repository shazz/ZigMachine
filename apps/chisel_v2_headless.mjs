// Headless CHISEL V2 driver (cart 112): boots the sealed machine + demo-chisel_v2.wasm and
// proves each mode draws what its HW 1.11.0 op promises, with a second model written here
// from docs/BLITTER_HW_SPEC.md §4.5-4.7 (not from machine/blitter_tex.zig):
//
//  ROTOZOOM, MODE 7  every AFFINE pixel equals the texel its span names (the list and the
//                    texture read back from cart RAM), outside the mode's two label lines
//  PHOTO             the same three checks with the parrot photo (P) at 128, 256, 64 (T):
//                    its stride and masks are the size's (apps/chisel_v2_play_check.mjs
//                    proves the keys move the picture)
//  TUNNEL           every MAP pixel equals the texel its map entry + offsets name
//  SPRITES           four bobs a frame, all four mirror combinations, COLL_EN on; the
//                    collision bit both set and clear over the run, as the bobs meet
//  FILL              an in-place IFE BLIT; every row of the box equals the model's
//                    per-bit carry fill of the edge pixels; the hollow centre stays 0
//
//   node apps/chisel_v2_headless.mjs [--break pixel|fill]
//     --break pixel  one ROTOZOOM pixel changed before the check: must be caught
//     --break fill   the model fills exclusive instead of inclusive: must be caught
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 128, OFF_PAL = 0x100, REG_FB_BASE = 0x44, OFF_BLIT = 0x80;
const W = 320, H = 200, FRAMES = 20;
const NAMES = ["ROTOZOOM", "MODE 7", "TUNNEL", "SPRITES", "FILL"];
const LABEL = { x1: W, y1: 24 }; // printText at (10, 8) and (10, 16): skip the label's rows
const broke = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : "";
const failures = [];
function check(name, ok, detail = "") {
    if (!ok) failures.push(name);
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`);
}

const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
const mem = () => new DataView(memory.buffer);
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
// this frame's ops: a copy of the block at each hwBlit, the collision byte after it, and
// for an area fill the plane just before it (its edges) and just after
const ops = [];
const hwBlit = () => {
    const VB = machine.hwVideoBase();
    const block = new Uint8Array(memory.buffer.slice(VB + OFF_BLIT, VB + OFF_BLIT + 0x80));
    const fill = block[0] === 1 && (block[2] & 0x30) !== 0;
    const before = fill ? Uint8Array.from(plane()) : null;
    machine.hwBlit();
    ops.push({ block, coll: new Uint8Array(memory.buffer)[VB + 0xE6] & 1, before, after: fill ? Uint8Array.from(plane()) : null });
};
const romBytes = await readFile("docs/rom.wasm");
const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit } })).instance.exports;
machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
const cartBytes = await readFile("docs/demo-chisel_v2.wasm"), env = { memory, ...rom };
for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
env.hwBlit = hwBlit;
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
    if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
machine.hwInit();
demo.boot();
demo.skipBoot();
const VB = machine.hwVideoBase();
const planeBase = () => VB + mem().getUint32(VB + REG_FB_BASE, true);
const plane = () => new Uint8Array(memory.buffer, planeBase(), W * H);

// the block as the op saw it
const R = (b) => {
    const v = new DataView(b.buffer);
    const u16 = (o) => v.getUint16(o - OFF_BLIT, true), u32 = (o) => v.getUint32(o - OFF_BLIT, true);
    return { cmd: b[0], mt: b[1], con: b[2], key: b[6], con2: b[7], abase: u32(0x88), astride: u16(0x8c),
        umask: u16(0x8e), bbase: u32(0x90), bstride: u16(0x94), vmask: u16(0x96), spanBase: u32(0x98),
        spans: u16(0x9c), w: u16(0xa8), h: u16(0xaa), x0: v.getInt16(0xac - OFF_BLIT, true), y0: v.getInt16(0xae - OFF_BLIT, true),
        uoff: u16(0xb0), voff: u16(0xb2) };
};
const texel = (r, U, V) => new Uint8Array(memory.buffer)[r.abase + (V & r.vmask) * r.astride + (U & r.umask)];
const inLabel = (x, y) => x < LABEL.x1 && y < LABEL.y1;

// AFFINE: every pixel of every span is the texel (u >> 16, v >> 16) (MT_B, no key, no clip by masks)
function affineBad(r, p) {
    let bad = 0;
    const m = mem();
    for (let k = 0; k < r.spans; k++) {
        const s = r.spanBase + 24 * k;
        const x0 = m.getInt16(s, true), x1 = m.getInt16(s + 2, true), y = m.getInt16(s + 4, true);
        let u = m.getUint32(s + 8, true), v = m.getUint32(s + 12, true);
        const du = m.getUint32(s + 16, true), dv = m.getUint32(s + 20, true);
        for (let x = x0; x < x1; x++, u = (u + du) >>> 0, v = (v + dv) >>> 0)
            if (x >= 0 && x < W && y >= 0 && y < H && !inLabel(x, y) && p[y * W + x] !== texel(r, u >>> 16, v >>> 16)) bad++;
    }
    return bad;
}
function mapBad(r, p) {
    let bad = 0;
    const m = mem();
    for (let j = 0; j < r.h; j++) for (let i = 0; i < r.w; i++) {
        const x = r.x0 + i, y = r.y0 + j;
        if (x < 0 || x >= W || y < 0 || y >= H || inLabel(x, y)) continue;
        const e = m.getUint16(r.bbase + j * r.bstride + 2 * i, true);
        if (p[y * W + x] !== texel(r, ((e & 255) + r.uoff) & 0xffff, ((e >> 8) + r.voff) & 0xffff)) bad++;
    }
    return bad;
}
// FILL: the plane before the BLIT is the edges; the model fills each row, per bit
function fillModel(edges, r, inclusive) {
    const out = Uint8Array.from(edges);
    for (let y = Math.max(r.y0, 0); y < Math.min(r.y0 + r.h, H); y++) {
        let carry = r.con2 & 0x80 ? 255 : 0;
        for (let x = Math.max(r.x0, 0); x < Math.min(r.x0 + r.w, W); x++) {
            const v = edges[y * W + x];
            out[y * W + x] = inclusive ? carry | v : carry ^ v;
            carry ^= v;
        }
    }
    return out;
}

for (let mode = 0; mode < NAMES.length; mode++) {
    demo.setShadeMode(mode);
    let bad = 0, cmdsOk = true, flips = new Set(), colls = new Set(), fillBad = 0, hollow = true, filled = 0;
    const frames = mode === 3 ? 64 : FRAMES; // SPRITES: a whole cycle of the bobs meeting and parting
    for (let f = 0; f < frames; f++) {
        ops.length = 0;
        demo.frame(16.6);
        const p = plane();
        if (broke === "pixel" && mode === 0 && f === 3) p[150 * W + 200] ^= 1;
        const rs = ops.map((o) => R(o.block));
        if (mode <= 1) {
            const a = rs.filter((r) => r.cmd === 6);
            cmdsOk &&= a.length === 1;
            if (a.length) bad += affineBad(a[0], p);
        } else if (mode === 2) {
            const a = rs.filter((r) => r.cmd === 7);
            cmdsOk &&= a.length === 1;
            if (a.length) bad += mapBad(a[0], p);
        } else if (mode === 3) {
            const b = rs.filter((r) => r.cmd === 1 && (r.con2 & 0x20));
            cmdsOk &&= b.length === 4;
            for (const r of b) flips.add(r.con2 & 0x18);
            colls.add(ops[ops.length - 1]?.coll ?? -1);
        } else {
            const k = rs.findIndex((r) => r.cmd === 1 && (r.con & 0x10) && r.mt === 0xaa);
            cmdsOk &&= k >= 0;
            if (k >= 0) {
                const want = fillModel(ops[k].before, rs[k], broke !== "fill");
                fillBad += want.filter((v, i) => v !== ops[k].after[i]).length;
            }
            filled += p.filter((v) => v !== 0).length;
            hollow &&= p[100 * W + 160] === 0;
        }
    }
    const n = NAMES[mode];
    check(`${n}: the op ran once a frame (the expected COMMAND)`, cmdsOk);
    if (mode <= 2) check(`${n}: every pixel is its texel (${FRAMES} frames, the model here)`, bad === 0, `${bad} px differ`);
    if (mode === 3) {
        check("SPRITES: all four mirror combinations drawn", flips.size === 4, [...flips].join(","));
        check("SPRITES: the collision bit both set and clear over the run", colls.has(1) && colls.has(0), [...colls].join(","));
    }
    if (mode === 4) {
        check("FILL: every row is the model's per-bit carry fill of the edges", fillBad === 0, `${fillBad} px differ`);
        check("FILL: the star is filled (more than its edges)", filled > FRAMES * 3000, `${filled} px`);
        check("FILL: odd-even leaves the centre hollow", hollow);
    }
}
demo.key(112); // P: the photo, at 128; T then goes to 256, then 64
for (const [presses, side] of [[0, 128], [1, 256], [1, 64]]) {
    for (let i = 0; i < presses; i++) demo.key(116);
    for (let mode = 0; mode <= 2; mode++) {
        demo.setShadeMode(mode);
        let bad = 0, sized = true;
        for (let f = 0; f < 5; f++) {
            ops.length = 0;
            demo.frame(16.6);
            const a = ops.map((o) => R(o.block)).filter((r) => r.cmd === (mode <= 1 ? 6 : 7));
            sized &&= a.length === 1 && a[0].astride === side && a[0].umask === side - 1 && a[0].vmask === side - 1;
            if (a.length) bad += (mode <= 1 ? affineBad : mapBad)(a[0], plane());
        }
        check(`${NAMES[mode]} PHOTO ${side}: every pixel is its texel, the texture ${side}x${side}`, bad === 0 && sized, `${bad} px differ`);
    }
}
if (broke) {
    const want = broke === "pixel" ? "ROTOZOOM: every pixel is its texel (20 frames, the model here)"
        : "FILL: every row is the model's per-bit carry fill of the edges";
    const hit = failures.includes(want);
    console.log(hit ? `chisel_v2: PASS (--break ${broke} caught)` : `chisel_v2: FAILED -- --break ${broke} was not caught`);
    process.exit(hit ? 0 : 1);
}
console.log(failures.length ? `chisel_v2: FAILED -- ${failures.join("; ")}` : "chisel_v2: all pass");
process.exit(failures.length ? 1 : 0);
