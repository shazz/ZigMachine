// Mount every .zmd the way docs/sealed-loader.js does, and INSTANTIATE its cart
// against the host's real import surface.
//
// WHY: a .zmd freezes its cart's wasm at pack time, so a disk carries the import
// list that existed the day it was packed. Retiring three host imports made every
// disk on the shelf fail to instantiate with a LinkError, and nothing caught it
// until a black screen in a browser (4c00b19). This is that check, offline.
//
// It deliberately mirrors the loader rather than importing it: if the two drift,
// this fails, which is the whole point.
//
// Usage: node apps/disk_check.mjs [disk.zmd ...]   (default: docs/*.zmd)
import { readFile, readdir } from "node:fs/promises";
import { cartRam, romRam, CART_RAM_TOP } from "../docs/wasm_hiwater.js";

const PAGES = 112; // memmap.SHARED_PAGES
const dec = new TextDecoder();
const str = (b, o, n) => dec.decode(b.subarray(o, o + n)).replace(/\0.*$/, "");

function beSum(b, words) {
    let s = 0;
    for (let i = 0; i < words; i++) s = (s + ((b[2 * i] << 8) | b[2 * i + 1])) & 0xFFFF;
    return s;
}

// Returns {fmt, title, bootable, cart, files} — cart null for a data disk, which
// boots GEM instead (so GEM is what we instantiate for it).
function mount(buf) {
    const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
    if (buf[0] === 0x00 && buf[1] === 0x61 && buf[2] === 0x73 && buf[3] === 0x6d) {
        if (str(buf, 0x400, 6) !== "ZMDISK") throw new Error("v2 disk: bad descriptor magic");
        const sum = beSum(buf, 512);
        if (sum !== 0x1234) throw new Error(`v2 boot sector not executable (sum 0x${sum.toString(16)})`);
        const start = dv.getUint32(0x408, true) * 512, len = dv.getUint32(0x40c, true);
        const n = dv.getUint16(0x4f4, true);
        return { fmt: "v2", title: str(buf, 0x410, 64), bootable: true,
                 boot: buf.slice(0, 1024), cart: buf.slice(start, start + len), nFiles: n };
    }
    if (str(buf, 0, 6) !== "ZMDISK") throw new Error("not a ZigMachine disk");
    const sum = beSum(buf, 256);
    if (sum !== 0x1234 && sum !== 0x0000)
        throw new Error(`boot-sector checksum 0x${sum.toString(16)} (neither bootable nor data)`);
    const bootable = sum === 0x1234;
    const start = dv.getUint32(0x0e, true) * dv.getUint16(0x08, true);
    const len = dv.getUint32(0x12, true);
    return { fmt: "v1", title: str(buf, 0x200, 64), bootable,
             cart: bootable ? buf.slice(start, start + len) : null,
             // A data disk still carries the app GEM launches off it: check that one too.
             appCart: bootable ? null : buf.slice(start, start + len),
             nFiles: dv.getUint16(0x2e4, true) };
}

// The host's env, exactly as sealed-loader.js builds it (retired names included —
// they are an ABI and stay as no-op stubs, never deletions).
async function hostEnv(memory, machine, rom) {
    const noop = () => {};
    return {
        ...rom, // the ROM chip's flat ABI — a cart links none of GEM itself
        memory,
        jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop,
        consoleLogJS: noop,
        hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit,
        hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop,
        hwRamSize: machine.hwRamSize, hwRamUsed: machine.hwRamUsed,
        hwRamFree: machine.hwRamFree,
        hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
        hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
        hwRomRamFree: machine.hwRomRamFree,
        beep: noop, diskReadBlock: noop,
        hostAudioStreamStart: noop, hostAudioFeed: noop, hostAudioStreamStop: noop,
        audioPlay: noop, audioStop: noop, loadSample: noop,   // RETIRED, kept as stubs
    };
}

const args = process.argv.slice(2);
const disks = args.length ? args
    : (await readdir("docs")).filter((f) => f.endsWith(".zmd")).sort().map((f) => `docs/${f}`);

const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo = null;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"),
    { env: { memory, hblDispatch: (id, p, l, x) => demo && demo.hblDispatch(id, p, l, x) } })).instance.exports;
const romBytes = await readFile("docs/rom.wasm");
const rom = (await WebAssembly.instantiate(romBytes, {
    env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
})).instance.exports;
machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
const env = await hostEnv(memory, machine, rom);

// A disk stores its cart ZX0-packed. Unpack it exactly as sealed-loader.js's
// unpackCart does: packed image into the ROM's free RAM, romDepack into the cart
// window, copy out. A disk the ROM cannot unpack FAILS here, before a browser.
function unpack(bytes, path) {
    if (!(bytes.length >= 10 && bytes[0] === 0x5a && bytes[1] === 0x58 && bytes[2] === 0x30 && bytes[3] === 0x21)) return bytes;
    if (bytes.length > machine.hwRomRamFree()) throw new Error(`${path}: packed cart does not fit the ROM's free RAM`);
    const src = machine.hwRomRamBase() + machine.hwRomRamUsed();
    new Uint8Array(memory.buffer, src, bytes.length).set(bytes);
    const dst = machine.hwRamBase();
    const n = rom.romDepack(src, bytes.length, dst, machine.hwRamSize());
    if (!n) throw new Error("packed cart is corrupt or too big for the cart window (romDepack returned 0)");
    return new Uint8Array(memory.buffer.slice(dst, dst + n));
}
const gem = await readFile("docs/demo-gem.wasm");

let bad = 0;
for (const path of disks) {
    try {
        const d = mount(new Uint8Array(await readFile(path)));
        // A data disk is not executable on purpose: the machine boots GEM, which
        // opens the disk's app. So GEM is the binary that must instantiate.
        if (d.appCart && d.appCart.length) {
            // The data disk's own app, which GEM launches: it must unpack and link too.
            const app = unpack(d.appCart, path);
            const appRam = cartRam(app);
            if (appRam.over) throw new Error(`the data disk's app overruns the RAM window`);
            await WebAssembly.instantiate(app, { env });
        }
        const cart = d.cart ? unpack(d.cart, path) : null;
        const wasm = cart ?? gem;
        const what = d.cart ? (cart.length !== d.cart.length ? `cart (packed ${(d.cart.length / 1024) | 0}KB)` : "cart") : "GEM (data disk)";
        const ram = cartRam(wasm);
        if (ram.over) throw new Error(`${what} overruns the RAM window (ends 0x${ram.high.toString(16)} >= 0x${CART_RAM_TOP.toString(16)})`);
        const inst = await WebAssembly.instantiate(wasm, { env });
        for (const fn of ["boot", "frame", "hblDispatch"])
            if (typeof inst.instance.exports[fn] !== "function")
                throw new Error(`${what} does not export ${fn}()`);
        console.log(`ok    ${path.padEnd(32)} ${d.fmt} ${d.bootable ? "bootable" : "data    "} ` +
                    `${String(d.nFiles).padStart(2)} file(s)  ${what} ${(ram.free / 1024) | 0}KB free`);
    } catch (e) {
        console.log(`FAIL  ${path.padEnd(32)} ${e.message}`);
        bad++;
    }
}
console.log(bad === 0 ? `\ndisks: all ${disks.length} mount and instantiate ✅`
                      : `\ndisks: ${bad}/${disks.length} FAILED ❌`);
process.exit(bad === 0 ? 0 : 1);
