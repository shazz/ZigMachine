// A tiny wasm assembler for perf_audit_test.mjs: builds minimal carts (the exports
// demo_main gives the host) whose frame() holds ONE planted pattern, so every detector
// is tested on a cart with the pattern and on its clean twin.
import { encU32, encS32, encName, section } from "./wasm_bin.mjs";

export const BUF = 0x180000, BUF2 = 0x1a0000; // cart RAM (0x100000..0x300000), unused by the host
export const PAL = 0x300000 + 0x100;          // HW_VIDEO_BASE + OFF_PAL: plane 0's palette

const f64b = (x) => [...new Uint8Array(new Float64Array([x]).buffer)];
const f32b = (x) => [...new Uint8Array(new Float32Array([x]).buffer)];
const ma = (op, align, off = 0) => [op, align, ...encU32(off)];

// Instruction helpers: each returns an array of bytes.
export const I = {
    i32: (v) => [0x41, ...encS32(v)], i64: (v) => [0x42, ...encS32(v)], f64: (x) => [0x44, ...f64b(x)], f32: (x) => [0x43, ...f32b(x)],
    get: (l) => [0x20, ...encU32(l)], set: (l) => [0x21, ...encU32(l)], tee: (l) => [0x22, ...encU32(l)],
    call: (f) => [0x10, ...encU32(f)], drop: [0x1a],
    add: [0x6a], mul: [0x6c], divu: [0x6e], remu: [0x70], shl: [0x74],
    i64add: [0x7c], i64mul: [0x7e], i64ext: [0xad], f64add: [0xa0], f64mul: [0xa2], f32add: [0x92], f32cvt: [0xb3],
    load8: (o) => ma(0x2d, 0, o), load: (o) => ma(0x28, 2, o), f32load: (o) => ma(0x2a, 2, o),
    store8: (o) => ma(0x3a, 0, o), store: (o) => ma(0x36, 2, o), i64store: (o) => ma(0x37, 3, o),
    f64store: (o) => ma(0x39, 3, o), f32store: (o) => ma(0x38, 2, o),
    fill: [0xfc, 0x0b, 0x00], copy: [0xfc, 0x0a, 0x00, 0x00],
};

// for (local[i] = 0; local[i] < n; local[i]++) body  -- a real wasm loop (block + loop + br_if)
export function loop(i, n, body) {
    return [...I.i32(0), ...I.set(i), 0x02, 0x40, 0x03, 0x40, ...body,
        ...I.get(i), ...I.i32(1), ...I.add, ...I.tee(i), ...I.i32(n), 0x49, 0x0d, 0x00, 0x0b, 0x0b];
}

const T = { void: [0x60, 0, 0], f32v: [0x60, 1, 0x7d, 0], i32i32: [0x60, 1, 0x7f, 1, 0x7f], f32f32: [0x60, 1, 0x7d, 1, 0x7d],
    hbl: [0x60, 4, 0x7f, 0x7f, 0x7f, 0x7f, 0], i32i32v: [0x60, 2, 0x7f, 0x7f, 0] };

// frameBody: bytes of frame(dt: f32); locals: [count, type] decls beyond the param
// (local 0 is dt). extra: [{name, type: key of T, locals, body}] helper functions,
// indices 5.. in order (call them with I.call(5 + k)).
export function cart(frameBody, { locals = [[4, 0x7f], [2, 0x7e], [2, 0x7c], [2, 0x7d]], extra = [] } = {}) {
    const fns = [
        { name: "boot", type: "void", body: [] }, { name: "skipBoot", type: "void", body: [] },
        { name: "frame", type: "f32v", locals, body: frameBody },
        { name: "isPlaneEnabled", type: "i32i32", body: I.i32(0) }, { name: "hblDispatch", type: "hbl", body: [] },
        ...extra,
    ];
    const tkeys = Object.keys(T);
    const types = section(1, [...encU32(tkeys.length), ...tkeys.flatMap((k) => T[k])]);
    const imports = section(2, [1, ...encName("env"), ...encName("memory"), 2, 1, 112, 112]);
    const funcs = section(3, [...encU32(fns.length), ...fns.map((f) => tkeys.indexOf(f.type))]);
    const exps = fns.slice(0, 5);
    const exports = section(7, [...encU32(exps.length), ...exps.flatMap((f, i) => [...encName(f.name), 0, i])]);
    const code = section(10, [...encU32(fns.length), ...fns.flatMap((f) => {
        const ls = f.locals ?? [];
        const b = [...encU32(ls.length), ...ls.flatMap(([n, t]) => [...encU32(n), t]), ...f.body, 0x0b];
        return [...encU32(b.length), ...b];
    })]);
    const nameMap = [...encU32(fns.length), ...fns.flatMap((f, i) => [...encU32(i), ...encName(f.name)])];
    const names = section(0, [...encName("name"), 1, ...encU32(nameMap.length), ...nameMap]);
    return new Uint8Array([0, 0x61, 0x73, 0x6d, 1, 0, 0, 0, ...types, ...imports, ...funcs, ...exports, ...code, ...names]);
}
