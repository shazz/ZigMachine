// Test the sealed RAM instructions (hwSetCartHigh / hwRam*) against the host-side
// measurement they are fed from, and check every built cart fits its window.
//
// The bug this guards: a cart's static data + stack ran past CART_RAM_TOP into the
// video region, which does not trap — it silently corrupts VRAM, and the machine
// died later somewhere else entirely. hwRamFree() is how a cart asks instead of
// guessing, so the instruction has to be right, including when it does not know.
//
// Usage: node apps/ram_check.mjs      (exit 1 on any failure)
import { readFile } from "node:fs/promises";
import { cartRam, CART_RAM_BASE, CART_RAM_TOP, ROM_RAM_BASE, ROM_RAM_TOP } from "../docs/wasm_hiwater.js";

const PAGES = 112; // memmap.SHARED_PAGES
let failures = 0;

function check(what, got, want) {
    const ok = got === want;
    if (!ok) failures++;
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${what}: got ${got}, want ${want}`);
}

async function machineExports() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const imports = { env: { memory, hblDispatch: () => {} } };
    const m = await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), imports);
    return m.instance.exports;
}

const hw = await machineExports();

console.log("the map the instructions report");
check("hwRamBase", hw.hwRamBase(), CART_RAM_BASE);
check("hwRamTop", hw.hwRamTop(), CART_RAM_TOP);
check("hwRamSize", hw.hwRamSize(), CART_RAM_TOP - CART_RAM_BASE);

console.log("undeclared: reports 0, never a number a cart could size a buffer from");
check("hwRamFree before any declaration", hw.hwRamFree(), 0);
check("hwRamUsed before any declaration", hw.hwRamUsed(), 0);

console.log("a declared cart");
const HIGH = CART_RAM_BASE + 512 * 1024;
hw.hwSetCartHigh(HIGH);
check("hwRamUsed", hw.hwRamUsed(), 512 * 1024);
check("hwRamFree", hw.hwRamFree(), CART_RAM_TOP - HIGH);

console.log("the declaration survives hwInit (it describes the cart, not the video)");
hw.hwInit();
check("hwRamFree after hwInit", hw.hwRamFree(), CART_RAM_TOP - HIGH);

console.log("out-of-range declarations report 0 rather than wrapping");
hw.hwSetCartHigh(CART_RAM_TOP); // exactly full
check("hwRamFree at the ceiling", hw.hwRamFree(), 0);
hw.hwSetCartHigh(CART_RAM_TOP + 4096); // overrun — the bug this exists for
check("hwRamFree past the ceiling", hw.hwRamFree(), 0);
check("hwRamUsed past the ceiling", hw.hwRamUsed(), 0);
hw.hwSetCartHigh(0x1000); // below the window (a cart linked somewhere else)
check("hwRamFree below the window", hw.hwRamFree(), 0);

console.log("the ROM window (Phase 2): its own 2 MiB ABOVE the video region");
check("hwRomRamBase", hw.hwRomRamBase(), ROM_RAM_BASE);
check("hwRomRamTop", hw.hwRomRamTop(), ROM_RAM_TOP);
check("hwRomRamSize", hw.hwRomRamSize(), ROM_RAM_TOP - ROM_RAM_BASE);
check("the ROM window starts above the cart's", ROM_RAM_BASE >= CART_RAM_TOP, true);
console.log("no ROM chip fitted yet: reports 0, same as a full one");
check("hwRomRamFree undeclared", hw.hwRomRamFree(), 0);
check("hwRomRamUsed undeclared", hw.hwRomRamUsed(), 0);
hw.hwSetRomHigh(ROM_RAM_BASE + 256 * 1024);
check("hwRomRamUsed declared", hw.hwRomRamUsed(), 256 * 1024);
check("hwRomRamFree declared", hw.hwRomRamFree(), ROM_RAM_TOP - ROM_RAM_BASE - 256 * 1024);
console.log("the two windows do not alias: declaring one leaves the other alone");
check("cart free after a ROM declaration", hw.hwRamFree(), 0); // still the past-ceiling value
hw.hwSetCartHigh(CART_RAM_BASE + 64 * 1024);
check("ROM used after a cart declaration", hw.hwRomRamUsed(), 256 * 1024);
check("cart used", hw.hwRamUsed(), 64 * 1024);
hw.hwInit();
check("both survive hwInit: ROM", hw.hwRomRamUsed(), 256 * 1024);
check("both survive hwInit: cart", hw.hwRamUsed(), 64 * 1024);
hw.hwSetRomHigh(0); // no chip fitted, for the per-cart checks below

console.log("the hardware agrees with the host's measurement, per cart");
for (const f of ["docs/demo-gem.wasm", "docs/demo-st_replay.wasm", "docs/demo.wasm"]) {
    const ram = cartRam(await readFile(f));
    hw.hwSetCartHigh(ram.known ? ram.high : 0);
    check(`${f} free`, hw.hwRamFree(), ram.free);
    check(`${f} used`, hw.hwRamUsed(), ram.used);
    if (ram.over) { console.log(`  FAIL  ${f} OVERRUNS the window`); failures++; }
}

console.log(failures === 0 ? "\nRAM instructions: PASS ✅" : `\nRAM instructions: ${failures} FAILURE(S) ❌`);
process.exit(failures === 0 ? 0 : 1);
