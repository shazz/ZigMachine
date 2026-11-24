// Regenerates apps/zig/scenes/sidwizard_z/old_cart_sid.bin: the C cart's (apps/ports/sidwizard, the whole C64 program on an emulated
// 6502) SID writes after F1 on FLASHBAK.SWM, as [register, value] byte pairs: the first 4000 from the song's start (the editor's
// player re-initialisation: 24 zero writes, descending). player_test.zig and sidwizard_z_check.mjs hold the Zig-driven player to it.
//   node apps/harness/sidwizard_z_golden.mjs
import { readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../../site/js/wasm_hiwater.js";
import { pageSound } from "./bard_queue_lib.mjs";

const CART = "site/carts/demo-sidwizard.wasm", DISK = "site/carts/demo-sidwizard.zmd", OUT = "apps/zig/scenes/sidwizard_z/old_cart_sid.bin";
const F1_AT = 322, FRAMES = 900, COUNT = 4000;
const memory = new WebAssembly.Memory({ initial: 128, maximum: 128 });
const machine = (await WebAssembly.instantiate(await readFile("site/machine-video.wasm"), { env: { memory, hblDispatch() {} } })).instance.exports;
const romBytes = await readFile("site/rom.wasm");
const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
const disk = await readFile(DISK), cartBytes = await readFile(CART);
const sound = await pageSound(memory, { frames: FRAMES });
const env = {
    memory, ...rom, hostBardAttach: sound.hostBardAttach, hostMicros: () => 0, consoleLogJS: () => {},
    diskReadBlock: (b, dst) => { const s = disk.subarray(b * 512, b * 512 + 512); new Uint8Array(memory.buffer, dst, s.length).set(s); return s.length; },
    kosFileOp: () => -46, kosDriveRead: () => 0,
};
for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes))) if (!(imp.name in env)) env[imp.name] = () => 0;
const demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
machine.hwInit(); demo.boot(); demo.skipBoot();
for (let f = 1; f <= FRAMES; f++) { if (f === F1_AT) demo.key(0xe001); if (f === F1_AT + 6) demo.keyUp(0xe001); demo.frame(16.6); sound.frame(732); }
const c = sound.commands(), w = [];
for (let i = 0; i + 3 < c.length; i += 4) if (c[i + 1] >= 0xd400 && c[i + 1] <= 0xd418) w.push([c[i + 1] - 0xd400, c[i + 2]]);
// the song's start is the last run of the 24 descending zero writes ($17..$00) the player's init makes
const run = (i) => w.slice(i, i + 24).every(([r, v], k) => r === 23 - k && v === 0);
let at = -1;
for (let i = 0; i + 24 <= w.length; i++) if (run(i) && i > 2500) { at = i; break; }
if (at < 0 || w.length - at < COUNT) throw new Error(`no song start with ${COUNT} writes after it (${w.length} writes)`);
await writeFile(OUT, Uint8Array.from(w.slice(at, at + COUNT).flat()));
console.log(`${OUT}: ${COUNT} writes from #${at}`);
