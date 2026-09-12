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
import { cartRam, CART_RAM_BASE, CART_RAM_TOP } from "../docs/wasm_hiwater.js";

const PAGES = 79; // memmap.SHARED_PAGES
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
