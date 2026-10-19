// Render the kickoff2 match plane to PPMs at several moments for visual checks.
import { readFile, writeFile } from "node:fs/promises";

const PAGES = 112;
const VBL_MS = 20;
const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const romEnv = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
const rom = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), { env: romEnv })).instance.exports;
const noop = () => {};
const cartBytes = await readFile("docs/demo-kickoff2.wasm");
const env = {
    ...romEnv,
    hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop, hwRamSize: machine.hwRamSize,
    hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
    hwRamAlloc: machine.hwRamAlloc, hwRamMark: machine.hwRamMark,
    hwRamRelease: machine.hwRamRelease, hwRamAllocFailures: machine.hwRamAllocFailures,
    hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
    hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
    hwRomRamFree: machine.hwRomRamFree, ...rom,
};
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
    if (imp.module === "env" && !(imp.name in env)) env[imp.name] = noop;
demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
machine.hwInit();
demo.boot();
demo.skipBoot();

const W = 320, H = 200;

// MATCH_PAL (pitch.zig, post-DAC)
const PAL = [
    [0,0,0],[0,170,0],[51,153,0],[0,136,0],[204,221,187],
    [255,221,204],[255,255,255],[0,0,255],[170,0,0],[0,0,255],
    [0,102,0],[255,255,255],[0,0,0],[153,153,153],[119,119,119],[0,204,255]
];
const hdrText = `P6\n${W} ${H}\n255\n`;

const shot = async (name) => {
    machine.hwRenderPlane(0);
    const fb = new Uint8Array(memory.buffer, demo.ko2ScreenPtr(), W * H);
    const rgb = Buffer.alloc(W * H * 3);
    const counts = {};
    for (let i = 0; i < W * H; i++) counts[fb[i]] = (counts[fb[i]] || 0) + 1;
    for (let i = 0; i < W * H; i++) {
        const c = PAL[fb[i] & 15] || [9, 9, 9];
        rgb[i*3] = c[0]; rgb[i*3+1] = c[1]; rgb[i*3+2] = c[2];
    }
    await writeFile(`/tmp/opencode/ko2_${name}.ppm`, Buffer.concat([Buffer.from(hdrText), rgb]));
    const top = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 8)
        .map(([k, v]) => `${k}x${v}`).join(" ");
    console.log(name, "ph=", demo.ko2Phase ? demo.ko2Phase() : -1, "| slots:", top);
};

for (let i = 0; i < 8; i++) { machine.hwClear(); demo.frame(VBL_MS); }
demo.key(32);
for (let i = 0; i < 3; i++) { machine.hwClear(); demo.frame(VBL_MS); }
demo.keyUp(32);
for (let i = 0; i < 9; i++) { machine.hwClear(); demo.frame(VBL_MS); }
console.log("fired");
for (const n of [30, 100, 200, 400]) {
    for (let i = 0; i < 30; i++) { machine.hwClear(); demo.frame(VBL_MS); }
    await shot(`f${n}`);
}
