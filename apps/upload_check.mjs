// "Run your own cart" (docs/upload-cart.js): a disk from the visitor's machine
// must mount EXACTLY like a disk from a URL, because carts stream their data
// files (stniccc's scene1.bin, textracker's FEEDME.RAW) through diskReadBlock off
// the mounted disk.
//
// For every docs/*.zmd this runs the REAL docs/sealed-loader.js in a vm (DOM
// stubbed) and compares, byte for byte: the pre-refactor parser (kept verbatim
// below as the reference), the URL path mountDisk(url), and the upload path
// mountDiskBytes(bytes). Then it throws bad uploads at bootUserFile.
//
// Usage: node apps/upload_check.mjs
import { readFile, readdir } from "node:fs/promises";
import vm from "node:vm";
import * as ZMDisk from "../docs/zmdisk.js";
import * as ZMRam from "../docs/wasm_hiwater.js";

const noise = () => {};
function stub() { // a DOM that accepts anything the loader's top level does to it
    return new Proxy(function () {}, {
        get: (t, k) => (k === "then" || typeof k === "symbol") ? undefined : stub(),
        set: () => true, apply: () => stub(), construct: () => stub(),
    });
}
const alerts = [];
const ctx = vm.createContext({
    console: { log: noise, warn: noise, error: noise }, alert: (m) => alerts.push(m),
    window: stub(), document: stub(), WebAssembly, TextDecoder, TextEncoder, URLSearchParams,
    fetch: async (url) => {
        const bytes = await readFile("docs/" + url.replace(/\?.*$/, ""));
        return { arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length) };
    },
    ZMDisk: { ...ZMDisk }, ZMRam: { ...ZMRam },
});
vm.runInContext(await readFile("docs/sealed-loader.js", "utf8"), ctx, { filename: "sealed-loader.js" });
vm.runInContext(await readFile("docs/upload-cart.js", "utf8"), ctx, { filename: "upload-cart.js" });
vm.runInContext(LEGACY(), ctx, { filename: "legacy-mount.js" });
const run = (code) => vm.runInContext(code, ctx);

let bad = 0;
const fail = (what, msg) => { console.log(`FAIL  ${what.padEnd(32)} ${msg}`); bad++; };
const same = (a, b) => a === b || (a && b && Buffer.compare(Buffer.from(new Uint8Array(a)), Buffer.from(new Uint8Array(b))) === 0);

function compare(path, ref, refDisk, got, gotDisk) {
    if (ref.bootable !== got.bootable || !!ref.v2 !== !!got.v2) return "bootable/v2 differ";
    if (!same(ref.cart, got.cart)) return "cart bytes differ";
    if (!same(refDisk.buf, gotDisk.buf)) return "disk image differs";
    if (JSON.stringify(refDisk.files) !== JSON.stringify(gotDisk.files)) return "FAT entries differ";
    if (JSON.stringify([refDisk.date, refDisk.v2, refDisk.chainCart]) !== JSON.stringify([gotDisk.date, gotDisk.v2, gotDisk.chainCart]))
        return "descriptor (date / v2 / chain cart) differs";
    return null;
}

// The drive: every FAT file's first and last block reads back the image's bytes.
function driveReads(image) {
    const mem = run("memory"), dst = 0x100000;
    const files = Object.values(run("mountedDisk").files);
    for (const blk of [0, 1, ...files.flatMap((f) => [f.start >> 9, (f.start + Math.max(f.len, 1) - 1) >> 9])]) {
        const n = run(`diskReadBlock(${blk}, ${dst})`);
        const want = image.subarray(blk * 512, blk * 512 + 512);
        if (n !== want.length || !same(new Uint8Array(mem.buffer, dst, n), want)) return `diskReadBlock(${blk}) differs`;
    }
    return null;
}

const disks = (await readdir("docs")).filter((f) => f.endsWith(".zmd")).sort();
for (const name of disks) {
    const image = new Uint8Array(await readFile("docs/" + name));
    try {
        const ref = await run(`legacyMountDisk(${JSON.stringify(name)})`), refDisk = run("mountedDisk");
        const url = await run(`mountDisk(${JSON.stringify(name)})`), urlDisk = run("mountedDisk");
        ctx.__bytes = image.slice();
        const up = run(`mountDiskBytes(__bytes, ${JSON.stringify(name)})`), upDisk = run("mountedDisk");
        const err = compare(name, ref, refDisk, url, urlDisk) || compare(name, ref, refDisk, up, upDisk)
            || driveReads(image) || (ZMDisk.classifyUpload(image).kind !== "disk" && "not sniffed as a disk");
        if (err) { fail(name, err); continue; }
        console.log(`ok    ${name.padEnd(32)} ${up.v2 ? "v2" : "v1"} ${up.bootable ? "bootable" : "data    "} ` +
                    `${String(Object.keys(upDisk.files).length).padStart(2)} file(s)  url == bytes == legacy`);
    } catch (e) { fail(name, e.message); }
}

// --- sniffing and caps ---------------------------------------------------------
const tut = new Uint8Array(await readFile("docs/demo-c-tutorial.wasm"));
const packed = ZMDisk.parseDisk(new Uint8Array(await readFile("docs/demo-ancool.zmd")), "ancool");
const packedCart = new Uint8Array(packed.mounted.chainCart
    ? packed.mounted.buf.slice(packed.mounted.chainCart.start, packed.mounted.chainCart.start + packed.mounted.chainCart.len)
    : packed.cart);
const big = (n, head) => { const b = new Uint8Array(n); b.set(head); return b; };
const sniff = [
    ["demo-c-tutorial.wasm", tut, "wasm"],
    ["ancool's packed cart", packedCart, "zx0"],
    ["a text file", new TextEncoder().encode("hello, this is not a cart\n"), null],
    ["an empty file", new Uint8Array(0), null],
    ["a 3 MB wasm", big(3 << 20, [0, 0x61, 0x73, 0x6d, 1, 0, 0, 0]), null],
    ["a 17 MB disk", big(17 << 20, new TextEncoder().encode("ZMDISK")), null],
];
for (const [what, bytes, want] of sniff) {
    const c = ZMDisk.classifyUpload(bytes);
    if ((c.kind ?? null) !== want) fail(what, `sniffed ${c.kind ?? "error: " + c.error}, want ${want ?? "refused"}`);
    else console.log(`ok    ${what.padEnd(32)} ${want ?? "refused: " + c.error}`);
}

// --- bootUserFile refuses without touching the running machine -------------------
run("demo = { marker: 1 }; machine = {}; currentTag = 'keep'; mountedDisk = { marker: 2 }");
const file = (name, bytes) => ({ name, size: bytes.length, arrayBuffer: async () => bytes.slice().buffer });
const corrupt = new Uint8Array(4096); corrupt.set(new TextEncoder().encode("ZMDISK")); corrupt[511] = 7;
const refusals = [
    ["a text file", file("notes.txt", sniff[2][1]), /not a ZigMachine cart/],
    ["a corrupt disk", file("bad.zmd", corrupt), /corrupt/],
    ["a wasm with no boot()", file("empty.wasm", new Uint8Array([0, 0x61, 0x73, 0x6d, 1, 0, 0, 0])), /does not export boot/],
    ["an over-size disk", { name: "huge.zmd", size: 20 << 20, arrayBuffer: async () => { throw new Error("read"); } }, /Too big/],
];
for (const [what, f, want] of refusals) {
    alerts.length = 0;
    ctx.__file = f;
    await run("bootUserFile(__file)");
    const intact = run("demo.marker === 1 && mountedDisk.marker === 2 && currentTag === 'keep' && swapping === false && cartTrapped === false");
    if (alerts.length !== 1 || !want.test(alerts[0]) || !intact) fail(what, `alerts ${JSON.stringify(alerts)}, machine intact ${intact}`);
    else console.log(`ok    ${what.padEnd(32)} refused, machine untouched`);
}
alerts.length = 0;
run("swapping = true");
await run("bootUserFile(__file)");
if (alerts.length !== 1 || !/busy/.test(alerts[0]) || !run("swapping === true")) fail("swap in flight", JSON.stringify(alerts));
else console.log(`ok    ${"swap in flight".padEnd(32)} refused, swap left alone`);

console.log(bad === 0 ? `\nupload: ${disks.length} disks mount identically from bytes, bad uploads refused ✅`
                      : `\nupload: ${bad} check(s) FAILED ❌`);
process.exit(bad === 0 ? 0 : 1);

// sealed-loader.js's mountDisk/mountDiskV2 as they were before mountDiskBytes
// (f2be1a9), verbatim but renamed: the reference the refactor must match.
function LEGACY() { return String.raw`
async function legacyMountDisk(url) {
    const buf = new Uint8Array(await fetch(url + BUST).then((r) => r.arrayBuffer()));
    if (buf[0] === 0x00 && buf[1] === 0x61 && buf[2] === 0x73 && buf[3] === 0x6d)
        return legacyMountDiskV2(url, buf);
    if (String.fromCharCode(...buf.subarray(0, 6)) !== "ZMDISK")
        throw new Error("not a ZigMachine disk: " + url);
    let sum = 0;
    for (let i = 0; i < 256; i++) sum = (sum + ((buf[2 * i] << 8) | buf[2 * i + 1])) & 0xFFFF;
    const bootable = sum === 0x1234;
    if (!bootable && sum !== 0x0000)
        throw new Error("disk corrupt: boot-sector checksum 0x" + sum.toString(16));
    const dv = new DataView(buf.buffer);
    const blockSize = dv.getUint16(0x08, true);
    const bootBlock = dv.getUint32(0x0e, true);
    const bootLen = dv.getUint32(0x12, true);
    const nFiles = dv.getUint16(0x2e4, true);
    const files = {};
    for (let i = 0; i < nFiles; i++) {
        const e = 0x300 + i * 32;
        const name = text_decoder.decode(buf.subarray(e, e + 16)).replace(/\0.*$/, "");
        files[name] = { start: dv.getUint32(e + 0x10, true), len: dv.getUint32(e + 0x14, true), type: buf[e + 0x18] };
    }
    mountedDisk = { buf, files };
    const start = bootBlock * blockSize;
    return { bootable, cart: bootable ? buf.buffer.slice(start, start + bootLen) : null };
}
function legacyMountDiskV2(url, buf) {
    let sum = 0;
    for (let i = 0; i < 512; i++) sum = (sum + ((buf[2 * i] << 8) | buf[2 * i + 1])) & 0xFFFF;
    const bootable = sum === 0x1234;
    const dv = new DataView(buf.buffer);
    if (String.fromCharCode(...buf.subarray(0x400, 0x406)) !== "ZMDISK")
        throw new Error("v2 disk: bad descriptor magic");
    const cartBlock = dv.getUint32(0x408, true);
    const cartLen = dv.getUint32(0x40c, true);
    const nFiles = dv.getUint16(0x4f4, true);
    const files = {};
    for (let i = 0; i < nFiles; i++) {
        const e = 0x800 + i * 32;
        const name = text_decoder.decode(buf.subarray(e, e + 16)).replace(/\0.*$/, "");
        files[name] = { start: dv.getUint32(e + 0x10, true), len: dv.getUint32(e + 0x14, true), type: buf[e + 0x18] };
    }
    const date = dv.getUint32(0x4f0, true);
    mountedDisk = { buf, files, date, v2: true, chainCart: { start: cartBlock * 512, len: cartLen } };
    return { bootable, v2: true, cart: bootable ? buf.buffer.slice(0, 1024) : null };
}`; }
