// --------------------------------------------------------------------------
// Measure a cart wasm's RAM high-water: the first byte of the cart window it
// does NOT own.
//
// Only the cart binary knows this — it is baked in by the linker — so the HOST
// measures it and declares it to the machine (hwSetCartHigh), which then answers
// hwRamFree() for any cart in any language. See machine/sdk/memmap.zig
// (REG_CART_HIGH) and docs/HW_API.md.
//
// Two layouts have to be handled, because wasm-lld places the shadow stack
// either above the data (Zig's default here: data, then stack growing down from
// __stack_pointer's init) or below it (--stack-first). Taking the MAX of the
// stack pointer's initial value and the end of the last data segment is correct
// for both: whichever sits on top is the high-water.
//
// Loaded by docs/sealed-loader.js (browser) and apps/*.mjs (node).
// --------------------------------------------------------------------------
export const CART_RAM_BASE = 0x100000; // memmap.CART_RAM_BASE
export const CART_RAM_TOP = 0x300000; // memmap.CART_RAM_TOP (= HW_VIDEO_BASE)
export const ROM_RAM_BASE = 0x500000; // memmap.ROM_RAM_BASE  (Phase 2)
export const ROM_RAM_TOP = 0x700000; // memmap.ROM_RAM_TOP

function uleb(b, p) {
    let r = 0, s = 0, x;
    do { x = b[p++]; r |= (x & 0x7f) << s; s += 7; } while (x & 0x80);
    return [r >>> 0, p];
}

function sleb(b, p) {
    let r = 0, s = 0, x;
    do { x = b[p++]; r |= (x & 0x7f) << s; s += 7; } while (x & 0x80);
    if (s < 32 && (x & 0x40)) r |= (~0 << s);
    return [r, p];
}

// Skip one constant-expression initialiser, returning its i32 value (or null).
function initExpr(b, p) {
    let v = null;
    if (b[p] === 0x41) { [v, p] = sleb(b, p + 1); } // i32.const
    while (b[p] !== 0x0b) p++; // tolerate anything else (global.get, i64...)
    return [v, p + 1];
}

// The first byte above the cart's static data + stack, or null if the module
// declares neither (nothing to measure — a cart with no memory of its own).
export function cartHighWater(bytes) {
    const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
    if (b[0] !== 0x00 || b[1] !== 0x61 || b[2] !== 0x73 || b[3] !== 0x6d) {
        throw new Error("not a wasm module");
    }
    let p = 8, high = null;
    while (p < b.length) {
        const id = b[p++];
        let len; [len, p] = uleb(b, p);
        const next = p + len;
        if (id === 6) { // Global — the mutable i32 one is __stack_pointer
            let n; [n, p] = uleb(b, p);
            for (let i = 0; i < n; i++) {
                const type = b[p++], mutable = b[p++];
                let v; [v, p] = initExpr(b, p);
                if (type === 0x7f && mutable === 1 && v !== null) {
                    high = Math.max(high ?? 0, v >>> 0);
                }
            }
        } else if (id === 11) { // Data — active segments are placed in memory
            let n; [n, p] = uleb(b, p);
            for (let i = 0; i < n; i++) {
                let flags; [flags, p] = uleb(b, p);
                if ((flags & 0x01) === 0) { // active
                    if (flags & 0x02) [, p] = uleb(b, p); // explicit memidx
                    let off; [off, p] = initExpr(b, p);
                    let sz; [sz, p] = uleb(b, p);
                    high = Math.max(high ?? 0, ((off ?? 0) >>> 0) + sz);
                    p += sz;
                } else { // passive: no memory placement
                    let sz; [sz, p] = uleb(b, p);
                    p += sz;
                }
            }
        }
        p = next;
    }
    return high;
}

// What the machine's hwRam* / hwRomRam* instructions will report for a module in
// the given window. Kept here so the checkers and the loader agree with the
// hardware to the byte.
export function windowRam(bytes, base, top) {
    const high = cartHighWater(bytes);
    const known = high !== null && high >= base && high < top;
    return {
        high,
        known,
        used: known ? high - base : 0,
        free: known ? top - high : 0,
        over: high !== null && high >= top,
    };
}

export const cartRam = (bytes) => windowRam(bytes, CART_RAM_BASE, CART_RAM_TOP);
export const romRam = (bytes) => windowRam(bytes, ROM_RAM_BASE, ROM_RAM_TOP);

// docs/sealed.html loads this as a module while sealed-loader.js is a classic
// script (it exposes main() to an inline onclick), so hand the two functions
// over on globalThis rather than splitting the parser in two.
globalThis.ZMRam = { cartHighWater, windowRam, cartRam, romRam,
                     CART_RAM_BASE, CART_RAM_TOP, ROM_RAM_BASE, ROM_RAM_TOP };
