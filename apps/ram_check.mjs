// Test the sealed RAM instructions (hwSetCartHigh / hwRam*) against the host-side
// measurement they are fed from, and check every built cart fits its window.
//
// The bug this guards: a cart's static data + stack ran past CART_RAM_TOP into the
// video region, which does not trap — it silently corrupts VRAM, and the machine
// died later somewhere else entirely. hwRamFree() is how a cart asks instead of
// guessing, so the instruction has to be right, including when it does not know.
//
// Also the RAM arena (1.7.0): hwRamAlloc/Mark/Release/AllocFailures in the sealed
// binary -- placement, zeroing, refusals counted, hwInit survival, per-cart reset.
//
// Usage: node apps/ram_check.mjs      (exit 1 on any failure)
import { readFile } from "node:fs/promises";
import { cartRam, romRam, CART_RAM_BASE, CART_RAM_TOP, ROM_RAM_BASE, ROM_RAM_TOP } from "../docs/wasm_hiwater.js";

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
    return { ...m.instance.exports, memory };
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

// --- the RAM arena (1.7.0): hwRamAlloc / Mark / Release / AllocFailures -------
// The rules are proven natively (machine/arena_test.zig); this proves the SEALED
// binary wires them to the right registers, window and reset points.
console.log("RAM arena (HW 1.7.0)");
check("hwVersion is 1.7.0 or a later 1.x", hw.hwVersion() >= 0x00010700 && hw.hwVersion() < 0x00020000, true);
console.log("RAM arena: undeclared high-water = no arena, every call refused and counted");
hw.hwSetCartHigh(0);
check("hwRamAlloc undeclared", hw.hwRamAlloc(64, 4), 0);
check("hwRamMark undeclared", hw.hwRamMark(), 0);
check("hwRamAllocFailures", hw.hwRamAllocFailures(), 1);

console.log("RAM arena: allocations sit above the high-water, aligned, ZEROED over a dirty window");
{
    const mem = new Uint8Array(hw.memory.buffer);
    const HI = CART_RAM_BASE + 100001; // odd, so alignment has work to do
    hw.hwSetCartHigh(HI);
    check("a new declaration zeroes the failure counter", hw.hwRamAllocFailures(), 0);
    check("hwRamMark = the high-water while empty", hw.hwRamMark(), HI);
    const a = hw.hwRamAlloc(1000, 256);
    check("first block, 256-aligned just above the high-water", a, Math.ceil(HI / 256) * 256);
    check("hwRamUsed counts the arena", hw.hwRamUsed(), a + 1000 - CART_RAM_BASE);
    check("hwRamFree = top - arena top", hw.hwRamFree(), CART_RAM_TOP - (a + 1000));
    check("used + free = the window", hw.hwRamUsed() + hw.hwRamFree(), CART_RAM_TOP - CART_RAM_BASE);
    const m = hw.hwRamMark();
    check("mark = arena top", m, a + 1000);
    const b = hw.hwRamAlloc(4096, 8);
    mem.fill(0x5a, b, b + 4096); // a part scribbles on its buffer...
    hw.hwRamRelease(m);
    const c = hw.hwRamAlloc(4096, 8); // ...and the next part gets it back
    check("release to a mark reuses the region", c, b);
    check("...zeroed", mem.subarray(c, c + 4096).every((x) => x === 0), true);
    console.log("RAM arena: exhaustion returns 0 and is counted, never silent");
    const room = hw.hwRamFree();
    check("one byte too many", hw.hwRamAlloc(room + 1, 1), 0);
    check("a non-power-of-two alignment", hw.hwRamAlloc(16, 12), 0);
    check("a release above the arena top", (hw.hwRamRelease(CART_RAM_TOP - 4), hw.hwRamAllocFailures()), 3);
    check("exactly what is left still fits", hw.hwRamAlloc(room, 1) !== 0, true);
    check("then the window is full", hw.hwRamFree(), 0);
    console.log("RAM arena: survives hwInit (it holds the cart's buffers, not video state)");
    const top = hw.hwRamMark();
    hw.hwInit();
    check("mark after hwInit", hw.hwRamMark(), top);
    check("failures after hwInit", hw.hwRamAllocFailures(), 3);
    console.log("RAM arena: a NEW cart (hwSetCartHigh, every boot/swap) starts empty");
    hw.hwSetCartHigh(HI);
    check("mark after a new declaration", hw.hwRamMark(), HI);
    check("failures after a new declaration", hw.hwRamAllocFailures(), 0);
    check("hwRamFree back to the static figure", hw.hwRamFree(), CART_RAM_TOP - HI);
}
hw.hwSetCartHigh(0);

console.log("the hardware agrees with the host's measurement, per cart");
for (const f of ["docs/demo-gem.wasm", "docs/demo-st_replay.wasm", "docs/demo.wasm"]) {
    const ram = cartRam(await readFile(f));
    hw.hwSetCartHigh(ram.known ? ram.high : 0);
    check(`${f} free`, hw.hwRamFree(), ram.free);
    check(`${f} used`, hw.hwRamUsed(), ram.used);
    if (ram.over) { console.log(`  FAIL  ${f} OVERRUNS the window`); failures++; }
}

console.log("the ROM chip fits its own window, and the hardware says so");
{
    const romBytes = await readFile("docs/rom.wasm");
    const r = romRam(romBytes);
    if (r.over) { console.log(`  FAIL  rom.wasm OVERRUNS the ROM window (ends 0x${r.high.toString(16)})`); failures++; }
    else if (!r.known) { console.log("  FAIL  rom.wasm is not linked into the ROM window"); failures++; }
    else console.log(`  ok    rom.wasm ${(r.used / 1024) | 0} KB used, ${(r.free / 1024) | 0} KB free`);
    hw.hwSetRomHigh(r.known ? r.high : 0);
    check("hwRomRamFree agrees", hw.hwRomRamFree(), r.free);
    check("hwRomRamUsed agrees", hw.hwRomRamUsed(), r.used);
    // The two windows must not overlap, now that both are really occupied.
    const cart = cartRam(await readFile("docs/demo-gem.wasm"));
    check("the cart ends below the ROM window", cart.high < ROM_RAM_BASE, true);
}

console.log(failures === 0 ? "\nRAM instructions: PASS ✅" : `\nRAM instructions: ${failures} FAILURE(S) ❌`);
process.exit(failures === 0 ? 0 : 1);
