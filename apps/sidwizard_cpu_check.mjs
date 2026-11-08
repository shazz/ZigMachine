// SID-Wizard's fast 6502 (apps/ports/sidwizard/kestrel_sw_cpu.c) is libcRSID's 6502, byte for byte: builds the cart
// with SW_CPU_TEST (make cputest), whose boot runs kestrel_sw_cpu_test.c before the editor starts:
//   op       all 256 opcodes, 48 random machines each (registers, memory map, RAM, pending I/O cycles, IRQ/NMI lines,
//            the stale Addr), one instruction by each 6502 from the same snapshot: the whole C64 (cRSID_C64, 275 KB)
//            and the I/O hand-over's counters the same after it, and the same cycles / return code
//   sample   4,000 C64 samples of random code: sw_emulate_c64() vs cRSID_emulateC64() (interrupts, the wait, I/O)
// --break: the fast ADC sets a wrong carry on A = $80 (SW_CPU_BREAK): the test must find it.
//   node apps/sidwizard_cpu_check.mjs [--break]
import { execFileSync } from "node:child_process";

const broke = process.argv.includes("--break");
const out = broke ? "build/cputest_break" : "build/cputest";
execFileSync("make", ["-s", "-C", "apps/ports/sidwizard", "cputest", `OUT=${out}`, ...(broke ? ["CPUTEST_EXTRA=-DSW_CPU_BREAK"] : [])],
    { stdio: ["ignore", "ignore", "pipe"] }); // the compiler's warnings stay quiet; a failed build throws with them
const log = execFileSync("node", ["apps/ports/sidwizard/run.mjs", "1", `apps/ports/sidwizard/${out}/frame`],
    { env: { ...process.env, CART: `apps/ports/sidwizard/${out}/demo-sidwizard.wasm` }, encoding: "utf8", maxBuffer: 1 << 24 });
const lines = log.split("\n").filter((l) => l.includes("cpu test"));
const sum = lines.map((l) => l.match(/cpu test: (\d+) cases, (\d+) differ/)).find(Boolean);
for (const l of lines.slice(0, 6)) console.log(`  ${l.replace(/^cart: /, "")}`);
let ok;
if (!sum) { console.log("sidwizard_cpu_check: FAIL (the test cart printed no summary)"); ok = false; }
else if (broke) {
    ok = +sum[2] > 0;
    console.log(`sidwizard_cpu_check: ${ok ? "PASS (--break caught" : "FAIL (--break NOT caught"}: ${sum[2]} of ${sum[1]} cases differ)`);
} else {
    ok = +sum[2] === 0 && +sum[1] >= 16000;
    console.log(`sidwizard_cpu_check: ${ok ? "all pass" : "FAIL"} (${sum[1]} cases, ${sum[2]} differ)`);
}
process.exit(ok ? 0 : 1);
