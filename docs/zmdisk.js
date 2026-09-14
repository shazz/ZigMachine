// --------------------------------------------------------------------------
// ZigMachine disk image parsing (docs/FLOPPY_DISK.md), shared by the page and
// the node checks.
//
// WHY A MODULE: the page mounts disks two ways, from a URL (a channel, ?disk=)
// and from bytes the visitor uploads. Both must produce the SAME drive state,
// because carts stream their data files through diskReadBlock off it. One parser
// used by both paths, and by apps/upload_check.mjs, is how that stays true.
// Same hand-over as wasm_hiwater.js: an ES module that publishes itself on
// globalThis for the classic sealed-loader.js.
// --------------------------------------------------------------------------

// Upload caps. A raw cart runs in the 2 MiB cart window, so a bigger wasm cannot
// fit; a ZX0-packed cart is also unpacked into it. A disk has no format limit
// (total blocks is a u32), so this is host policy: the biggest disk on the shelf
// is under 1 MB, and 16 MiB leaves room while refusing a mistaken multi-GB pick.
export const CART_MAX_BYTES = 2 * 1024 * 1024;
export const DISK_MAX_BYTES = 16 * 1024 * 1024;

const dec = new TextDecoder();
const cstr = (b, o, n) => dec.decode(b.subarray(o, o + n)).replace(/\0.*$/, "");
const isWasm = (b) => b.length >= 4 && b[0] === 0x00 && b[1] === 0x61 && b[2] === 0x73 && b[3] === 0x6d;
const isZx0 = (b) => b.length >= 10 && b[0] === 0x5a && b[1] === 0x58 && b[2] === 0x30 && b[3] === 0x21;
const hasMagic = (b, off) => b.length >= off + 6 && cstr(b, off, 6) === "ZMDISK";

// Sum of the first `words` big-endian 16-bit words (the ST $1234 rule).
function beSum(b, words) {
    let s = 0;
    for (let i = 0; i < words; i++) s = (s + ((b[2 * i] << 8) | b[2 * i + 1])) & 0xFFFF;
    return s;
}

// The flat FAT: 32-byte entries, name[16] start[4] len[4] type[1].
function readFat(b, dv, base, n) {
    const files = {};
    for (let i = 0; i < n; i++) {
        const e = base + i * 32;
        files[cstr(b, e, 16)] = { start: dv.getUint32(e + 0x10, true), len: dv.getUint32(e + 0x14, true), type: b[e + 0x18] };
    }
    return files;
}

// Parse a disk image. `buf` is a Uint8Array starting at offset 0 of its buffer
// (the cart slices come from buf.buffer, exactly as the loader always did).
// Returns { bootable, v2, title, nFiles, cart, mounted }: `mounted` is the drive
// state (sealed-loader.js mountedDisk), `cart` the bytes to run first (null for
// a data disk, which boots GEM). Throws on anything that is not a valid disk.
export function parseDisk(buf, name) {
    if (buf.byteOffset !== 0 || buf.byteLength !== buf.buffer.byteLength) buf = buf.slice();
    if (buf.length < 0x600) throw new Error(`not a ZigMachine disk (too short): ${name}`);
    const dv = new DataView(buf.buffer);
    // Format v2: block 0 is an EXECUTABLE boot sector (a wasm module), descriptor at $400.
    if (isWasm(buf)) return parseV2(buf, dv);
    if (!hasMagic(buf, 0)) throw new Error("not a ZigMachine disk: " + name);
    // v1. Boot sector words sum to $1234 = BOOTABLE; $0000 = a DATA disk (boots GEM).
    const sum = beSum(buf, 256);
    const bootable = sum === 0x1234;
    if (!bootable && sum !== 0x0000) throw new Error("disk corrupt: boot-sector checksum 0x" + sum.toString(16));
    const start = dv.getUint32(0x0e, true) * dv.getUint16(0x08, true);
    const bootLen = dv.getUint32(0x12, true);
    const nFiles = dv.getUint16(0x2e4, true);
    return {
        bootable, v2: false, title: cstr(buf, 0x200, 64), nFiles,
        cart: bootable ? buf.buffer.slice(start, start + bootLen) : null,
        mounted: { buf, files: readFat(buf, dv, 0x300, nFiles) },
    };
}

// v2: the 1 KB boot sector runs first and chainloads the cart (swapCart req 2),
// whose pointer is in the descriptor. Not executable -> a data disk (GEM).
function parseV2(buf, dv) {
    if (!hasMagic(buf, 0x400)) throw new Error("v2 disk: bad descriptor magic");
    const bootable = beSum(buf, 512) === 0x1234;
    const nFiles = dv.getUint16(0x4f4, true);
    const chainCart = { start: dv.getUint32(0x408, true) * 512, len: dv.getUint32(0x40c, true) };
    return {
        bootable, v2: true, title: cstr(buf, 0x410, 64), nFiles,
        cart: bootable ? buf.buffer.slice(0, 1024) : null,
        mounted: { buf, files: readFat(buf, dv, 0x800, nFiles), date: dv.getUint32(0x4f0, true), v2: true, chainCart },
    };
}

// What a visitor's file IS, by content, never by extension: "disk" (v1 or v2),
// "wasm" (a raw cart), "zx0" (a ZX0-packed raw cart). Returns { kind } or
// { error } with a message fit to show the visitor.
export function classifyUpload(bytes) {
    const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
    const mb = (n) => (n / 1048576).toFixed(0) + " MB";
    let kind = null;
    if (hasMagic(b, 0) || (isWasm(b) && hasMagic(b, 0x400))) kind = "disk";
    else if (isWasm(b)) kind = "wasm";
    else if (isZx0(b)) kind = "zx0";
    if (!kind) return { error: "This is not a ZigMachine cart (.wasm) or disk (.zmd)." };
    const max = kind === "disk" ? DISK_MAX_BYTES : CART_MAX_BYTES;
    if (b.length > max)
        return { error: `Too big: ${(b.length / 1048576).toFixed(1)} MB. A ${kind === "disk" ? "disk" : "cart"} can be at most ${mb(max)}.` };
    return { kind };
}

globalThis.ZMDisk = { parseDisk, classifyUpload, CART_MAX_BYTES, DISK_MAX_BYTES };
