// The OBJ DEMO cart (apps/zig/scenes/obj_demo.zig) booted the way docs/ loads
// it, for apps/obj_headless.mjs: plane 0's palette indices, frames stepped at a
// fixed dt, keys sent through demo.key() (the cart owns the keyboard).
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const OFF_PAL = 0x0100, REG_FB_STRIDE = 0x34, REG_FB_BASE = 0x44; // memmap.zig
export const W = 320, H = 200;
// The rows the object can reach (radius 1 at DIST 3.2, FOV 150: |dy| <= 69):
// the HUD lines sit outside them, so these rows are the object alone.
export const OBJ_Y0 = 24, OBJ_Y1 = 176;

// onLog gets each Console.log line (the cart logs V/F on every model change).
export async function bootObj(cartPath = "docs/demo-obj.wasm", onLog = () => {}) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"),
        { env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) } })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes,
        { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(cartPath), env = { memory, ...rom };
    let pending = "";
    env.jsConsoleLogWrite = (ptr, len) => { pending += new TextDecoder().decode(new Uint8Array(memory.buffer, ptr, len)); };
    env.jsConsoleLogFlush = () => { onLog(pending); pending = ""; };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => 0;
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    const VB = machine.hwVideoBase();
    const regs = () => new DataView(memory.buffer, VB, OFF_PAL);
    const stride = () => regs().getUint16(REG_FB_STRIDE, true);
    const indices = () => new Uint8Array(memory.buffer, VB + regs().getUint32(REG_FB_BASE, true), stride() * H);
    const pal = () => new Uint32Array(memory.buffer, VB + OFF_PAL, 256);
    const frame = () => { machine.hwClear(); demo.frame(1000 / 60); machine.hwRenderPlane(0); };
    const pixel = (x, y) => indices()[y * stride() + x];
    // A copy of rows y0..y1-1, 320 wide (the stride may be wider).
    const rows = (y0 = 0, y1 = H) => {
        const out = new Uint8Array((y1 - y0) * W), idx = indices(), s = stride();
        for (let y = y0; y < y1; y++) out.set(idx.subarray(y * s, y * s + W), (y - y0) * W);
        return out;
    };
    const hashOf = (bytes) => createHash("sha256").update(bytes).digest("hex").slice(0, 16);
    const hash = (y0 = OBJ_Y0, y1 = OBJ_Y1) => hashOf(rows(y0, y1));
    // Zero rows y0..y1-1 of the plane (what a full clear would leave there).
    const clearRows = (y0 = OBJ_Y0, y1 = OBJ_Y1) => { const s = stride(); indices().fill(0, y0 * s, y1 * s); };
    return { memory, machine, demo, frame, pixel, rows, hash, hashOf, clearRows, indices, pal, stride };
}

export const key = (S, ch) => S.demo.key(typeof ch === "number" ? ch : ch.charCodeAt(0));
