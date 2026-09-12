// The ROM's BOUNDARY CONTRACT: a caller's bug must not become the ROM's bug.
//
// rom.wasm is called across a module boundary by programs it did not compile —
// including C and Rust ones, which share no type system with it — so every entry
// point takes raw u32/i32 and must survive whatever arrives.
//
// This fills the memory AROUND plane 0's framebuffer with a canary, throws absurd
// coordinates, sizes, colours and handles at the ROM, and fails if any byte of it
// moved or if any call trapped.
//
// WHAT IT ACTUALLY GUARDS, stated honestly because I checked: it is the CLIPPING
// contract, not the casts. Reverting rom_main.zig's saturating narrows to bare
// @intCast leaves this test green — Gui.plot and the blitter already clip, so a
// truncated coordinate was contained anyway. The narrows are still right (an
// out-of-range @intCast is undefined behaviour in ReleaseSmall, where it is
// unchecked, and clamping makes the result defined instead of truncated), but
// they are not what this catches.
//
// What it WOULD catch is the clipping regressing — someone optimising Gui.plot,
// or a new entry point that writes the framebuffer without going through one of
// the clipped primitives. That is a real risk on a surface designed to grow, and
// nothing else in the gate looks for it.
//
// Usage: node apps/rom_abi_check.mjs        (exit 1 on any failure)
import { readFile } from "node:fs/promises";

const PAGES = 112;               // memmap.SHARED_PAGES
const VIDEO = 0x300000;          // HW_VIDEO_BASE
const OFF_VRAM = 0x1100;         // plane framebuffer pool base
const FB_BYTES = 320 * 200;      // one normal plane
const CANARY = 0x5a;

const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
const machine = (await WebAssembly.instantiate(
    await readFile("docs/machine-video.wasm"),
    { env: { memory, hblDispatch: () => {} } })).instance.exports;
const rom = (await WebAssembly.instantiate(
    await readFile("docs/rom.wasm"),
    { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
machine.hwInit();
rom.romReset();

const h = rom.guiOpenPlane(0, 320, 200);
if (!h) { console.log("FAIL  guiOpenPlane returned 0"); process.exit(1); }

// Canary the 256 KB AFTER plane 0's framebuffer — where an out-of-range write
// would land: the other planes, then the VRAM pool.
const guardBase = VIDEO + OFF_VRAM + FB_BYTES;
const guardLen = 256 * 1024;
const guard = new Uint8Array(memory.buffer, guardBase, guardLen);
guard.fill(CANARY);

const hostile = [
    ["guiRect   colour out of range", () => rom.guiRect(h, 0, 0, 10, 10, 99999)],
    ["guiRect   coords past the plane", () => rom.guiRect(h, 70000, 70000, 100, 100, 1)],
    ["guiRect   negative size", () => rom.guiRect(h, 0, 0, -5, -5, 1)],
    ["guiRect   size past the plane", () => rom.guiRect(h, 0, 0, 100000, 100000, 1)],
    ["guiFill   negative size", () => rom.guiFill(h, 0, 0, -1, -1, 1)],
    ["guiFill   size past the plane", () => rom.guiFill(h, 10, 10, 99999, 99999, 2)],
    ["guiFrame  coords past the plane", () => rom.guiFrame(h, -70000, -70000, 99999, 99999, 3)],
    ["guiPlot   far out of range", () => rom.guiPlot(h, 2000000, -2000000, 300)],
    ["guiBox    absurd inset", () => rom.guiBox(h, 0, 0, 50, 50, 9999)],
    ["guiButton absurd border", () => rom.guiButton(h, 0, 0, 40, 12, 0, 0, 5, 999)],
    ["guiText   ink/paper out of range", () => rom.guiText(h, 0, 0, 0, 0, 70000, 70000)],
    ["guiText   text past the plane", () => rom.guiText(h, 0, 0, 60000, 60000, 1, 0)],
    ["handle    never opened", () => rom.guiRect(12345, 0, 0, 10, 10, 1)],
    ["handle    zero", () => rom.guiRect(0, 0, 0, 10, 10, 1)],
    ["desk      screen size negative", () => rom.deskSetScreen(-900000, -900000)],
    ["desk      calls before init", () => { rom.deskRender(); rom.deskKey(65); rom.deskSetFileCount(9999); }],
];

let failures = 0;
for (const [name, fn] of hostile) {
    let note = "ok  ";
    try { fn(); } catch (e) { note = "TRAP"; failures++; }
    const moved = guard.findIndex((b) => b !== CANARY);
    if (moved !== -1) {
        note = "CORRUPT";
        failures++;
        guard.fill(CANARY); // reset so the next case reports independently
    }
    console.log(`  ${note.padEnd(7)} ${name}`);
}

console.log(failures === 0
    ? "\nROM boundary: hostile arguments stay inside the caller's plane ✅"
    : `\nROM boundary: ${failures} FAILURE(S) ❌`);
process.exit(failures === 0 ? 0 : 1);
