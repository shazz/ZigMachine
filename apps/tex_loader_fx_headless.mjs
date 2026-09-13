// Headless TEX LOADER depack effect (zx0 fx = tex_loader) on real data.
//
// 1. packs a real cart asset with zx0pack --fx tex_loader --panel <the Union Demo
//    main menu's loader panel>;
// 2. compiles apps/tex_loader_fx/cart.zig with apps/zig/demo_main.zig into a
//    one-off cart that embeds the packed image (not a scene, nothing registered);
// 3. boots the sealed machine as sealed-loader.js does, runs the depack frame by
//    frame and writes PNGs of the 320x200 window at the start, the middle (half
//    the bytes written) and the end (the last frame before the data is ready);
// 4. checks the depacked bytes equal the original file.
//
//   node apps/tex_loader_fx_headless.mjs [outdir] [asset] [bytes_per_line]
// Needs zig on PATH and a prior `zig build -Drelease=true -Dwasm` (zx0pack, machine).
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const out = process.argv[2] || "/tmp/tex_loader_fx";
const asset = process.argv[3] || "apps/zig/assets/screens/union_intro/trsi_turn.raw";
// 7 bytes a line = 1960 a frame: the 196,560-byte TRSI turn depacks in 101 frames,
// about the 99 frames (13,820 ms at 140 ms a frame) the remake's panel takes.
const bytesPerLine = Number(process.argv[4] || 7);
const PANEL = "apps/zig/assets/screens/union_demo/loader_main_menu.txt";

function run(cmd, args) {
    const r = spawnSync(cmd, args, { stdio: "inherit" });
    if (r.status !== 0) throw new Error(`${cmd} failed (${r.status ?? r.error})`);
}

async function buildCart(work) {
    const image = `${work}/asset.zx0`;
    run("zig-out/bin/zx0pack", ["--fx", "tex_loader", "--panel", PANEL, asset, image]);
    await writeFile(`${work}/tex_packed.zig`,
        `pub const image = @embedFile("asset.zx0");\npub const bytes_per_line: u32 = ${bytesPerLine};\n`);
    const wasm = `${work}/tex_loader_fx.wasm`;
    run("zig", ["build-exe", "-target", "wasm32-freestanding-musl", "-OReleaseSmall",
        "-fno-entry", "-rdynamic", "--import-memory", "--stack", String(6 * 65536),
        `--initial-memory=${PAGES * 65536}`, `--max-memory=${PAGES * 65536}`, "--global-base=1048576",
        `-femit-bin=${wasm}`,
        "--dep", "zigos", "--dep", "boot_rom", "--dep", "cart", "--dep", "tvnoise",
        "-Mroot=apps/zig/demo_main.zig",
        "--dep", "hardware", "-Mzigos=libs/zig/zigos.zig",
        "--dep", "hardware", "-Mboot_rom=machine/boot.zig",
        "--dep", "zigos", "--dep", "hardware", "--dep", "depackers", "--dep", "tex_packed",
        "-Mcart=apps/tex_loader_fx/cart.zig",
        "-Mtvnoise=libs/zig/tvnoise/tvnoise.zig",
        "-Mhardware=machine/sdk/hardware.zig",
        "-Mdepackers=libs/zig/depackers/depackers.zig",
        `-Mtex_packed=${work}/tex_packed.zig`]);
    return wasm;
}

async function boot(cartPath) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(cartPath);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

function crc32(buf) {
    let c, crc = 0xffffffff;
    for (const b of buf) {
        c = (crc ^ b) & 0xff;
        for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
        crc = (crc >>> 8) ^ c;
    }
    return (crc ^ 0xffffffff) >>> 0;
}

function png(w, h, rgb) {
    const raw = Buffer.alloc((w * 3 + 1) * h);
    for (let y = 0; y < h; y++) rgb.copy(raw, y * (w * 3 + 1) + 1, y * w * 3, (y + 1) * w * 3);
    const chunk = (type, data) => {
        const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
        const td = Buffer.concat([Buffer.from(type), data]);
        const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
        return Buffer.concat([len, td, crc]);
    };
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
        chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

await mkdir(`${out}/work`, { recursive: true });
const { memory, machine, demo } = await boot(await buildCart(`${out}/work`));
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();

// The window as the host shows it: background, then each enabled plane blended.
async function shot(name, frame) {
    const X0 = 80, Y0 = 40, VW = 320, VH = 200, img = Buffer.alloc(VW * VH * 3);
    machine.hwClear();
    for (let p = 0; p < machine.hwPlanesNumber(); p++) {
        if (!demo.isPlaneEnabled(p)) continue;
        machine.hwRenderPlane(p);
        const px = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
        for (let y = 0; y < VH; y++) for (let x = 0; x < VW; x++) {
            const i = ((Y0 + y) * W + X0 + x * 2) * 4, a = px[i + 3] / 255, o = (y * VW + x) * 3;
            for (let c = 0; c < 3; c++) img[o + c] = img[o + c] * (1 - a) + px[i + c] * a;
        }
    }
    const path = `${out}/${name}.png`;
    await writeFile(path, png(VW, VH, img));
    console.log(`  shot: ${path} (frame ${frame}, ${demo.texWritten()}/${demo.texTotal()} bytes)`);
}

const perFrame = bytesPerLine * H;
let frame = 0, middle = false;
if (demo.texState() !== 0) throw new Error(`depack did not start (state ${demo.texState()})`);
while (demo.texState() === 0) {
    demo.frame(16.6);
    frame++;
    if (demo.texState() !== 0) break;
    if (frame === 1) await shot("start", frame);
    if (!middle && demo.texWritten() * 2 >= demo.texTotal()) { middle = true; await shot("middle", frame); }
    if (demo.texTotal() - demo.texWritten() <= perFrame) await shot("end", frame);
}
if (demo.texState() !== 1) throw new Error(`depack failed (state ${demo.texState()})`);
const original = await readFile(asset);
const got = Buffer.from(new Uint8Array(memory.buffer, demo.texDstPtr(), demo.texTotal()));
if (got.length !== original.length || !got.equals(original)) throw new Error("depacked bytes differ from the original");
console.log(`  depacked ${got.length} bytes in ${frame} frames at ${bytesPerLine} bytes/line: identical to ${asset}`);
