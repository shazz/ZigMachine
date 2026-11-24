// The capability word (HW 1.19.0, docs/hardware/ABI_RULES.md): machine/sdk/caps.zig's bits, the machine's
// hwCaps/hwSetCaps, the ABI doc's bit table, and a cart that asks before it uses an optional unit.
//   word     a fresh machine says every unit it emulates (ALL); hwSetCaps(0) says none; a bit nobody defined
//            is dropped (an old cart never sees a bit it cannot name); the desk bit is hwDeskAvailable's
//   table    docs/hardware/ABI_RULES.md lists every bit of caps.zig, same name, same number
//   fallback COPRO's ASTROLABE pages with every capability off: no hwAstro call at all, the same pictures as
//            ZIGGY's soft f64 (switch 6); with them on, one call a frame
//   node apps/harness/caps_check.mjs [--break caps]
//   --break caps: the machine says every unit is there whatever was declared (hwCaps lies): the cart calls
//            hwAstro in the capabilities-off run, and the fallback check must fail (then exit 0)
import { readFile } from "node:fs/promises";
import { boot } from "./copro_boot.mjs";

const BRK = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
if (BRK !== null && BRK !== "caps") throw new Error(`--break caps, not ${BRK}`);
let failed = 0, caught = 0;
const ok = (c, m) => { console.log(`  ${c ? "ok  " : "FAIL"} ${m}`); if (!c) failed++; };

const src = await readFile("machine/sdk/caps.zig", "utf8");
const bits = [...src.matchAll(/^\s*(\w+) = (\d+),$/gm)].map((m) => [m[1], Number(m[2])]);
const ALL = bits.reduce((a, [, n]) => a | (1 << n), 0);
const machine = (await WebAssembly.instantiate(await readFile("site/machine-video.wasm"), {
    env: { memory: new WebAssembly.Memory({ initial: 128, maximum: 128 }), hblDispatch: () => 0 },
})).instance.exports;

console.log("caps word");
ok(bits.length >= 6 && new Set(bits.map((b) => b[1])).size === bits.length, `${bits.length} bits, each number once`);
ok(machine.hwCaps() === ALL, `a fresh machine says every unit it emulates (0x${ALL.toString(16)})`);
machine.hwSetCaps(0);
ok(machine.hwCaps() === 0, "hwSetCaps(0): no optional unit");
machine.hwSetCaps(0xffffffff);
ok(machine.hwCaps() === ALL, "a bit nobody defined is dropped");
machine.hwSetCaps(ALL);
machine.hwSetDeskAvailable(0);
const desk = bits.find(([n]) => n === "desk")[1];
ok(machine.hwCaps() === (ALL & ~(1 << desk)), "desk bit follows hwDeskAvailable (0)");
machine.hwSetCaps(0);
ok(machine.hwDeskAvailable() === 0, "capabilities off: hwDeskAvailable is 0 too");
machine.hwSetCaps(ALL);
machine.hwSetDeskAvailable(1);
ok(machine.hwCaps() === ALL && machine.hwDeskAvailable() === 1, "...and (1)");

console.log("caps table");
const doc = await readFile("docs/hardware/ABI_RULES.md", "utf8");
for (const [name, n] of bits) ok(new RegExp(`\\|\\s*${n}\\s*\\|\\s*\`${name}\`\\s*\\|`).test(doc), `ABI_RULES.md lists bit ${n} \`${name}\``);

console.log("caps fallback (COPRO F64 ZOOM / CLOTH)");
for (const [p, name] of [[4, "F64 ZOOM"], [5, "F64 CLOTH"]]) {
    const off = await boot([p], BRK === "caps" ? "capsliar" : null, null, 0), on = await boot([p]), soft = await boot([6, p]);
    for (let f = 0; f < 40; f++) { off.frame(); on.frame(); soft.frame(); }
    const rows = (r) => r.plane().subarray(0, 176 * 320);
    ok(off.log.astro === 0, `${name}: capabilities off, ${off.log.astro} hwAstro calls`);
    ok(on.log.astro >= 40, `${name}: capabilities on, ${on.log.astro} hwAstro calls for 40 frames`);
    ok(Buffer.compare(rows(off), rows(soft)) === 0, `${name}: the fallback draws ZIGGY's soft f64 picture`);
    if (BRK === "caps" && off.log.astro !== 0) caught++;
}
if (BRK === "caps") {
    console.log(caught === 2 ? "caps: --break caps caught (the cart trusted hwCaps, the lie reached hwAstro)" : `caps: --break caps NOT caught (${caught} of 2)`);
    process.exit(caught === 2 ? 0 : 1);
}
console.log(failed ? `caps: ${failed} FAILED` : "caps: all ok");
process.exit(failed ? 1 : 0);
