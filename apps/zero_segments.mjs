// Zero-filled statics gate: fail on any cart whose data section carries a run
// of zero bytes of ZERO_RUN_MIN or more.
//
// Why: the cart imports its memory, which the linker cannot assume is zero, so
// a module-scope buffer (`var work: [N]u8 = undefined;`, `static uint8_t w[N];`)
// is written out byte for byte into the data segment. It costs N bytes of the
// cart binary AND of the 2 MiB window before the cart runs a line (check_fits
// only sees the total, not that it is air). demo-swedish_newyear.wasm carried a
// 922,018-byte segment that was 100% zeros. Since HW 1.7.0 such a buffer comes
// from the machine's RAM arena instead: zg.mem.alloc(T, n) in Zig, zm_alloc() in
// C, zigmachine_mem::alloc() in Rust (docs/MEMORY.md).
//
// ALLOW lists the carts that exceeded the limit when the gate landed, with the
// zero bytes they carried in over-limit runs then. Each entry is a TODO: migrate
// the buffer to the arena and delete the entry. The gate fails if an allowed
// cart GROWS past its entry, and on a STALE entry (the cart is under the limit
// now): delete it, so the list only ever shrinks.
//
//   node apps/zero_segments.mjs docs/demo-*.wasm   (exit 1 on any failure)
//   node apps/zero_segments.mjs --break            a synthetic cart with a 70 KB
//                                                  zero segment must be caught
import { readFile } from "node:fs/promises";

const ZERO_RUN_MIN = 64 * 1024;

// cart file -> zero bytes in runs >= ZERO_RUN_MIN, measured 2026-09-26.
const ALLOW = {
    // The AUDIO thread's module (players + 68000 core): it has no RAM arena
    // (the arena is a machine-video instruction), so this one needs another fix.
    "demo-audio.wasm": 590760,
    "demo-cuddly_starwars.wasm": 223510,
    "demo-dbug.wasm": 117350,
    "demo-dhs_0pxl0reg.wasm": 341426,
    "demo-joust.wasm": 153614,
    "demo-maxi.wasm": 94438,
    "demo-north_south.wasm": 204174,
    "demo-obj.wasm": 86318,
    "demo-rno_natrium.wasm": 85302,
    "demo-rno_sodium.wasm": 277702,
    "demo-stniccc.wasm": 137614,
    "demo-st_replay.wasm": 1579078,
    "demo-supplex_fs2.wasm": 73277,
    "demo-tex_neoshow.wasm": 71918,
    "demo-ulm_spoon_distorter.wasm": 95482,
    // demo-swedish_newyear.wasm (922,018 B) is being migrated on its own branch;
    // it is not on main yet, so it has no entry here.
};

function uleb(b, p) {
    let r = 0, s = 0, x;
    do { x = b[p++]; r += (x & 0x7f) * 2 ** s; s += 7; } while (x & 0x80);
    return [r, p];
}

// Skip a constant expression; return its i32.const value (or null) and the end.
function initExpr(b, p) {
    let v = null;
    if (b[p] === 0x41) { // i32.const, signed LEB
        let r = 0, s = 0, x; p++;
        do { x = b[p++]; r |= (x & 0x7f) << s; s += 7; } while (x & 0x80);
        if (s < 32 && (x & 0x40)) r |= (~0 << s);
        v = r >>> 0;
    }
    while (b[p] !== 0x0b) p++;
    return [v, p + 1];
}

// Every run of >= min zero bytes in any data segment: [{seg, addr, len}].
export function zeroRuns(bytes, min = ZERO_RUN_MIN) {
    const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
    if (b[0] !== 0x00 || b[1] !== 0x61 || b[2] !== 0x73 || b[3] !== 0x6d) throw new Error("not a wasm module");
    const runs = [];
    let p = 8;
    while (p < b.length) {
        const id = b[p++];
        let len; [len, p] = uleb(b, p);
        const next = p + len;
        if (id === 11) {
            let n; [n, p] = uleb(b, p);
            for (let seg = 0; seg < n; seg++) {
                let flags, off = null; [flags, p] = uleb(b, p);
                if ((flags & 0x01) === 0) { // active: placed at an offset
                    if (flags & 0x02) [, p] = uleb(b, p);
                    [off, p] = initExpr(b, p);
                }
                let sz; [sz, p] = uleb(b, p);
                let i = p;
                const end = p + sz;
                while (i < end) {
                    if (b[i] !== 0) { i++; continue; }
                    const start = i;
                    while (i < end && b[i] === 0) i++;
                    if (i - start >= min) runs.push({ seg, addr: off === null ? null : off + (start - p), len: i - start });
                }
                p = end;
            }
        }
        p = next;
    }
    return runs;
}

const hex = (a) => (a === null ? "passive" : "0x" + a.toString(16));
const kb = (n) => `${(n / 1024).toFixed(0)} KB`;

// One cart against the limit and its allow-list entry; true when it passes.
function judge(name, runs, allow) {
    const total = runs.reduce((s, r) => s + r.len, 0);
    const allowed = allow[name];
    const where = runs.map((r) => `seg ${r.seg} @${hex(r.addr)}: ${r.len} B`).join(", ");
    if (total === 0) {
        if (allowed === undefined) return true;
        console.log(`STALE ${name}  allow-listed (${allowed} B) but no zero run >= ${kb(ZERO_RUN_MIN)} left: delete its ALLOW entry`);
        return false;
    }
    if (allowed === undefined) {
        console.log(`FAIL  ${name}  ${total} B of zero-filled statics in the data section (${where}).`);
        console.log(`      Allocate the buffer at boot instead: zg.mem.alloc(T, n) / zm_alloc / zigmachine_mem::alloc (docs/MEMORY.md)`);
        return false;
    }
    if (total > allowed) {
        console.log(`GREW  ${name}  ${total} B of zero runs, allow-list says ${allowed} B (${where})`);
        return false;
    }
    console.log(`TODO  ${name}  ${total} B of zero runs (allow-listed; migrate to the RAM arena)`);
    return true;
}

// A cart with one active 70 KB zero segment: the gate must refuse it.
function syntheticCart() {
    const seg = 70 * 1024;
    const lebU = (n) => { const o = []; do { let x = n & 0x7f; n >>>= 7; if (n) x |= 0x80; o.push(x); } while (n); return o; };
    // one segment, active (flags 0), at i32.const 0x100000 (SLEB 80 80 c0 00)
    const body = [1, 0x00, 0x41, 0x80, 0x80, 0xc0, 0x00, 0x0b, ...lebU(seg)];
    const section = [11, ...lebU(body.length + seg), ...body];
    const out = new Uint8Array(8 + section.length + seg);
    out.set([0x00, 0x61, 0x73, 0x6d, 1, 0, 0, 0]);
    out.set(section, 8);
    return out; // trailing bytes are already zero
}

if (process.argv.includes("--break")) {
    const runs = zeroRuns(syntheticCart());
    const caught = !judge("demo-break.wasm", runs, {});
    console.log(caught ? "zero_segments: PASS (--break was caught)"
                       : "zero_segments: FAIL (--break: a 70 KB zero segment went through)");
    process.exit(caught ? 0 : 1);
}

let ok = true, todo = 0;
for (const f of process.argv.slice(2)) {
    const name = f.split("/").pop();
    try {
        const runs = zeroRuns(await readFile(f));
        if (!judge(name, runs, ALLOW)) ok = false;
        else if (runs.length) todo++;
    } catch (e) {
        console.log(`ERROR ${f}: ${e.message}`);
        ok = false;
    }
}
console.log(`zero_segments: ${ok ? "PASS" : "FAIL"} (limit ${kb(ZERO_RUN_MIN)} a run; ${todo} allow-listed cart(s) still to migrate)`);
process.exit(ok ? 0 : 1);
